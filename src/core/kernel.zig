// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
//
// The kernel: the host-agnostic intelligence, v0.
//
// This is the implementation of the rule specified and proved about in
// `src/interface/Abi/Foreign.idr` (`decide`, `tickModel`). Keep the two in step:
// the specification is the Idris2 module, this is the code that runs, and the
// golden trace in `tests/golden/` is the differential tie between them.
//
// Everything here is integer arithmetic. No floating point, no `libm`, no
// allocation, no clock, no I/O — the properties ADR-0006 requires are also the
// properties that make a replay bit-exact.
//
// The kernel is deliberately naive in its POLICY and strict in its DISCIPLINE
// (deterministic, budgeted, capability-aware). Phase 2 has added perception memory
// (ADR-0009, `src/interface/Abi/Memory.idr`) and replaced the branch chain with a
// utility graph (ADR-0010, `src/interface/Abi/Utility.idr`) — a refactor that
// moved no digest. Nothing here has grown a dependency.

const abi = @import("abi");

// ── Fixed point, Q16.16 ─────────────────────────────────────────────────────
// Multiplication goes through a 64-bit intermediate and shifts back down, so the
// result is exact wherever the product is representable.

pub fn fxMul(a: i32, b: i32) i32 {
    const p: i64 = @as(i64, a) * @as(i64, b);
    return @intCast(p >> 16);
}

pub fn fxDiv(a: i32, b: i32) i32 {
    if (b == 0) return 0;
    const p: i64 = (@as(i64, a) << 16);
    return @intCast(@divTrunc(p, @as(i64, b)));
}

pub fn fxAbs(a: i32) i32 {
    return if (a < 0) -a else a;
}

/// Clamp to `[lo, hi]`. Total: every input has an answer, including hi < lo.
pub fn fxClamp(v: i32, lo: i32, hi: i32) i32 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// ── Deterministic RNG ───────────────────────────────────────────────────────
// SplitMix64. The point is not statistical excellence; it is that the same seed
// and the same call count give the same numbers on every platform, forever.

pub fn rngNext(state: *u64) u64 {
    state.* +%= 0x9E3779B97F4A7C15;
    var z: u64 = state.*;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

// ── Perception: nearest contact ─────────────────────────────────────────────
// Contacts are published 0..contact_count-1 by the host. "Nearest" is the least
// distance; ties go to the LOWEST index, which keeps the choice deterministic
// rather than merely arbitrary.

pub const Nearest = struct {
    index: usize,
    id: u16,
    distance: i32,
    threat: i32,
    bearing_cos: u16,
    bearing_sin: u16,
};

/// Nearest contact, or null when the snapshot declares none. A contact_count
/// larger than the array is clamped rather than trusted: the host may be wrong,
/// and a wrong count must not read past the end of the struct.
pub fn nearestContact(snap: *const abi.EeSnapshot) ?Nearest {
    const declared = snap.contact_count;
    const available: usize = 8;
    const count: usize = if (declared > available) available else declared;
    if (count == 0) return null;

    const contacts = [8]abi.EeContact{
        snap.contact0, snap.contact1, snap.contact2, snap.contact3,
        snap.contact4, snap.contact5, snap.contact6, snap.contact7,
    };

    var best: usize = 0;
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (contacts[i].distance < contacts[best].distance) best = i;
    }
    const c = contacts[best];
    return Nearest{
        .index = best,
        .id = c.id,
        .distance = c.distance,
        .threat = c.threat,
        .bearing_cos = c.bearing_cos,
        .bearing_sin = c.bearing_sin,
    };
}

// ── Decision ────────────────────────────────────────────────────────────────

pub const Decision = struct {
    action: u32,
    target: u32,
    priority: u32,
    speed: i32,
    move_x: i32,
    move_y: i32,
    look_x: i32,
    look_y: i32,
};

/// Branch conditions, in Q16.16. These ARE the policy: changing one changes what
/// enemies do, so they live in one place with the reason beside them.
const WOUNDED_BELOW: i32 = 16384; // 0.25 — "hurt enough to consider running"
const ATTACK_RANGE: i32 = 65536; // 1.00 — can engage from here
const FLEE_RANGE: i32 = 131072; // 2.00 — but only runs from threats this close

/// The v0 rule. The branch ORDER is the policy: an unarmed agent reloads even
/// while wounded and under fire, which `Abi.Foreign.reloadOutranksFlee` pins.
// ── The utility graph (Phase 2, ADR-0010) ──────────────────────────────────
// The five-branch chain IS the policy; these numbers are that policy with the
// branch structure taken out, so it can be extended by adding a score instead of
// by arguing about where a new branch goes. The model, and the proofs that each
// branch of v0 still comes out of the graph, are in src/interface/Abi/Utility.idr.
//
// Every weight here is a number the intents ALREADY reported in `priority`
// (65536/58982/52428/26214, plus Phase 2's 32768 for INVESTIGATE). That is why
// replacing the chain with a maximum over them moves no digest: it is the rule v0
// was already following, written where it can be read. If a future tuning changes
// a number, the digests move and that is the point.
//
// The weights are deliberately NOT in ee.h: policy weights are not ABI. A host may
// read `priority` to compare two intents, but a host that hard-codes 58982 as
// "flee" would break the day the graph is tuned, and tuning it is what the graph
// is for.

const UTILITY_RELOAD: u32 = 65536; // 1.00
const UTILITY_FLEE: u32 = 58982; // 0.90
const UTILITY_ATTACK: u32 = 52428; // 0.80
const UTILITY_INVESTIGATE: u32 = 32768; // 0.50
const UTILITY_ADVANCE: u32 = 26214; // 0.40

/// What the agent is already doing is worth this much more than a challenger, in the
/// same units: 8192 is 0.125 (ADR-0012, `Abi.Modes.stickiness`).
///
/// This is the whole of the hysteresis mechanism. There is no dwell counter and no
/// timer: the incumbent's score is boosted, so a challenger must beat it by MORE than
/// this margin to take over. Enter and exit thresholds differ, so tick-to-tick
/// flapping requires a swing larger than the margin rather than a rounding error at a
/// boundary.
///
/// The boost can only hold a mode that still applies, because a mode whose
/// precondition fails scores zero and 0 + 8192 loses to any real score. Commitment
/// never becomes blindness: `Abi.Modes.engagementEndsWhenTheContactLeaves` pins it.
///
/// Not emitted to `ee.h`: the mode is ABI, the margin is policy (ADR-0010 §3).
const MODE_STICKINESS: u32 = 8192;

/// The candidates, in tie-break order — the model's `allCandidates`. The order is
/// v0's branch order, because a tie the scores cannot settle should be settled the
/// way the chain settled it, and the order is checked against the model, which
/// breaks ties the same way. `candidatesFor` below narrows this list for the one
/// moment where v0's memory branch outranked everything else.
const CANDIDATES = [_]u32{
    abi.ACTION_RELOAD,
    abi.ACTION_FLEE,
    abi.ACTION_ATTACK,
    abi.ACTION_INVESTIGATE,
    abi.ACTION_ADVANCE,
    abi.ACTION_HOLD,
};

/// One action's score in one moment. Thresholds are the same literals the model
/// pins (`Abi.Foreign`: 16384 wounded, 65536 attack range, 131072 flee range).
fn utilityOf(action: u32, snap: *const abi.EeSnapshot, near: ?Nearest, memory_fresh: bool) u32 {
    return switch (action) {
        abi.ACTION_RELOAD => if (snap.ammo == 0) UTILITY_RELOAD else 0,
        abi.ACTION_FLEE => if (near) |n|
            (if (snap.health < WOUNDED_BELOW and n.distance < FLEE_RANGE) UTILITY_FLEE else 0)
        else
            0,
        abi.ACTION_ATTACK => if (near) |n|
            (if (n.distance <= ATTACK_RANGE) UTILITY_ATTACK else 0)
        else
            0,
        // Not enough to have no contact: with nothing visible and nothing
        // remembered, walking is worth more than investigating nothing.
        abi.ACTION_INVESTIGATE => if (near == null and memory_fresh) UTILITY_INVESTIGATE else 0,
        abi.ACTION_ADVANCE => if (near != null)
            UTILITY_ADVANCE
        else if (memory_fresh)
            0 // the memory is worth more than a walk, so walking scores nothing
        else
            UTILITY_ADVANCE,
        // IDLE, TAKE_COVER, REGROUP and anything the ABI grows later: not
        // candidates. Zero can never beat a positive score, so this is a
        // deliberate "no opinion" rather than a silent default.
        else => 0,
    };
}

/// The first maximum, in candidate order.
/// The candidates for a MOMENT — the model's `Abi.Utility.candidates`, which is a
/// function of the situation rather than a constant list, and for one reason.
///
/// v0 decided with a chain and then ran its memory branch on the way out, so a
/// memory that was fresh and had nothing to compete with REPLACED the decision.
/// The chain and the memory branch disagree at exactly one kind of moment — nothing
/// visible, a fresh lead, no ammo: the chain says reload, the memory branch says
/// investigate — and the memory branch won, because it ran last.
///
/// Measured, not assumed: this trace drops contacts every fifth tick and empties
/// the magazine every seventeenth, so the collision lands on ticks 85, 170, ...
/// and letting reload win there moved the pinned digest from
/// 14165495496352896129 to 57428431722396483. So the moment is written as having
/// one candidate. Investigation is not scoring higher than reload — with nothing to
/// look at, the lead is the task, and raising its score instead would change the
/// priority the intent REPORTS, which is ABI.
///
/// Whether an ammo-less agent should investigate at all is a policy question this
/// refactor is not allowed to answer. It is recorded as open in ADR-0010; answering
/// it moves the digest, which is how the change announces itself as policy.
fn candidatesFor(near: ?Nearest, memory_fresh: bool) []const u32 {
    if (near == null and memory_fresh) return &[_]u32{abi.ACTION_INVESTIGATE};
    return &CANDIDATES;
}

/// The best action for this moment, given what the agent is already doing.
///
/// `incumbent_mode` is the S2 layer (ADR-0012): the action the agent is committed to
/// gets `MODE_STICKINESS` added to its score, so the graph still ranks the tactics and
/// the margin damps the ranking. Ties break toward the earlier candidate, as before.
fn chooseAction(
    snap: *const abi.EeSnapshot,
    near: ?Nearest,
    memory_fresh: bool,
    incumbent_mode: u32,
) u32 {
    var best_action: u32 = abi.ACTION_HOLD;
    var best_score: u32 = 0;
    for (candidatesFor(near, memory_fresh)) |a| {
        var sc = utilityOf(a, snap, near, memory_fresh);
        if (modeForAction(a) == incumbent_mode) sc += MODE_STICKINESS;
        if (sc > best_score) {
            best_score = sc;
            best_action = a;
        }
    }
    return best_action;
}

/// Decide what this agent should do.
///
/// Reads `agent` for exactly one thing — whether the memory is fresh — and reads
/// it BEFORE the tick's bookkeeping, so the freshness it acts on is the freshness
/// the tick opened with. That is what makes this the same rule as
/// `Abi.Memory.decideWithMemory` rather than a similar one.
pub fn decide(snap: *const abi.EeSnapshot, agent: *const abi.EeAgent) Decision {
    const near = nearestContact(snap);

    switch (chooseAction(snap, near, memoryFresh(agent), modeOf(agent))) {
        abi.ACTION_RELOAD => return .{
            .action = abi.ACTION_RELOAD,
            .target = 0,
            .priority = UTILITY_RELOAD,
            .speed = 0,
            .move_x = 0,
            .move_y = 0,
            .look_x = 0,
            .look_y = 0,
        },

        // FLEE and ATTACK score zero without a contact, so the graph cannot pick
        // them here without one. The `.?` is that invariant, asserted by the
        // switch rather than assumed by the reader.
        abi.ACTION_FLEE => {
            const n = near.?;
            return .{
                .action = abi.ACTION_FLEE,
                .target = n.id,
                .priority = UTILITY_FLEE,
                .speed = 2 * abi.FX_ONE,
                .move_x = -@as(i32, n.bearing_cos),
                .move_y = -@as(i32, n.bearing_sin),
                .look_x = @intCast(n.bearing_cos),
                .look_y = @intCast(n.bearing_sin),
            };
        },

        abi.ACTION_ATTACK => {
            const n = near.?;
            return .{
                .action = abi.ACTION_ATTACK,
                .target = n.id,
                .priority = UTILITY_ATTACK,
                .speed = 0,
                .move_x = -@as(i32, n.bearing_cos),
                .move_y = -@as(i32, n.bearing_sin),
                .look_x = @intCast(n.bearing_cos),
                .look_y = @intCast(n.bearing_sin),
            };
        },

        // The Phase 2 branch, unchanged in what it does and now reached by score
        // rather than by an `else if` in the tick.
        abi.ACTION_INVESTIGATE => return investigate(agent),

        abi.ACTION_ADVANCE => {
            if (near) |n| {
                return .{
                    .action = abi.ACTION_ADVANCE,
                    .target = n.id,
                    .priority = UTILITY_ADVANCE,
                    .speed = abi.FX_ONE,
                    .move_x = @intCast(n.bearing_cos),
                    .move_y = @intCast(n.bearing_sin),
                    .look_x = @intCast(n.bearing_cos),
                    .look_y = @intCast(n.bearing_sin),
                };
            }
            // Nothing visible and nothing remembered: v0's walk, with no target.
            return .{
                .action = abi.ACTION_ADVANCE,
                .target = 0,
                .priority = UTILITY_ADVANCE,
                .speed = abi.FX_ONE,
                .move_x = 0,
                .move_y = 0,
                .look_x = 0,
                .look_y = 0,
            };
        },

        else => return .{
            .action = abi.ACTION_HOLD,
            .target = 0,
            .priority = 0,
            .speed = 0,
            .move_x = 0,
            .move_y = 0,
            .look_x = 0,
            .look_y = 0,
        },
    }
}

// ── The tick ────────────────────────────────────────────────────────────────

// ── Perception memory (Phase 2, ADR-0009) ───────────────────────────────────
// Where the memory lives, why no layout moved, and what each slot means: see
// Abi.Memory's header and ADR-0009. In one line: the memory is a DIRECTION and an
// age, and it is stored in the fields `ee_agent` has carried unused since v0.

/// Is there a direction worth walking along?
///
/// The comparison is against `abi.memory_ttl`, the constant Abi.Gen emits from the
/// model — the same 36 that `Abi.Memory`'s theorems pin (`freshJustBeforeTtl`,
/// `staleAtTtl`). The kernel does not get to have its own idea of the TTL.
/// The mode the agent is in, read back out of the flags word (ADR-0012).
pub fn modeOf(agent: *const abi.EeAgent) u32 {
    return (agent.flags & abi.AGENT_MODE_MASK) >> abi.AGENT_MODE_SHIFT;
}

/// Write the mode without disturbing bit 0. The mask is a multiple of two, so the
/// memory flag is outside it — proved in `Abi.Types.agentModeMaskLeavesBitZeroAlone`,
/// asserted here because a mode write that cleared `MEMORY_VALID` would look like an
/// agent forgetting things at random.
pub fn setMode(agent: *abi.EeAgent, mode: u32) void {
    agent.flags = (agent.flags & ~abi.AGENT_MODE_MASK) |
        ((mode << abi.AGENT_MODE_SHIFT) & abi.AGENT_MODE_MASK);
}

/// The mode an action belongs to. HOLD and the actions nothing produces yet are the
/// neutral mode, exactly as `Abi.Modes.actionMode` says.
pub fn modeForAction(action: u32) u32 {
    return switch (action) {
        abi.ACTION_RELOAD => abi.AGENT_MODE_RELOAD,
        abi.ACTION_FLEE => abi.AGENT_MODE_EVADE,
        abi.ACTION_ATTACK => abi.AGENT_MODE_ENGAGE,
        abi.ACTION_INVESTIGATE => abi.AGENT_MODE_INVESTIGATE,
        else => abi.AGENT_MODE_ADVANCE,
    };
}

fn memoryFresh(agent: *const abi.EeAgent) bool {
    return (agent.flags & abi.AGENT_FLAG_MEMORY_VALID) != 0 and
        agent.memory_age < abi.memory_ttl;
}

/// Forgetting clears the payload rather than only lowering the flag: a forgotten
/// memory that still held a direction is one bug away from steering an agent at a
/// contact that is two minutes stale. `Abi.Memory.forgottenHoldsNothing` says the
/// same thing about the model, and this is the code it is talking about.
fn forget(agent: *abi.EeAgent) void {
    agent.flags &= ~abi.AGENT_FLAG_MEMORY_VALID;
    agent.memory_x = 0;
    agent.memory_y = 0;
    agent.memory_age = 0;
}

/// A tick in which nothing was seen: the age advances, and at the TTL the memory
/// is forgotten — `age + 1 < ttl` keeps it, equality or past it forgets. The
/// boundary is the TTL itself, so "still actionable one tick short of it, gone at
/// it" holds in the kernel exactly as `Abi.Memory` proves it of the model.
fn ageMemory(agent: *abi.EeAgent) void {
    if ((agent.flags & abi.AGENT_FLAG_MEMORY_VALID) == 0) return;
    if (agent.memory_age +% 1 < abi.memory_ttl) {
        agent.memory_age +%= 1;
        return;
    }
    forget(agent);
}

/// Walk towards where the contact was. The remembered id is REPORTED, never
/// dereferenced: the kernel holds no pointers into host memory and cannot follow a
/// stale id anywhere.
fn investigate(agent: *const abi.EeAgent) Decision {
    return .{
        .action = abi.ACTION_INVESTIGATE,
        .target = agent.cached_target,
        .priority = 32768, // 0.50 — between advance (0.40) and attack (0.80)
        .speed = abi.FX_ONE,
        .move_x = agent.memory_x,
        .move_y = agent.memory_y,
        .look_x = agent.memory_x,
        .look_y = agent.memory_y,
    };
}

/// Work the decision costs, in budget units. Crude on purpose at v0: five fixed
/// units plus one per contact examined, mirroring `tickModel` in Abi.Foreign.
pub fn workUnits(snap: *const abi.EeSnapshot) u32 {
    return 5 + @as(u32, snap.contact_count);
}

/// One tick, as a pure function of (context, snapshot, agent). No allocation, no
/// I/O, no host calls: the caller passes the state and receives the intent.
///
/// The budget guard degrades the agent's own behaviour rather than the frame:
/// when the work would exceed the host's allowance, the kernel still answers, but
/// says so in `flags` and reports the clamped usage, so a host can see which
/// agents are being starved and act.
pub fn tick(
    ctx: *abi.EeContext,
    snap: *const abi.EeSnapshot,
    agent: *abi.EeAgent,
) abi.EeIntent {
    const wanted = workUnits(snap);
    const budget = ctx.budget_units;
    const used: u32 = if (wanted > budget) budget else wanted;
    const degraded: bool = wanted > budget;

    // The RNG advances every tick whether or not this rule reads it, so the
    // stream is a function of the tick count alone and never depends on a branch
    // taken earlier. A Phase 2 policy that consumes randomness inherits a stream
    // that already has this property.
    _ = rngNext(&agent.rng_state);

    const near = nearestContact(snap);

    // The memory a tick DECIDES with is the one it carried in; the time it spends
    // is accounted for on the way out. The graph reads `memoryFresh(agent)` here,
    // BEFORE the bookkeeping below — that ordering is what makes this code and
    // `Abi.Memory.decideWithMemory` one rule rather than two similar ones.
    const d = decide(snap, agent);

    // An intent that came from memory says so. INVESTIGATE scores above zero only
    // when there is no contact AND the memory is fresh, so being chosen is the
    // same test the old flag performed — without a second variable to keep in step
    // with the action.
    const from_memory = d.action == abi.ACTION_INVESTIGATE;

    if (near) |n| {
        // The most recent look is the best one: the direction is overwritten and
        // the age resets. The id needs no field of its own — `cached_target` is
        // about to be written with it from the same decision.
        agent.memory_x = @as(i32, n.bearing_cos);
        agent.memory_y = @as(i32, n.bearing_sin);
        agent.memory_age = 0;
        agent.flags |= abi.AGENT_FLAG_MEMORY_VALID;
    } else {
        ageMemory(agent);
    }

    var flags: u32 = 0;
    if (degraded) flags |= abi.INTENT_FLAG_DEGRADED;
    if (agent.cached_target != d.target) flags |= abi.INTENT_FLAG_NEW_TARGET;
    if (from_memory) flags |= abi.INTENT_FLAG_FROM_MEMORY;

    agent.tick_last = snap.tick;
    // The mode is the decision's action, not the post-degradation one: what the agent
    // is committed to is what it decided, and `degradeForCapabilities` is the host's
    // answer to what the world allows (ADR-0012 §4).
    setMode(agent, modeForAction(d.action));
    agent.cached_action = d.action;
    agent.cached_target = d.target;
    agent.budget_used = used;
    if (degraded) agent.degraded_ticks +%= 1;

    ctx.ticks_run +%= 1;
    if (degraded) ctx.degraded_ticks +%= 1;

    return .{
        .action = d.action,
        .target_id = d.target,
        .move_x = d.move_x,
        .move_y = d.move_y,
        .move_z = 0,
        .look_x = d.look_x,
        .look_y = d.look_y,
        .speed = d.speed,
        .priority = d.priority,
        .budget_used = used,
        .flags = flags,
        .reserved0 = 0,
    };
}

// ── Capability degradation ──────────────────────────────────────────────────
// ADR-0004: an absent capability narrows what the kernel will ask for, rather
// than aborting the host. v0 has one such rule, and one place to grow them.

/// Does the host declare this capability?
///
/// Takes a MASK (`abi.CAP_*`), not a bit index: the generated constants are masks
/// in both languages, which is what lets the same number appear in a C host and in
/// this file and mean the same thing.
pub fn hasCapability(ctx: *const abi.EeContext, mask: u32) bool {
    return (ctx.capabilities & mask) != 0;
}

/// Without navigation data the kernel may not ask an agent to leave its ground:
/// ADVANCE is downgraded to HOLD. This is the ladder in miniature — the same
/// shape later capabilities will use.
pub fn degradeForCapabilities(ctx: *const abi.EeContext, intent: *abi.EeIntent) void {
    if (!hasCapability(ctx, abi.CAP_NAVMESH) and intent.action == abi.ACTION_ADVANCE) {
        intent.action = abi.ACTION_HOLD;
        intent.speed = 0;
        intent.move_x = 0;
        intent.move_y = 0;
        intent.flags |= abi.INTENT_FLAG_UNREACHABLE;
    }
}

// ════════════════════════════════════════════════════════════════════════════
// ABI 1.1 — THE MIND (ADR-0013, `src/interface/Abi/Affect.idr`)
// ════════════════════════════════════════════════════════════════════════════
//
// Three affect reservoirs (arousal, fear, grievance), an affect token, three bodily
// tells (startle, hesitate, fixate), a grievance-widened commitment margin, and a
// per-tick trace record. Everything above this line is the 1.0 kernel and is NOT
// touched by this section: `tick` does not call into it, and the four pinned `ee_tick`
// digests are the evidence (ADR-0006 table).
//
// Four rules bind this code, and each one is enforced by construction here, not by a
// comment:
//
//   1. Integer arithmetic only. Every reservoir is a u32 fraction of `FULL`.
//   2. Affect buys ATTENTION, never belief. A reservoir changes how long a memory is
//      attended to (`ttlFor`), how readily a commitment is held (`mindMargin`), how
//      evade ranks (`mindUtility`), and whether the body hesitates or freezes. No
//      reservoir is ever an argument to a function that writes a bearing, an id or a
//      position: `rememberSighting` takes perception and nothing else.
//   3. Scores never leave. The trace carries the RANKING of modes (an order) and the
//      selected mode; `mindUtility` is private to this file.
//   4. A token change carries its cause (`causeFor`), and a token that did not change
//      carries `CAUSE_NONE` — `Abi.Affect.tokenChangeHasCause` proves the pair.
//
// The constants are policy, not ABI (ADR-0010 §3): none is in `ee.h`. ADR-0013 lists
// every one with its measured effect, and the pinned mind digests move if any does.

/// Full scale of a reservoir: 1.0 in Q16.16.
const FULL: u32 = 65536;

// Leaky integrator shifts: x' = x - ceil(x / 2^k) + input. Half-lives (≈ 0.69 · 2^k):
const AROUSAL_LEAK_SHIFT: u5 = 5; // ~22 ticks: a startle fades within a second at 60 Hz
const FEAR_LEAK_SHIFT: u5 = 4; // ~11 ticks: fear tracks the danger, not the memory of it
const GRIEVANCE_LEAK_SHIFT: u5 = 8; // ~177 ticks: ~5x the 36-tick memory TTL

// Arousal inputs.
const CLOSE_RANGE: i32 = 65536; // 1.0 — a NEW contact nearer than this is a surprise
const AROUSAL_CLOSE_CONTACT: u32 = 32768; // 0.5 per surprising appearance
const AROUSAL_CONTRADICTION: u32 = 16384; // 0.25 when a lead comes to nothing
// (damage fills arousal one-for-one: a hit of 0.125 health is 0.125 arousal)

// Fear inputs.
const FEAR_HEALTH_BELOW: i32 = 32768; // 0.5 — below this, health feeds fear
const FEAR_HEALTH_SHIFT: u5 = 3; // (0.5 - health) / 8 per tick, so at most 4096
const FEAR_THREATS_FROM: u32 = 3; // three or more visible contacts feed fear
const FEAR_PER_EXTRA_THREAT: u32 = 1024; // per contact beyond two
const FEAR_NO_AMMO: u32 = 2048;

// Grievance input: attributed damage, times four.
const GRIEVANCE_GAIN_SHIFT: u5 = 2;

// The token: the highest reservoir at or above ENTER, the incumbent's reservoir boosted
// by BAND — the same margin-not-counter hysteresis as the modes (ADR-0012 §3).
const TOKEN_ENTER: u32 = 16384; // 0.25
const TOKEN_BAND: u32 = 4096; // 0.0625: exits below 0.1875

// Tells.
const STARTLE_AROUSAL: u32 = 24576; // 0.375 — crossing it upward on a surprise freezes one tick
const HESITATE_AROUSAL: u32 = 24576; // hesitation needs arousal at least this high...
const HESITATE_FEAR_BELOW: u32 = 16384; // ...and fear below this
const HESITATE_TICKS: u8 = 3; // at most three ticks of delay before a new action
const HESITATE_FEAR_SHIFT: u5 = 12; // before FLIGHT, fear >> 12 ticks are taken off
const FIXATE_GRIEVANCE: u32 = 32768; // 0.5 — gaze locks onto the grudge target

// Effects on attention and commitment.
const AROUSAL_TTL_SHIFT: u5 = 11; // memory lifetime + arousal / 2048: at most +32 ticks
const FEAR_EVADE_SHIFT: u5 = 4; // evade score + fear / 16: at most +4096, below reload
const GRIEVANCE_MARGIN_SHIFT: u5 = 2; // pursuit margin + grievance / 4: at most +16384

/// Ceil(x / 2^k) for x > 0, and 0 for 0 — the leak. Rounding UP is what makes a
/// reservoir with no input reach zero: the brief's `x >> k` floors, and a floored leak
/// stalls forever at any x < 2^k (a grievance of 255 would widen the margin for the
/// rest of the game). ADR-0013 records the departure; `Abi.Affect.leakReachesZero`
/// is the property it buys.
pub fn leak(x: u32, k: u5) u32 {
    if (x == 0) return 0;
    return ((x - 1) >> k) + 1;
}

/// One step of a leaky integrator, clamped to [0, FULL]. A garbage value written by
/// the host is clamped on the way in, so the range holds whatever the struct held.
pub fn integrate(x_in: u32, input: u32, k: u5) u32 {
    const x = if (x_in > FULL) FULL else x_in;
    const kept: u64 = x - leak(x, k); // leak(x) <= x, so this cannot wrap
    const sum = kept + @as(u64, input);
    return if (sum > FULL) FULL else @intCast(sum);
}

fn satAdd(a: u32, b: u32) u32 {
    const s = @as(u64, a) + @as(u64, b);
    return if (s > FULL) FULL else @intCast(s);
}

/// Memory lifetime under arousal: 36 at rest, up to 68 at full arousal. With arousal
/// zero this IS `abi.memory_ttl`, which `Abi.Affect.calmTtlIsTheFrozenTtl` pins.
pub fn ttlFor(arousal: u32) u32 {
    const a = if (arousal > FULL) FULL else arousal;
    return abi.memory_ttl + (a >> AROUSAL_TTL_SHIFT);
}

/// The incumbent's bonus. With grievance zero, or when the agent is not pursuing its
/// grudge, it is exactly the 1.0 margin `MODE_STICKINESS` (`Abi.Affect.calmMarginIsTheModesMargin`).
pub fn mindMargin(pursuing: bool, grievance: u32) u32 {
    const g = if (grievance > FULL) FULL else grievance;
    return MODE_STICKINESS + (if (pursuing) g >> GRIEVANCE_MARGIN_SHIFT else 0);
}

/// Attention mass (enaction ADR-0016: units of 1/10 000) of a reservoir level.
pub fn massOf(level: u32) u16 {
    const l: u64 = if (level > FULL) FULL else level;
    const m = (l * abi.MASS_FULL) >> 16;
    return @intCast(if (m > abi.MASS_FULL) abi.MASS_FULL else m);
}

/// The token for three reservoir levels, in declaration order (arousal → WARY,
/// fear → AFRAID, grievance → ANGRY), given the token the tick opened with.
pub fn tokenOf(arousal: u32, fear: u32, grievance: u32, prev: u8) u8 {
    const levels = [3]u32{ arousal, fear, grievance };
    var best_token: u8 = @intCast(abi.AFFECT_CALM);
    var best: u32 = 0;
    for (levels, 0..) |lvl, i| {
        const tok: u8 = @intCast(i + 1);
        const sc = lvl + (if (tok == prev) TOKEN_BAND else 0);
        if (sc > best) {
            best = sc;
            best_token = tok;
        }
    }
    return if (best >= TOKEN_ENTER) best_token else @intCast(abi.AFFECT_CALM);
}

/// The inputs of one tick, by reservoir, in a fixed declared order — the order the
/// cause is chosen in when two inputs tie.
const Inputs = struct {
    close_contact: u32 = 0, // arousal
    damage: u32 = 0, // arousal
    contradiction: u32 = 0, // arousal
    low_health: u32 = 0, // fear
    threats: u32 = 0, // fear
    no_ammo: u32 = 0, // fear
    attributed: u32 = 0, // grievance
    close_id: u16 = 0,
    source_id: u16 = 0,
};

const Cause = struct { code: u8, contact: u16 };

fn largest(comptime n: usize, vals: [n]u32, codes: [n]u8) ?u8 {
    var best: u32 = 0;
    var code: ?u8 = null;
    for (vals, codes) |v, c| {
        if (v > best) {
            best = v;
            code = c;
        }
    }
    return code;
}

/// Why the token is what it is. NONE exactly when it did not change; otherwise the
/// largest input this tick to the reservoir the new token names, or DECAY when that
/// reservoir got no input (it won because another drained) or the new token is calm.
fn causeFor(prev: u8, now: u8, in: Inputs) Cause {
    if (prev == now) return .{ .code = @intCast(abi.CAUSE_NONE), .contact = 0 };
    const decay = Cause{ .code = @intCast(abi.CAUSE_DECAY), .contact = 0 };
    const code: ?u8 = switch (now) {
        abi.AFFECT_WARY => largest(3, .{ in.close_contact, in.damage, in.contradiction }, .{
            @intCast(abi.CAUSE_CLOSE_CONTACT), @intCast(abi.CAUSE_DAMAGE), @intCast(abi.CAUSE_CONTRADICTION),
        }),
        abi.AFFECT_AFRAID => largest(3, .{ in.low_health, in.threats, in.no_ammo }, .{
            @intCast(abi.CAUSE_LOW_HEALTH), @intCast(abi.CAUSE_THREATS), @intCast(abi.CAUSE_NO_AMMO),
        }),
        abi.AFFECT_ANGRY => if (in.attributed > 0) @as(u8, @intCast(abi.CAUSE_ATTRIBUTED_DAMAGE)) else null,
        else => null,
    };
    const c = code orelse return decay;
    const contact: u16 = switch (c) {
        abi.CAUSE_CLOSE_CONTACT => in.close_id,
        abi.CAUSE_DAMAGE, abi.CAUSE_ATTRIBUTED_DAMAGE => in.source_id,
        else => 0,
    };
    return .{ .code = c, .contact = contact };
}

fn contactsOf(snap: *const abi.EeSnapshot) [8]abi.EeContact {
    return .{
        snap.contact0, snap.contact1, snap.contact2, snap.contact3,
        snap.contact4, snap.contact5, snap.contact6, snap.contact7,
    };
}

fn visibleCount(snap: *const abi.EeSnapshot) usize {
    return if (snap.contact_count > 8) 8 else snap.contact_count;
}

fn seenId(mind: *const abi.EeMind, i: usize) u16 {
    const word = if (i < 4) mind.seen_ids_lo else mind.seen_ids_hi;
    return @truncate(word >> @intCast(16 * (i % 4)));
}

fn wasSeen(mind: *const abi.EeMind, id: u16) bool {
    const n: usize = if (mind.seen_count > 8) 8 else mind.seen_count;
    var i: usize = 0;
    while (i < n) : (i += 1) if (seenId(mind, i) == id) return true;
    return false;
}

/// A lead the INVESTIGATE candidate can follow: the grudge slot or the 1.0 memory.
const Lead = struct { id: u32, x: i32, y: i32 };

/// One mode candidate's score in the mind. Equal to the 1.0 `utilityOf` when fear is
/// zero and the lead is exactly 1.0's (nothing visible, memory fresh) — which is the
/// whole of the mind's footprint on the graph when it is calm and holds no grudge.
fn mindUtility(action: u32, snap: *const abi.EeSnapshot, near: ?Nearest, lead: ?Lead, fear: u32) u32 {
    return switch (action) {
        abi.ACTION_RELOAD => if (snap.ammo == 0) UTILITY_RELOAD else 0,
        abi.ACTION_FLEE => if (near) |n|
            (if (snap.health < WOUNDED_BELOW and n.distance < FLEE_RANGE)
                UTILITY_FLEE + (@min(fear, FULL) >> FEAR_EVADE_SHIFT)
            else
                0)
        else
            0,
        abi.ACTION_ATTACK => if (near) |n|
            (if (n.distance <= ATTACK_RANGE) UTILITY_ATTACK else 0)
        else
            0,
        abi.ACTION_INVESTIGATE => if (lead != null) UTILITY_INVESTIGATE else 0,
        abi.ACTION_ADVANCE => if (near != null)
            UTILITY_ADVANCE
        else if (lead != null)
            0
        else
            UTILITY_ADVANCE,
        else => 0,
    };
}

fn mindCandidates(near: ?Nearest, lead: ?Lead) []const u32 {
    if (near == null and lead != null) return &[_]u32{abi.ACTION_INVESTIGATE};
    return &CANDIDATES;
}

/// The ranking: mode candidates by score, highest first, ties in candidate order.
/// HOLD is not a mode and is not ranked (`enaction-mind-trace/1` candidates are modes).
const Ranking = struct { packed_modes: u32, count: u8, first: u32 };

fn rankModes(snap: *const abi.EeSnapshot, near: ?Nearest, lead: ?Lead, fear: u32) Ranking {
    var modes: [5]u32 = undefined;
    var scores: [5]u32 = undefined;
    var n: usize = 0;
    for (mindCandidates(near, lead)) |a| {
        if (a == abi.ACTION_HOLD) continue;
        const sc = mindUtility(a, snap, near, lead, fear);
        // Stable insertion: a later candidate passes an earlier one only if STRICTLY
        // greater, so equal scores stay in candidate order.
        var j: usize = n;
        while (j > 0 and scores[j - 1] < sc) : (j -= 1) {
            modes[j] = modes[j - 1];
            scores[j] = scores[j - 1];
        }
        modes[j] = modeForAction(a);
        scores[j] = sc;
        n += 1;
    }
    var p: u32 = 0;
    for (modes[0..n], 0..) |m, i| p |= m << @intCast(4 * i);
    return .{ .packed_modes = p, .count = @intCast(n), .first = modes[0] };
}

fn chooseMind(snap: *const abi.EeSnapshot, near: ?Nearest, lead: ?Lead, fear: u32, incumbent: u32, margin: u32) u32 {
    var best_action: u32 = abi.ACTION_HOLD;
    var best_score: u32 = 0;
    for (mindCandidates(near, lead)) |a| {
        var sc = mindUtility(a, snap, near, lead, fear);
        if (modeForAction(a) == incumbent) sc += margin;
        if (sc > best_score) {
            best_score = sc;
            best_action = a;
        }
    }
    return best_action;
}

fn mindDecision(action: u32, near: ?Nearest, lead: ?Lead) Decision {
    return switch (action) {
        abi.ACTION_RELOAD => .{ .action = action, .target = 0, .priority = UTILITY_RELOAD, .speed = 0, .move_x = 0, .move_y = 0, .look_x = 0, .look_y = 0 },
        abi.ACTION_FLEE => blk: {
            const n = near.?;
            break :blk .{ .action = action, .target = n.id, .priority = UTILITY_FLEE, .speed = 2 * abi.FX_ONE, .move_x = -@as(i32, n.bearing_cos), .move_y = -@as(i32, n.bearing_sin), .look_x = n.bearing_cos, .look_y = n.bearing_sin };
        },
        abi.ACTION_ATTACK => blk: {
            const n = near.?;
            break :blk .{ .action = action, .target = n.id, .priority = UTILITY_ATTACK, .speed = 0, .move_x = -@as(i32, n.bearing_cos), .move_y = -@as(i32, n.bearing_sin), .look_x = n.bearing_cos, .look_y = n.bearing_sin };
        },
        abi.ACTION_INVESTIGATE => blk: {
            const l = lead.?;
            break :blk .{ .action = action, .target = l.id, .priority = UTILITY_INVESTIGATE, .speed = abi.FX_ONE, .move_x = l.x, .move_y = l.y, .look_x = l.x, .look_y = l.y };
        },
        abi.ACTION_ADVANCE => if (near) |n|
            .{ .action = action, .target = n.id, .priority = UTILITY_ADVANCE, .speed = abi.FX_ONE, .move_x = n.bearing_cos, .move_y = n.bearing_sin, .look_x = n.bearing_cos, .look_y = n.bearing_sin }
        else
            .{ .action = action, .target = 0, .priority = UTILITY_ADVANCE, .speed = abi.FX_ONE, .move_x = 0, .move_y = 0, .look_x = 0, .look_y = 0 },
        else => .{ .action = abi.ACTION_HOLD, .target = 0, .priority = 0, .speed = 0, .move_x = 0, .move_y = 0, .look_x = 0, .look_y = 0 },
    };
}

/// How many ticks the body delays a NEW action. Zero unless arousal is high and fear is
/// low; before flight, fear takes ticks off (fear >> 12, so 0..3 in the band allowed).
pub fn hesitationFor(action: u32, arousal: u32, fear: u32) u8 {
    if (arousal < HESITATE_AROUSAL or fear >= HESITATE_FEAR_BELOW) return 0;
    if (action != abi.ACTION_FLEE) return HESITATE_TICKS;
    const cut: u32 = fear >> HESITATE_FEAR_SHIFT;
    return if (cut >= HESITATE_TICKS) 0 else HESITATE_TICKS - @as(u8, @intCast(cut));
}

/// Perception writes the grudge slot: the bearing it SAW, age zero. This is the only
/// function that writes `grudge_x`/`grudge_y`, and it takes no reservoir.
fn rememberSighting(mind: *abi.EeMind, c: abi.EeContact) void {
    mind.grudge_x = c.bearing_cos;
    mind.grudge_y = c.bearing_sin;
    mind.grudge_age = 0;
    mind.flags |= @intCast(abi.MIND_FLAG_GRUDGE_LEAD);
}

fn forgetGrudgeLead(mind: *abi.EeMind) void {
    mind.flags &= ~@as(u8, @intCast(abi.MIND_FLAG_GRUDGE_LEAD));
    mind.grudge_x = 0;
    mind.grudge_y = 0;
    mind.grudge_age = 0;
}

/// What one mind tick produced, besides the writes into the caller-owned structs.
pub const MindResult = struct { intent: abi.EeIntent, trace: abi.EeMindTrace };

/// One tick with a mind. Pure in the same sense as `tick`: a function of (context,
/// snapshot, agent, mind), writing only into the agent and the mind the caller owns.
pub fn tickMind(
    ctx: *abi.EeContext,
    snap: *const abi.EeSnapshot,
    agent: *abi.EeAgent,
    mind: *abi.EeMind,
) MindResult {
    const wanted = workUnits(snap);
    const budget = ctx.budget_units;
    const used: u32 = if (wanted > budget) budget else wanted;
    const degraded: bool = wanted > budget;
    _ = rngNext(&agent.rng_state); // the stream stays a function of tick count alone

    const near = nearestContact(snap);
    const contacts = contactsOf(snap);
    const count = visibleCount(snap);
    const primed = (mind.flags & abi.MIND_FLAG_PRIMED) != 0;

    // Reservoirs as the tick opened, clamped against a host that wrote garbage.
    const arousal0 = @min(mind.arousal, FULL);
    const fear0 = @min(mind.fear, FULL);
    const grievance0 = @min(mind.grievance, FULL);
    const token0: u8 = if (mind.token > abi.AFFECT_ANGRY) @intCast(abi.AFFECT_CALM) else mind.token;
    const ttl = ttlFor(arousal0); // attention: how long a lead is followed

    // ── Appraisal: what this tick's snapshot means, as inputs ─────────────────
    var in = Inputs{};

    // Damage is the drop in health since the last mind tick. Not on the first tick:
    // with no baseline there is nothing to have dropped from.
    if (primed and mind.last_health > snap.health) {
        const d: i64 = @as(i64, mind.last_health) - @as(i64, snap.health);
        in.damage = if (d > FULL) FULL else @intCast(d);
    }

    // Attribution needs the capability, damage, and a contact the host flagged.
    var source: ?abi.EeContact = null;
    if (in.damage > 0 and hasCapability(ctx, abi.CAP_DAMAGE_EVENTS)) {
        for (contacts[0..count]) |c| {
            if ((c.flags & abi.CONTACT_FLAG_DAMAGE_SOURCE) != 0) {
                source = c;
                break;
            }
        }
    }
    if (source) |s| in.source_id = s.id;

    // A NEW contact at close range: the nearest one not visible last tick.
    var surprise: ?abi.EeContact = null;
    if (primed) {
        for (contacts[0..count]) |c| {
            if (c.distance < CLOSE_RANGE and !wasSeen(mind, c.id)) {
                if (surprise == null or c.distance < surprise.?.distance) surprise = c;
            }
        }
    }
    if (surprise) |s| {
        in.close_contact = AROUSAL_CLOSE_CONTACT;
        in.close_id = s.id;
    }

    // The grudge target, if visible this tick.
    const has_grudge = grievance0 > 0;
    var grudge_seen: ?abi.EeContact = null;
    if (has_grudge) {
        for (contacts[0..count]) |c| {
            if (c.id == mind.grudge_id) {
                grudge_seen = c;
                break;
            }
        }
    }

    // A contradiction: a lead reaches the end of its lifetime with nothing found — the
    // agent went where the target was and the target was not there. (Memory is a
    // bearing, not a position, so "arrived" is "followed it for its whole lifetime".)
    const mem_valid = (agent.flags & abi.AGENT_FLAG_MEMORY_VALID) != 0;
    const mem_ends = near == null and mem_valid and agent.memory_age +% 1 >= ttl;
    const grudge_lead_valid = (mind.flags & abi.MIND_FLAG_GRUDGE_LEAD) != 0;
    const grudge_ends = has_grudge and grudge_seen == null and grudge_lead_valid and mind.grudge_age +% 1 >= ttl;
    if (mem_ends or grudge_ends) in.contradiction = AROUSAL_CONTRADICTION;

    if (snap.health < FEAR_HEALTH_BELOW) {
        const h: i32 = if (snap.health < 0) 0 else snap.health;
        in.low_health = @intCast((FEAR_HEALTH_BELOW - h) >> FEAR_HEALTH_SHIFT);
    }
    if (count >= FEAR_THREATS_FROM) in.threats = FEAR_PER_EXTRA_THREAT * @as(u32, @intCast(count - 2));
    if (snap.ammo == 0) in.no_ammo = FEAR_NO_AMMO;

    // Grievance belongs to one target. Harm from that target (or with no grudge yet)
    // feeds it; harm from another target transfers the grudge only if it outweighs it.
    var grievance_base = grievance0;
    var grudge_id = mind.grudge_id;
    if (source) |s| {
        const g_in: u32 = @intCast(@min(@as(u64, in.damage) << GRIEVANCE_GAIN_SHIFT, FULL));
        if (grievance0 == 0 or s.id == mind.grudge_id) {
            grudge_id = s.id;
            in.attributed = g_in;
        } else if (g_in > grievance0) {
            grudge_id = s.id;
            grievance_base = 0;
            in.attributed = g_in;
            forgetGrudgeLead(mind);
        }
    }

    // ── Integration ─────────────────────────────────────────────────────────────
    const arousal = integrate(arousal0, satAdd(satAdd(in.close_contact, in.damage), in.contradiction), AROUSAL_LEAK_SHIFT);
    const fear = integrate(fear0, satAdd(satAdd(in.low_health, in.threats), in.no_ammo), FEAR_LEAK_SHIFT);
    const grievance = integrate(grievance_base, in.attributed, GRIEVANCE_LEAK_SHIFT);
    if (grievance == 0) {
        grudge_id = 0;
        forgetGrudgeLead(mind);
    }

    const token = tokenOf(arousal, fear, grievance, token0);
    const cause = causeFor(token0, token, in);
    const attention = massOf(@max(arousal, @max(fear, grievance)));

    // ── Perception of the grudge target, BEFORE the decision ───────────────────
    // A sighting is perception, so it is current: the lead the agent hunts with is
    // the bearing it sees now if it sees the target at all.
    if (grievance > 0) {
        if (source) |s| {
            if (s.id == grudge_id) rememberSighting(mind, s);
        }
        for (contacts[0..count]) |c| {
            if (c.id == grudge_id) {
                rememberSighting(mind, c);
                break;
            }
        }
    }
    const grudge_visible_now = grievance > 0 and blk: {
        for (contacts[0..count]) |c| if (c.id == grudge_id) break :blk true;
        break :blk false;
    };
    const grudge_lead_fresh = grievance > 0 and (mind.flags & abi.MIND_FLAG_GRUDGE_LEAD) != 0 and mind.grudge_age < ttl;

    // ── Conation: the lead, the margin, the choice, the ranking ────────────────
    const mem_fresh = mem_valid and agent.memory_age < ttl;
    var lead: ?Lead = null;
    if (grudge_lead_fresh and (near == null or near.?.id != grudge_id)) {
        lead = .{ .id = grudge_id, .x = mind.grudge_x, .y = mind.grudge_y };
    } else if (near == null and mem_fresh) {
        lead = .{ .id = agent.cached_target, .x = agent.memory_x, .y = agent.memory_y };
    }

    const incumbent = modeOf(agent);
    const pursuing = incumbent == abi.AGENT_MODE_INVESTIGATE and grievance > 0 and
        agent.cached_target == grudge_id;
    const margin = mindMargin(pursuing, grievance);
    const action = chooseMind(snap, near, lead, fear, incumbent, margin);
    const ranking = rankModes(snap, near, lead, fear);
    const d = mindDecision(action, near, lead);

    // ── The body: tells change the motor output, never the decision ────────────
    var tells: u8 = 0;
    var out_action = d.action;
    var speed = d.speed;
    var move_x = d.move_x;
    var move_y = d.move_y;
    var look_x = d.look_x;
    var look_y = d.look_y;
    var acts = true;

    const startle = arousal0 < STARTLE_AROUSAL and arousal >= STARTLE_AROUSAL and
        (in.close_contact > 0 or in.contradiction > 0);
    if (startle) {
        tells |= @intCast(abi.TELL_STARTLE);
        acts = false;
        out_action = abi.ACTION_HOLD;
        speed = 0;
        move_x = 0;
        move_y = 0;
        if (surprise) |s| {
            look_x = s.bearing_cos; // the look snaps to what startled it
            look_y = s.bearing_sin;
        }
    } else {
        const is_new = d.action != agent.cached_action;
        if (is_new and (mind.flags & abi.MIND_FLAG_HESITATED) == 0) {
            mind.hesitate_left = hesitationFor(d.action, arousal, fear);
            mind.flags |= @intCast(abi.MIND_FLAG_HESITATED);
        }
        if (is_new and mind.hesitate_left > 0) {
            mind.hesitate_left -= 1;
            tells |= @intCast(abi.TELL_HESITATE);
            acts = false;
            out_action = abi.ACTION_HOLD;
            speed = 0;
            move_x = 0;
            move_y = 0;
        }
    }
    if (acts) {
        mind.flags &= ~@as(u8, @intCast(abi.MIND_FLAG_HESITATED));
        mind.hesitate_left = 0;
    }
    if (grievance >= FIXATE_GRIEVANCE and grudge_lead_fresh) {
        tells |= @intCast(abi.TELL_FIXATE);
        look_x = mind.grudge_x;
        look_y = mind.grudge_y;
    }

    // ── Bookkeeping: perception writes memory; affect only set its lifetime ─────
    if (near) |n| {
        agent.memory_x = @as(i32, n.bearing_cos);
        agent.memory_y = @as(i32, n.bearing_sin);
        agent.memory_age = 0;
        agent.flags |= abi.AGENT_FLAG_MEMORY_VALID;
    } else if (mem_valid) {
        if (agent.memory_age +% 1 < ttl) agent.memory_age +%= 1 else forget(agent);
    }
    if (grievance > 0 and !grudge_visible_now and (mind.flags & abi.MIND_FLAG_GRUDGE_LEAD) != 0) {
        if (mind.grudge_age +% 1 < ttl) mind.grudge_age +%= 1 else forgetGrudgeLead(mind);
    }

    var lo: u64 = 0;
    var hi: u64 = 0;
    for (contacts[0..count], 0..) |c, i| {
        const sh: u6 = @intCast(16 * (i % 4));
        if (i < 4) lo |= @as(u64, c.id) << sh else hi |= @as(u64, c.id) << sh;
    }
    mind.seen_ids_lo = lo;
    mind.seen_ids_hi = hi;
    mind.seen_count = @intCast(count);
    mind.last_health = snap.health;
    mind.flags |= @intCast(abi.MIND_FLAG_PRIMED);
    mind.arousal = arousal;
    mind.fear = fear;
    mind.grievance = grievance;
    mind.grudge_id = grudge_id;
    mind.token = token;
    mind.reserved0 = 0;

    var flags: u32 = 0;
    if (degraded) flags |= abi.INTENT_FLAG_DEGRADED;
    if (agent.cached_target != d.target) flags |= abi.INTENT_FLAG_NEW_TARGET;
    if (out_action == abi.ACTION_INVESTIGATE) flags |= abi.INTENT_FLAG_FROM_MEMORY;
    flags |= @as(u32, tells) << 4;

    agent.tick_last = snap.tick;
    if (acts) {
        setMode(agent, modeForAction(d.action));
        agent.cached_action = d.action;
        agent.cached_target = d.target;
    }
    agent.budget_used = used;
    if (degraded) agent.degraded_ticks +%= 1;
    ctx.ticks_run +%= 1;
    if (degraded) ctx.degraded_ticks +%= 1;

    return .{
        .intent = .{
            .action = out_action,
            .target_id = d.target,
            .move_x = move_x,
            .move_y = move_y,
            .move_z = 0,
            .look_x = look_x,
            .look_y = look_y,
            .speed = speed,
            .priority = d.priority,
            .budget_used = used,
            .flags = flags,
            .reserved0 = 0,
        },
        .trace = .{
            .struct_size = @sizeOf(abi.EeMindTrace),
            .target_id = d.target,
            .tick = snap.tick,
            .ranking = ranking.packed_modes,
            .attention = attention,
            .cause_contact = cause.contact,
            .ranking_count = ranking.count,
            .selected = @intCast(modeForAction(d.action)),
            .incumbent = @intCast(incumbent),
            .token = token,
            .token_prev = token0,
            .cause = cause.code,
            .tells = tells,
            .reserved0 = 0,
        },
    };
}
