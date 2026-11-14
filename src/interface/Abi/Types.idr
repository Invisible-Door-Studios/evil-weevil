-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
||| Evil Weevil ABI v0 — the type model.
|||
||| This module is the SINGLE SOURCE OF TRUTH for the C ABI. `Abi.Gen` reads the
||| field lists below and emits both `include/evil_weevil/ee.h` and
||| `src/interface/generated/ee_layout.zig` from them; `Abi.Layout` proves the
||| offsets and sizes computed from the same lists. Nothing about the wire format
||| is written down twice, and no constant in the header is hand-typed.
|||
||| Two design rules make the whole thing checkable (ADR-0005):
|||
|||   1. NO POINTER-SIZED FIELD appears in any struct crossing the ABI. Pointers
|||      appear only as function PARAMETERS. This keeps the layout identical on
|||      every 64-bit target and keeps host addresses out of deterministic state.
|||   2. Field order is descending by alignment, with explicit pad fields where
|||      padding would otherwise be implicit. The declared offsets therefore equal
|||      C's natural layout, which C's own `_Static_assert`s then verify per
|||      compiler (see the generated header).
|||
||| Idris2 cannot reduce `map` in a proof position, so the size lists below are
||| written out literally beside each named field list. That duplication is not
||| decorative: the generator cross-checks the two at runtime and exits non-zero on
||| any divergence, so a field added to one and not the other fails `just abi-check`
||| rather than silently reshaping the ABI.

module Abi.Types

import Data.Nat
import Data.So

%default total

--------------------------------------------------------------------------------
-- Platform model
--------------------------------------------------------------------------------

||| Targets this ABI layout is validated for.
|||
||| 32-bit targets (including wasm32) are deliberately ABSENT. Idris2's layout
||| model below is 64-bit; claiming wasm32 compat without re-deriving it would be
||| exactly the kind of unverified claim this repo exists to avoid. A 32-bit
||| variant is Phase 4 work with its own layout proofs.
public export
data Platform = Linux64 | MacOS64 | Windows64

||| Pointer size in bytes per platform (all current targets are 64-bit).
public export
ptrBytes : Platform -> Nat
ptrBytes Linux64 = 8
ptrBytes MacOS64 = 8
ptrBytes Windows64 = 8

--------------------------------------------------------------------------------
-- C type model
--------------------------------------------------------------------------------

||| The C-level types the ABI is built from. Sizes and alignments are the
||| System V / Windows x86-64 values for the fixed-width types plus the two
||| composite types this ABI defines.
public export
data CType = U8 | U16 | U32 | U64 | I32 | I64 | Fx | CVersion | CContact

public export
sizeOf : CType -> Nat
sizeOf U8 = 1
sizeOf U16 = 2
sizeOf U32 = 4
sizeOf U64 = 8
sizeOf I32 = 4
sizeOf I64 = 8
sizeOf Fx = 4
sizeOf CVersion = 8
sizeOf CContact = 16

public export
alignOf : CType -> Nat
alignOf U8 = 1
alignOf U16 = 2
alignOf U32 = 4
alignOf U64 = 8
alignOf I32 = 4
alignOf I64 = 8
alignOf Fx = 4
alignOf CVersion = 2
alignOf CContact = 4

--------------------------------------------------------------------------------
-- Fixed point
--------------------------------------------------------------------------------

||| All kernel arithmetic is integer/fixed-point (ADR-0006). This is Q16.16 in an
||| i32: range ±32768, resolution 1/65536. Named export so the header documents it
||| and so a future Q32.32 widening is a visible change, not a silent one.
public export
fxFractionBits : Nat
fxFractionBits = 16

public export
fxOne : Nat
fxOne = 65536

||| The scaling factor (2^16 = 65536, the `fxOne` above) is comfortably inside
||| i32 range, so Q16.16 is representable at all. The theorem is stated over the
||| literal 65536 and the tie to `fxOne` is definitional — a qualified constant
||| DOES reduce, whatever the earlier comment here said; see the correction in
||| `Abi.Foreign`'s header and docs/developer/IDRIS2-NOTES.adoc.
export
fxOneFitsI32 : So (65536 < 2147483647)
fxOneFitsI32 = Oh

--------------------------------------------------------------------------------
-- Version and handshake
--------------------------------------------------------------------------------

public export
record Version where
  constructor MkVersion
  major : Nat
  minor : Nat
  patch : Nat

||| The ABI version this kernel implements. Bumping `major` is a breaking change
||| and requires a new ADR; `minor` is additive (ADR-0005).
|||
||| 1.1 (ADR-0013) is additive: two new structs (`ee_mind`, `ee_mind_trace`), one
||| new entrance (`ee_tick_mind`), and bits the freeze left undefined in
||| `ee_intent.flags` and `ee_contact.flags`. No existing field changed meaning, size
||| or offset, `EE_ABI_FINGERPRINT` is still computed over the seven 1.0 structs
||| only (see `frozenStructs`), and `ee_tick` is the same function it was at 1.0.
public export
abiVersion : Version
abiVersion = MkVersion 1 1 0

public export
data Handshake
  = Compatible
  | HostTooOld
  | HostTooNew
  | FingerprintMismatch

||| The handshake decision, as a total function of the two versions.
||| Total means every input has an answer: there is no input for which the kernel
||| "forgets" to reply, and the compiler checks that (ADR-0005 §3).
public export
negotiate : (kernel : Version) -> (host : Version) -> Handshake
negotiate (MkVersion kmaj _ _) (MkVersion hmaj _ _) =
  if hmaj == kmaj
     then Compatible
     else if hmaj < kmaj
             then HostTooOld
             else HostTooNew

||| Concrete behaviour of the handshake, proved rather than asserted in prose.
||| Literals rather than `abiVersion` for the reason given at `fxOneFitsI32`.
export
sameVersionCompatible : negotiate (MkVersion 1 0 0) (MkVersion 1 0 0) = Compatible
sameVersionCompatible = Refl

export
olderHostRejected : negotiate (MkVersion 2 0 0) (MkVersion 1 0 0) = HostTooOld
olderHostRejected = Refl

export
newerHostRejected : negotiate (MkVersion 1 0 0) (MkVersion 2 0 0) = HostTooNew
newerHostRejected = Refl

--------------------------------------------------------------------------------
-- Status codes
--------------------------------------------------------------------------------

||| Every entry point returns one of these. Codes are part of the ABI: the numbers
||| are emitted into the header, and `statusCode` is total, so adding a constructor
||| without a code is a compile error rather than an unhandled case at runtime.
public export
data Status
  = EeOk
  | EeBadParam
  | EeVersionMismatch
  | EeFingerprintMismatch
  | EeCapabilityUnsupported
  | EeBufferTooSmall
  | EePanicCaught

public export
statusCode : Status -> Nat
statusCode EeOk = 0
statusCode EeBadParam = 1
statusCode EeVersionMismatch = 2
statusCode EeFingerprintMismatch = 3
statusCode EeCapabilityUnsupported = 4
statusCode EeBufferTooSmall = 5
statusCode EePanicCaught = 6

--------------------------------------------------------------------------------
-- Host capabilities
--------------------------------------------------------------------------------

||| What a host may declare it can do. The kernel degrades along a documented
||| ladder for each absent capability rather than aborting (ADR-0004).
public export
data Capability
  = CapNavmesh
  | CapLineOfSight
  | CapRaycast
  | CapWaypointGraph
  | CapSpawnRights
  | CapAnimationHooks
  | CapDamageEvents
  | CapSoundEvents
  | CapVehicleBoarding
  | CapTerrainHeight

||| Bit index of each capability in the u32 mask.
public export
capBit : Capability -> Nat
capBit CapNavmesh = 0
capBit CapLineOfSight = 1
capBit CapRaycast = 2
capBit CapWaypointGraph = 3
capBit CapSpawnRights = 4
capBit CapAnimationHooks = 5
capBit CapDamageEvents = 6
capBit CapSoundEvents = 7
capBit CapVehicleBoarding = 8
capBit CapTerrainHeight = 9

||| Every capability fits in the 32-bit mask, proved per constructor.
||| (One case per constructor: a new capability added without checking this fails
||| to compile here, not at runtime in somebody's game.)
export
capBitFits : (c : Capability) -> So (capBit c < 32)
capBitFits CapNavmesh = Oh
capBitFits CapLineOfSight = Oh
capBitFits CapRaycast = Oh
capBitFits CapWaypointGraph = Oh
capBitFits CapSpawnRights = Oh
capBitFits CapAnimationHooks = Oh
capBitFits CapDamageEvents = Oh
capBitFits CapSoundEvents = Oh
capBitFits CapVehicleBoarding = Oh
capBitFits CapTerrainHeight = Oh

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

||| What the kernel may ask the host to do. Values are stable ABI; new actions are
||| appended, never reordered (ADR-0005 §5).
public export
data Action
  = ActIdle
  | ActAdvance
  | ActHold
  | ActFlee
  | ActAttack
  | ActReload
  | ActTakeCover
  | ActRegroup
  | ActInvestigate

public export
actionCode : Action -> Nat
actionCode ActIdle = 0
actionCode ActAdvance = 1
actionCode ActHold = 2
actionCode ActFlee = 3
actionCode ActAttack = 4
actionCode ActReload = 5
actionCode ActTakeCover = 6
actionCode ActRegroup = 7
actionCode ActInvestigate = 8

--------------------------------------------------------------------------------
-- Field lists — the ABI itself
--------------------------------------------------------------------------------

public export
versionFields : List (String, CType)
versionFields =
  [ ("major", U16), ("minor", U16), ("patch", U16), ("reserved", U16) ]

public export
initDescFields : List (String, CType)
initDescFields =
  [ ("struct_size", U32)
  , ("abi_major", U32)
  , ("abi_minor", U32)
  , ("capabilities", U32)
  , ("max_agents", U32)
  , ("flags", U32)
  , ("host_tick_num", U64)
  , ("host_tick_den", U64)
  , ("rng_seed", U64)
  , ("abi_fingerprint", U64)
  , ("reserved0", U64)
  ]

public export
contactFields : List (String, CType)
contactFields =
  [ ("id", U16)
  , ("flags", U16)
  , ("bearing_cos", U16)
  , ("bearing_sin", U16)
  , ("distance", Fx)
  , ("threat", Fx)
  ]

public export
snapshotFields : List (String, CType)
snapshotFields =
  [ ("tick", U64)
  , ("capability_mask", U32)
  , ("agent_id", U16)
  , ("contact_count", U16)
  , ("self_x", Fx)
  , ("self_y", Fx)
  , ("self_z", Fx)
  , ("self_vx", Fx)
  , ("self_vy", Fx)
  , ("health", Fx)
  , ("ammo", Fx)
  , ("flags", U32)
  , ("contact0", CContact)
  , ("contact1", CContact)
  , ("contact2", CContact)
  , ("contact3", CContact)
  , ("contact4", CContact)
  , ("contact5", CContact)
  , ("contact6", CContact)
  , ("contact7", CContact)
  , ("cooldown", U32)
  , ("reserved0", U32)
  ]

public export
agentFields : List (String, CType)
agentFields =
  [ ("rng_state", U64)
  , ("tick_last", U64)
  , ("memory_x", Fx)
  , ("memory_y", Fx)
  , ("memory_age", U32)
  , ("cached_action", U32)
  , ("cached_target", U32)
  , ("budget_used", U32)
  , ("degraded_ticks", U32)
  , ("flags", U32)
  ]

public export
intentFields : List (String, CType)
intentFields =
  [ ("action", U32)
  , ("target_id", U32)
  , ("move_x", Fx)
  , ("move_y", Fx)
  , ("move_z", Fx)
  , ("look_x", Fx)
  , ("look_y", Fx)
  , ("speed", Fx)
  , ("priority", U32)
  , ("budget_used", U32)
  , ("flags", U32)
  , ("reserved0", U32)
  ]

public export
contextFields : List (String, CType)
contextFields =
  [ ("abi_major", U32)
  , ("flags", U32)
  , ("capabilities", U32)
  , ("budget_units", U32)
  , ("max_agents", U32)
  , ("reserved0", U32)
  , ("abi_fingerprint", U64)
  , ("rng_seed", U64)
  , ("tick_rate_num", U64)
  , ("tick_rate_den", U64)
  , ("ticks_run", U64)
  , ("degraded_ticks", U64)
  ]

||| ABI 1.1 (ADR-0013): the per-agent MIND state, caller-owned, one per agent, passed
||| to `ee_tick_mind` beside the 1.0 `ee_agent`. The host zeroes it and sets
||| `struct_size`; the kernel never allocates it and keeps nothing between calls
||| (ADR-0009 decision 6 applies unchanged: no hidden state).
|||
||| The three reservoirs are Q16.16 fractions in [0, 65536]. `seen_ids_lo`/`_hi` pack
||| the ids of the contacts visible on the previous tick (four u16 per word), so a
||| contact can be recognised as NEW without the kernel keeping a list of its own.
||| The grudge slot (`grudge_*`) is a second memory, written ONLY by perception of the
||| contact that harmed the agent — affect decides how long it is attended to, never
||| what it says (ADR-0013 §2).
public export
mindFields : List (String, CType)
mindFields =
  [ ("struct_size", U32)
  , ("arousal", U32)
  , ("seen_ids_lo", U64)
  , ("seen_ids_hi", U64)
  , ("fear", U32)
  , ("grievance", U32)
  , ("last_health", Fx)
  , ("grudge_x", Fx)
  , ("grudge_y", Fx)
  , ("grudge_age", U32)
  , ("grudge_id", U16)
  , ("seen_count", U16)
  , ("token", U8)
  , ("hesitate_left", U8)
  , ("flags", U8)
  , ("reserved0", U8)
  ]

||| ABI 1.1 (ADR-0013): one record per agent per tick, written by `ee_tick_mind` when
||| the host passes one. It is the kernel's half of `enaction-mind-trace/1`: the
||| affect TOKEN and an attention MASS (never a reservoir value), the RANKING of the
||| mode candidates (an order, never a score), the incumbent and selected modes, the
||| cause of a token change, and the tells. Commitment override is deliberately NOT a
||| field: a reader derives it from `ranking`, `incumbent` and `selected`.
|||
||| `ranking` packs mode codes four bits each, rank 0 in the low nibble;
||| `ranking_count` says how many nibbles are meaningful.
public export
mindTraceFields : List (String, CType)
mindTraceFields =
  [ ("struct_size", U32)
  , ("target_id", U32)
  , ("tick", U64)
  , ("ranking", U32)
  , ("attention", U16)
  , ("cause_contact", U16)
  , ("ranking_count", U8)
  , ("selected", U8)
  , ("incumbent", U8)
  , ("token", U8)
  , ("token_prev", U8)
  , ("cause", U8)
  , ("tells", U8)
  , ("reserved0", U8)
  ]

--------------------------------------------------------------------------------
-- The proven literal size lists
--------------------------------------------------------------------------------
-- Exactly two representations of the layout exist, and this is the second:
--
--   1. the NAMED field lists above — what a maintainer edits, with names and types;
--   2. these LITERAL size lists — what `Abi.Layout` states its theorems about,
--      because Idris2 will not reduce a name in a proof position.
--
-- They are tied by `Abi.Gen`, which recomputes (1) from the field lists and
-- refuses to emit anything unless it equals (2). Adding a field to one list and
-- not the other therefore fails `just abi-check`, naming the struct, with no file
-- written — rather than silently reshaping the ABI.

public export
snapshotSizes : List Nat
snapshotSizes =
  [ 8, 4, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4
  , 16, 16, 16, 16, 16, 16, 16, 16
  , 4, 4
  ]

--------------------------------------------------------------------------------
-- Flags
--------------------------------------------------------------------------------

||| Bits in `ee_intent.flags`.
public export
IntentFlag : Type
IntentFlag = Nat

public export
intentFlagDegraded : Nat
intentFlagDegraded = 1

public export
intentFlagNewTarget : Nat
intentFlagNewTarget = 2

public export
intentFlagUnreachable : Nat
intentFlagUnreachable = 4

||| Bits in `ee_agent.flags`. The field existed in v0 with no defined bits, which
||| is why Phase 2 needs no layout change: the memory slots (`memory_x`,
||| `memory_y`, `memory_age`) were already reserved beside it. Using an undefined
||| bit is additive — a host that zeroed the struct and ignored the field behaves
||| exactly as before — so the layout checksum does not move and the ABI stays 1.0.
||| See ADR-0009.
public export
agentFlagMemoryValid : Nat
agentFlagMemoryValid = 1

||| Set when the intent is aimed at somewhere the agent REMEMBERS rather than at
||| something it can see right now (Phase 2). Without this bit a host cannot tell
||| "walking towards an enemy" from "walking towards where an enemy was", and the
||| difference is the entire point of having memory.
public export
intentFlagFromMemory : Nat
intentFlagFromMemory = 8

||| The agent flag is bit 0, as a bit VALUE (1). Pinned like the intent flags, so
||| a change fails to compile here rather than quietly redefining a wire bit.
export
agentFlagMemoryValidIsOne : Abi.Types.agentFlagMemoryValid = 1
agentFlagMemoryValidIsOne = Refl

||| Where the agent's MODE lives in the SAME flags word: bits 1..3 (ADR-0012). Bit 0
||| was the only bit the freeze defined (ADR-0009); these three were left undefined,
||| so Phase 2 puts the mode there rather than growing the struct. Three bits, five
||| modes, three spare — an ABI that runs out of flag bits has to break its layout to
||| grow, and that is a cost paid by every host.
public export
agentModeShift : Nat
agentModeShift = 1

public export
agentModeMask : Nat
agentModeMask = 14

public export
agentModeAdvance : Nat
agentModeAdvance = 0

public export
agentModeEngage : Nat
agentModeEngage = 1

public export
agentModeEvade : Nat
agentModeEvade = 2

public export
agentModeReload : Nat
agentModeReload = 3

public export
agentModeInvestigate : Nat
agentModeInvestigate = 4

export
agentModeShiftIsOne : Abi.Types.agentModeShift = 1
agentModeShiftIsOne = Refl

export
agentModeMaskIsFourteen : Abi.Types.agentModeMask = 14
agentModeMaskIsFourteen = Refl

||| The property that matters: the mask is seven shifted left by one, i.e. a MULTIPLE
||| OF TWO, so bit 0 — `EE_AGENT_FLAG_MEMORY_VALID` — is outside it and a mode write
||| cannot touch the memory flag. Stated as the multiplication rather than as
||| `mod` 2 = 0 because `mod` does not reduce for a literal in this base, and a proof
||| that does not reduce is not a proof.
export
agentModeMaskLeavesBitZeroAlone : Abi.Types.agentModeMask = 7 * 2
agentModeMaskLeavesBitZeroAlone = Refl

||| How long a sighting stays actionable, in ticks. Six tenths of a second at
||| 60 Hz: long enough to keep pursuing somebody who stepped behind a pillar, short
||| enough that an agent does not walk to where a player stood ten seconds ago.
public export
memoryTtl : Nat
memoryTtl = 36

--------------------------------------------------------------------------------
-- ABI 1.1: the mind (ADR-0013) — wire constants only
--------------------------------------------------------------------------------
-- The NAMES a host needs: bits it reads, codes it decodes. The constants that make
-- the mind behave (leak shifts, thresholds, gains) are policy, not ABI, and live in
-- `Abi.Affect` and the kernel only — the same split ADR-0010 §3 made for the weights.

||| `ee_contact.flags` bit 0: the host attributes this tick's damage to this contact.
||| The freeze left every bit of `ee_contact.flags` undefined; defining one is
||| additive (ADR-0009 precedent). Read ONLY by `ee_tick_mind`, and only when the host
||| declared `EE_CAP_DAMAGE_EVENTS`; `ee_tick` never reads it.
public export
contactFlagDamageSource : Nat
contactFlagDamageSource = 1

||| The bodily tells, as `ee_intent.flags` bits 4..6 (bits 0..3 are 1.0's). Set only
||| by `ee_tick_mind`; `ee_tick` never sets them, so a 1.0 host never sees them.
public export
intentFlagStartle : Nat
intentFlagStartle = 16

public export
intentFlagHesitate : Nat
intentFlagHesitate = 32

public export
intentFlagFixate : Nat
intentFlagFixate = 64

||| The same tells as `ee_mind_trace.tells` bits: the intent bit shifted down by four.
public export
tellStartle : Nat
tellStartle = 1

public export
tellHesitate : Nat
tellHesitate = 2

public export
tellFixate : Nat
tellFixate = 4

||| `ee_mind.flags` bits.
public export
mindFlagPrimed : Nat
mindFlagPrimed = 1

public export
mindFlagGrudgeLead : Nat
mindFlagGrudgeLead = 2

public export
mindFlagHesitated : Nat
mindFlagHesitated = 4

||| The affect-token vocabulary, in declaration order — which is also the tie-break
||| order (`enaction-mind-trace/1` "affect_tokens": calm, wary, afraid, angry).
public export
affectCalm : Nat
affectCalm = 0

public export
affectWary : Nat
affectWary = 1

public export
affectAfraid : Nat
affectAfraid = 2

public export
affectAngry : Nat
affectAngry = 3

||| Why a token changed: which INPUT caused it. `NONE` appears exactly when the token
||| did not change (`Abi.Affect.tokenChangeHasCause`).
public export
causeNone : Nat
causeNone = 0

public export
causeCloseContact : Nat
causeCloseContact = 1

public export
causeDamage : Nat
causeDamage = 2

public export
causeContradiction : Nat
causeContradiction = 3

public export
causeLowHealth : Nat
causeLowHealth = 4

public export
causeThreats : Nat
causeThreats = 5

public export
causeNoAmmo : Nat
causeNoAmmo = 6

public export
causeAttributedDamage : Nat
causeAttributedDamage = 7

public export
causeDecay : Nat
causeDecay = 8

||| Full scale of an attention mass (`enaction` ADR-0016: units of 1/10 000).
public export
massFull : Nat
massFull = 10000

||| The tells sit above every 1.0 intent bit: the lowest tell (16) is above the
||| highest 1.0 bit (8), so no tell can be mistaken for a 1.0 flag.
export
tellsAboveTheFrozenBits : So (8 < 16)
tellsAboveTheFrozenBits = Oh

export
intentTellsAreTheTraceTellsShifted :
  ( Abi.Types.intentFlagStartle, Abi.Types.intentFlagHesitate, Abi.Types.intentFlagFixate )
  = ( Abi.Types.tellStartle * 16, Abi.Types.tellHesitate * 16, Abi.Types.tellFixate * 16 )
intentTellsAreTheTraceTellsShifted = Refl

--------------------------------------------------------------------------------
-- Total name maps and enumerations
--------------------------------------------------------------------------------
-- Each of these PATTERN MATCHES ON EVERY CONSTRUCTOR of its type. That is the
-- point: adding a Capability, Status or Action without giving it a name here
-- fails to compile, so nothing can reach the header unnamed, and the generator
-- (which iterates the lists below) cannot silently omit it.

public export
capName : Capability -> String
capName CapNavmesh = "NAVMESH"
capName CapLineOfSight = "LINE_OF_SIGHT"
capName CapRaycast = "RAYCAST"
capName CapWaypointGraph = "WAYPOINT_GRAPH"
capName CapSpawnRights = "SPAWN_RIGHTS"
capName CapAnimationHooks = "ANIMATION_HOOKS"
capName CapDamageEvents = "DAMAGE_EVENTS"
capName CapSoundEvents = "SOUND_EVENTS"
capName CapVehicleBoarding = "VEHICLE_BOARDING"
capName CapTerrainHeight = "TERRAIN_HEIGHT"

public export
statusName : Status -> String
statusName EeOk = "OK"
statusName EeBadParam = "BAD_PARAM"
statusName EeVersionMismatch = "VERSION_MISMATCH"
statusName EeFingerprintMismatch = "FINGERPRINT_MISMATCH"
statusName EeCapabilityUnsupported = "CAPABILITY_UNSUPPORTED"
statusName EeBufferTooSmall = "BUFFER_TOO_SMALL"
statusName EePanicCaught = "PANIC_CAUGHT"

public export
actionName : Action -> String
actionName ActIdle = "IDLE"
actionName ActAdvance = "ADVANCE"
actionName ActHold = "HOLD"
actionName ActFlee = "FLEE"
actionName ActAttack = "ATTACK"
actionName ActReload = "RELOAD"
actionName ActTakeCover = "TAKE_COVER"
actionName ActRegroup = "REGROUP"
actionName ActInvestigate = "INVESTIGATE"

public export
allCapabilities : List Capability
allCapabilities =
  [ CapNavmesh, CapLineOfSight, CapRaycast, CapWaypointGraph, CapSpawnRights
  , CapAnimationHooks, CapDamageEvents, CapSoundEvents, CapVehicleBoarding
  , CapTerrainHeight ]

public export
allStatuses : List Status
allStatuses =
  [ EeOk, EeBadParam, EeVersionMismatch, EeFingerprintMismatch
  , EeCapabilityUnsupported, EeBufferTooSmall, EePanicCaught ]

public export
allActions : List Action
allActions =
  [ ActIdle, ActAdvance, ActHold, ActFlee, ActAttack, ActReload
  , ActTakeCover, ActRegroup, ActInvestigate ]

--------------------------------------------------------------------------------
-- Struct-level metadata the generator needs
--------------------------------------------------------------------------------

||| C name, struct tag and field list, in the order the header emits them.
||| A record rather than a tuple so the generator cannot confuse the two strings.
public export
record Struct where
  constructor MkStruct
  sTag : String
  sFields : List (String, CType)

||| The seven structs frozen at ABI 1.0. `EE_ABI_FINGERPRINT` is computed over THESE
||| and nothing else, because a 1.0 host compiled `EE_ABI_FINGERPRINT` into its
||| binary and `ee_init` compares against it: a fingerprint that grew to cover the
||| 1.1 structs would refuse every 1.0 host, which is the opposite of additive.
public export
frozenStructs : List Struct
frozenStructs =
  [ MkStruct "ee_version" versionFields
  , MkStruct "ee_init_desc" initDescFields
  , MkStruct "ee_contact" contactFields
  , MkStruct "ee_snapshot" snapshotFields
  , MkStruct "ee_agent" agentFields
  , MkStruct "ee_intent" intentFields
  , MkStruct "ee_context" contextFields
  ]

||| The structs ABI 1.1 adds (ADR-0013). They carry their own fingerprint,
||| `EE_MIND_FINGERPRINT`, and each carries `struct_size`, which `ee_tick_mind` checks
||| on every call.
public export
mindStructs : List Struct
mindStructs =
  [ MkStruct "ee_mind" mindFields
  , MkStruct "ee_mind_trace" mindTraceFields
  ]

||| Every struct the header emits, frozen first, in emission order.
public export
allStructs : List Struct
allStructs = frozenStructs ++ mindStructs

||| The literal size list that `Abi.Layout` proves theorems about, paired with
||| the same struct, so `Abi.Gen` can cross-check named fields against proven
||| sizes without a lookup table.
public export
provenSizeLists : List (List Nat)
provenSizeLists =
  [ [2, 2, 2, 2]
  , [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8]
  , [2, 2, 2, 2, 4, 4]
  , [8, 4, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16, 16, 16, 16, 16, 16, 16, 4, 4]
  , [8, 8, 4, 4, 4, 4, 4, 4, 4, 4]
  , [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]
  , [4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8]
  , [4, 4, 8, 8, 4, 4, 4, 4, 4, 4, 2, 2, 1, 1, 1, 1]
  , [4, 4, 8, 4, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1]
  ]
