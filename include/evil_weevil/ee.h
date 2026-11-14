/* SPDX-License-Identifier: MPL-2.0 */
/*
 * ee.h — the Evil Weevil C ABI, version 1.
 *
 * GENERATED FILE — DO NOT EDIT BY HAND.
 * Source of truth: src/interface/Abi/Types.idr (field lists).
 * Layout proofs:   src/interface/Abi/Layout.idr.
 * Regenerate:       just abi-gen
 * Verify in CI:     just abi-check   (regenerates and diffs)
 *
 * The _Static_asserts below check the declared layout against what THIS
 * compiler actually produces. If they fire, the ABI changed — read ADR-0005
 * before touching anything: bumping the major version is a new ADR, and an
 * adapter written against a moving header is the one mistake that sinks the
 * 'universally injectable' claim.
 *
 * No pointer-sized FIELD appears in any struct here; pointers are function
 * parameters only (ADR-0005 §1). That keeps the layout identical across
 * 64-bit targets and keeps host addresses out of deterministic state.
 * 32-bit hosts, including wasm32, are NOT supported by this layout and get a
 * distinct, separately-proved ABI in Phase 4.
 */

#ifndef EVIL_WEVIL_EE_H
#define EVIL_WEVIL_EE_H

#include <stdint.h>
#include <stddef.h>

#if defined(__cplusplus)
#define EE_STATIC_ASSERT(c, m) static_assert(c, m)
extern "C" {
#else
#define EE_STATIC_ASSERT(c, m) _Static_assert(c, m)
#endif

#define EE_ABI_MAJOR 1
#define EE_ABI_MINOR 1
#define EE_ABI_FINGERPRINT 18276775ULL
/* ABI 1.1: the fingerprint of ee_mind and ee_mind_trace only (ADR-0013). */
#define EE_MIND_FINGERPRINT 1047490ULL

/* Q16.16 fixed point: all kernel arithmetic is integer (ADR-0006). */
#define EE_FX_FRACTION_BITS 16
#define EE_FX_ONE 65536
typedef int32_t ee_fx;

#define EE_CAP_NAVMESH (1u << 0u)
#define EE_CAP_LINE_OF_SIGHT (1u << 1u)
#define EE_CAP_RAYCAST (1u << 2u)
#define EE_CAP_WAYPOINT_GRAPH (1u << 3u)
#define EE_CAP_SPAWN_RIGHTS (1u << 4u)
#define EE_CAP_ANIMATION_HOOKS (1u << 5u)
#define EE_CAP_DAMAGE_EVENTS (1u << 6u)
#define EE_CAP_SOUND_EVENTS (1u << 7u)
#define EE_CAP_VEHICLE_BOARDING (1u << 8u)
#define EE_CAP_TERRAIN_HEIGHT (1u << 9u)

#define EE_STATUS_OK 0
#define EE_STATUS_BAD_PARAM 1
#define EE_STATUS_VERSION_MISMATCH 2
#define EE_STATUS_FINGERPRINT_MISMATCH 3
#define EE_STATUS_CAPABILITY_UNSUPPORTED 4
#define EE_STATUS_BUFFER_TOO_SMALL 5
#define EE_STATUS_PANIC_CAUGHT 6

/* Every entry point returns one of these; the codes above are its values. */
typedef uint32_t ee_status;

#define EE_ACTION_IDLE 0
#define EE_ACTION_ADVANCE 1
#define EE_ACTION_HOLD 2
#define EE_ACTION_FLEE 3
#define EE_ACTION_ATTACK 4
#define EE_ACTION_RELOAD 5
#define EE_ACTION_TAKE_COVER 6
#define EE_ACTION_REGROUP 7
#define EE_ACTION_INVESTIGATE 8

/* Bits in ee_intent.flags. */
#define EE_INTENT_FLAG_DEGRADED 1u
#define EE_INTENT_FLAG_NEW_TARGET 2u
#define EE_INTENT_FLAG_UNREACHABLE 4u
#define EE_INTENT_FLAG_FROM_MEMORY 8u
#define EE_INTENT_FLAG_STARTLE 16u
#define EE_INTENT_FLAG_HESITATE 32u
#define EE_INTENT_FLAG_FIXATE 64u

/* Bits in ee_agent.flags. */
#define EE_AGENT_FLAG_MEMORY_VALID 1u

/* The mode field inside ee_agent.flags: bits 1..3 (ADR-0012). */
#define EE_AGENT_MODE_SHIFT 1u
#define EE_AGENT_MODE_MASK 14u
#define EE_AGENT_MODE_ADVANCE 0u
#define EE_AGENT_MODE_ENGAGE 1u
#define EE_AGENT_MODE_EVADE 2u
#define EE_AGENT_MODE_RELOAD 3u
#define EE_AGENT_MODE_INVESTIGATE 4u

/* Ticks a sighting stays actionable before the agent forgets it (Phase 2). */
#define EE_MEMORY_TTL 36u

/* Bits in ee_contact.flags (ABI 1.1; read only by ee_tick_mind, with EE_CAP_DAMAGE_EVENTS). */
#define EE_CONTACT_FLAG_DAMAGE_SOURCE 1u

/* Bits in ee_mind_trace.tells: the intent tell bits shifted down by four. */
#define EE_TELL_STARTLE 1u
#define EE_TELL_HESITATE 2u
#define EE_TELL_FIXATE 4u

/* Bits in ee_mind.flags. */
#define EE_MIND_FLAG_PRIMED 1u
#define EE_MIND_FLAG_GRUDGE_LEAD 2u
#define EE_MIND_FLAG_HESITATED 4u

/* Affect tokens, in declaration (and tie-break) order: ee_mind.token, ee_mind_trace.token. */
#define EE_AFFECT_CALM 0u
#define EE_AFFECT_WARY 1u
#define EE_AFFECT_AFRAID 2u
#define EE_AFFECT_ANGRY 3u

/* Why the affect token changed: ee_mind_trace.cause. NONE exactly when it did not. */
#define EE_CAUSE_NONE 0u
#define EE_CAUSE_CLOSE_CONTACT 1u
#define EE_CAUSE_DAMAGE 2u
#define EE_CAUSE_CONTRADICTION 3u
#define EE_CAUSE_LOW_HEALTH 4u
#define EE_CAUSE_THREATS 5u
#define EE_CAUSE_NO_AMMO 6u
#define EE_CAUSE_ATTRIBUTED_DAMAGE 7u
#define EE_CAUSE_DECAY 8u

/* Full scale of ee_mind_trace.attention, in units of 1/10000 (a mass, not a probability). */
#define EE_MASS_FULL 10000u

typedef struct {
  uint16_t major;
  uint16_t minor;
  uint16_t patch;
  uint16_t reserved;
} ee_version;

#define EE_SIZEOF_ee_version 8
#define EE_OFFSET_ee_version_major 0
#define EE_OFFSET_ee_version_minor 2
#define EE_OFFSET_ee_version_patch 4
#define EE_OFFSET_ee_version_reserved 6

typedef struct {
  uint32_t struct_size;
  uint32_t abi_major;
  uint32_t abi_minor;
  uint32_t capabilities;
  uint32_t max_agents;
  uint32_t flags;
  uint64_t host_tick_num;
  uint64_t host_tick_den;
  uint64_t rng_seed;
  uint64_t abi_fingerprint;
  uint64_t reserved0;
} ee_init_desc;

#define EE_SIZEOF_ee_init_desc 64
#define EE_OFFSET_ee_init_desc_struct_size 0
#define EE_OFFSET_ee_init_desc_abi_major 4
#define EE_OFFSET_ee_init_desc_abi_minor 8
#define EE_OFFSET_ee_init_desc_capabilities 12
#define EE_OFFSET_ee_init_desc_max_agents 16
#define EE_OFFSET_ee_init_desc_flags 20
#define EE_OFFSET_ee_init_desc_host_tick_num 24
#define EE_OFFSET_ee_init_desc_host_tick_den 32
#define EE_OFFSET_ee_init_desc_rng_seed 40
#define EE_OFFSET_ee_init_desc_abi_fingerprint 48
#define EE_OFFSET_ee_init_desc_reserved0 56

typedef struct {
  uint16_t id;
  uint16_t flags;
  uint16_t bearing_cos;
  uint16_t bearing_sin;
  ee_fx distance;
  ee_fx threat;
} ee_contact;

#define EE_SIZEOF_ee_contact 16
#define EE_OFFSET_ee_contact_id 0
#define EE_OFFSET_ee_contact_flags 2
#define EE_OFFSET_ee_contact_bearing_cos 4
#define EE_OFFSET_ee_contact_bearing_sin 6
#define EE_OFFSET_ee_contact_distance 8
#define EE_OFFSET_ee_contact_threat 12

typedef struct {
  uint64_t tick;
  uint32_t capability_mask;
  uint16_t agent_id;
  uint16_t contact_count;
  ee_fx self_x;
  ee_fx self_y;
  ee_fx self_z;
  ee_fx self_vx;
  ee_fx self_vy;
  ee_fx health;
  ee_fx ammo;
  uint32_t flags;
  ee_contact contact0;
  ee_contact contact1;
  ee_contact contact2;
  ee_contact contact3;
  ee_contact contact4;
  ee_contact contact5;
  ee_contact contact6;
  ee_contact contact7;
  uint32_t cooldown;
  uint32_t reserved0;
} ee_snapshot;

#define EE_SIZEOF_ee_snapshot 184
#define EE_OFFSET_ee_snapshot_tick 0
#define EE_OFFSET_ee_snapshot_capability_mask 8
#define EE_OFFSET_ee_snapshot_agent_id 12
#define EE_OFFSET_ee_snapshot_contact_count 14
#define EE_OFFSET_ee_snapshot_self_x 16
#define EE_OFFSET_ee_snapshot_self_y 20
#define EE_OFFSET_ee_snapshot_self_z 24
#define EE_OFFSET_ee_snapshot_self_vx 28
#define EE_OFFSET_ee_snapshot_self_vy 32
#define EE_OFFSET_ee_snapshot_health 36
#define EE_OFFSET_ee_snapshot_ammo 40
#define EE_OFFSET_ee_snapshot_flags 44
#define EE_OFFSET_ee_snapshot_contact0 48
#define EE_OFFSET_ee_snapshot_contact1 64
#define EE_OFFSET_ee_snapshot_contact2 80
#define EE_OFFSET_ee_snapshot_contact3 96
#define EE_OFFSET_ee_snapshot_contact4 112
#define EE_OFFSET_ee_snapshot_contact5 128
#define EE_OFFSET_ee_snapshot_contact6 144
#define EE_OFFSET_ee_snapshot_contact7 160
#define EE_OFFSET_ee_snapshot_cooldown 176
#define EE_OFFSET_ee_snapshot_reserved0 180

typedef struct {
  uint64_t rng_state;
  uint64_t tick_last;
  ee_fx memory_x;
  ee_fx memory_y;
  uint32_t memory_age;
  uint32_t cached_action;
  uint32_t cached_target;
  uint32_t budget_used;
  uint32_t degraded_ticks;
  uint32_t flags;
} ee_agent;

#define EE_SIZEOF_ee_agent 48
#define EE_OFFSET_ee_agent_rng_state 0
#define EE_OFFSET_ee_agent_tick_last 8
#define EE_OFFSET_ee_agent_memory_x 16
#define EE_OFFSET_ee_agent_memory_y 20
#define EE_OFFSET_ee_agent_memory_age 24
#define EE_OFFSET_ee_agent_cached_action 28
#define EE_OFFSET_ee_agent_cached_target 32
#define EE_OFFSET_ee_agent_budget_used 36
#define EE_OFFSET_ee_agent_degraded_ticks 40
#define EE_OFFSET_ee_agent_flags 44

typedef struct {
  uint32_t action;
  uint32_t target_id;
  ee_fx move_x;
  ee_fx move_y;
  ee_fx move_z;
  ee_fx look_x;
  ee_fx look_y;
  ee_fx speed;
  uint32_t priority;
  uint32_t budget_used;
  uint32_t flags;
  uint32_t reserved0;
} ee_intent;

#define EE_SIZEOF_ee_intent 48
#define EE_OFFSET_ee_intent_action 0
#define EE_OFFSET_ee_intent_target_id 4
#define EE_OFFSET_ee_intent_move_x 8
#define EE_OFFSET_ee_intent_move_y 12
#define EE_OFFSET_ee_intent_move_z 16
#define EE_OFFSET_ee_intent_look_x 20
#define EE_OFFSET_ee_intent_look_y 24
#define EE_OFFSET_ee_intent_speed 28
#define EE_OFFSET_ee_intent_priority 32
#define EE_OFFSET_ee_intent_budget_used 36
#define EE_OFFSET_ee_intent_flags 40
#define EE_OFFSET_ee_intent_reserved0 44

typedef struct {
  uint32_t abi_major;
  uint32_t flags;
  uint32_t capabilities;
  uint32_t budget_units;
  uint32_t max_agents;
  uint32_t reserved0;
  uint64_t abi_fingerprint;
  uint64_t rng_seed;
  uint64_t tick_rate_num;
  uint64_t tick_rate_den;
  uint64_t ticks_run;
  uint64_t degraded_ticks;
} ee_context;

#define EE_SIZEOF_ee_context 72
#define EE_OFFSET_ee_context_abi_major 0
#define EE_OFFSET_ee_context_flags 4
#define EE_OFFSET_ee_context_capabilities 8
#define EE_OFFSET_ee_context_budget_units 12
#define EE_OFFSET_ee_context_max_agents 16
#define EE_OFFSET_ee_context_reserved0 20
#define EE_OFFSET_ee_context_abi_fingerprint 24
#define EE_OFFSET_ee_context_rng_seed 32
#define EE_OFFSET_ee_context_tick_rate_num 40
#define EE_OFFSET_ee_context_tick_rate_den 48
#define EE_OFFSET_ee_context_ticks_run 56
#define EE_OFFSET_ee_context_degraded_ticks 64

typedef struct {
  uint32_t struct_size;
  uint32_t arousal;
  uint64_t seen_ids_lo;
  uint64_t seen_ids_hi;
  uint32_t fear;
  uint32_t grievance;
  ee_fx last_health;
  ee_fx grudge_x;
  ee_fx grudge_y;
  uint32_t grudge_age;
  uint16_t grudge_id;
  uint16_t seen_count;
  uint8_t token;
  uint8_t hesitate_left;
  uint8_t flags;
  uint8_t reserved0;
} ee_mind;

#define EE_SIZEOF_ee_mind 56
#define EE_OFFSET_ee_mind_struct_size 0
#define EE_OFFSET_ee_mind_arousal 4
#define EE_OFFSET_ee_mind_seen_ids_lo 8
#define EE_OFFSET_ee_mind_seen_ids_hi 16
#define EE_OFFSET_ee_mind_fear 24
#define EE_OFFSET_ee_mind_grievance 28
#define EE_OFFSET_ee_mind_last_health 32
#define EE_OFFSET_ee_mind_grudge_x 36
#define EE_OFFSET_ee_mind_grudge_y 40
#define EE_OFFSET_ee_mind_grudge_age 44
#define EE_OFFSET_ee_mind_grudge_id 48
#define EE_OFFSET_ee_mind_seen_count 50
#define EE_OFFSET_ee_mind_token 52
#define EE_OFFSET_ee_mind_hesitate_left 53
#define EE_OFFSET_ee_mind_flags 54
#define EE_OFFSET_ee_mind_reserved0 55

typedef struct {
  uint32_t struct_size;
  uint32_t target_id;
  uint64_t tick;
  uint32_t ranking;
  uint16_t attention;
  uint16_t cause_contact;
  uint8_t ranking_count;
  uint8_t selected;
  uint8_t incumbent;
  uint8_t token;
  uint8_t token_prev;
  uint8_t cause;
  uint8_t tells;
  uint8_t reserved0;
} ee_mind_trace;

#define EE_SIZEOF_ee_mind_trace 32
#define EE_OFFSET_ee_mind_trace_struct_size 0
#define EE_OFFSET_ee_mind_trace_target_id 4
#define EE_OFFSET_ee_mind_trace_tick 8
#define EE_OFFSET_ee_mind_trace_ranking 16
#define EE_OFFSET_ee_mind_trace_attention 20
#define EE_OFFSET_ee_mind_trace_cause_contact 22
#define EE_OFFSET_ee_mind_trace_ranking_count 24
#define EE_OFFSET_ee_mind_trace_selected 25
#define EE_OFFSET_ee_mind_trace_incumbent 26
#define EE_OFFSET_ee_mind_trace_token 27
#define EE_OFFSET_ee_mind_trace_token_prev 28
#define EE_OFFSET_ee_mind_trace_cause 29
#define EE_OFFSET_ee_mind_trace_tells 30
#define EE_OFFSET_ee_mind_trace_reserved0 31

EE_STATIC_ASSERT(sizeof(ee_version) == EE_SIZEOF_ee_version, "size");
EE_STATIC_ASSERT(offsetof(ee_version, major) == EE_OFFSET_ee_version_major, "offset");
EE_STATIC_ASSERT(offsetof(ee_version, minor) == EE_OFFSET_ee_version_minor, "offset");
EE_STATIC_ASSERT(offsetof(ee_version, patch) == EE_OFFSET_ee_version_patch, "offset");
EE_STATIC_ASSERT(offsetof(ee_version, reserved) == EE_OFFSET_ee_version_reserved, "offset");
EE_STATIC_ASSERT(sizeof(ee_init_desc) == EE_SIZEOF_ee_init_desc, "size");
EE_STATIC_ASSERT(offsetof(ee_init_desc, struct_size) == EE_OFFSET_ee_init_desc_struct_size, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, abi_major) == EE_OFFSET_ee_init_desc_abi_major, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, abi_minor) == EE_OFFSET_ee_init_desc_abi_minor, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, capabilities) == EE_OFFSET_ee_init_desc_capabilities, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, max_agents) == EE_OFFSET_ee_init_desc_max_agents, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, flags) == EE_OFFSET_ee_init_desc_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, host_tick_num) == EE_OFFSET_ee_init_desc_host_tick_num, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, host_tick_den) == EE_OFFSET_ee_init_desc_host_tick_den, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, rng_seed) == EE_OFFSET_ee_init_desc_rng_seed, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, abi_fingerprint) == EE_OFFSET_ee_init_desc_abi_fingerprint, "offset");
EE_STATIC_ASSERT(offsetof(ee_init_desc, reserved0) == EE_OFFSET_ee_init_desc_reserved0, "offset");
EE_STATIC_ASSERT(sizeof(ee_contact) == EE_SIZEOF_ee_contact, "size");
EE_STATIC_ASSERT(offsetof(ee_contact, id) == EE_OFFSET_ee_contact_id, "offset");
EE_STATIC_ASSERT(offsetof(ee_contact, flags) == EE_OFFSET_ee_contact_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_contact, bearing_cos) == EE_OFFSET_ee_contact_bearing_cos, "offset");
EE_STATIC_ASSERT(offsetof(ee_contact, bearing_sin) == EE_OFFSET_ee_contact_bearing_sin, "offset");
EE_STATIC_ASSERT(offsetof(ee_contact, distance) == EE_OFFSET_ee_contact_distance, "offset");
EE_STATIC_ASSERT(offsetof(ee_contact, threat) == EE_OFFSET_ee_contact_threat, "offset");
EE_STATIC_ASSERT(sizeof(ee_snapshot) == EE_SIZEOF_ee_snapshot, "size");
EE_STATIC_ASSERT(offsetof(ee_snapshot, tick) == EE_OFFSET_ee_snapshot_tick, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, capability_mask) == EE_OFFSET_ee_snapshot_capability_mask, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, agent_id) == EE_OFFSET_ee_snapshot_agent_id, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact_count) == EE_OFFSET_ee_snapshot_contact_count, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, self_x) == EE_OFFSET_ee_snapshot_self_x, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, self_y) == EE_OFFSET_ee_snapshot_self_y, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, self_z) == EE_OFFSET_ee_snapshot_self_z, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, self_vx) == EE_OFFSET_ee_snapshot_self_vx, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, self_vy) == EE_OFFSET_ee_snapshot_self_vy, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, health) == EE_OFFSET_ee_snapshot_health, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, ammo) == EE_OFFSET_ee_snapshot_ammo, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, flags) == EE_OFFSET_ee_snapshot_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact0) == EE_OFFSET_ee_snapshot_contact0, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact1) == EE_OFFSET_ee_snapshot_contact1, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact2) == EE_OFFSET_ee_snapshot_contact2, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact3) == EE_OFFSET_ee_snapshot_contact3, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact4) == EE_OFFSET_ee_snapshot_contact4, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact5) == EE_OFFSET_ee_snapshot_contact5, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact6) == EE_OFFSET_ee_snapshot_contact6, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, contact7) == EE_OFFSET_ee_snapshot_contact7, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, cooldown) == EE_OFFSET_ee_snapshot_cooldown, "offset");
EE_STATIC_ASSERT(offsetof(ee_snapshot, reserved0) == EE_OFFSET_ee_snapshot_reserved0, "offset");
EE_STATIC_ASSERT(sizeof(ee_agent) == EE_SIZEOF_ee_agent, "size");
EE_STATIC_ASSERT(offsetof(ee_agent, rng_state) == EE_OFFSET_ee_agent_rng_state, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, tick_last) == EE_OFFSET_ee_agent_tick_last, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, memory_x) == EE_OFFSET_ee_agent_memory_x, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, memory_y) == EE_OFFSET_ee_agent_memory_y, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, memory_age) == EE_OFFSET_ee_agent_memory_age, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, cached_action) == EE_OFFSET_ee_agent_cached_action, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, cached_target) == EE_OFFSET_ee_agent_cached_target, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, budget_used) == EE_OFFSET_ee_agent_budget_used, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, degraded_ticks) == EE_OFFSET_ee_agent_degraded_ticks, "offset");
EE_STATIC_ASSERT(offsetof(ee_agent, flags) == EE_OFFSET_ee_agent_flags, "offset");
EE_STATIC_ASSERT(sizeof(ee_intent) == EE_SIZEOF_ee_intent, "size");
EE_STATIC_ASSERT(offsetof(ee_intent, action) == EE_OFFSET_ee_intent_action, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, target_id) == EE_OFFSET_ee_intent_target_id, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, move_x) == EE_OFFSET_ee_intent_move_x, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, move_y) == EE_OFFSET_ee_intent_move_y, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, move_z) == EE_OFFSET_ee_intent_move_z, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, look_x) == EE_OFFSET_ee_intent_look_x, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, look_y) == EE_OFFSET_ee_intent_look_y, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, speed) == EE_OFFSET_ee_intent_speed, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, priority) == EE_OFFSET_ee_intent_priority, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, budget_used) == EE_OFFSET_ee_intent_budget_used, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, flags) == EE_OFFSET_ee_intent_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_intent, reserved0) == EE_OFFSET_ee_intent_reserved0, "offset");
EE_STATIC_ASSERT(sizeof(ee_context) == EE_SIZEOF_ee_context, "size");
EE_STATIC_ASSERT(offsetof(ee_context, abi_major) == EE_OFFSET_ee_context_abi_major, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, flags) == EE_OFFSET_ee_context_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, capabilities) == EE_OFFSET_ee_context_capabilities, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, budget_units) == EE_OFFSET_ee_context_budget_units, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, max_agents) == EE_OFFSET_ee_context_max_agents, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, reserved0) == EE_OFFSET_ee_context_reserved0, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, abi_fingerprint) == EE_OFFSET_ee_context_abi_fingerprint, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, rng_seed) == EE_OFFSET_ee_context_rng_seed, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, tick_rate_num) == EE_OFFSET_ee_context_tick_rate_num, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, tick_rate_den) == EE_OFFSET_ee_context_tick_rate_den, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, ticks_run) == EE_OFFSET_ee_context_ticks_run, "offset");
EE_STATIC_ASSERT(offsetof(ee_context, degraded_ticks) == EE_OFFSET_ee_context_degraded_ticks, "offset");
EE_STATIC_ASSERT(sizeof(ee_mind) == EE_SIZEOF_ee_mind, "size");
EE_STATIC_ASSERT(offsetof(ee_mind, struct_size) == EE_OFFSET_ee_mind_struct_size, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, arousal) == EE_OFFSET_ee_mind_arousal, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, seen_ids_lo) == EE_OFFSET_ee_mind_seen_ids_lo, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, seen_ids_hi) == EE_OFFSET_ee_mind_seen_ids_hi, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, fear) == EE_OFFSET_ee_mind_fear, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, grievance) == EE_OFFSET_ee_mind_grievance, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, last_health) == EE_OFFSET_ee_mind_last_health, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, grudge_x) == EE_OFFSET_ee_mind_grudge_x, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, grudge_y) == EE_OFFSET_ee_mind_grudge_y, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, grudge_age) == EE_OFFSET_ee_mind_grudge_age, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, grudge_id) == EE_OFFSET_ee_mind_grudge_id, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, seen_count) == EE_OFFSET_ee_mind_seen_count, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, token) == EE_OFFSET_ee_mind_token, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, hesitate_left) == EE_OFFSET_ee_mind_hesitate_left, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, flags) == EE_OFFSET_ee_mind_flags, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind, reserved0) == EE_OFFSET_ee_mind_reserved0, "offset");
EE_STATIC_ASSERT(sizeof(ee_mind_trace) == EE_SIZEOF_ee_mind_trace, "size");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, struct_size) == EE_OFFSET_ee_mind_trace_struct_size, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, target_id) == EE_OFFSET_ee_mind_trace_target_id, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, tick) == EE_OFFSET_ee_mind_trace_tick, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, ranking) == EE_OFFSET_ee_mind_trace_ranking, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, attention) == EE_OFFSET_ee_mind_trace_attention, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, cause_contact) == EE_OFFSET_ee_mind_trace_cause_contact, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, ranking_count) == EE_OFFSET_ee_mind_trace_ranking_count, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, selected) == EE_OFFSET_ee_mind_trace_selected, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, incumbent) == EE_OFFSET_ee_mind_trace_incumbent, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, token) == EE_OFFSET_ee_mind_trace_token, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, token_prev) == EE_OFFSET_ee_mind_trace_token_prev, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, cause) == EE_OFFSET_ee_mind_trace_cause, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, tells) == EE_OFFSET_ee_mind_trace_tells, "offset");
EE_STATIC_ASSERT(offsetof(ee_mind_trace, reserved0) == EE_OFFSET_ee_mind_trace_reserved0, "offset");

/*
 * Entry points. The kernel performs NO allocation: `ee_context` and the
 * `ee_agent` array are host-owned storage whose size is fixed by this header
 * (ADR-0005 §4). `ee_init` validates struct_size, the major version and the
 * fingerprint, and answers every mismatch with a status code rather than
 * throwing or aborting the host (ADR-0005 §3).
 *
 * `ee_tick` is PURE with respect to the host: it reads the snapshot and the
 * agent, writes the agent and returns an intent. It never calls back into the
 * host mid-tick (ADR-0004), and its result depends only on its arguments and
 * the context — which is what makes replays bit-exact (ADR-0006).
 */
ee_status ee_init(const ee_init_desc *desc, ee_context *ctx);
ee_status ee_tick(ee_context *ctx, const ee_snapshot *snap, ee_agent *agent, ee_intent *out);
ee_version ee_version_info(void);
uint64_t ee_abi_fingerprint(void);
const char *ee_status_name(ee_status status);

/*
 * ABI 1.1 (ADR-0013): the mind. A host that never calls this gets 1.0 exactly:
 * `ee_tick` is unchanged and its pinned digests did not move.
 *
 * `mind` is caller-owned per-agent state (zeroed, `struct_size` set). `trace` may
 * be NULL; when it is not, its `struct_size` must be set and one record is written.
 * The trace publishes a RANKING of modes and the selected mode — never a score —
 * and an affect TOKEN with an attention mass — never a reservoir value.
 */
ee_status ee_tick_mind(ee_context *ctx, const ee_snapshot *snap, ee_agent *agent,
                       ee_mind *mind, ee_intent *out, ee_mind_trace *trace);
uint64_t ee_mind_fingerprint(void);

#if defined(__cplusplus)
}
#endif

#endif /* EVIL_WEVIL_EE_H */
