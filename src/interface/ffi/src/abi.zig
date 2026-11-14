// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (metadatastician) <j.d.a.jewell@open.ac.uk>
//
// The ABI structs, as Zig sees them, plus the comptime gate that ties them to the
// generated numbers.
//
// This is the third and last layer of the layout net (see Abi/Layout.idr):
//
//   1. Idris2 proves the offsets and sizes we INTEND.
//   2. The C compiler asserts (in the generated header) that it produced them.
//   3. THIS FILE asserts that the Zig structs the kernel actually reads and writes
//      have those same offsets and sizes — at compile time, so a mismatch is a
//      build failure and can never become memory corruption in somebody's game.
//
// Nothing here is hand-numbered: every expected value comes from the generated
// `ee_layout.zig`, which `Abi.Gen` emits from the same model as the C header.

const layout = @import("layout");

// ── Enum constants ──────────────────────────────────────────────────────────
// Re-exported from the generated file so the kernel never retypes a bit position.

pub const STATUS_OK = layout.STATUS_OK;
pub const STATUS_BAD_PARAM = layout.STATUS_BAD_PARAM;
pub const STATUS_VERSION_MISMATCH = layout.STATUS_VERSION_MISMATCH;
pub const STATUS_FINGERPRINT_MISMATCH = layout.STATUS_FINGERPRINT_MISMATCH;
pub const STATUS_CAPABILITY_UNSUPPORTED = layout.STATUS_CAPABILITY_UNSUPPORTED;
pub const STATUS_BUFFER_TOO_SMALL = layout.STATUS_BUFFER_TOO_SMALL;
pub const STATUS_PANIC_CAUGHT = layout.STATUS_PANIC_CAUGHT;

pub const ACTION_IDLE = layout.ACTION_IDLE;
pub const ACTION_ADVANCE = layout.ACTION_ADVANCE;
pub const ACTION_HOLD = layout.ACTION_HOLD;
pub const ACTION_FLEE = layout.ACTION_FLEE;
pub const ACTION_ATTACK = layout.ACTION_ATTACK;
pub const ACTION_RELOAD = layout.ACTION_RELOAD;
pub const ACTION_TAKE_COVER = layout.ACTION_TAKE_COVER;
pub const ACTION_REGROUP = layout.ACTION_REGROUP;
pub const ACTION_INVESTIGATE = layout.ACTION_INVESTIGATE;

pub const CAP_NAVMESH = layout.CAP_NAVMESH;
pub const CAP_LINE_OF_SIGHT = layout.CAP_LINE_OF_SIGHT;
pub const CAP_RAYCAST = layout.CAP_RAYCAST;
pub const CAP_WAYPOINT_GRAPH = layout.CAP_WAYPOINT_GRAPH;
pub const CAP_SPAWN_RIGHTS = layout.CAP_SPAWN_RIGHTS;
pub const CAP_ANIMATION_HOOKS = layout.CAP_ANIMATION_HOOKS;
pub const CAP_DAMAGE_EVENTS = layout.CAP_DAMAGE_EVENTS;
pub const CAP_SOUND_EVENTS = layout.CAP_SOUND_EVENTS;
pub const CAP_VEHICLE_BOARDING = layout.CAP_VEHICLE_BOARDING;
pub const CAP_TERRAIN_HEIGHT = layout.CAP_TERRAIN_HEIGHT;

pub const ABI_MAJOR = layout.abi_major;
pub const ABI_MINOR = layout.abi_minor;
pub const ABI_FINGERPRINT = layout.abi_fingerprint;
pub const FX_ONE: i32 = layout.fx_one;

// Intent and agent flag bits, RE-EXPORTED from the generated file. They used to be
// hand-copied here (Abi.Types: intentFlagDegraded/NewTarget/Unreachable), which made
// this "nothing here is hand-numbered" file hand-number the two values a host is
// most likely to branch on. Abi.Gen emits them now, from the same model as the
// header, so a host reading ee.h and the kernel that produced the bits cannot
// disagree — and adding a flag can no longer update one side and not the other.
pub const INTENT_FLAG_DEGRADED = layout.INTENT_FLAG_DEGRADED;
pub const INTENT_FLAG_NEW_TARGET = layout.INTENT_FLAG_NEW_TARGET;
pub const INTENT_FLAG_UNREACHABLE = layout.INTENT_FLAG_UNREACHABLE;
pub const INTENT_FLAG_FROM_MEMORY = layout.INTENT_FLAG_FROM_MEMORY;
pub const AGENT_FLAG_MEMORY_VALID = layout.AGENT_FLAG_MEMORY_VALID;
pub const memory_ttl = layout.memory_ttl;

// The agent's mode field, bits 1..3 of the same flags word (ADR-0012). Re-exported
// for the reason learned the hard way in the memory slice: a constant the generator
// emits is invisible to the kernel until the wrapper names it.
pub const AGENT_MODE_SHIFT = layout.AGENT_MODE_SHIFT;
pub const AGENT_MODE_MASK = layout.AGENT_MODE_MASK;
pub const AGENT_MODE_ADVANCE = layout.AGENT_MODE_ADVANCE;
pub const AGENT_MODE_ENGAGE = layout.AGENT_MODE_ENGAGE;
pub const AGENT_MODE_EVADE = layout.AGENT_MODE_EVADE;
pub const AGENT_MODE_RELOAD = layout.AGENT_MODE_RELOAD;
pub const AGENT_MODE_INVESTIGATE = layout.AGENT_MODE_INVESTIGATE;

// ABI 1.1 (ADR-0013): the names of the mind, re-exported from the generated file for
// the same reason as everything above — the kernel never retypes a bit or a code.
pub const MIND_FINGERPRINT = layout.mind_fingerprint;
pub const INTENT_FLAG_STARTLE = layout.INTENT_FLAG_STARTLE;
pub const INTENT_FLAG_HESITATE = layout.INTENT_FLAG_HESITATE;
pub const INTENT_FLAG_FIXATE = layout.INTENT_FLAG_FIXATE;
pub const CONTACT_FLAG_DAMAGE_SOURCE = layout.CONTACT_FLAG_DAMAGE_SOURCE;
pub const TELL_STARTLE = layout.TELL_STARTLE;
pub const TELL_HESITATE = layout.TELL_HESITATE;
pub const TELL_FIXATE = layout.TELL_FIXATE;
pub const MIND_FLAG_PRIMED = layout.MIND_FLAG_PRIMED;
pub const MIND_FLAG_GRUDGE_LEAD = layout.MIND_FLAG_GRUDGE_LEAD;
pub const MIND_FLAG_HESITATED = layout.MIND_FLAG_HESITATED;
pub const AFFECT_CALM = layout.AFFECT_CALM;
pub const AFFECT_WARY = layout.AFFECT_WARY;
pub const AFFECT_AFRAID = layout.AFFECT_AFRAID;
pub const AFFECT_ANGRY = layout.AFFECT_ANGRY;
pub const CAUSE_NONE = layout.CAUSE_NONE;
pub const CAUSE_CLOSE_CONTACT = layout.CAUSE_CLOSE_CONTACT;
pub const CAUSE_DAMAGE = layout.CAUSE_DAMAGE;
pub const CAUSE_CONTRADICTION = layout.CAUSE_CONTRADICTION;
pub const CAUSE_LOW_HEALTH = layout.CAUSE_LOW_HEALTH;
pub const CAUSE_THREATS = layout.CAUSE_THREATS;
pub const CAUSE_NO_AMMO = layout.CAUSE_NO_AMMO;
pub const CAUSE_ATTRIBUTED_DAMAGE = layout.CAUSE_ATTRIBUTED_DAMAGE;
pub const CAUSE_DECAY = layout.CAUSE_DECAY;
pub const MASS_FULL = layout.MASS_FULL;

// ── The ABI structs ─────────────────────────────────────────────────────────
// `extern struct` gives C layout. Field order and types mirror Abi.Types exactly.

pub const EeFx = i32;

pub const EeVersion = extern struct {
    major: u16,
    minor: u16,
    patch: u16,
    reserved: u16,
};

pub const EeInitDesc = extern struct {
    struct_size: u32,
    abi_major: u32,
    abi_minor: u32,
    capabilities: u32,
    max_agents: u32,
    flags: u32,
    host_tick_num: u64,
    host_tick_den: u64,
    rng_seed: u64,
    abi_fingerprint: u64,
    reserved0: u64,
};

pub const EeContact = extern struct {
    id: u16,
    flags: u16,
    bearing_cos: u16,
    bearing_sin: u16,
    distance: EeFx,
    threat: EeFx,
};

pub const EeSnapshot = extern struct {
    tick: u64,
    capability_mask: u32,
    agent_id: u16,
    contact_count: u16,
    self_x: EeFx,
    self_y: EeFx,
    self_z: EeFx,
    self_vx: EeFx,
    self_vy: EeFx,
    health: EeFx,
    ammo: EeFx,
    flags: u32,
    contact0: EeContact,
    contact1: EeContact,
    contact2: EeContact,
    contact3: EeContact,
    contact4: EeContact,
    contact5: EeContact,
    contact6: EeContact,
    contact7: EeContact,
    cooldown: u32,
    reserved0: u32,
};

pub const EeAgent = extern struct {
    rng_state: u64,
    tick_last: u64,
    memory_x: EeFx,
    memory_y: EeFx,
    memory_age: u32,
    cached_action: u32,
    cached_target: u32,
    budget_used: u32,
    degraded_ticks: u32,
    flags: u32,
};

pub const EeIntent = extern struct {
    action: u32,
    target_id: u32,
    move_x: EeFx,
    move_y: EeFx,
    move_z: EeFx,
    look_x: EeFx,
    look_y: EeFx,
    speed: EeFx,
    priority: u32,
    budget_used: u32,
    flags: u32,
    reserved0: u32,
};

pub const EeContext = extern struct {
    abi_major: u32,
    flags: u32,
    capabilities: u32,
    budget_units: u32,
    max_agents: u32,
    reserved0: u32,
    abi_fingerprint: u64,
    rng_seed: u64,
    tick_rate_num: u64,
    tick_rate_den: u64,
    ticks_run: u64,
    degraded_ticks: u64,
};

// ABI 1.1 (ADR-0013). Caller-owned per-agent mind state, and the per-tick trace
// record. Both carry `struct_size` at offset 0, checked on every `ee_tick_mind` call.

pub const EeMind = extern struct {
    struct_size: u32,
    arousal: u32,
    seen_ids_lo: u64,
    seen_ids_hi: u64,
    fear: u32,
    grievance: u32,
    last_health: EeFx,
    grudge_x: EeFx,
    grudge_y: EeFx,
    grudge_age: u32,
    grudge_id: u16,
    seen_count: u16,
    token: u8,
    hesitate_left: u8,
    flags: u8,
    reserved0: u8,
};

pub const EeMindTrace = extern struct {
    struct_size: u32,
    target_id: u32,
    tick: u64,
    ranking: u32,
    attention: u16,
    cause_contact: u16,
    ranking_count: u8,
    selected: u8,
    incumbent: u8,
    token: u8,
    token_prev: u8,
    cause: u8,
    tells: u8,
    reserved0: u8,
};

// ── The comptime gate ───────────────────────────────────────────────────────
// One helper, called once per field. If any of these fires, the Zig struct no
// longer matches the ABI that Idris2 proved and the C compiler asserted — which
// is exactly the failure that must never reach a host.

fn assertSize(comptime T: type, comptime expected: usize, comptime what: []const u8) void {
    if (@sizeOf(T) != expected) @compileError("ABI drift: size of " ++ what);
}

fn assertOffset(comptime T: type, comptime field: []const u8, comptime expected: usize, comptime what: []const u8) void {
    if (@offsetOf(T, field) != expected) @compileError("ABI drift: offset of " ++ what);
}

comptime {
    assertSize(EeVersion, layout.sizeof_ee_version, "ee_version");
    assertOffset(EeVersion, "major", layout.offset_ee_version_major, "ee_version.major");
    assertOffset(EeVersion, "minor", layout.offset_ee_version_minor, "ee_version.minor");
    assertOffset(EeVersion, "patch", layout.offset_ee_version_patch, "ee_version.patch");
    assertOffset(EeVersion, "reserved", layout.offset_ee_version_reserved, "ee_version.reserved");

    assertSize(EeInitDesc, layout.sizeof_ee_init_desc, "ee_init_desc");
    assertOffset(EeInitDesc, "struct_size", layout.offset_ee_init_desc_struct_size, "ee_init_desc.struct_size");
    assertOffset(EeInitDesc, "abi_major", layout.offset_ee_init_desc_abi_major, "ee_init_desc.abi_major");
    assertOffset(EeInitDesc, "abi_minor", layout.offset_ee_init_desc_abi_minor, "ee_init_desc.abi_minor");
    assertOffset(EeInitDesc, "capabilities", layout.offset_ee_init_desc_capabilities, "ee_init_desc.capabilities");
    assertOffset(EeInitDesc, "max_agents", layout.offset_ee_init_desc_max_agents, "ee_init_desc.max_agents");
    assertOffset(EeInitDesc, "flags", layout.offset_ee_init_desc_flags, "ee_init_desc.flags");
    assertOffset(EeInitDesc, "host_tick_num", layout.offset_ee_init_desc_host_tick_num, "ee_init_desc.host_tick_num");
    assertOffset(EeInitDesc, "host_tick_den", layout.offset_ee_init_desc_host_tick_den, "ee_init_desc.host_tick_den");
    assertOffset(EeInitDesc, "rng_seed", layout.offset_ee_init_desc_rng_seed, "ee_init_desc.rng_seed");
    assertOffset(EeInitDesc, "abi_fingerprint", layout.offset_ee_init_desc_abi_fingerprint, "ee_init_desc.abi_fingerprint");
    assertOffset(EeInitDesc, "reserved0", layout.offset_ee_init_desc_reserved0, "ee_init_desc.reserved0");

    assertSize(EeContact, layout.sizeof_ee_contact, "ee_contact");
    assertOffset(EeContact, "id", layout.offset_ee_contact_id, "ee_contact.id");
    assertOffset(EeContact, "flags", layout.offset_ee_contact_flags, "ee_contact.flags");
    assertOffset(EeContact, "bearing_cos", layout.offset_ee_contact_bearing_cos, "ee_contact.bearing_cos");
    assertOffset(EeContact, "bearing_sin", layout.offset_ee_contact_bearing_sin, "ee_contact.bearing_sin");
    assertOffset(EeContact, "distance", layout.offset_ee_contact_distance, "ee_contact.distance");
    assertOffset(EeContact, "threat", layout.offset_ee_contact_threat, "ee_contact.threat");

    assertSize(EeSnapshot, layout.sizeof_ee_snapshot, "ee_snapshot");
    assertOffset(EeSnapshot, "tick", layout.offset_ee_snapshot_tick, "ee_snapshot.tick");
    assertOffset(EeSnapshot, "capability_mask", layout.offset_ee_snapshot_capability_mask, "ee_snapshot.capability_mask");
    assertOffset(EeSnapshot, "agent_id", layout.offset_ee_snapshot_agent_id, "ee_snapshot.agent_id");
    assertOffset(EeSnapshot, "contact_count", layout.offset_ee_snapshot_contact_count, "ee_snapshot.contact_count");
    assertOffset(EeSnapshot, "self_x", layout.offset_ee_snapshot_self_x, "ee_snapshot.self_x");
    assertOffset(EeSnapshot, "self_y", layout.offset_ee_snapshot_self_y, "ee_snapshot.self_y");
    assertOffset(EeSnapshot, "self_z", layout.offset_ee_snapshot_self_z, "ee_snapshot.self_z");
    assertOffset(EeSnapshot, "self_vx", layout.offset_ee_snapshot_self_vx, "ee_snapshot.self_vx");
    assertOffset(EeSnapshot, "self_vy", layout.offset_ee_snapshot_self_vy, "ee_snapshot.self_vy");
    assertOffset(EeSnapshot, "health", layout.offset_ee_snapshot_health, "ee_snapshot.health");
    assertOffset(EeSnapshot, "ammo", layout.offset_ee_snapshot_ammo, "ee_snapshot.ammo");
    assertOffset(EeSnapshot, "flags", layout.offset_ee_snapshot_flags, "ee_snapshot.flags");
    assertOffset(EeSnapshot, "contact0", layout.offset_ee_snapshot_contact0, "ee_snapshot.contact0");
    assertOffset(EeSnapshot, "contact7", layout.offset_ee_snapshot_contact7, "ee_snapshot.contact7");
    assertOffset(EeSnapshot, "cooldown", layout.offset_ee_snapshot_cooldown, "ee_snapshot.cooldown");
    assertOffset(EeSnapshot, "reserved0", layout.offset_ee_snapshot_reserved0, "ee_snapshot.reserved0");

    assertSize(EeAgent, layout.sizeof_ee_agent, "ee_agent");
    assertOffset(EeAgent, "rng_state", layout.offset_ee_agent_rng_state, "ee_agent.rng_state");
    assertOffset(EeAgent, "tick_last", layout.offset_ee_agent_tick_last, "ee_agent.tick_last");
    assertOffset(EeAgent, "memory_x", layout.offset_ee_agent_memory_x, "ee_agent.memory_x");
    assertOffset(EeAgent, "memory_y", layout.offset_ee_agent_memory_y, "ee_agent.memory_y");
    assertOffset(EeAgent, "memory_age", layout.offset_ee_agent_memory_age, "ee_agent.memory_age");
    assertOffset(EeAgent, "cached_action", layout.offset_ee_agent_cached_action, "ee_agent.cached_action");
    assertOffset(EeAgent, "cached_target", layout.offset_ee_agent_cached_target, "ee_agent.cached_target");
    assertOffset(EeAgent, "budget_used", layout.offset_ee_agent_budget_used, "ee_agent.budget_used");
    assertOffset(EeAgent, "degraded_ticks", layout.offset_ee_agent_degraded_ticks, "ee_agent.degraded_ticks");
    assertOffset(EeAgent, "flags", layout.offset_ee_agent_flags, "ee_agent.flags");

    assertSize(EeIntent, layout.sizeof_ee_intent, "ee_intent");
    assertOffset(EeIntent, "action", layout.offset_ee_intent_action, "ee_intent.action");
    assertOffset(EeIntent, "target_id", layout.offset_ee_intent_target_id, "ee_intent.target_id");
    assertOffset(EeIntent, "move_x", layout.offset_ee_intent_move_x, "ee_intent.move_x");
    assertOffset(EeIntent, "move_y", layout.offset_ee_intent_move_y, "ee_intent.move_y");
    assertOffset(EeIntent, "move_z", layout.offset_ee_intent_move_z, "ee_intent.move_z");
    assertOffset(EeIntent, "look_x", layout.offset_ee_intent_look_x, "ee_intent.look_x");
    assertOffset(EeIntent, "look_y", layout.offset_ee_intent_look_y, "ee_intent.look_y");
    assertOffset(EeIntent, "speed", layout.offset_ee_intent_speed, "ee_intent.speed");
    assertOffset(EeIntent, "priority", layout.offset_ee_intent_priority, "ee_intent.priority");
    assertOffset(EeIntent, "budget_used", layout.offset_ee_intent_budget_used, "ee_intent.budget_used");
    assertOffset(EeIntent, "flags", layout.offset_ee_intent_flags, "ee_intent.flags");
    assertOffset(EeIntent, "reserved0", layout.offset_ee_intent_reserved0, "ee_intent.reserved0");

    assertSize(EeContext, layout.sizeof_ee_context, "ee_context");
    assertOffset(EeContext, "abi_major", layout.offset_ee_context_abi_major, "ee_context.abi_major");
    assertOffset(EeContext, "capabilities", layout.offset_ee_context_capabilities, "ee_context.capabilities");
    assertOffset(EeContext, "budget_units", layout.offset_ee_context_budget_units, "ee_context.budget_units");
    assertOffset(EeContext, "max_agents", layout.offset_ee_context_max_agents, "ee_context.max_agents");
    assertOffset(EeContext, "abi_fingerprint", layout.offset_ee_context_abi_fingerprint, "ee_context.abi_fingerprint");
    assertOffset(EeContext, "rng_seed", layout.offset_ee_context_rng_seed, "ee_context.rng_seed");
    assertOffset(EeContext, "tick_rate_num", layout.offset_ee_context_tick_rate_num, "ee_context.tick_rate_num");
    assertOffset(EeContext, "tick_rate_den", layout.offset_ee_context_tick_rate_den, "ee_context.tick_rate_den");
    assertOffset(EeContext, "ticks_run", layout.offset_ee_context_ticks_run, "ee_context.ticks_run");
    assertOffset(EeContext, "degraded_ticks", layout.offset_ee_context_degraded_ticks, "ee_context.degraded_ticks");

    // ABI 1.1 — every field, not a sample: these structs are new, so nothing older
    // than this file has checked them.
    assertSize(EeMind, layout.sizeof_ee_mind, "ee_mind");
    assertOffset(EeMind, "struct_size", layout.offset_ee_mind_struct_size, "ee_mind.struct_size");
    assertOffset(EeMind, "arousal", layout.offset_ee_mind_arousal, "ee_mind.arousal");
    assertOffset(EeMind, "seen_ids_lo", layout.offset_ee_mind_seen_ids_lo, "ee_mind.seen_ids_lo");
    assertOffset(EeMind, "seen_ids_hi", layout.offset_ee_mind_seen_ids_hi, "ee_mind.seen_ids_hi");
    assertOffset(EeMind, "fear", layout.offset_ee_mind_fear, "ee_mind.fear");
    assertOffset(EeMind, "grievance", layout.offset_ee_mind_grievance, "ee_mind.grievance");
    assertOffset(EeMind, "last_health", layout.offset_ee_mind_last_health, "ee_mind.last_health");
    assertOffset(EeMind, "grudge_x", layout.offset_ee_mind_grudge_x, "ee_mind.grudge_x");
    assertOffset(EeMind, "grudge_y", layout.offset_ee_mind_grudge_y, "ee_mind.grudge_y");
    assertOffset(EeMind, "grudge_age", layout.offset_ee_mind_grudge_age, "ee_mind.grudge_age");
    assertOffset(EeMind, "grudge_id", layout.offset_ee_mind_grudge_id, "ee_mind.grudge_id");
    assertOffset(EeMind, "seen_count", layout.offset_ee_mind_seen_count, "ee_mind.seen_count");
    assertOffset(EeMind, "token", layout.offset_ee_mind_token, "ee_mind.token");
    assertOffset(EeMind, "hesitate_left", layout.offset_ee_mind_hesitate_left, "ee_mind.hesitate_left");
    assertOffset(EeMind, "flags", layout.offset_ee_mind_flags, "ee_mind.flags");
    assertOffset(EeMind, "reserved0", layout.offset_ee_mind_reserved0, "ee_mind.reserved0");

    assertSize(EeMindTrace, layout.sizeof_ee_mind_trace, "ee_mind_trace");
    assertOffset(EeMindTrace, "struct_size", layout.offset_ee_mind_trace_struct_size, "ee_mind_trace.struct_size");
    assertOffset(EeMindTrace, "target_id", layout.offset_ee_mind_trace_target_id, "ee_mind_trace.target_id");
    assertOffset(EeMindTrace, "tick", layout.offset_ee_mind_trace_tick, "ee_mind_trace.tick");
    assertOffset(EeMindTrace, "ranking", layout.offset_ee_mind_trace_ranking, "ee_mind_trace.ranking");
    assertOffset(EeMindTrace, "attention", layout.offset_ee_mind_trace_attention, "ee_mind_trace.attention");
    assertOffset(EeMindTrace, "cause_contact", layout.offset_ee_mind_trace_cause_contact, "ee_mind_trace.cause_contact");
    assertOffset(EeMindTrace, "ranking_count", layout.offset_ee_mind_trace_ranking_count, "ee_mind_trace.ranking_count");
    assertOffset(EeMindTrace, "selected", layout.offset_ee_mind_trace_selected, "ee_mind_trace.selected");
    assertOffset(EeMindTrace, "incumbent", layout.offset_ee_mind_trace_incumbent, "ee_mind_trace.incumbent");
    assertOffset(EeMindTrace, "token", layout.offset_ee_mind_trace_token, "ee_mind_trace.token");
    assertOffset(EeMindTrace, "token_prev", layout.offset_ee_mind_trace_token_prev, "ee_mind_trace.token_prev");
    assertOffset(EeMindTrace, "cause", layout.offset_ee_mind_trace_cause, "ee_mind_trace.cause");
    assertOffset(EeMindTrace, "tells", layout.offset_ee_mind_trace_tells, "ee_mind_trace.tells");
    assertOffset(EeMindTrace, "reserved0", layout.offset_ee_mind_trace_reserved0, "ee_mind_trace.reserved0");
}
