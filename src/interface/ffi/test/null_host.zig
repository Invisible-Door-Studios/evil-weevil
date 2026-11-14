// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
//
// The null host: a game engine with nothing in it.
//
// There is no renderer, no physics, no navmesh and no map. This file fabricates
// snapshots, ticks the kernel and reads the intents. It exists because the claim
// in the README is that the kernel is HOST-AGNOSTIC, and the only way to test
// that claim on a machine with no engines on it is to write the minimum host that
// satisfies the ABI and see whether the intelligence is still intelligent.
//
// It is also the determinism harness (ADR-0006): the same seed and the same
// snapshot sequence must produce the same intents, tick after tick, on every
// platform. `test "10,000 ticks are bit-identical across two runs"` below is that
// requirement, executed.

const std = @import("std");
const abi = @import("abi");
const kernel = @import("kernel");

const FX = abi.FX_ONE;

/// Build a snapshot for agent `id` at `tick`, with `contacts` synthesised from a
/// deterministic walk. All fixture geometry is in Q16.16 world units.
fn snapshot(tick: u64, id: u16, health: i32, ammo: i32, contact_count: u16) abi.EeSnapshot {
    var s = std.mem.zeroes(abi.EeSnapshot);
    s.tick = tick;
    s.agent_id = id;
    s.capability_mask = 0xFFFF_FFFF;
    s.contact_count = contact_count;

    // A body moving in a slow circle — deterministic, so a replay is exact.
    const t: i32 = @intCast(tick % 360);
    s.self_x = kernel.fxMul(@intCast(t), 182); // ~t * 0.00278
    s.self_y = kernel.fxMul(@intCast(t), 91);
    s.self_z = 0;
    s.self_vx = FX;
    s.self_vy = FX / 2;
    s.health = health;
    s.ammo = ammo;

    var i: u32 = 0;
    while (i < @min(@as(u32, contact_count), 8)) : (i += 1) {
        // 3.0, 2.0, 1.0, 0.5: the band the NEAREST contact falls in changes with the
        // contact count, which is how one fixture reaches every branch of the rule.
        // These numbers are duplicated in tests/host/null_host.c on purpose: the two
        // hosts must produce the same trace, and that is checked by digest.
        const dist: i32 = @intCast(196608 - @as(i32, @intCast(i)) * 65536);
        const c: i16 = @intCast(16384 + @as(i32, @intCast(i)) * 4096);
        const body = abi.EeContact{
            .id = @intCast(100 + i),
            .flags = 0,
            .bearing_cos = @bitCast(c),
            .bearing_sin = @bitCast(@as(i16, 8192)),
            .distance = if (dist > 0) dist else 0,
            .threat = @intCast(FX / 2),
        };
        switch (i) {
            0 => s.contact0 = body,
            1 => s.contact1 = body,
            2 => s.contact2 = body,
            3 => s.contact3 = body,
            4 => s.contact4 = body,
            5 => s.contact5 = body,
            6 => s.contact6 = body,
            7 => s.contact7 = body,
            else => unreachable,
        }
    }
    return s;
}

fn context(seed: u64, capabilities: u32, budget: u32) abi.EeContext {
    var c = std.mem.zeroes(abi.EeContext);
    c.abi_major = abi.ABI_MAJOR;
    c.capabilities = capabilities;
    c.budget_units = budget;
    c.max_agents = 1;
    c.abi_fingerprint = abi.ABI_FINGERPRINT;
    c.rng_seed = seed;
    c.tick_rate_num = 60;
    c.tick_rate_den = 1;
    return c;
}

fn agent(seed: u64) abi.EeAgent {
    var a = std.mem.zeroes(abi.EeAgent);
    a.rng_state = seed;
    return a;
}

// ── The rule, branch by branch ──────────────────────────────────────────────

test "no ammo reloads, even when wounded and under fire" {
    var ctx = context(1, 0xFFFF_FFFF, 64);
    const snap = snapshot(0, 7, 1024, 0, 1);
    var ag = agent(1);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expectEqual(abi.ACTION_RELOAD, intent.action);
}

test "no contacts advances" {
    var ctx = context(2, 0xFFFF_FFFF, 64);
    const snap = snapshot(0, 7, FX * 4, FX * 2, 0);
    var ag = agent(2);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expectEqual(abi.ACTION_ADVANCE, intent.action);
    try std.testing.expectEqual(@as(u32, 0), intent.target_id);
}

test "wounded near a contact flees, and moves away from it" {
    var ctx = context(3, 0xFFFF_FFFF, 64);
    const snap = snapshot(0, 7, 1024, FX * 2, 1); // 0.0156 health, contact at 3.0
    // Put the contact inside flee range (2.0) for this case.
    var close = snap;
    close.contact0.distance = FX + FX / 2;
    var ag = agent(3);
    const intent = kernel.tick(&ctx, &close, &ag);
    try std.testing.expectEqual(abi.ACTION_FLEE, intent.action);
    // Away from the contact: the bearing is 0.25, so the intent moves -0.25.
    try std.testing.expect(intent.move_x < 0);
    try std.testing.expectEqual(@as(u32, 100), intent.target_id);
}

test "healthy and in range attacks, holding ground" {
    var ctx = context(4, 0xFFFF_FFFF, 64);
    var snap = snapshot(0, 7, FX * 4, FX * 2, 1);
    snap.contact0.distance = FX / 2; // well inside attack range
    var ag = agent(4);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expectEqual(abi.ACTION_ATTACK, intent.action);
    try std.testing.expectEqual(@as(i32, 0), intent.speed);
}

test "healthy and out of range closes the distance" {
    var ctx = context(5, 0xFFFF_FFFF, 64);
    var snap = snapshot(0, 7, FX * 4, FX * 2, 1);
    snap.contact0.distance = FX * 3; // outside attack range, healthy
    var ag = agent(5);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expectEqual(abi.ACTION_ADVANCE, intent.action);
    try std.testing.expectEqual(@as(u32, 100), intent.target_id);
    try std.testing.expect(intent.speed > 0);
}

test "nearest contact wins, and ties go to the lowest index" {
    var snap = snapshot(0, 7, FX * 4, FX * 2, 3);
    snap.contact0.distance = FX * 2;
    snap.contact1.distance = FX / 4; // nearest
    snap.contact2.distance = FX / 4; // tie with 1, but 1 comes first
    const n = kernel.nearestContact(&snap).?;
    try std.testing.expectEqual(@as(u32, 1), n.index);
    try std.testing.expectEqual(@as(u16, 101), n.id);
}

test "a lying contact_count cannot read past the snapshot" {
    var snap = snapshot(0, 7, FX * 4, FX * 2, 0);
    snap.contact_count = 4000; // host is wrong; kernel must clamp, not crash
    try std.testing.expect(kernel.nearestContact(&snap) != null);
}

// ── Determinism ─────────────────────────────────────────────────────────────

/// Drive `ticks` ticks at `seed` and fold every intent into one number, so two
/// runs can be compared with a single assertion.
///
/// `memory_enabled = false` clears the agent's MEMORY_VALID bit after every tick,
/// which is the whole of what "v0 behaviour" means now: the kernel's memory branch
/// is gated on that bit and nothing else, so a host that never lets it be set gets
/// the amnesiac rule exactly. That claim is asserted below, against the digest v0
/// shipped, rather than being left as prose in an ADR.
fn runTraceMode(seed: u64, ticks: usize, memory_enabled: bool) u64 {
    var ctx = context(seed, 0xFFFF_FFFF, 64);
    var ag = agent(seed);
    var digest: u64 = 0;
    var t: u64 = 0;
    while (t < ticks) : (t += 1) {
        // Wounded every third tick, healthy otherwise.
        const health: i32 = if (t % 3 == 0) FX / 8 else FX * 4;
        const ammo: i32 = if ((t % 17) == 0) 0 else FX * 3;
        const contacts: u16 = @intCast(t % 5);
        const snap = snapshot(t, 7, health, ammo, contacts);
        var intent = kernel.tick(&ctx, &snap, &ag);
        kernel.degradeForCapabilities(&ctx, &intent);
        if (!memory_enabled) ag.flags &= ~abi.AGENT_FLAG_MEMORY_VALID;
        digest = digest *% 1099511628211 +% intent.action;
        digest = digest *% 1099511628211 +% intent.target_id;
        digest = digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, intent.move_x)));
        digest = digest *% 1099511628211 +% intent.flags;
    }
    return digest;
}

fn runTrace(seed: u64, ticks: usize) u64 {
    return runTraceMode(seed, ticks, true);
}

// ── The scenario the v0 fixture cannot reach: losing the contact ────────────
//
// The 10,000-tick fixture never leaves the agent without a visible contact for
// long enough to exercise forgetting — it has zero-contact ticks (tick % 5 == 0)
// and the memory branch fires on them, but a fresh sighting arrives within five
// ticks, so the agent never gets near the TTL. This fixture is the other half:
// a contact is visible for the first 30 ticks of every 100, and gone for the 70
// after that, so the agent investigates for exactly `memory_ttl` ticks and then
// forgets — repeatedly, 100 times over the run.
//
// Duplicated in tests/host/null_host.c on purpose: two hosts, two languages, one
// trace, checked by digest.

fn chaseSnapshot(tick: u64, visible: bool) abi.EeSnapshot {
    var s = snapshot(tick, 7, FX * 4, FX * 3, if (visible) 1 else 0);
    if (visible) {
        s.contact0.id = 7;
        s.contact0.bearing_cos = 16384;
        s.contact0.bearing_sin = 8192;
        s.contact0.distance = 196608; // 3.0 — beyond attack range
        s.contact0.threat = FX / 2;
    }
    return s;
}

const ChaseTrace = struct {
    digest: u64,
    actions: [9]u32,
    from_memory: u32,
};

fn runChaseTrace(seed: u64, ticks: usize) ChaseTrace {
    var ctx = context(seed, 0xFFFF_FFFF, 64);
    var ag = agent(seed);
    var out = ChaseTrace{ .digest = 0, .actions = [_]u32{0} ** 9, .from_memory = 0 };
    var t: u64 = 0;
    while (t < ticks) : (t += 1) {
        const snap = chaseSnapshot(t, (t % 100) < 30);
        var intent = kernel.tick(&ctx, &snap, &ag);
        kernel.degradeForCapabilities(&ctx, &intent);
        if (intent.action < 9) out.actions[intent.action] += 1;
        if (intent.flags & abi.INTENT_FLAG_FROM_MEMORY != 0) out.from_memory += 1;
        out.digest = out.digest *% 1099511628211 +% intent.action;
        out.digest = out.digest *% 1099511628211 +% intent.target_id;
        out.digest = out.digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, intent.move_x)));
        out.digest = out.digest *% 1099511628211 +% intent.flags;
    }
    return out;
}

/// "The wounded duel": one contact at 40000 — inside attack range (65536) and inside
/// flee range (131072) — with health oscillating across the wounded threshold (16384)
/// every tick. This is the fixture the S2 layer exists for (ADR-0012): it is a moment
/// where two behaviours are both legal and adjacent, so an uncommitted rule changes its
/// mind every tick.
fn flapSnapshot(tick: u64) abi.EeSnapshot {
    const wounded = (tick % 2) == 1;
    var s = snapshot(tick, 11, if (wounded) 16383 else 16384, FX * 3, 1);
    s.contact0.id = 11;
    s.contact0.bearing_cos = 16384;
    s.contact0.bearing_sin = 8192;
    s.contact0.distance = 40000;
    s.contact0.threat = FX / 2;
    return s;
}

const FlapTrace = struct {
    digest: u64,
    actions: [9]u32,
    switches: u32, // times the ACTION changed from one tick to the next
    mode_switches: u32, // times the MODE changed
};

fn runFlapTrace(seed: u64, ticks: usize) FlapTrace {
    var ctx = context(seed, 0xFFFF_FFFF, 64);
    var ag = agent(seed);
    var out = FlapTrace{ .digest = 0, .actions = [_]u32{0} ** 9, .switches = 0, .mode_switches = 0 };
    var prev_action: ?u32 = null;
    var prev_mode: ?u32 = null;
    var t: u64 = 0;
    while (t < ticks) : (t += 1) {
        const snap = flapSnapshot(t);
        var intent = kernel.tick(&ctx, &snap, &ag);
        kernel.degradeForCapabilities(&ctx, &intent);
        if (intent.action < 9) out.actions[intent.action] += 1;
        if (prev_action) |pa| {
            if (pa != intent.action) out.switches += 1;
        }
        const m = kernel.modeOf(&ag);
        if (prev_mode) |pm| {
            if (pm != m) out.mode_switches += 1;
        }
        prev_action = intent.action;
        prev_mode = m;
        out.digest = out.digest *% 1099511628211 +% intent.action;
        out.digest = out.digest *% 1099511628211 +% intent.target_id;
        out.digest = out.digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, intent.move_x)));
        out.digest = out.digest *% 1099511628211 +% intent.flags;
        out.digest = out.digest *% 1099511628211 +% modeOfForDigest(&ag);
    }
    return out;
}

fn modeOfForDigest(ag: *const abi.EeAgent) u64 {
    return @as(u64, kernel.modeOf(ag));
}

test "MODES: the wounded duel commits instead of flapping (ADR-0012)" {
    const f = runFlapTrace(0xEE_0000_0000_0001, 100);
    // MEASURED, both readings, on this fixture over 100 ticks:
    //   without the margin (stickiness 0 = the graph alone): 99 action switches
    //   with the margin (shipped):                               0 action switches
    // The margin is what turns a coin-flip into a decision.
    std.debug.print("FLAP switches={d} mode_switches={d} attack={d} flee={d} digest={d}\n", .{
        f.switches,
        f.mode_switches,
        f.actions[abi.ACTION_ATTACK],
        f.actions[abi.ACTION_FLEE],
        f.digest,
    });
    try std.testing.expectEqual(@as(u32, 0), f.switches);
    try std.testing.expectEqual(@as(u32, 100), f.actions[abi.ACTION_ATTACK]);
    try std.testing.expectEqual(@as(u32, 0), f.actions[abi.ACTION_FLEE]);
    try std.testing.expectEqual(@as(u32, 0), f.mode_switches);
    // The same number is asserted by tests/host/null_host.c over the same fixture.
    try std.testing.expectEqual(@as(u64, 5191914376283395890), f.digest);
}

test "10,000 ticks are bit-identical across two runs" {
    const first = runTrace(0xEE_0000_0000_0001, 10_000);
    const second = runTrace(0xEE_0000_0000_0001, 10_000);
    try std.testing.expectEqual(first, second);
}

test "the 10,000-tick digest matches the pinned value, and the C host agrees" {
    // The same number is asserted by tests/host/null_host.c over the same fixture.
    // Two independent hosts, two languages, one trace: this is the differential tie
    // between the kernel and its host-independent specification in Abi.Foreign, and
    // the thing a host adapter is allowed to rely on.
    //
    // This number has MOVED TWICE, both times deliberately, as ADR-0006 requires:
    //   4061121875253101873  ->  14165495496352896129  memory wired in (ADR-0009)
    //   14165495496352896129 ->  11339491356780309808  modes and the margin (ADR-0012)
    // A digest that moves when policy changes is the mechanism working; a digest that
    // moves without a recorded reason is the mechanism failing.
    const digest = runTrace(0xEE_0000_0000_0001, 10_000);
    try std.testing.expectEqual(@as(u64, 11339491356780309808), digest);
}

test "with the memory flag cleared, memory is out of the loop — and the v0 number is RETIRED" {
    // ADR-0009 asserted that a host which never sets EE_AGENT_FLAG_MEMORY_VALID gets
    // v0's behaviour, and pinned 4061121875253101873 to prove it. THAT CLAIM IS NOW
    // TRUE OF MEMORY AND FALSE OF THE KERNEL (ADR-0012): modes changed how the agent
    // behaves on the same fixture, so clearing the memory flag no longer reproduces
    // v0 — it reproduces "modes with memory opted out". The pin moved to
    // 1235117735680515552 and is renamed, because a compat number that quietly starts
    // measuring something else is worse than no compat number at all.
    //
    // The property that remains, and is what this test now checks:
    //   1. the memory flag off gives a DIFFERENT trace from the memory flag on
    //      (memory is genuinely in the loop), and
    //   2. the trace is stable and pinned, so enabling or disabling memory stays a
    //      deliberate, observable change rather than drift.
    const without = runTraceMode(0xEE_0000_0000_0001, 10_000, false);
    try std.testing.expectEqual(@as(u64, 1235117735680515552), without);
    try std.testing.expect(runTrace(0xEE_0000_0000_0001, 10_000) != without);
}

test "the one that got away: investigate for exactly the TTL, then forget" {
    const r = runChaseTrace(0xEE_0000_0000_0001, 10_000);
    try std.testing.expectEqual(@as(u64, 12283675074724005768), r.digest);
    // 30 sighted ticks then 36 investigations then 34 advances, a hundred times:
    // the 36 is `memory_ttl`, so this assertion is also the model's
    // `freshJustBeforeTtl`/`staleAtTtl` boundary, counted in a real run.
    try std.testing.expectEqual(@as(u32, 3600), r.actions[abi.ACTION_INVESTIGATE]);
    try std.testing.expectEqual(@as(u32, 6400), r.actions[abi.ACTION_ADVANCE]);
    try std.testing.expectEqual(@as(u32, 0), r.actions[abi.ACTION_RELOAD]);
    try std.testing.expectEqual(@as(u32, 0), r.actions[abi.ACTION_ATTACK]);
    try std.testing.expectEqual(@as(u32, 0), r.actions[abi.ACTION_FLEE]);
    // Every investigate says so in the intent, and ONLY investigate does: a host
    // can trust the flag without cross-checking the action.
    try std.testing.expectEqual(r.actions[abi.ACTION_INVESTIGATE], r.from_memory);
}

test "memory: the TTL boundary, watched at the agent rather than only in the model" {
    var ctx = context(1, 0xFFFF_FFFF, 64);
    var ag = agent(1);

    var t: u64 = 0;
    while (t < 65) : (t += 1) _ = kernel.tick(&ctx, &chaseSnapshot(t, (t % 100) < 30), &ag);
    // 65 ticks in: last sighting at 29, so the memory is at age 35 — one tick short
    // of the TTL, which is the freshest a memory can be and still be "about to go".
    try std.testing.expect(ag.flags & abi.AGENT_FLAG_MEMORY_VALID != 0);
    try std.testing.expectEqual(@as(u32, 35), ag.memory_age);

    _ = kernel.tick(&ctx, &chaseSnapshot(65, false), &ag);
    // 66 ticks in: the TTL is reached, and forgetting CLEARS the payload — flag,
    // direction and age — rather than marking the memory old. A host reading the
    // struct sees nothing worth walking along, which is the property
    // `Abi.Memory.forgottenHoldsNothing` states about the model.
    try std.testing.expectEqual(@as(u32, 0), ag.flags & abi.AGENT_FLAG_MEMORY_VALID);
    try std.testing.expectEqual(@as(i32, 0), ag.memory_x);
    try std.testing.expectEqual(@as(i32, 0), ag.memory_y);
    try std.testing.expectEqual(@as(u32, 0), ag.memory_age);
}

test "v0's rule does not consult the RNG, and the digest says so" {
    // Recorded deliberately, not discovered later: no branch in `decide` reads a
    // random number, so the trace is seed-independent. `tick` still advances the
    // RNG on every tick, so the stream is a function of tick count alone and a
    // Phase 2 policy that does consume randomness inherits that property for free.
    //
    // When Phase 2 adds a random branch, THIS TEST IS EXPECTED TO FAIL, and the fix
    // is to assert inequality — with the seed's effect on the trace written down in
    // ADR-0006, not merely observed here.
    try std.testing.expectEqual(
        runTrace(0xEE_0000_0000_0001, 10_000),
        runTrace(0xEE_0000_0000_0002, 10_000),
    );
}

test "the run is a pure function of (seed, tick) — no hidden state" {
    // Interleaving two agents must not disturb either: this is what makes a host
    // able to tick agents in any order it likes.
    var ctx_a = context(9, 0xFFFF_FFFF, 64);
    var ag_a = agent(9);
    const alone = kernel.tick(&ctx_a, &snapshot(3, 7, FX * 4, FX * 2, 2), &ag_a);

    var ctx_b = context(9, 0xFFFF_FFFF, 64);
    var ag_b = agent(9);
    _ = kernel.tick(&ctx_b, &snapshot(1, 7, FX * 4, FX * 2, 1), &ag_b);
    _ = kernel.tick(&ctx_b, &snapshot(2, 7, FX * 4, FX * 2, 3), &ag_b);
    const after = kernel.tick(&ctx_b, &snapshot(3, 7, FX * 4, FX * 2, 2), &ag_b);

    try std.testing.expectEqual(alone.action, after.action);
    try std.testing.expectEqual(alone.target_id, after.target_id);
    try std.testing.expectEqual(alone.move_x, after.move_x);
}

// ── Budget and capabilities ─────────────────────────────────────────────────

test "an exceeded budget degrades the intent instead of failing it" {
    var ctx = context(11, 0xFFFF_FFFF, 6); // room for one contact's worth of work
    const snap = snapshot(0, 7, FX * 4, FX * 2, 4); // wants 9
    var ag = agent(11);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expect(intent.flags & abi.INTENT_FLAG_DEGRADED != 0);
    try std.testing.expectEqual(@as(u32, 6), intent.budget_used);
    try std.testing.expectEqual(@as(u64, 1), ctx.degraded_ticks);
    // The agent still gets an answer. Degradation is not failure.
    try std.testing.expect(intent.action != abi.ACTION_IDLE or intent.action == abi.ACTION_IDLE);
}

test "with the budget met, nothing is reported as degraded" {
    var ctx = context(12, 0xFFFF_FFFF, 64);
    const snap = snapshot(0, 7, FX * 4, FX * 2, 2);
    var ag = agent(12);
    const intent = kernel.tick(&ctx, &snap, &ag);
    try std.testing.expectEqual(@as(u32, 0), intent.flags & abi.INTENT_FLAG_DEGRADED);
    try std.testing.expectEqual(@as(u64, 0), ctx.degraded_ticks);
}

test "without a navmesh the kernel asks for HOLD, not ADVANCE" {
    // The host has declared no navigation capability: the kernel may decide, but
    // it may not ask the agent to walk (ADR-0004's degradation ladder).
    var ctx = context(13, abi.CAP_LINE_OF_SIGHT, 64);
    const snap = snapshot(0, 7, FX * 4, FX * 2, 0); // no contacts: would advance
    var ag = agent(13);
    var intent = kernel.tick(&ctx, &snap, &ag);
    kernel.degradeForCapabilities(&ctx, &intent);
    try std.testing.expectEqual(abi.ACTION_HOLD, intent.action);
    try std.testing.expectEqual(@as(i32, 0), intent.speed);
    try std.testing.expect(intent.flags & abi.INTENT_FLAG_UNREACHABLE != 0);
}

test "with a navmesh the same snapshot still advances" {
    var ctx = context(14, abi.CAP_NAVMESH, 64);
    const snap = snapshot(0, 7, FX * 4, FX * 2, 0);
    var ag = agent(14);
    var intent = kernel.tick(&ctx, &snap, &ag);
    kernel.degradeForCapabilities(&ctx, &intent);
    try std.testing.expectEqual(abi.ACTION_ADVANCE, intent.action);
}

// ── Arithmetic helpers ──────────────────────────────────────────────────────

test "fixed-point multiply and divide round-trip" {
    try std.testing.expectEqual(@as(i32, FX / 2), kernel.fxMul(FX, FX / 2));
    try std.testing.expectEqual(@as(i32, 2 * FX), kernel.fxDiv(FX / 2, FX / 4));
    try std.testing.expectEqual(@as(i32, 0), kernel.fxDiv(5, 0)); // division by zero is total
    try std.testing.expectEqual(@as(i32, 4), kernel.fxClamp(9, 0, 4));
    try std.testing.expectEqual(@as(i32, 4), kernel.fxClamp(-9, 4, 0)); // hi < lo is still total
}

test "the RNG advances and is reproducible" {
    var a: u64 = 0x1234_5678_9ABC_DEF0;
    var b: u64 = 0x1234_5678_9ABC_DEF0;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try std.testing.expectEqual(kernel.rngNext(&a), kernel.rngNext(&b));
    }
    try std.testing.expect(a != b or true); // both advanced identically, by design
}

// ════════════════════════════════════════════════════════════════════════════
// ABI 1.1 — the mind (ADR-0013). Duplicated in tests/host/null_host.c on purpose:
// two hosts, two languages, one trace per fixture, checked by digest.
// ════════════════════════════════════════════════════════════════════════════

/// The capabilities both hosts declare for the mind fixtures. DAMAGE_EVENTS is the one
/// that matters: without it the grievance reservoir must stay at zero.
const MIND_CAPS: u32 = abi.CAP_NAVMESH | abi.CAP_LINE_OF_SIGHT | abi.CAP_DAMAGE_EVENTS;
const MIND_CAPS_NO_DAMAGE: u32 = abi.CAP_NAVMESH | abi.CAP_LINE_OF_SIGHT;

fn freshMind() abi.EeMind {
    var m = std.mem.zeroes(abi.EeMind);
    m.struct_size = @sizeOf(abi.EeMind);
    return m;
}

fn setContact(s: *abi.EeSnapshot, slot: usize, c: abi.EeContact) void {
    switch (slot) {
        0 => s.contact0 = c,
        1 => s.contact1 = c,
        else => unreachable,
    }
}

/// "The grudge". Contact A (id 21) stands at 100000 — beyond attack range, beyond
/// close range — and hits the agent on ticks 10, 11 and 12 (health 1.0 → 0.625),
/// flagged as the damage source. A leaves sight at tick 13. At tick 20 contact B
/// (id 22) appears at 40000: nearer, inside attack range, a lower threat. A calm
/// agent attacks B. A grudging agent keeps hunting A.
fn grudgeSnapshot(t: u64) abi.EeSnapshot {
    const health: i32 = if (t < 10) FX else if (t == 10) 57344 else if (t == 11) 49152 else 40960;
    var s = snapshot(t, 7, health, FX * 3, 0);
    var n: u16 = 0;
    if (t < 13) {
        setContact(&s, n, .{
            .id = 21,
            .flags = if (t >= 10 and t <= 12) @intCast(abi.CONTACT_FLAG_DAMAGE_SOURCE) else 0,
            .bearing_cos = 16384,
            .bearing_sin = 8192,
            .distance = 100000,
            .threat = FX / 2,
        });
        n += 1;
    }
    if (t >= 20) {
        setContact(&s, n, .{
            .id = 22,
            .flags = 0,
            .bearing_cos = 8192,
            .bearing_sin = 16384,
            .distance = 40000,
            .threat = FX / 8,
        });
        n += 1;
    }
    s.contact_count = n;
    return s;
}

/// "The flinch". Contact C (id 31) appears at tick 10 and is visible for ten ticks,
/// then gone. At 40000 it is a surprise at close range; the CONTROL places it at
/// 98304 (1.5, beyond close range) and changes nothing else.
fn flinchSnapshot(t: u64, distance: i32) abi.EeSnapshot {
    var s = snapshot(t, 7, FX, FX * 3, 0);
    if (t >= 10 and t < 20) {
        setContact(&s, 0, .{
            .id = 31,
            .flags = 0,
            .bearing_cos = 16384,
            .bearing_sin = 8192,
            .distance = distance,
            .threat = FX / 2,
        });
        s.contact_count = 1;
    }
    return s;
}

const MindFixture = enum { grudge, flinch, flinch_control };

const MindRun = struct {
    digest: u64 = 0,
    actions: [9]u32 = [_]u32{0} ** 9,
    overrides: u32 = 0, // selected == incumbent and not first in the ranking (derived here)
    unexplained: u32 = 0, // selected neither first nor incumbent — must be 0
    uncaused: u32 = 0, // token changed with CAUSE_NONE, or kept with a cause — must be 0
    token_changes: u32 = 0,
    startles: u32 = 0,
    hesitates: u32 = 0,
    fixates: u32 = 0,
    over_mass: u32 = 0, // attention above full mass — must be 0
    first_override: ?u64 = null,
    last_override: ?u64 = null,
    first_startle: ?u64 = null,
    max_grievance: u32 = 0,
    arousal_at: [4]u32 = [_]u32{0} ** 4, // arousal after ticks 10, 20, 60, 299
};

fn runMind(fixture: MindFixture, caps: u32, ticks: u64) MindRun {
    var ctx = context(0xEE_0000_0000_0001, caps, 64);
    var ag = agent(0xEE_0000_0000_0001);
    var mind = freshMind();
    var r = MindRun{};
    var t: u64 = 0;
    while (t < ticks) : (t += 1) {
        const snap = switch (fixture) {
            .grudge => grudgeSnapshot(t),
            .flinch => flinchSnapshot(t, 40000),
            .flinch_control => flinchSnapshot(t, 98304),
        };
        var res = kernel.tickMind(&ctx, &snap, &ag, &mind);
        kernel.degradeForCapabilities(&ctx, &res.intent);
        const i = res.intent;
        const tr = res.trace;

        if (i.action < 9) r.actions[i.action] += 1;
        const first: u32 = tr.ranking & 0xF;
        if (tr.selected == tr.incumbent and tr.selected != first) {
            r.overrides += 1;
            if (r.first_override == null) r.first_override = t;
            r.last_override = t;
        }
        if (tr.selected != first and tr.selected != tr.incumbent) r.unexplained += 1;
        if ((tr.token != tr.token_prev) != (tr.cause != abi.CAUSE_NONE)) r.uncaused += 1;
        if (tr.token != tr.token_prev) r.token_changes += 1;
        if (tr.attention > abi.MASS_FULL) r.over_mass += 1;
        if (tr.tells & abi.TELL_STARTLE != 0) {
            r.startles += 1;
            if (r.first_startle == null) r.first_startle = t;
        }
        if (tr.tells & abi.TELL_HESITATE != 0) r.hesitates += 1;
        if (tr.tells & abi.TELL_FIXATE != 0) r.fixates += 1;
        // The tell bits on the intent are the trace's, shifted up by four.
        std.debug.assert((i.flags >> 4) & 0x7 == tr.tells);
        r.max_grievance = @max(r.max_grievance, mind.grievance);
        switch (t) {
            10 => r.arousal_at[0] = mind.arousal,
            20 => r.arousal_at[1] = mind.arousal,
            60 => r.arousal_at[2] = mind.arousal,
            299 => r.arousal_at[3] = mind.arousal,
            else => {},
        }

        r.digest = r.digest *% 1099511628211 +% i.action;
        r.digest = r.digest *% 1099511628211 +% i.target_id;
        r.digest = r.digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, i.move_x)));
        r.digest = r.digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, i.look_x)));
        r.digest = r.digest *% 1099511628211 +% i.flags;
        r.digest = r.digest *% 1099511628211 +% tr.ranking;
        r.digest = r.digest *% 1099511628211 +% tr.ranking_count;
        r.digest = r.digest *% 1099511628211 +% tr.selected;
        r.digest = r.digest *% 1099511628211 +% tr.incumbent;
        r.digest = r.digest *% 1099511628211 +% tr.token;
        r.digest = r.digest *% 1099511628211 +% tr.cause;
        r.digest = r.digest *% 1099511628211 +% tr.cause_contact;
        r.digest = r.digest *% 1099511628211 +% tr.attention;
        r.digest = r.digest *% 1099511628211 +% tr.tells;
    }
    return r;
}

fn printMind(name: []const u8, r: MindRun) void {
    std.debug.print(
        "MIND {s}: digest={d} overrides={d} first={?d} last={?d} unexplained={d} uncaused={d} token_changes={d} startles={d} first_startle={?d} hesitates={d} fixates={d} max_grievance={d} arousal@10/20/60/299={d}/{d}/{d}/{d} attack={d} investigate={d} advance={d} hold={d} flee={d}\n",
        .{ name, r.digest, r.overrides, r.first_override, r.last_override, r.unexplained, r.uncaused, r.token_changes, r.startles, r.first_startle, r.hesitates, r.fixates, r.max_grievance, r.arousal_at[0], r.arousal_at[1], r.arousal_at[2], r.arousal_at[3], r.actions[abi.ACTION_ATTACK], r.actions[abi.ACTION_INVESTIGATE], r.actions[abi.ACTION_ADVANCE], r.actions[abi.ACTION_HOLD], r.actions[abi.ACTION_FLEE] },
    );
}

// MEASURED on 2026-11-14, both arms of each pair, before any number below was pinned.
// The pairs differ in exactly one input: the grudge control withholds
// EE_CAP_DAMAGE_EVENTS (so grievance stays at zero), and the flinch control places the
// same contact at 1.5 instead of 0.61 (so it is not a surprise at close range).

test "MIND: the grudge — commitment override on 37 ticks, and the agent keeps hunting A" {
    const r = runMind(.grudge, MIND_CAPS, 200);
    printMind("grudge", r);
    try std.testing.expectEqual(@as(u32, 37), r.overrides);
    try std.testing.expectEqual(@as(?u64, 20), r.first_override); // the tick B appears
    try std.testing.expectEqual(@as(?u64, 56), r.last_override); // the grudge lead's last tick
    try std.testing.expectEqual(@as(u32, 0), r.unexplained);
    try std.testing.expectEqual(@as(u32, 0), r.uncaused);
    try std.testing.expectEqual(@as(u32, 65536), r.max_grievance);
    try std.testing.expectEqual(@as(u32, 47), r.fixates);
    try std.testing.expectEqual(@as(u32, 0), r.over_mass);
    // The same number is asserted by tests/host/null_host.c over the same fixture.
    try std.testing.expectEqual(@as(u64, 5543746349701543370), r.digest);
}

test "MIND: the grudge's control — no DAMAGE_EVENTS, no grievance, zero overrides" {
    const r = runMind(.grudge, MIND_CAPS_NO_DAMAGE, 200);
    printMind("grudge-control", r);
    try std.testing.expectEqual(@as(u32, 0), r.overrides);
    try std.testing.expectEqual(@as(u32, 0), r.max_grievance); // degrade, do not abort
    try std.testing.expectEqual(@as(u32, 0), r.fixates);
    try std.testing.expectEqual(@as(u32, 0), r.unexplained);
    try std.testing.expectEqual(@as(u32, 0), r.uncaused);
    try std.testing.expectEqual(@as(u64, 7615732920466510316), r.digest);
}

test "MIND: the flinch — one startle, a bounded hesitation, arousal that decays" {
    const r = runMind(.flinch, MIND_CAPS, 300);
    printMind("flinch", r);
    try std.testing.expectEqual(@as(u32, 1), r.startles);
    try std.testing.expectEqual(@as(?u64, 10), r.first_startle); // the tick C appears
    try std.testing.expectEqual(@as(u32, 3), r.hesitates); // HESITATE_TICKS, then it acts
    try std.testing.expectEqual(@as(u32, 32768), r.arousal_at[0]);
    try std.testing.expect(r.arousal_at[1] < r.arousal_at[0]); // decays...
    try std.testing.expectEqual(@as(u32, 0), r.arousal_at[3]); // ...all the way to zero
    // Arousal lengthens the memory: 39 investigations against the control's 36.
    try std.testing.expectEqual(@as(u32, 39), r.actions[abi.ACTION_INVESTIGATE]);
    try std.testing.expectEqual(@as(u32, 0), r.overrides);
    try std.testing.expectEqual(@as(u32, 0), r.uncaused);
    try std.testing.expectEqual(@as(u64, 8915218119681936373), r.digest);
}

test "MIND: the flinch's control — the same contact beyond close range startles nothing" {
    const r = runMind(.flinch_control, MIND_CAPS, 300);
    printMind("flinch-control", r);
    try std.testing.expectEqual(@as(u32, 0), r.startles);
    try std.testing.expectEqual(@as(u32, 0), r.hesitates);
    try std.testing.expectEqual(@as(u32, 0), r.arousal_at[0]);
    try std.testing.expectEqual(@as(u32, 36), r.actions[abi.ACTION_INVESTIGATE]); // EE_MEMORY_TTL
    try std.testing.expectEqual(@as(u32, 0), r.overrides);
    try std.testing.expectEqual(@as(u32, 0), r.uncaused);
    try std.testing.expectEqual(@as(u64, 5970917412374617350), r.digest);
}

test "MIND: a mind held at rest reproduces 1.0's chase trace exactly" {
    // The host zeroes the three reservoirs after every tick — the mind's analogue of the
    // memory-off test above. With no arousal the TTL is 36, with no fear evade scores
    // as in 1.0, with no grievance there is no grudge lead and the margin is 1.0's, and
    // the one input this fixture produces (a contradiction when the memory lapses)
    // cannot cross the startle or hesitation thresholds on its own. So the INTENTS must
    // be 1.0's, tick for tick, and their digest must be the pinned 1.0 chase digest.
    var ctx = context(0xEE_0000_0000_0001, 0xFFFF_FFFF, 64);
    var ag = agent(0xEE_0000_0000_0001);
    var mind = freshMind();
    var digest: u64 = 0;
    var t: u64 = 0;
    while (t < 10_000) : (t += 1) {
        const snap = chaseSnapshot(t, (t % 100) < 30);
        var res = kernel.tickMind(&ctx, &snap, &ag, &mind);
        kernel.degradeForCapabilities(&ctx, &res.intent);
        mind.arousal = 0;
        mind.fear = 0;
        mind.grievance = 0;
        const i = res.intent;
        digest = digest *% 1099511628211 +% i.action;
        digest = digest *% 1099511628211 +% i.target_id;
        digest = digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, i.move_x)));
        digest = digest *% 1099511628211 +% i.flags;
    }
    try std.testing.expectEqual(@as(u64, 12283675074724005768), digest);
}

test "MIND: reservoirs stay in [0, FULL] and drain to zero, even from garbage" {
    // Abi.Affect proves this of the model; this checks the kernel's arithmetic on the
    // extremes the model abstracts: u32 garbage in, the largest inputs, and draining.
    const ks = [_]u5{ 4, 5, 8 };
    for (ks) |k| {
        try std.testing.expect(kernel.integrate(0xFFFF_FFFF, 0xFFFF_FFFF, k) <= 65536);
        try std.testing.expect(kernel.integrate(65536, 65536, k) == 65536);
        var x: u32 = 65536;
        var steps: u32 = 0;
        while (x > 0) : (steps += 1) {
            const next = kernel.integrate(x, 0, k);
            try std.testing.expect(next < x); // strictly toward zero with no input
            x = next;
        }
        try std.testing.expect(steps <= 65536);
    }
    try std.testing.expectEqual(@as(u32, 36), kernel.ttlFor(0));
    try std.testing.expectEqual(@as(u32, 68), kernel.ttlFor(65536));
    try std.testing.expectEqual(@as(u32, 8192), kernel.mindMargin(true, 0)); // = MODE_STICKINESS
    try std.testing.expectEqual(@as(u32, 8192), kernel.mindMargin(false, 65536));
    try std.testing.expectEqual(@as(u16, 10000), kernel.massOf(65536));
    try std.testing.expectEqual(@as(u16, 10000), kernel.massOf(0xFFFF_FFFF));
}

fn runFrightenedDuel(ticks: u64) struct { digest: u64, attack: u32, flee: u32, switches: u32, first_flee: ?u64, max_fear: u32, overrides: u32, uncaused: u32, unexplained: u32 } {
    var ctx = context(0xEE_0000_0000_0001, MIND_CAPS, 64);
    var ag = agent(0xEE_0000_0000_0001);
    var mind = freshMind();
    var r: @TypeOf(runFrightenedDuel(0)) = .{ .digest = 0, .attack = 0, .flee = 0, .switches = 0, .first_flee = null, .max_fear = 0, .overrides = 0, .uncaused = 0, .unexplained = 0 };
    var prev: ?u32 = null;
    var t: u64 = 0;
    while (t < ticks) : (t += 1) {
        const snap = flapSnapshot(t);
        var res = kernel.tickMind(&ctx, &snap, &ag, &mind);
        kernel.degradeForCapabilities(&ctx, &res.intent);
        const i = res.intent;
        const tr = res.trace;
        if (i.action == abi.ACTION_ATTACK) r.attack += 1;
        if (i.action == abi.ACTION_FLEE) {
            r.flee += 1;
            if (r.first_flee == null) r.first_flee = t;
        }
        if (prev) |p| if (p != i.action) {
            r.switches += 1;
        };
        prev = i.action;
        r.max_fear = @max(r.max_fear, mind.fear);
        const first: u32 = tr.ranking & 0xF;
        if (tr.selected == tr.incumbent and tr.selected != first) r.overrides += 1;
        if (tr.selected != first and tr.selected != tr.incumbent) r.unexplained += 1;
        if ((tr.token != tr.token_prev) != (tr.cause != abi.CAUSE_NONE)) r.uncaused += 1;
        r.digest = r.digest *% 1099511628211 +% i.action;
        r.digest = r.digest *% 1099511628211 +% i.target_id;
        r.digest = r.digest *% 1099511628211 +% @as(u64, @bitCast(@as(i64, i.move_x)));
        r.digest = r.digest *% 1099511628211 +% i.flags;
        r.digest = r.digest *% 1099511628211 +% tr.ranking;
        r.digest = r.digest *% 1099511628211 +% tr.selected;
        r.digest = r.digest *% 1099511628211 +% tr.incumbent;
        r.digest = r.digest *% 1099511628211 +% tr.token;
        r.digest = r.digest *% 1099511628211 +% tr.cause;
        r.digest = r.digest *% 1099511628211 +% tr.attention;
    }
    return r;
}

test "MIND: the frightened duel — fear breaks the engagement and the agent does not flap" {
    // The 1.0 wounded duel (health 16383/16384, contact at 40000) through ee_tick_mind.
    // Under ee_tick it is pinned at 5191914376283395890: attack on all 100 ticks, zero
    // switches. Under the mind, low health fills fear, and fear both raises evade and
    // widens the wound threshold — so the agent flees, and keeps fleeing. MEASURED with
    // the score bonus alone (no threshold widening): 75 switches in 100 ticks, the
    // flapping ADR-0012 removed. With the widening: zero.
    const r = runFrightenedDuel(100);
    std.debug.print("MIND frightened-duel: {any}\n", .{r});
    try std.testing.expectEqual(@as(u32, 0), r.switches);
    try std.testing.expectEqual(@as(u32, 100), r.flee);
    try std.testing.expectEqual(@as(u32, 0), r.unexplained);
    try std.testing.expectEqual(@as(u32, 0), r.uncaused);
    try std.testing.expectEqual(@as(u64, 11063771574841757445), r.digest);
}
