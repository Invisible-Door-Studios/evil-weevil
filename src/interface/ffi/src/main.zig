// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
//
// The C ABI, as exported symbols.
//
// This file is the boundary and nothing more: it validates arguments, delegates
// to the kernel, and answers every failure with a status code. It allocates
// nothing (the host owns `ee_context` and the agent array — ADR-0005 §4), it
// never calls into the host (ADR-0004), and it contains no policy.
//
// The structs and every numeric constant come from `abi.zig`, which asserts the
// layout at comptime against the numbers `Abi.Gen` emitted from the Idris2 model.

const abi = @import("abi");
const kernel = @import("kernel");

// ── Introspection ───────────────────────────────────────────────────────────

pub export fn ee_version_info() abi.EeVersion {
    return .{
        .major = @intCast(abi.ABI_MAJOR),
        .minor = @intCast(abi.ABI_MINOR),
        .patch = 0,
        .reserved = 0,
    };
}

pub export fn ee_abi_fingerprint() u64 {
    return abi.ABI_FINGERPRINT;
}

/// Human-readable status name. Static storage — the caller must not free it, and
/// no allocation happens on this path either.
pub export fn ee_status_name(status: u32) [*:0]const u8 {
    return switch (status) {
        abi.STATUS_OK => "ee_ok",
        abi.STATUS_BAD_PARAM => "ee_bad_param",
        abi.STATUS_VERSION_MISMATCH => "ee_version_mismatch",
        abi.STATUS_FINGERPRINT_MISMATCH => "ee_fingerprint_mismatch",
        abi.STATUS_CAPABILITY_UNSUPPORTED => "ee_capability_unsupported",
        abi.STATUS_BUFFER_TOO_SMALL => "ee_buffer_too_small",
        abi.STATUS_PANIC_CAUGHT => "ee_panic_caught",
        else => "ee_unknown_status",
    };
}

/// Work units per tick, per agent, before the kernel starts degrading.
///
/// A constant, and stated as one rather than dressed up as a calculation: the v0
/// `ee_init_desc` has no field to carry a host-declared budget, so there is nothing
/// to compute it FROM. Sixteen units is enough for the five-branch rule plus a
/// handful of contacts, which means an honest v0 host sees no degradation at all and
/// the degradation path is exercised by tests rather than by every call.
///
/// `max_agents` is the only input available, and scaling the per-agent budget by how
/// many agents the host declared would be a policy the model does not contain — a
/// number that looks considered but is not. When the descriptor grows a
/// `budget_units` field (a minor version bump, ADR-0005) this becomes that field, and
/// this comment goes away rather than quietly becoming wrong.
fn defaultBudgetUnits(max_agents: u32) u32 {
    _ = max_agents;
    return 16;
}

// ── Init ────────────────────────────────────────────────────────────────────

/// Validate the host's declaration and initialise the caller-owned context.
///
/// Every rejection is ANSWERED, not thrown: a version mismatch, a fingerprint
/// mismatch and a host that cannot hold our agent struct all come back as status
/// codes with the reason visible, because a host that links successfully and
/// fails silently at runtime is the failure mode this ABI exists to prevent
/// (ADR-0005 §2 and §3).
pub export fn ee_init(desc: ?*const abi.EeInitDesc, ctx: ?*abi.EeContext) u32 {
    const d = desc orelse return abi.STATUS_BAD_PARAM;
    const c = ctx orelse return abi.STATUS_BAD_PARAM;

    // The host states the size it compiled against; if it does not match ours,
    // its struct disagrees with the ABI, and every later call is unsafe.
    if (d.struct_size != @sizeOf(abi.EeInitDesc)) return abi.STATUS_BUFFER_TOO_SMALL;

    if (d.abi_major != abi.ABI_MAJOR) return abi.STATUS_VERSION_MISMATCH;

    // A zero fingerprint means "not declared": a host may skip the check, but a
    // host that declares one is held to it.
    if (d.abi_fingerprint != 0 and d.abi_fingerprint != abi.ABI_FINGERPRINT) {
        return abi.STATUS_FINGERPRINT_MISMATCH;
    }

    c.* = .{
        .abi_major = d.abi_major,
        .flags = d.flags,
        .capabilities = d.capabilities,
        .budget_units = defaultBudgetUnits(d.max_agents),
        .max_agents = d.max_agents,
        .reserved0 = 0,
        .abi_fingerprint = abi.ABI_FINGERPRINT,
        .rng_seed = d.rng_seed,
        .tick_rate_num = d.host_tick_num,
        .tick_rate_den = d.host_tick_den,
        .ticks_run = 0,
        .degraded_ticks = 0,
    };
    return abi.STATUS_OK;
}

// ── Tick ────────────────────────────────────────────────────────────────────

/// One agent, one tick. Returns the intent by value: the caller owns nothing, and
/// nothing is allocated.
///
/// Argument validation is deliberately total — every pointer is checked, and a
/// rejected call returns a status rather than dereferencing anything.
pub export fn ee_tick(
    ctx: ?*abi.EeContext,
    snap: ?*const abi.EeSnapshot,
    agent: ?*abi.EeAgent,
    out: ?*abi.EeIntent,
) u32 {
    const c = ctx orelse return abi.STATUS_BAD_PARAM;
    const s = snap orelse return abi.STATUS_BAD_PARAM;
    const a = agent orelse return abi.STATUS_BAD_PARAM;
    const o = out orelse return abi.STATUS_BAD_PARAM;

    // A context that was never initialised, or was overwritten, is refused here
    // rather than producing plausible-looking garbage intents.
    if (c.abi_major != abi.ABI_MAJOR) return abi.STATUS_VERSION_MISMATCH;

    var intent = kernel.tick(c, s, a);
    kernel.degradeForCapabilities(c, &intent);
    o.* = intent;
    return abi.STATUS_OK;
}

// ── ABI 1.1: the mind (ADR-0013) ─────────────────────────────────────────────

pub export fn ee_mind_fingerprint() u64 {
    return abi.MIND_FINGERPRINT;
}

/// One agent, one tick, with a mind. A new entrance rather than a change to `ee_tick`,
/// so a host that never calls it gets 1.0 behaviour exactly — `ee_tick` above is the
/// same function it was at 1.0, and its pinned digests are the evidence.
///
/// Every argument is validated BEFORE anything is written, so a rejected call leaves the
/// agent, the mind and the context exactly as they were. `trace` is optional; a host
/// that passes one states its size, and a size smaller than this ABI's record is refused
/// rather than overrun.
pub export fn ee_tick_mind(
    ctx: ?*abi.EeContext,
    snap: ?*const abi.EeSnapshot,
    agent: ?*abi.EeAgent,
    mind: ?*abi.EeMind,
    out: ?*abi.EeIntent,
    trace: ?*abi.EeMindTrace,
) u32 {
    const c = ctx orelse return abi.STATUS_BAD_PARAM;
    const s = snap orelse return abi.STATUS_BAD_PARAM;
    const a = agent orelse return abi.STATUS_BAD_PARAM;
    const m = mind orelse return abi.STATUS_BAD_PARAM;
    const o = out orelse return abi.STATUS_BAD_PARAM;

    if (c.abi_major != abi.ABI_MAJOR) return abi.STATUS_VERSION_MISMATCH;
    if (m.struct_size < @sizeOf(abi.EeMind)) return abi.STATUS_BUFFER_TOO_SMALL;
    if (trace) |t| {
        if (t.struct_size < @sizeOf(abi.EeMindTrace)) return abi.STATUS_BUFFER_TOO_SMALL;
    }

    var r = kernel.tickMind(c, s, a, m);
    kernel.degradeForCapabilities(c, &r.intent);
    o.* = r.intent;
    if (trace) |t| t.* = r.trace;
    return abi.STATUS_OK;
}

// ── Shutdown ────────────────────────────────────────────────────────────────

/// Nothing to free: the kernel owns no memory. Present so a host's teardown path
/// has a place to call, and so the ABI's shape does not change when Phase 2 does
/// need per-context release.
pub export fn ee_shutdown(ctx: ?*abi.EeContext) void {
    const c = ctx orelse return;
    c.ticks_run = 0;
}
