-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
||| Evil Weevil ABI v0 — the generator.
|||
||| Emits, from the type model in `Abi.Types`:
|||
|||   * `include/evil_weevil/ee.h`          — the C ABI every host compiles against
|||   * `src/interface/generated/ee_layout.zig` — the same numbers for Zig's comptime asserts
|||
||| and refuses to emit anything at all if the model is internally inconsistent.
|||
||| == Why this exists
|||
||| `Abi.Layout` proves offsets and sizes about LITERAL size lists, because Idris2
||| will not reduce a named constant in a proof position. The field lists in
||| `Abi.Types` are the human-maintained truth; the literal lists are the proven
||| ones. This program recomputes the sizes from the NAMED lists, compares them to
||| the DECLARED lists, and exits non-zero on any difference — so the two cannot
||| drift apart unnoticed. That check is the whole reason a generator is worth
||| having here rather than a hand-written header.
|||
||| Run: `just abi-gen` (or `just abi-check`, which regenerates and diffs).

module Abi.Gen

import Abi.Types
import Abi.Layout
import Data.List
import Data.String
import System
import System.File

%default total

--------------------------------------------------------------------------------
-- Rendering primitives
--------------------------------------------------------------------------------

||| A C type name for each model type. Total, so a new CType without a name here
||| is a compile error rather than a silent omission from the header.
cName : CType -> String
cName U8 = "uint8_t"
cName U16 = "uint16_t"
cName U32 = "uint32_t"
cName U64 = "uint64_t"
cName I32 = "int32_t"
cName I64 = "int64_t"
cName Fx = "ee_fx"
cName CVersion = "ee_version"
cName CContact = "ee_contact"

fieldDecl : (String, CType) -> String
fieldDecl (n, t) = "  " ++ cName t ++ " " ++ n ++ ";"

||| `#define EE_CAP_NAVMESH (1u << 0)` — the shift comes from `capBit`, so the
||| numbers in the header are the model's, never retyped.
capDefine : Capability -> String
capDefine c = "#define EE_CAP_" ++ capName c ++ " (1u << " ++ show (capBit c) ++ "u)"

||| The capability's MASK (1 << bit), which is what both files must carry: the C
||| header computes it with a shift, so the Zig constant has to be the same number,
||| not the bit index. Emitting the index here would compile, and would silently
||| mean something else in each language — the exact class of drift this file exists
||| to make impossible.
pow2 : Nat -> Nat
pow2 Z = 1
pow2 (S k) = 2 * pow2 k

capMask : Capability -> Nat
capMask c = pow2 (capBit c)

statusDefine : Status -> String
statusDefine s = "#define EE_STATUS_" ++ statusName s ++ " " ++ show (statusCode s)

actionDefine : Action -> String
actionDefine a = "#define EE_ACTION_" ++ actionName a ++ " " ++ show (actionCode a)

||| Intent flags, emitted rather than hand-copied. The Zig side used to declare its
||| own INTENT_FLAG_* constants with the same numbers typed in by hand, and the C
||| header had none at all — so a host could not name the bits it was being handed,
||| and the two languages could disagree without anything noticing. These are
||| bit VALUES (1, 2, 4, 8), not bit indices: `<<` is written into the header for
||| the reader's benefit and the value is what the kernel ors together.
intentFlagDefine : (String, Nat) -> String
intentFlagDefine (n, v) = "#define EE_INTENT_FLAG_" ++ n ++ " " ++ show v ++ "u"

intentFlagZigConst : (String, Nat) -> String
intentFlagZigConst (n, v) = "pub const INTENT_FLAG_" ++ n ++ ": u32 = " ++ show v ++ ";"

public export
allIntentFlags : List (String, Nat)
allIntentFlags =
  [ ("DEGRADED", intentFlagDegraded)
  , ("NEW_TARGET", intentFlagNewTarget)
  , ("UNREACHABLE", intentFlagUnreachable)
  , ("FROM_MEMORY", intentFlagFromMemory)
  , ("STARTLE", intentFlagStartle)
  , ("HESITATE", intentFlagHesitate)
  , ("FIXATE", intentFlagFixate)
  ]

||| Bits in `ee_agent.flags` — the agent's own state, as opposed to the intent it
||| just produced. Emitted for the same reason the intent flags are: a bit a host
||| cannot name is a bit a host cannot check.
agentFlagDefine : (String, Nat) -> String
agentFlagDefine (n, v) = "#define EE_AGENT_FLAG_" ++ n ++ " " ++ show v ++ "u"

agentFlagZigConst : (String, Nat) -> String
agentFlagZigConst (n, v) = "pub const AGENT_FLAG_" ++ n ++ ": u32 = " ++ show v ++ ";"

public export
allAgentFlags : List (String, Nat)
allAgentFlags = [ ("MEMORY_VALID", agentFlagMemoryValid) ]

||| The agent's mode field (ADR-0012): a shift, a mask and the codes that go in it.
||| Emitted because the mode IS on the wire — it lives in `ee_agent.flags`, which the
||| host owns and can inspect — unlike the margin that produces it, which is policy and
||| stays out of the header (ADR-0010 §3).
agentModeDefine : (String, Nat) -> String
agentModeDefine (n, v) = "#define EE_AGENT_MODE_" ++ n ++ " " ++ show v ++ "u"

agentModeZigConst : (String, Nat) -> String
agentModeZigConst (n, v) = "pub const AGENT_MODE_" ++ n ++ ": u32 = " ++ show v ++ ";"

public export
allAgentModes : List (String, Nat)
allAgentModes =
  [ ("SHIFT", agentModeShift)
  , ("MASK", agentModeMask)
  , ("ADVANCE", agentModeAdvance)
  , ("ENGAGE", agentModeEngage)
  , ("EVADE", agentModeEvade)
  , ("RELOAD", agentModeReload)
  , ("INVESTIGATE", agentModeInvestigate)
  ]

||| ABI 1.1 (ADR-0013): the names of the mind. Every list below is (NAME, value) and
||| becomes `#define EE_<PREFIX>_<NAME> <value>u` in C and `pub const <PREFIX>_<NAME>`
||| in Zig, so the two languages cannot disagree about a bit or a code. The constants
||| that make the mind BEHAVE (shifts, thresholds, gains) are not here: like the
||| utility weights and the mode margin, they are policy, and stay out of the header.
public export
mindConstGroups : List (String, String, List (String, Nat))
mindConstGroups =
  [ ( "CONTACT_FLAG"
    , "Bits in ee_contact.flags (ABI 1.1; read only by ee_tick_mind, with EE_CAP_DAMAGE_EVENTS)."
    , [ ("DAMAGE_SOURCE", contactFlagDamageSource) ] )
  , ( "TELL"
    , "Bits in ee_mind_trace.tells: the intent tell bits shifted down by four."
    , [ ("STARTLE", tellStartle), ("HESITATE", tellHesitate), ("FIXATE", tellFixate) ] )
  , ( "MIND_FLAG"
    , "Bits in ee_mind.flags."
    , [ ("PRIMED", mindFlagPrimed), ("GRUDGE_LEAD", mindFlagGrudgeLead)
      , ("HESITATED", mindFlagHesitated) ] )
  , ( "AFFECT"
    , "Affect tokens, in declaration (and tie-break) order: ee_mind.token, ee_mind_trace.token."
    , [ ("CALM", affectCalm), ("WARY", affectWary), ("AFRAID", affectAfraid)
      , ("ANGRY", affectAngry) ] )
  , ( "CAUSE"
    , "Why the affect token changed: ee_mind_trace.cause. NONE exactly when it did not."
    , [ ("NONE", causeNone), ("CLOSE_CONTACT", causeCloseContact), ("DAMAGE", causeDamage)
      , ("CONTRADICTION", causeContradiction), ("LOW_HEALTH", causeLowHealth)
      , ("THREATS", causeThreats), ("NO_AMMO", causeNoAmmo)
      , ("ATTRIBUTED_DAMAGE", causeAttributedDamage), ("DECAY", causeDecay) ] )
  , ( "MASS"
    , "Full scale of ee_mind_trace.attention, in units of 1/10000 (a mass, not a probability)."
    , [ ("FULL", massFull) ] )
  ]

mindGroupC : (String, String, List (String, Nat)) -> String
mindGroupC (pfx, comment, entries) =
  "/* " ++ comment ++ " */\n"
  ++ unlines (map (\(n, v) => "#define EE_" ++ pfx ++ "_" ++ n ++ " " ++ show v ++ "u") entries)
  ++ "\n"

mindGroupZig : (String, String, List (String, Nat)) -> List String
mindGroupZig (pfx, _, entries) =
  map (\(n, v) => "pub const " ++ pfx ++ "_" ++ n ++ ": u32 = " ++ show v ++ ";") entries

--------------------------------------------------------------------------------
-- Checksumming the layout
--------------------------------------------------------------------------------

||| Sum of each value times its 1-based position. Any change of value, or any
||| reordering, moves it; the growth is bounded by construction (values are field
||| sizes, so the total stays in the low millions).
weighted : Nat -> List Nat -> Nat
weighted i [] = 0
weighted i (v :: vs) = v * (i + 1) + weighted (S i) vs

flat : List (List Nat) -> List Nat
flat [] = []
flat (x :: xs) = x ++ flat xs

||| Every field size in a set of structs, in struct and field order.
sizesIn : List Struct -> List Nat
sizesIn sts = flat (map (sizesOf . sFields) sts)

||| The checksum formula, over any set of structs.
checksumOf : List Struct -> Nat
checksumOf sts =
  weighted 0 (sizesIn sts) * 1024
  + length (sizesIn sts) * 32
  + length sts

||| The ABI checksum: position-weighted sum of every field size, mixed with the
||| field count and the struct count.
|||
||| Two honest limitations, stated rather than discovered later:
|||
|||   * This is a DRIFT DETECTOR, not a cryptographic hash. It detects accidental
|||     divergence (a resized field, a reordered field, a dropped field) with no
|||     false negatives; it does not resist a deliberate collision, and nothing in
|||     ADR-0005 needs it to.
|||   * It is arithmetic on Nat with no modulus, bounded by construction. FNV-1a
|||     would be the conventional choice, but wrapping 64-bit multiply needs
|||     `Data.Bits`, and a modulus in Nat needs an `Integral Nat` instance that is
|||     not in scope here. A subtraction-based modulo is not an option either: it
|||     is O(value / modulus) and hangs for an hour on a 2^64 modulus (measured).
|||     Field names are deliberately NOT included: renaming a field does not change
|||     the wire format, so it must not change the checksum.
|||
||| ABI 1.1 (ADR-0013): computed over `frozenStructs` — the seven 1.0 structs — and
||| NOT over `allStructs`. A 1.0 host compiled this number into its binary and
||| `ee_init` refuses a mismatch, so covering the 1.1 structs here would refuse every
||| 1.0 host: the opposite of additive. The value is still 18276775.
layoutChecksum : Nat
layoutChecksum = checksumOf frozenStructs

||| The same drift detector over the structs 1.1 added. A host that uses
||| `ee_tick_mind` can compare `ee_mind_fingerprint()` against `EE_MIND_FINGERPRINT`.
mindChecksum : Nat
mindChecksum = checksumOf mindStructs

--------------------------------------------------------------------------------
-- Cross-checks — nothing is emitted until these pass
--------------------------------------------------------------------------------

||| Everything that can make this generator refuse to write.
|||
||| A sum type rather than a tuple: the two failures are different kinds of
||| mistake with different fixes, and a tuple would have forced the stride failure
||| to be reported as though a field list were at fault.
public export
data GenError
  = ||| The named field list and the proven size list disagree for this struct.
    SizeMismatch String (List Nat) (List Nat)
  | ||| The struct's size is not a whole number of alignment units, so arrays of it
    ||| would step past the end of each element.
    UnsafeStride String Nat

checkOne : (Struct, List Nat) -> Either GenError (Struct, List Nat)
checkOne (st, declared) =
  let computed = sizesOf (sFields st)
  in if computed /= declared
        then Left (SizeMismatch (sTag st) computed declared)
        else if strideEqSize structAlignUnit computed
               then Right (st, computed)
               else Left (UnsafeStride (sTag st) (totalOf computed))

||| Every struct, checked, with its computed sizes.
export
checkedStructs : Either GenError (List (Struct, List Nat))
checkedStructs = traverse checkOne (zip allStructs provenSizeLists)

--------------------------------------------------------------------------------
-- The C header
--------------------------------------------------------------------------------

layoutDefines : (Struct, List Nat) -> List String
layoutDefines (st, sizes) =
  [ "#define EE_SIZEOF_" ++ sTag st ++ " " ++ show (totalOf sizes) ]
  ++ zipWith (\f, o => "#define EE_OFFSET_" ++ sTag st ++ "_" ++ fst f
                       ++ " " ++ show o) (sFields st) (offsetsOf sizes)

||| Asserts the DECLARED layout is the REAL one, per compiler. This is the layer
||| that turns "we intend these offsets" into "this compiler produced them".
staticAsserts : (Struct, List Nat) -> List String
staticAsserts (st, sizes) =
  [ "EE_STATIC_ASSERT(sizeof(" ++ sTag st ++ ") == EE_SIZEOF_" ++ sTag st ++ ", \"size\");" ]
  ++ map (\(n, _) => "EE_STATIC_ASSERT(offsetof(" ++ sTag st ++ ", " ++ n
                     ++ ") == EE_OFFSET_" ++ sTag st ++ "_" ++ n ++ ", \"offset\");")
         (sFields st)

||| One struct: the typedef, then the size/offset defines it is checked against.
||| The sizes come from the same tuple the cross-check validated, so a struct whose
||| sizes were not checked cannot be emitted.
structBlock : (Struct, List Nat) -> String
structBlock (st, sizes) =
  unlines ( [ "typedef struct {" ]
            ++ map fieldDecl (sFields st)
            ++ [ "} " ++ sTag st ++ ";", "" ]
            ++ layoutDefines (st, sizes) )

cVersionNum : Version -> String
cVersionNum v = show (major v)

cVersionMinor : Version -> String
cVersionMinor v = show (minor v)

headerPreamble : String
headerPreamble =
  unlines
    [ "/* SPDX-License-Identifier: MPL-2.0 */"
    , "/*"
    , " * ee.h — the Evil Weevil C ABI, version " ++ cVersionNum abiVersion ++ "."
    , " *"
    , " * GENERATED FILE — DO NOT EDIT BY HAND."
    , " * Source of truth: src/interface/Abi/Types.idr (field lists)."
    , " * Layout proofs:   src/interface/Abi/Layout.idr."
    , " * Regenerate:       just abi-gen"
    , " * Verify in CI:     just abi-check   (regenerates and diffs)"
    , " *"
    , " * The _Static_asserts below check the declared layout against what THIS"
    , " * compiler actually produces. If they fire, the ABI changed — read ADR-0005"
    , " * before touching anything: bumping the major version is a new ADR, and an"
    , " * adapter written against a moving header is the one mistake that sinks the"
    , " * 'universally injectable' claim."
    , " *"
    , " * No pointer-sized FIELD appears in any struct here; pointers are function"
    , " * parameters only (ADR-0005 §1). That keeps the layout identical across"
    , " * 64-bit targets and keeps host addresses out of deterministic state."
    , " * 32-bit hosts, including wasm32, are NOT supported by this layout and get a"
    , " * distinct, separately-proved ABI in Phase 4."
    , " */"
    , ""
    , "#ifndef EVIL_WEVIL_EE_H"
    , "#define EVIL_WEVIL_EE_H"
    , ""
    , "#include <stdint.h>"
    , "#include <stddef.h>"
    , ""
    , "#if defined(__cplusplus)"
    , "#define EE_STATIC_ASSERT(c, m) static_assert(c, m)"
    , "extern \"C\" {"
    , "#else"
    , "#define EE_STATIC_ASSERT(c, m) _Static_assert(c, m)"
    , "#endif"
    , ""
    , "#define EE_ABI_MAJOR " ++ cVersionNum abiVersion
    , "#define EE_ABI_MINOR " ++ cVersionMinor abiVersion
    , "#define EE_ABI_FINGERPRINT " ++ show layoutChecksum ++ "ULL"
    , "/* ABI 1.1: the fingerprint of ee_mind and ee_mind_trace only (ADR-0013). */"
    , "#define EE_MIND_FINGERPRINT " ++ show mindChecksum ++ "ULL"
    , ""
    , "/* Q16.16 fixed point: all kernel arithmetic is integer (ADR-0006). */"
    , "#define EE_FX_FRACTION_BITS " ++ show fxFractionBits
    , "#define EE_FX_ONE " ++ show fxOne
    , "typedef int32_t ee_fx;"
    , ""
    ]

entryPoints : String
entryPoints =
  unlines
    [ "/*"
    , " * Entry points. The kernel performs NO allocation: `ee_context` and the"
    , " * `ee_agent` array are host-owned storage whose size is fixed by this header"
    , " * (ADR-0005 §4). `ee_init` validates struct_size, the major version and the"
    , " * fingerprint, and answers every mismatch with a status code rather than"
    , " * throwing or aborting the host (ADR-0005 §3)."
    , " *"
    , " * `ee_tick` is PURE with respect to the host: it reads the snapshot and the"
    , " * agent, writes the agent and returns an intent. It never calls back into the"
    , " * host mid-tick (ADR-0004), and its result depends only on its arguments and"
    , " * the context — which is what makes replays bit-exact (ADR-0006)."
    , " */"
    , "ee_status ee_init(const ee_init_desc *desc, ee_context *ctx);"
    , "ee_status ee_tick(ee_context *ctx, const ee_snapshot *snap, ee_agent *agent, ee_intent *out);"
    , "ee_version ee_version_info(void);"
    , "uint64_t ee_abi_fingerprint(void);"
    , "const char *ee_status_name(ee_status status);"
    , ""
    , "/*"
    , " * ABI 1.1 (ADR-0013): the mind. A host that never calls this gets 1.0 exactly:"
    , " * `ee_tick` is unchanged and its pinned digests did not move."
    , " *"
    , " * `mind` is caller-owned per-agent state (zeroed, `struct_size` set). `trace` may"
    , " * be NULL; when it is not, its `struct_size` must be set and one record is written."
    , " * The trace publishes a RANKING of modes and the selected mode — never a score —"
    , " * and an affect TOKEN with an attention mass — never a reservoir value."
    , " */"
    , "ee_status ee_tick_mind(ee_context *ctx, const ee_snapshot *snap, ee_agent *agent,"
    , "                       ee_mind *mind, ee_intent *out, ee_mind_trace *trace);"
    , "uint64_t ee_mind_fingerprint(void);"
    , ""
    , "#if defined(__cplusplus)"
    , "}"
    , "#endif"
    , ""
    , "#endif /* EVIL_WEVIL_EE_H */"
    ]

|||| Render the whole header.
export
renderHeader : Either GenError String
renderHeader =
  case checkedStructs of
    Left e => Left e
    Right sts =>
      Right (headerPreamble
             ++ unlines (map capDefine allCapabilities)
             ++ "\n"
             ++ unlines (map statusDefine allStatuses)
             ++ "\n/* Every entry point returns one of these; the codes above are its values. */\n"
             ++ "typedef uint32_t ee_status;\n\n"
             ++ unlines (map actionDefine allActions)
             ++ "\n/* Bits in ee_intent.flags. */\n"
             ++ unlines (map intentFlagDefine allIntentFlags)
             ++ "\n/* Bits in ee_agent.flags. */\n"
             ++ unlines (map agentFlagDefine allAgentFlags)
             ++ "\n/* The mode field inside ee_agent.flags: bits 1..3 (ADR-0012). */\n"
             ++ unlines (map agentModeDefine allAgentModes)
             ++ "\n"
             ++ "/* Ticks a sighting stays actionable before the agent forgets it (Phase 2). */\n"
             ++ "#define EE_MEMORY_TTL " ++ show memoryTtl ++ "u\n\n"
             ++ concatMap mindGroupC mindConstGroups
             ++ unlines (map structBlock sts)
             ++ unlines (concatMap staticAsserts sts)
             ++ "\n"
             ++ entryPoints)

--------------------------------------------------------------------------------
-- The Zig constants
--------------------------------------------------------------------------------

zigPreamble : String
zigPreamble =
  unlines
    ( [ "// SPDX-License-Identifier: MPL-2.0"
      , "//"
      , "// GENERATED FILE — DO NOT EDIT BY HAND."
      , "// Emitted by Abi.Gen from the same model as include/evil_weevil/ee.h."
      , "// Regenerate: just abi-gen    Verify: just abi-check"
      , "//"
      , "// The Zig kernel asserts its own @sizeOf/@offsetOf against these at comptime,"
      , "// so a struct that drifts from the C ABI fails the BUILD rather than corrupting"
      , "// a host's memory at runtime."
      , ""
      , "pub const abi_major: u32 = " ++ cVersionNum abiVersion ++ ";"
      , "pub const abi_minor: u32 = " ++ cVersionMinor abiVersion ++ ";"
      , "pub const abi_fingerprint: u64 = " ++ show layoutChecksum ++ ";"
      , "pub const mind_fingerprint: u64 = " ++ show mindChecksum ++ ";"
      , "pub const fx_fraction_bits: u32 = " ++ show fxFractionBits ++ ";"
      , "pub const fx_one: i32 = " ++ show fxOne ++ ";"
      , ""
      , "// Capability bits, status codes and action codes — the same numbers the C"
      , "// header defines, emitted from the same model so the two cannot disagree."
      ]
      ++ map (\c => "pub const CAP_" ++ capName c ++ ": u32 = " ++ show (capMask c)
                 ++ "; // bit " ++ show (capBit c)) allCapabilities
      ++ [ "" ]
      ++ map (\c => "pub const STATUS_" ++ statusName c ++ ": u32 = " ++ show (statusCode c) ++ ";") allStatuses
      ++ [ "" ]
      ++ map (\c => "pub const ACTION_" ++ actionName c ++ ": u32 = " ++ show (actionCode c) ++ ";") allActions
      ++ [ "" ]
      ++ map intentFlagZigConst allIntentFlags
      ++ map agentFlagZigConst allAgentFlags
      ++ map agentModeZigConst allAgentModes
      ++ [ "pub const memory_ttl: u32 = " ++ show memoryTtl ++ ";" ]
      ++ concatMap mindGroupZig mindConstGroups
      ++ [ "" ] )

zigStruct : (Struct, List Nat) -> List String
zigStruct (st, sizes) =
  [ "pub const sizeof_" ++ sTag st ++ ": usize = " ++ show (totalOf sizes) ++ ";" ]
  ++ zipWith (\f, o => "pub const offset_" ++ sTag st ++ "_" ++ fst f ++ ": usize = " ++ show o ++ ";")
             (sFields st) (offsetsOf sizes)

export
renderZig : Either GenError String
renderZig =
  case checkedStructs of
    Left e => Left e
    Right sts =>
      Right (zigPreamble ++ unlines (concatMap zigStruct sts))

--------------------------------------------------------------------------------
-- Driving it
--------------------------------------------------------------------------------

reportMismatch : GenError -> IO ()
reportMismatch (SizeMismatch name computed declared) = do
  putStrLn ("ABI MODEL MISMATCH in " ++ name)
  putStrLn ("  field list computes to: " ++ show computed)
  putStrLn ("  declared (and proven):  " ++ show declared)
  putStrLn "  The proven literal list and the named field list must agree."
  die "  Fix Abi.Types (both lists), then re-run. Nothing was written."

reportMismatch (UnsafeStride name size) = do
  putStrLn ("UNSAFE STRIDE in " ++ name ++ " (" ++ show size ++ " bytes)")
  putStrLn ("  Not a whole number of alignment units (" ++ show structAlignUnit ++ "),")
  putStrLn "  so an array of these would step past the end of each element."
  putStrLn "  Add or resize padding fields until the size is a multiple of 8."
  die "  Fix Abi.Types (the padding), then re-run. Nothing was written."

writeOrDie : String -> String -> IO ()
writeOrDie path body =
  case !(writeFile path body) of
    Right () => putStrLn ("  wrote " ++ path ++ " (" ++ show (length body) ++ " bytes)")
    Left err => do
      putStrLn ("FAILED to write " ++ path)
      die (show err)

||| One line per struct, so `abi-gen` reports the shape it just laid down.
structSummary : (Struct, List Nat) -> String
structSummary (st, sizes) =
  "    " ++ sTag st ++ ": " ++ show (totalOf sizes) ++ " bytes, "
  ++ show (length (sFields st)) ++ " fields, "
  ++ show (length (offsetsOf sizes)) ++ " offset defines"

structSummaries : List (Struct, List Nat) -> String
structSummaries [] = ""
structSummaries (x :: xs) = structSummary x ++ "\n" ++ structSummaries xs

export
main : IO ()
main = do
  args <- getArgs
  let root = case args of
               (_ :: r :: _) => r
               _ => "."
  putStrLn "ee abi-gen — generating the seam from Abi.Types"
  putStrLn ("  abi version:   " ++ cVersionNum abiVersion ++ "." ++ cVersionMinor abiVersion)
  putStrLn ("  fingerprint:   " ++ show layoutChecksum)
  putStrLn ("  mind (1.1):    " ++ show mindChecksum)
  case (renderHeader, renderZig) of
    (Left m, _) => reportMismatch m
    (_, Left m) => reportMismatch m
    (Right hdr, Right zg) => do
      writeOrDie (root ++ "/include/evil_weevil/ee.h") hdr
      writeOrDie (root ++ "/src/interface/generated/ee_layout.zig") zg
      putStrLn "  structs:"
      case checkedStructs of
        Left _ => pure ()
        Right sts => putStrLn (structSummaries sts)
      putStrLn "done. Now compile C and Zig against it: just kernel-build"
