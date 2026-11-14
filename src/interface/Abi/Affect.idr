-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
||| Evil Weevil ABI 1.1 — the mind: affect and volition (mind slice 1, ADR-0013).
|||
||| The specification of the code below the `ABI 1.1 — THE MIND` line in
||| `src/core/kernel.zig`. Three reservoirs (arousal, fear, grievance), an affect token
||| with a cause, a commitment margin that grievance widens, and the three bodily tells.
||| The kernel implements what is written here; four pinned digests per host make a
||| divergence loud, as for every other module of the seam.
|||
||| == The four rules this module exists to make checkable
|||
||| 1. Integer only. Every quantity here is a `Nat`; the kernel's are u32.
||| 2. AFFECT BUYS ATTENTION, NEVER BELIEF. A reservoir changes how long a lead is
|||    followed (`ttlFor`), how readily a commitment is held (`mindMargin`), how evade
|||    ranks (`mindScore`) and what the body does. It never writes a bearing: the lead a
|||    sighting writes is the same whatever the reservoirs hold
|||    (`sightingIgnoresAffect`), and without a sighting a lead keeps its bearing or is
|||    cleared — it is never given a new one (`leadNeverInventsABearing`).
||| 3. Scores never leave the kernel. The trace publishes `rankModes`, an ORDER; this
|||    module's scores are not emitted into `ee.h`, exactly like `Abi.Utility`'s.
||| 4. A token change has a cause (`tokenChangeHasCause`), and an unchanged token has
|||    none (`tokenKeptHasNoCause`). Both are GENERAL theorems, not instances.
|||
||| == What is proved in general, and what is pinned by instance
|||
||| General (for every input): reservoirs stay in [0, full]; the leak with no input is
||| monotone non-increasing AND strictly decreasing above zero, so a reservoir with no
||| input reaches zero; token change iff cause; grievance zero gives the 1.0 margin;
||| no damage capability keeps grievance at zero; attention never exceeds full mass.
|||
||| By instance (the moments the fixtures are built on): the grudge holds a pursuit
||| against an easier target, a calm agent releases it, the grudge never holds against
||| flight or reload, fear breaks the wounded duel. The convention is the one
||| `Abi.Memory` records: prove what reduces in general; pin the rest by instance and by
||| digest; say which is which.

module Abi.Affect

import Abi.Types
import Abi.Utility
import Abi.Modes
import Data.Maybe
import Data.Nat
import Data.So

%default total

--------------------------------------------------------------------------------
-- The constants (policy, not ABI: none of these is in ee.h)
--------------------------------------------------------------------------------
-- Each is the kernel's constant of the same name. The leak shifts are written as the
-- divisor 2^k, because the model divides and the kernel shifts.

public export
full : Nat
full = 65536

||| 2^5: arousal half-life about 22 ticks.
public export
arousalLeakDiv : Nat
arousalLeakDiv = 32

||| 2^4: fear half-life about 11 ticks.
public export
fearLeakDiv : Nat
fearLeakDiv = 16

||| 2^8: grievance half-life about 177 ticks — about five times `memoryTtl`.
public export
grievanceLeakDiv : Nat
grievanceLeakDiv = 256

public export
tokenEnter : Nat
tokenEnter = 16384

public export
tokenBand : Nat
tokenBand = 4096

||| Memory lifetime gains arousal / 2048 ticks: at most 32.
public export
arousalTtlDiv : Nat
arousalTtlDiv = 2048

||| Evade gains fear / 16: at most 4096.
public export
fearEvadeDiv : Nat
fearEvadeDiv = 16

||| A pursuit's margin gains grievance / 4: at most 16384.
public export
grievanceMarginDiv : Nat
grievanceMarginDiv = 4

--------------------------------------------------------------------------------
-- Small order lemmas (this base has no lteRefl/lteSuccRight: see the MANIFEST)
--------------------------------------------------------------------------------

export
lteSelf : (n : Nat) -> LTE n n
lteSelf Z = LTEZero
lteSelf (S k) = LTESucc (lteSelf k)

export
lteStepRight : LTE a b -> LTE a (S b)
lteStepRight LTEZero = LTEZero
lteStepRight (LTESucc p) = LTESucc (lteStepRight p)

export
lteChain : LTE a b -> LTE b c -> LTE a c
lteChain LTEZero _ = LTEZero
lteChain (LTESucc p) (LTESucc q) = LTESucc (lteChain p q)

||| `lte` said no, so the order is the other way round.
export
lteFalseFlips : (a, b : Nat) -> lte a b = False -> LTE b a
lteFalseFlips Z _ Refl impossible
lteFalseFlips (S a) Z _ = LTEZero
lteFalseFlips (S a) (S b) prf = LTESucc (lteFalseFlips a b prf)

||| Saturating subtraction never grows.
export
minusShrinks : (a, b : Nat) -> LTE (minus a b) a
minusShrinks Z _ = LTEZero
minusShrinks (S k) Z = lteSelf (S k)
minusShrinks (S k) (S j) = lteStepRight (minusShrinks k j)

--------------------------------------------------------------------------------
-- The clamp and the leaky integrator
--------------------------------------------------------------------------------

||| `v` if it fits under `cap`, otherwise `cap`. Written with the Boolean `lte` rather
||| than the decision `isLTE`: both are provable from, but `isLTE` builds a unary proof
||| term on a literal like 65536 and `lte` does not (measured: `isLTE` stalls the
||| instance theorems below, `lte` checks them in about a second).
public export
clampTo : (cap, v : Nat) -> Nat
clampTo cap v = if lte v cap then v else cap

export
clampInRange : (cap, v : Nat) -> LTE (clampTo cap v) cap
clampInRange cap v with (lte v cap) proof p
  clampInRange cap v | True = lteReflectsLTE v cap p
  clampInRange cap v | False = lteSelf cap

export
clampNeverGrows : (cap, v : Nat) -> LTE (clampTo cap v) v
clampNeverGrows cap v with (lte v cap) proof p
  clampNeverGrows cap v | True = lteSelf v
  clampNeverGrows cap v | False = lteFalseFlips v cap p

||| Division in the model goes through `Integer`, whose primitive `div` reduces on a
||| literal at once. `Nat`'s `div` does not: `divNatNZ 65536 2048` ran ten minutes
||| without an answer (measured), so no theorem stated with it could ever be checked.
||| The kernel's `x >> k` is this with d = 2^k.
public export
idiv : (n, d : Nat) -> Nat
idiv n d = integerToNat (div (natToInteger n) (natToInteger d))

||| The leak, rounding UP: ceil(x / d) for x > 0, and nothing from nothing. Written as
||| `S (idiv k d)` on `S k` — that IS ceil((k + 1) / d) — so "every non-empty reservoir
||| loses at least one unit" is visible in the shape of the definition and needs no
||| lemma about division at all.
|||
||| The brief specified `x - (x >> k)`, which FLOORS. A floored leak stalls: any
||| x < 2^k satisfies x >> k = 0 and never drains, so a grievance of 255 would widen
||| the margin for the rest of the game, and "with grievance zero the margin is 1.0's"
||| would be true of a state the agent never returns to. ADR-0013 §3 records the
||| departure.
public export
leak : (d : Nat) -> Nat -> Nat
leak d Z = Z
leak d (S k) = S (idiv k d)

||| One step of a leaky integrator: leak, add the input, clamp to [0, full]. (The kernel
||| also clamps the state on the way IN, against a host that wrote garbage; for a state
||| already in range that clamp is the identity, and the range theorem below is what
||| keeps the state in range.)
public export
integrate : (d : Nat) -> (x, input : Nat) -> Nat
integrate d x input = clampTo Abi.Affect.full (minus x (leak d x) + input)

||| RESERVOIRS STAY IN RANGE: whatever the state and whatever the input.
export
integrateInRange : (d, x, input : Nat) -> LTE (integrate d x input) Abi.Affect.full
integrateInRange d x input = clampInRange Abi.Affect.full (minus x (leak d x) + input)

||| THE LEAK IS MONOTONE TOWARD ZERO WITH NO INPUT: it never grows...
export
leakNeverGrows : (d, x : Nat) -> LTE (integrate d x 0) x
leakNeverGrows d x =
  rewrite plusZeroRightNeutral (minus x (leak d x)) in
  lteChain (clampNeverGrows Abi.Affect.full (minus x (leak d x)))
           (minusShrinks x (leak d x))

||| ...and it strictly shrinks every non-empty reservoir, so after at most x ticks with
||| no input the reservoir is zero. (This is the property the floored form lacks.)
export
leakStrictlyShrinks : (d, k : Nat) -> LT (integrate d (S k) 0) (S k)
leakStrictlyShrinks d k =
  rewrite plusZeroRightNeutral (minus k (idiv k d)) in
  LTESucc (lteChain (clampNeverGrows Abi.Affect.full (minus k (idiv k d)))
                    (minusShrinks k (idiv k d)))

||| Zero stays zero with no input.
export
zeroStaysZero : (d : Nat) -> integrate d 0 0 = 0
zeroStaysZero d = Refl

--------------------------------------------------------------------------------
-- Grievance needs the damage capability
--------------------------------------------------------------------------------

||| The grievance input: attributed damage times four, and nothing at all unless the host
||| declared `EE_CAP_DAMAGE_EVENTS`.
public export
grievanceInput : (capDamageEvents : Bool) -> (damage : Nat) -> Nat
grievanceInput False _ = 0
grievanceInput True dmg = clampTo Abi.Affect.full (dmg * 4)

public export
grievanceStep : (capDamageEvents : Bool) -> (grievance, damage : Nat) -> Nat
grievanceStep cap g dmg = integrate Abi.Affect.grievanceLeakDiv g (grievanceInput cap dmg)

||| DEGRADE, DO NOT ABORT: without the capability, grievance that starts at zero stays at
||| zero whatever damage arrives — so by induction it stays zero for the whole run.
export
noCapabilityNoGrievance : (damage : Nat) -> grievanceStep False 0 damage = 0
noCapabilityNoGrievance damage = Refl

--------------------------------------------------------------------------------
-- Attention: memory lifetime, and the attention mass on the trace
--------------------------------------------------------------------------------

||| How long a lead is followed. Arousal lengthens it; it never shortens it.
public export
ttlFor : (arousal : Nat) -> Nat
ttlFor a = Abi.Types.memoryTtl + idiv a Abi.Affect.arousalTtlDiv

||| At rest the lifetime IS the frozen 1.0 TTL.
export
calmTtlIsTheFrozenTtl : ttlFor 0 = Abi.Types.memoryTtl
calmTtlIsTheFrozenTtl = Refl

||| And at full arousal it is 68 ticks — the bound ADR-0013 states.
export
fullArousalTtl : ttlFor 65536 = 68
fullArousalTtl = Refl

||| Arousal never shortens the lifetime.
export
arousalNeverShortensMemory : (a : Nat) -> LTE Abi.Types.memoryTtl (ttlFor a)
arousalNeverShortensMemory a = lteAddRight Abi.Types.memoryTtl

||| The attention mass on the trace: the level as a fraction of 10 000, clamped. The
||| product is formed in `Integer`: a `Nat` product of 65536 and 10000 is a unary number
||| the type checker runs out of memory building (measured).
public export
massOf : (level : Nat) -> Nat
massOf l = clampTo Abi.Types.massFull
                   (integerToNat (div (natToInteger l * 10000) 65536))

export
massInRange : (l : Nat) -> LTE (massOf l) Abi.Types.massFull
massInRange l = clampInRange Abi.Types.massFull
                             (integerToNat (div (natToInteger l * 10000) 65536))

export
fullReservoirIsFullMass : massOf 65536 = 10000
fullReservoirIsFullMass = Refl

--------------------------------------------------------------------------------
-- What affect may not do: write a belief
--------------------------------------------------------------------------------

||| A sighting: the bearing perception reports for a contact this tick.
public export
record Sighting where
  constructor MkSighting
  sightCos : Nat
  sightSin : Nat

||| A lead: a remembered bearing and its age. The grudge slot is one; `Abi.Memory`'s
||| memory is the other.
public export
record Lead where
  constructor MkLead
  leadValid : Bool
  leadCos   : Nat
  leadSin   : Nat
  leadAge   : Nat

public export
noLead : Lead
noLead = MkLead False 0 0 0

||| One tick of a lead's bookkeeping. The ONLY affect-dependent argument is `ttl`, the
||| lifetime — which is attention. A sighting writes what was seen; no sighting ages the
||| lead and forgets it at the lifetime, clearing the payload (as `Abi.Memory` does).
public export
stepLead : (ttl : Nat) -> Maybe Sighting -> Lead -> Lead
stepLead ttl (Just s) _ = MkLead True (sightCos s) (sightSin s) 0
stepLead ttl Nothing l =
  if leadValid l
     then (if S (leadAge l) < ttl then MkLead True (leadCos l) (leadSin l) (S (leadAge l))
                                  else noLead)
     else l

||| AFFECT NEVER WRITES A BELIEF, part 1: what a sighting writes is the same whatever
||| arousal is — for every pair of arousal levels, every sighting, every prior lead.
export
sightingIgnoresAffect :
  (a1, a2 : Nat) -> (s : Sighting) -> (l : Lead) ->
  stepLead (ttlFor a1) (Just s) l = stepLead (ttlFor a2) (Just s) l
sightingIgnoresAffect a1 a2 s l = Refl

||| A lead's bearing, as a pair.
public export
bearingOf : Lead -> (Nat, Nat)
bearingOf l = (leadCos l, leadSin l)

||| AFFECT NEVER WRITES A BELIEF, part 2: without a sighting, whatever the lifetime, the
||| lead keeps the bearing it had or is cleared. It is never given a bearing nobody saw.
export
leadNeverInventsABearing :
  (ttl : Nat) -> (l : Lead) ->
  Either (bearingOf (stepLead ttl Nothing l) = bearingOf l)
         (bearingOf (stepLead ttl Nothing l) = (0, 0))
leadNeverInventsABearing ttl (MkLead False c s a) = Left Refl
leadNeverInventsABearing ttl (MkLead True c s a) with (S a < ttl)
  leadNeverInventsABearing ttl (MkLead True c s a) | True = Left Refl
  leadNeverInventsABearing ttl (MkLead True c s a) | False = Right Refl

--------------------------------------------------------------------------------
-- The affect token, and its cause
--------------------------------------------------------------------------------

public export
data Token = Calm | Wary | Afraid | Angry

public export
tokenCode : Token -> Nat
tokenCode Calm = 0
tokenCode Wary = 1
tokenCode Afraid = 2
tokenCode Angry = 3

public export
eqToken : Token -> Token -> Bool
eqToken Calm Calm = True
eqToken Wary Wary = True
eqToken Afraid Afraid = True
eqToken Angry Angry = True
eqToken _ _ = False

export
tokensMatchTheWire :
  (tokenCode Calm, tokenCode Wary, tokenCode Afraid, tokenCode Angry)
  = (Abi.Types.affectCalm, Abi.Types.affectWary, Abi.Types.affectAfraid, Abi.Types.affectAngry)
tokensMatchTheWire = Refl

||| The token for three levels, given the token the tick opened with: the highest
||| reservoir, the incumbent's boosted by the band, the earliest among equals, and calm
||| unless the winner reaches `tokenEnter`. Enter at 0.25, exit below 0.1875.
public export
tokenOf : (arousal, fear, grievance : Nat) -> (prev : Token) -> Token
tokenOf a f g prev =
  let sa = a + (if eqToken prev Wary then Abi.Affect.tokenBand else 0)
      sf = f + (if eqToken prev Afraid then Abi.Affect.tokenBand else 0)
      sg = g + (if eqToken prev Angry then Abi.Affect.tokenBand else 0)
      (t1, b1) = (if sa > 0 then (Wary, sa) else (Calm, 0))
      (t2, b2) = (if sf > b1 then (Afraid, sf) else (t1, b1))
      (t3, b3) = (if sg > b2 then (Angry, sg) else (t2, b2))
  in if b3 >= Abi.Affect.tokenEnter then t3 else Calm

||| The causes a CHANGE of token can have. There is no "none" here on purpose: a change
||| cannot be given a cause that is not one.
public export
data ChangeCause
  = CloseContact | Damage | Contradiction | LowHealth | Threats | NoAmmo
  | AttributedDamage | Decay

public export
changeCode : ChangeCause -> Nat
changeCode CloseContact = 1
changeCode Damage = 2
changeCode Contradiction = 3
changeCode LowHealth = 4
changeCode Threats = 5
changeCode NoAmmo = 6
changeCode AttributedDamage = 7
changeCode Decay = 8

export
causesMatchTheWire :
  the (List Nat)
    [ changeCode CloseContact, changeCode Damage, changeCode Contradiction
    , changeCode LowHealth, changeCode Threats, changeCode NoAmmo
    , changeCode AttributedDamage, changeCode Decay ]
  = [ Abi.Types.causeCloseContact, Abi.Types.causeDamage, Abi.Types.causeContradiction
    , Abi.Types.causeLowHealth, Abi.Types.causeThreats, Abi.Types.causeNoAmmo
    , Abi.Types.causeAttributedDamage, Abi.Types.causeDecay ]
causesMatchTheWire = Refl

||| No change cause is coded as `EE_CAUSE_NONE` (0).
export
changeCodeIsNeverNone : (c : ChangeCause) -> IsSucc (changeCode c)
changeCodeIsNeverNone CloseContact = ItIsSucc
changeCodeIsNeverNone Damage = ItIsSucc
changeCodeIsNeverNone Contradiction = ItIsSucc
changeCodeIsNeverNone LowHealth = ItIsSucc
changeCodeIsNeverNone Threats = ItIsSucc
changeCodeIsNeverNone NoAmmo = ItIsSucc
changeCodeIsNeverNone AttributedDamage = ItIsSucc
changeCodeIsNeverNone Decay = ItIsSucc

||| One tick's inputs, by reservoir, in declaration order — the order ties are broken in.
public export
record Inputs where
  constructor MkInputs
  inClose        : Nat
  inDamage       : Nat
  inContradiction : Nat
  inLowHealth    : Nat
  inThreats      : Nat
  inNoAmmo       : Nat
  inAttributed   : Nat

||| The earliest of three strictly largest positive inputs, or decay if all are zero.
largestOf3 : (Nat, ChangeCause) -> (Nat, ChangeCause) -> (Nat, ChangeCause) -> ChangeCause
largestOf3 (v1, c1) (v2, c2) (v3, c3) =
  let (b1, k1) = (if v1 > 0 then (v1, c1) else (0, Decay))
      (b2, k2) = (if v2 > b1 then (v2, c2) else (b1, k1))
  in if v3 > b2 then c3 else k2

||| The cause of a change TO `now`: the largest input to the reservoir `now` names, or
||| decay when that reservoir got no input or `now` is calm.
public export
changeCauseFor : Token -> Inputs -> ChangeCause
changeCauseFor Calm _ = Decay
changeCauseFor Wary i =
  largestOf3 (inClose i, CloseContact) (inDamage i, Damage) (inContradiction i, Contradiction)
changeCauseFor Afraid i =
  largestOf3 (inLowHealth i, LowHealth) (inThreats i, Threats) (inNoAmmo i, NoAmmo)
changeCauseFor Angry i = if inAttributed i > 0 then AttributedDamage else Decay

||| The cause on the trace: nothing when the token did not change, a change cause when it
||| did.
public export
causeFor : (prev, now : Token) -> Inputs -> Maybe ChangeCause
causeFor prev now i = if eqToken prev now then Nothing else Just (changeCauseFor now i)

||| The wire code of a trace cause: `EE_CAUSE_NONE` for nothing.
public export
causeWire : Maybe ChangeCause -> Nat
causeWire Nothing = Abi.Types.causeNone
causeWire (Just c) = changeCode c

||| A TOKEN CHANGE IMPLIES A RECORDED CAUSE — for every pair of tokens and every input.
export
tokenChangeHasCause :
  (prev, now : Token) -> (i : Inputs) -> eqToken prev now = False -> IsJust (causeFor prev now i)
tokenChangeHasCause prev now i changed = rewrite changed in ItIsJust

||| ...and the converse: a token that did not change carries no cause.
export
tokenKeptHasNoCause :
  (prev, now : Token) -> (i : Inputs) -> eqToken prev now = True -> causeFor prev now i = Nothing
tokenKeptHasNoCause prev now i kept = rewrite kept in Refl

||| Together, on the wire: a changed token's cause is never coded as NONE.
export
changedTokenCauseIsNotNone :
  (prev, now : Token) -> (i : Inputs) -> eqToken prev now = False ->
  IsSucc (causeWire (causeFor prev now i))
changedTokenCauseIsNotNone prev now i changed =
  rewrite changed in changeCodeIsNeverNone (changeCauseFor now i)

-- The token's hysteresis, by instance.

||| Calm at rest; wary at the startle level; and a wary agent stays wary at 0.19, where a
||| calm one would not become wary — the band.
export
tokenHysteresis :
  ( tokenOf 0 0 0 Calm, tokenOf 32768 0 0 Calm
  , tokenOf 12500 0 0 Wary, tokenOf 12500 0 0 Calm )
  = (Calm, Wary, Wary, Calm)
tokenHysteresis = Refl

||| Ties go to declaration order: equal arousal and grievance is WARY, not ANGRY.
export
tokenTieGoesToDeclarationOrder : tokenOf 40000 0 40000 Calm = Wary
tokenTieGoesToDeclarationOrder = Refl

--------------------------------------------------------------------------------
-- Volition: the margin, the scores, the ranking, the choice
--------------------------------------------------------------------------------

||| The incumbent's margin. Grievance widens it only while the agent PURSUES its grudge
||| (investigating the grudge target's lead).
public export
mindMargin : (pursuing : Bool) -> (grievance : Nat) -> Nat
mindMargin pursuing g =
  Abi.Modes.stickiness + (if pursuing then idiv g Abi.Affect.grievanceMarginDiv else 0)

||| WITH GRIEVANCE ZERO THE MARGIN IS THE 1.0 MARGIN — pursuing or not.
export
calmMarginIsTheModesMargin : (pursuing : Bool) -> mindMargin pursuing 0 = Abi.Modes.stickiness
calmMarginIsTheModesMargin True = Refl
calmMarginIsTheModesMargin False = Refl

||| Not pursuing, the margin is 1.0's whatever the grievance.
export
noPursuitNoWidening : (g : Nat) -> mindMargin False g = Abi.Modes.stickiness
noPursuitNoWidening g = Refl

||| What the mind's graph is asked about a moment: the 1.0 situation, with the lead
||| generalised (a grudge lead may exist while something else is visible) and fear.
public export
record MindSituation where
  constructor MkMind
  msContact   : Bool
  msDistance  : Nat
  msWounded   : Bool
  msAmmoZero  : Bool
  msLead      : Bool
  msFear      : Nat

||| The mind's score for each mode. Equal to `Abi.Utility.scoreOf` when fear is zero and
||| the lead is 1.0's (see `calmMindAgreesWithTheGraph`).
public export
mindScore : Mode -> MindSituation -> Nat
mindScore ModeReload s = if msAmmoZero s then Abi.Utility.scoreReload else 0
mindScore ModeEvade s =
  if msContact s && msWounded s && msDistance s < 131072
     then Abi.Utility.scoreFlee + idiv (clampTo Abi.Affect.full (msFear s)) Abi.Affect.fearEvadeDiv
     else 0
mindScore ModeEngage s =
  if msContact s && msDistance s <= 65536 then Abi.Utility.scoreAttack else 0
mindScore ModeInvestigate s = if msLead s then Abi.Utility.scoreInvestigate else 0
mindScore ModeAdvance s =
  if msContact s then Abi.Utility.scoreAdvance
     else if msLead s then 0 else Abi.Utility.scoreAdvance

||| The mode candidates: one when nothing is visible and a lead exists (ADR-0010 §4's
||| singleton, generalised to the grudge lead), all five otherwise, in tie-break order.
public export
mindModes : MindSituation -> List Mode
mindModes s =
  if not (msContact s) && msLead s
     then [ModeInvestigate]
     else [ModeReload, ModeEvade, ModeEngage, ModeInvestigate, ModeAdvance]

||| The choice: the earliest maximum of score plus margin-for-the-incumbent.
public export
mindBest : Mode -> Nat -> Mode -> Nat -> List Mode -> MindSituation -> Mode
mindBest inc margin best bestSc [] s = best
mindBest inc margin best bestSc (m :: ms) s =
  let sc = mindScore m s + (if eqMode m inc then margin else 0) in
  if sc > bestSc then mindBest inc margin m sc ms s else mindBest inc margin best bestSc ms s

public export
mindChoose : (incumbent : Mode) -> (margin : Nat) -> MindSituation -> Mode
mindChoose inc margin s = mindBest inc margin ModeAdvance 0 (mindModes s) s

||| Insert keeping the order stable: a later mode passes an earlier one only if strictly
||| greater, so equal scores stay in candidate order.
insertRanked : MindSituation -> Mode -> List Mode -> List Mode
insertRanked s m [] = [m]
insertRanked s m (x :: xs) =
  if mindScore m s > mindScore x s then m :: x :: xs else x :: insertRanked s m xs

||| THE RANKING the trace publishes: an order of modes, never a score.
public export
rankModes : MindSituation -> List Mode
rankModes s = go (mindModes s) []
  where
    go : List Mode -> List Mode -> List Mode
    go [] acc = acc
    go (m :: ms) acc = go ms (insertRankedLast m acc)
      where
        -- stable: m is placed after every mode already ranked that it does not beat
        insertRankedLast : Mode -> List Mode -> List Mode
        insertRankedLast m' [] = [m']
        insertRankedLast m' (x :: xs) =
          if mindScore m' s > mindScore x s then m' :: x :: xs else x :: insertRankedLast m' xs

public export
firstRanked : MindSituation -> Mode
firstRanked s = case rankModes s of
                  [] => ModeAdvance
                  (m :: _) => m

-- The moments the fixtures are built on.

||| "The grudge", tick 20: the agent is investigating A's lead with a full grudge; B
||| appears at 40000, healthy, armed. Engage ranks FIRST (52428 against 32768) and the
||| agent still selects its incumbent, because 32768 + 8192 + 16384 = 57344 > 52428.
||| That is commitment override: selected is the incumbent and is not first.
export
theGrudgeHoldsThePursuit :
  ( firstRanked (MkMind True 40000 False False True 0)
  , mindChoose ModeInvestigate (mindMargin True 65536) (MkMind True 40000 False False True 0) )
  = (ModeEngage, ModeInvestigate)
theGrudgeHoldsThePursuit = Refl

||| The control: the same moment with no grievance. The margin is 1.0's, and the agent
||| takes the ranking's first.
export
withoutGrievanceTheRankingWins :
  mindChoose ModeInvestigate (mindMargin True 0) (MkMind True 40000 False False True 0) = ModeEngage
withoutGrievanceTheRankingWins = Refl

||| The grudge at 0.7 of full scale still holds (32768 + 8192 + 11468 > 52428 needs
||| grievance above 45872); at 0.69 it does not — the boundary the fixture drains across.
export
theGrudgeBoundary :
  ( mindChoose ModeInvestigate (mindMargin True 45880) (MkMind True 40000 False False True 0)
  , mindChoose ModeInvestigate (mindMargin True 45868) (MkMind True 40000 False False True 0) )
  = (ModeInvestigate, ModeEngage)
theGrudgeBoundary = Refl

||| A GRUDGE NEVER HOLDS AGAINST SELF-PRESERVATION: wounded with the threat close, the
||| agent flees even at full grievance (57344 < 58982)...
export
theGrudgeYieldsToFlight :
  mindChoose ModeInvestigate (mindMargin True 65536) (MkMind True 40000 True False True 0) = ModeEvade
theGrudgeYieldsToFlight = Refl

||| ...and never against an empty magazine (57344 < 65536).
export
theGrudgeYieldsToReload :
  mindChoose ModeInvestigate (mindMargin True 65536) (MkMind True 40000 False True True 0) = ModeReload
theGrudgeYieldsToReload = Refl

||| The widest margin and the largest fear bonus both stay below reload, so no affect can
||| hold a mode against an empty magazine.
export
affectStaysBelowReload :
  ( So (Abi.Utility.scoreInvestigate + Abi.Modes.stickiness + idiv 65536 4 < Abi.Utility.scoreReload)
  , So (Abi.Utility.scoreFlee + idiv 65536 16 < Abi.Utility.scoreReload) )
affectStaysBelowReload = (Oh, Oh)

||| Fear raises evade: the wounded duel (`Abi.Modes.engagedAgentHoldsThroughAWound`) holds
||| an engaged agent at fear zero, and a frightened one breaks off (58982 + 4096 = 63078
||| against 52428 + 8192 = 60620).
export
fearBreaksTheWoundedDuel :
  ( mindChoose ModeEngage Abi.Modes.stickiness (MkMind True 40000 True False False 0)
  , mindChoose ModeEngage Abi.Modes.stickiness (MkMind True 40000 True False False 65536) )
  = (ModeEngage, ModeEvade)
fearBreaksTheWoundedDuel = Refl

||| A CALM MIND IS THE 1.0 GRAPH: with fear zero, grievance zero and the lead exactly
||| 1.0's (nothing visible and the memory fresh), the mind chooses `Abi.Modes.nextMode`'s
||| mode — checked on the moments `Abi.Modes` pins.
export
calmMindAgreesWithTheGraph :
  ( mindChoose ModeEngage (mindMargin False 0) (MkMind True 40000 True False False 0)
  , mindChoose ModeAdvance (mindMargin False 0) (MkMind True 40000 True False False 0)
  , mindChoose ModeEngage (mindMargin False 0) (MkMind True 196608 False False False 0)
  , mindChoose ModeEngage (mindMargin False 0) (MkMind False 0 False True True 0)
  , mindChoose ModeEvade (mindMargin False 0) (MkMind False 0 False False False 0) )
  = ( nextMode ModeEngage (MkSituation True 40000 True False False)
    , nextMode ModeAdvance (MkSituation True 40000 True False False)
    , nextMode ModeEngage (MkSituation True 196608 False False False)
    , nextMode ModeEngage (MkSituation False 0 False True True)
    , nextMode ModeEvade (MkSituation False 0 False False False) )
calmMindAgreesWithTheGraph = Refl

||| The ranking is an order of all five modes, highest first, ties in candidate order —
||| and with nothing visible and a lead it is exactly one mode.
export
rankingsOfTheFixtureMoments :
  ( rankModes (MkMind True 40000 False False True 0)
  , rankModes (MkMind False 0 False False True 0) )
  = ( [ModeEngage, ModeInvestigate, ModeAdvance, ModeReload, ModeEvade]
    , [ModeInvestigate] )
rankingsOfTheFixtureMoments = Refl
