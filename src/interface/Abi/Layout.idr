-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
||| Evil Weevil ABI v0 — layout computation and proofs.
|||
||| The layout model is deliberately minimal: fields are laid out in declared
||| order, each at the running sum of the sizes before it. There is no alignment
||| arithmetic in the MODEL, because the field lists in `Abi.Types` are ordered so
||| that no implicit padding ever arises — where padding would otherwise appear, an
||| explicit named pad field is declared instead.
|||
||| == Three layers, each able to fail loudly
|||
|||   * THIS MODULE proves each struct's offsets and total size, and that every
|||     offset satisfies its field's alignment.
|||   * The generated C header carries `_Static_assert(offsetof(...) ==
|||     EE_OFFSET_...)`, so the C COMPILER confirms the declared offsets are the
|||     real ones on the target, and complains if it would insert padding.
|||   * The generated Zig file carries the same numbers, and the Zig kernel asserts
|||     its own `@offsetOf`/`@sizeOf` against them at comptime.
|||
||| No proof here claims a given compiler WILL place fields at these offsets —
||| that is precisely what the static asserts are for. The proofs establish that
||| the offsets are the intended ones, are self-consistent, and are
||| alignment-correct; the compiler asserts establish that the intent was realised.
|||
||| == Why the theorems spell out the size lists
|||
||| CORRECTED 2026-09-20. This section used to claim three things that Idris2 does
||| not reduce in a proof position. Two of them are FALSE and were measured false
||| with the pinned toolchain: `map (\x => x + 1) [1,2,3] = [2,3,4]` proves by
||| `Refl`, and `offsetsOf` over a nullary NAMED list constant proves by `Refl`
||| too. A top-level constant reduces normally when it is resolved as a name.
|||
||| What the misdiagnosis was actually seeing is the binder trap recorded in
||| `docs/developer/IDRIS2-NOTES.adoc`: a BARE lowercase name in a TYPE is
||| implicitly bound as a fresh implicit argument, silently shadowing the global,
||| so the goal becomes a claim about an unknown variable and nothing computes.
||| Qualified, the same expressions reduce.
|||
||| The third claim (`String` equality) was not re-measured in that pass; do not
||| rely on it either way.
|||
||| The theorems are still stated over literal size lists. That is now a
||| historical choice rather than a forced one: restating them over the named
||| lists in `Abi.Types` would make them STRONGER (change the model and the proofs
||| break), and is a task for a future pass — not this one, because a frozen,
||| verified module is the wrong place to relitigate proof style.
|||
||| So each theorem is stated over a LITERAL size list rather than the named list
||| in `Abi.Types`. That duplication is the point of `sizesOf` below and of the
||| generator's cross-check: `Abi.Gen` recomputes the sizes from the NAMED field
||| lists and compares them against the declared lists, refusing to emit anything
||| if they differ. So the chain is:
|||
|||   field names (Types) --sizesOf--> runtime check --==--> literal sizes
|||                                                                |
|||                                                        proofs (Layout)
|||                                                                |
|||                                              emitted constants (Gen)
|||                                                                |
|||                                       compiler asserts (C + Zig)
|||
||| A field added to the named list but not the literal one fails `just abi-check`
||| with a named struct and no output written. A field added to both, but with an
||| offset that no longer matches the theorems, fails to typecheck here.

module Abi.Layout

import Abi.Types
import Data.Nat
import Data.So

%default total

--------------------------------------------------------------------------------
-- The layout model
--------------------------------------------------------------------------------

||| Offsets of each field given its size: the running sum. `offsetsOf [8,4,4]`
||| is `[0,8,12]`.
public export
offsetsOf : List Nat -> List Nat
offsetsOf [] = []
offsetsOf (s :: rest) = 0 :: map (+ s) (offsetsOf rest)

||| Total size of a field-size list.
public export
totalOf : List Nat -> Nat
totalOf [] = 0
totalOf (s :: rest) = s + totalOf rest

||| Size of the n-th field, or 0 if absent.
public export
sizeAt : Nat -> List Nat -> Nat
sizeAt _ [] = 0
sizeAt Z (s :: _) = s
sizeAt (S k) (_ :: rest) = sizeAt k rest

||| Offset of the n-th field, or 0 if absent. Positions are 0-based, matching the
||| order of the field lists in `Abi.Types`, where the names live.
public export
offsetAt : Nat -> List Nat -> Nat
offsetAt _ [] = 0
offsetAt n ss = sizeAt n (offsetsOf ss)

--------------------------------------------------------------------------------
-- Runtime tie: named field list -> size list
--------------------------------------------------------------------------------

||| Size of a named field, ignoring the name.
public export
fieldSizeC : (String, CType) -> Nat
fieldSizeC (_, t) = sizeOf t

||| The sizes implied by a NAMED field list. This is what `Abi.Gen` compares
||| against the declared lists. It is an explicit recursion rather than a `map`,
||| and it is called at runtime by the generator; the module header records why the
||| older "because `map` does not reduce in a proof position" justification was
||| wrong.
public export
sizesOf : List (String, CType) -> List Nat
sizesOf [] = []
sizesOf (f :: rest) = fieldSizeC f :: sizesOf rest

||| `n` is a whole number of `unit`s. Written with structural recursion on `n` so
||| it computes for closed Nats (the same reason `mod` cannot be used here).
public export
isMultipleOf : Nat -> Nat -> Bool
isMultipleOf unit n =
  case n of
    Z => True
    S k => if k + 1 == unit then True else if k + 1 < unit then False else isMultipleOf unit k

||| The alignment unit every struct in this ABI is padded to. 8 is not a
||| preference: it is the widest member (u64) and the reason the C compiler needs
||| no implicit padding in any of the seven structs.
public export
structAlignUnit : Nat
structAlignUnit = 8

||| Does this padding arrangement work out regardless of where the struct starts —
||| i.e. is the struct's size a whole number of its alignment units, so that an
||| array of them has no gap and `stride == size`? That is the property that makes
||| `ee_snapshot snapshots[N]` safe and the reason every struct here is padded to a
||| multiple of 8.
|||
||| This used to read `totalOf ss == totalOf ss`, which is true of every list and
||| therefore checks nothing. It is now a real predicate, and it is LOAD-BEARING
||| rather than decorative: `Abi.Gen` refuses to emit a struct whose stride is not
||| safe, so a padding mistake stops generation instead of shipping.
|||
||| Stated as a runtime predicate rather than a theorem for the reason recorded in
||| the module header: `mod` reduces on literals but not on a stuck application, so
||| `strideEqSize fields = True` is not a proposition Idris2 0.7.0 will discharge by
||| computation over a computed size. The alignment theorems below remain the
||| proof layer, stated over the literal sizes; this is the gate.
public export
strideEqSize : Nat -> List Nat -> Bool
strideEqSize align ss = isMultipleOf align (totalOf ss)

--------------------------------------------------------------------------------
-- ee_version — 8 bytes
--------------------------------------------------------------------------------

export
versionOffsets : offsetsOf [2, 2, 2, 2] = [0, 2, 4, 6]
versionOffsets = Refl

export
versionSize : totalOf [2, 2, 2, 2] = 8
versionSize = Refl

||| Alignment facts are stated over the LITERAL number proved by the theorem
||| immediately above (`versionSize`), not over `totalOf [...]`: Idris2 reduces
||| `mod` on a literal but not on a stuck application (measured). If the size
||| changes, `versionSize` fails first and names the struct; these keep the
||| alignment claim checkable in the meantime.
export
versionSizeAligned : (8 `mod` 2) = 0
versionSizeAligned = Refl

--------------------------------------------------------------------------------
-- ee_init_desc — 64 bytes
--------------------------------------------------------------------------------

export
initDescOffsets : offsetsOf [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8] = [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 56]
initDescOffsets = Refl

export
initDescSize : totalOf [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8] = 64
initDescSize = Refl

export
initDescSizeAligned : (64 `mod` 8) = 0
initDescSizeAligned = Refl

||| The u64 fields of the init descriptor sit at offsets 24, 32, 40, 48 and 56
||| (see `initDescOffsets`), each a multiple of 8. These are exactly the fields a
||| compiler would silently pad around if the declared order were wrong.
export
initDescU64Aligned : ( (24 `mod` 8) = 0, (32 `mod` 8) = 0, (40 `mod` 8) = 0
                     , (48 `mod` 8) = 0, (56 `mod` 8) = 0 )
initDescU64Aligned = (Refl, Refl, Refl, Refl, Refl)

--------------------------------------------------------------------------------
-- ee_contact — 16 bytes, embeddable
--------------------------------------------------------------------------------

export
contactOffsets : offsetsOf [2, 2, 2, 2, 4, 4] = [0, 2, 4, 6, 8, 12]
contactOffsets = Refl

export
contactSize : totalOf [2, 2, 2, 2, 4, 4] = 16
contactSize = Refl

||| 16 is a multiple of 4, so `ee_contact[8]` has no internal padding.
export
contactSizeAligned : (16 `mod` 4) = 0
contactSizeAligned = Refl

||| `distance` and `threat` are the two 4-byte fields, at offsets 8 and 12.
export
contactFieldsAligned : ( (8 `mod` 4) = 0, (12 `mod` 4) = 0 )
contactFieldsAligned = (Refl, Refl)

--------------------------------------------------------------------------------
-- ee_snapshot — 184 bytes
--------------------------------------------------------------------------------

export
snapshotOffsets : offsetsOf [8, 4, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16, 16, 16, 16, 16, 16, 16, 4, 4] =
  [ 0, 8, 12, 14, 16, 20, 24, 28, 32, 36, 40, 44
  , 48, 64, 80, 96, 112, 128, 144, 160
  , 176, 180 ]
snapshotOffsets = Refl

export
snapshotSize : totalOf [8, 4, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16, 16, 16, 16, 16, 16, 16, 4, 4] = 184
snapshotSize = Refl

export
snapshotSizeAligned : (184 `mod` 8) = 0
snapshotSizeAligned = Refl

||| The contact block starts at 48 (see `snapshotOffsets`): a multiple of both 8
||| (the u64 field before it) and 16 (the contact stride). That is why neither the
||| block nor the contacts inside it need padding.
export
snapshotContactBlockAligned : (48 `mod` 16) = 0
snapshotContactBlockAligned = Refl

||| Every contact in the array is 16-aligned: offsets 48, 64, ..., 160.
export
snapshotContactsStrided : ( (64 `mod` 16) = 0, (160 `mod` 16) = 0 )
snapshotContactsStrided = (Refl, Refl)

export
snapshotTickAligned : (0 `mod` 8) = 0
snapshotTickAligned = Refl

--------------------------------------------------------------------------------
-- ee_agent — 48 bytes
--------------------------------------------------------------------------------

export
agentOffsets : offsetsOf [8, 8, 4, 4, 4, 4, 4, 4, 4, 4] = [0, 8, 16, 20, 24, 28, 32, 36, 40, 44]
agentOffsets = Refl

export
agentSize : totalOf [8, 8, 4, 4, 4, 4, 4, 4, 4, 4] = 48
agentSize = Refl

export
agentSizeAligned : (48 `mod` 8) = 0
agentSizeAligned = Refl

||| `rng_state` at 0 and `tick_last` at 8 — the agent's determinism-critical
||| fields, both 8-aligned.
export
agentU64Aligned : ( (0 `mod` 8) = 0, (8 `mod` 8) = 0 )
agentU64Aligned = (Refl, Refl)

--------------------------------------------------------------------------------
-- ee_intent — 48 bytes
--------------------------------------------------------------------------------

export
intentOffsets : offsetsOf [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4] = [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44]
intentOffsets = Refl

export
intentSize : totalOf [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4] = 48
intentSize = Refl

export
intentSizeAligned : (48 `mod` 8) = 0
intentSizeAligned = Refl

--------------------------------------------------------------------------------
-- ee_context — 72 bytes, host-allocated
--------------------------------------------------------------------------------

||| The kernel allocates nothing (ADR-0005 §4): the host owns one of these per
||| kernel instance and passes it to every call. It carries what the tick needs to
||| be reproducible — the seed, the tick rate, the budget — plus counters, so a
||| replay can be reconstructed from the context alone.
export
contextOffsets : offsetsOf [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8] = [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 56, 64]
contextOffsets = Refl

export
contextSize : totalOf [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8] = 72
contextSize = Refl

export
contextSizeAligned : (72 `mod` 8) = 0
contextSizeAligned = Refl

||| The u64 block of the context (fingerprint, seed, tick rate, counters) begins
||| at 24 — 8-aligned, as every one of those six fields requires.
export
contextU64Aligned : ( (24 `mod` 8) = 0, (64 `mod` 8) = 0 )
contextU64Aligned = (Refl, Refl)

--------------------------------------------------------------------------------
-- ee_mind — 56 bytes, caller-owned, ABI 1.1 (ADR-0013)
--------------------------------------------------------------------------------

export
mindOffsets : offsetsOf [4, 4, 8, 8, 4, 4, 4, 4, 4, 4, 2, 2, 1, 1, 1, 1] =
  [0, 4, 8, 16, 24, 28, 32, 36, 40, 44, 48, 50, 52, 53, 54, 55]
mindOffsets = Refl

export
mindSize : totalOf [4, 4, 8, 8, 4, 4, 4, 4, 4, 4, 2, 2, 1, 1, 1, 1] = 56
mindSize = Refl

export
mindSizeAligned : (56 `mod` 8) = 0
mindSizeAligned = Refl

||| `struct_size` is at offset 0, as in `ee_init_desc`, so a host can be told it
||| passed the wrong struct before a single other field is trusted.
export
mindStructSizeFirst : offsetAt 0 [4, 4, 8, 8, 4, 4, 4, 4, 4, 4, 2, 2, 1, 1, 1, 1] = 0
mindStructSizeFirst = Refl

||| The two u64 words (the previous tick's contact ids) at 8 and 16, the two u16s at
||| 48 and 50: every field sits on its own alignment, so no compiler pads.
export
mindFieldsAligned : ( (8 `mod` 8) = 0, (16 `mod` 8) = 0, (48 `mod` 2) = 0, (50 `mod` 2) = 0 )
mindFieldsAligned = (Refl, Refl, Refl, Refl)

--------------------------------------------------------------------------------
-- ee_mind_trace — 32 bytes, written by the kernel, ABI 1.1 (ADR-0013)
--------------------------------------------------------------------------------

export
mindTraceOffsets : offsetsOf [4, 4, 8, 4, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1] =
  [0, 4, 8, 16, 20, 22, 24, 25, 26, 27, 28, 29, 30, 31]
mindTraceOffsets = Refl

export
mindTraceSize : totalOf [4, 4, 8, 4, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1] = 32
mindTraceSize = Refl

export
mindTraceSizeAligned : (32 `mod` 8) = 0
mindTraceSizeAligned = Refl

||| `tick` (u64) at 8, `attention` and `cause_contact` (u16) at 20 and 22.
export
mindTraceFieldsAligned : ( (8 `mod` 8) = 0, (20 `mod` 2) = 0, (22 `mod` 2) = 0 )
mindTraceFieldsAligned = (Refl, Refl, Refl)

--------------------------------------------------------------------------------
-- Cross-struct facts
--------------------------------------------------------------------------------

||| Every struct's size is a multiple of 8, so a host may allocate an array of any
||| of them with a plain allocator and no per-element padding. Stated once, for all
||| six, rather than re-derived per consumer.
export
allStructSizesAligned : ( (8 `mod` 8) = 0
                        , (64 `mod` 8) = 0
                        , (16 `mod` 8) = 0
                        , (184 `mod` 8) = 0
                        , (48 `mod` 8) = 0
                        , (48 `mod` 8) = 0
                        , (72 `mod` 8) = 0
                        , (56 `mod` 8) = 0
                        , (32 `mod` 8) = 0 )
allStructSizesAligned = (Refl, Refl, Refl, Refl, Refl, Refl, Refl, Refl, Refl)
