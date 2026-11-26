## The rows [GSWeaponHitscan] trades with gs-sim's [code]GSSimWeaponSpread[/code] (never named: ClassDB), and the idle
## gate's verify mode. Preloaded by path (no class_name), so a pack that loads gs_weapon by path parses it too.
extends RefCounted


## The tuning row of [code]GSSimWeaponSpread.set_tuning[/code], written into [param row] (16 long, kept by the
## behaviour, so a re-send allocates nothing); [param h] is the [GSWeaponHitscan] whose class presets fill the terms
## left at -1. What the row holds: docs/native-tick.md#the-tuning-row.
static func tuning_into(h: Object, b: GSWeaponBallistics, row: PackedFloat64Array) -> void:
	h._class_of(b)
	row[0] = b.spread
	row[1] = b.spread_moving
	row[2] = b.spread_speed_ref
	row[3] = b.spread_airborne
	row[4] = b.spread_crouched
	row[5] = b.bloom
	row[6] = b.bloom_max
	row[7] = h.scaled_per_tick(b.bloom_recovery)
	row[8] = h._bloom_delay_of(b)
	row[9] = h._settle_ticks_of(b)
	row[10] = b.spread_hip if b.spread_hip >= 0.0 else h._pre_hip
	row[11] = b.spread_slide if b.spread_slide >= 0.0 else h._pre_slide
	row[12] = b.spread_sprint if b.spread_sprint >= 0.0 else h._pre_sprint
	row[13] = b.spread_flinch if b.spread_flinch >= 0.0 else h._pre_flinch
	row[14] = b.bloom_crouch if b.bloom_crouch >= 0.0 else h._pre_crouch
	row[15] = b.spread_aim if b.spread_aim >= 0.0 else h._pre_aim


## Whether the GameSpice Sim extension is loaded at all (to tell a stale build from no gs-sim).
static func gs_sim_loaded() -> bool:
	for path in GDExtensionManager.get_loaded_extensions():
		if path.get_file() == "gs_sim.gdextension":
			return true
	return false


## A tuning row of [code]set_tuning[/code]'s length (16), zeroed.
static func tuning_row() -> PackedFloat64Array:
	var row := PackedFloat64Array()
	row.resize(16)
	return row


## The frame's rules row of [code]GSSimWeaponSpread.set_frame[/code]; empty for no rules object.
static func rules_row(r: GSWeaponSpreadRules, rate: int) -> PackedFloat64Array:
	if r == null:
		return PackedFloat64Array()
	return PackedFloat64Array([
		1.0 if r.enabled else 0.0, r.scale, r.mult_hip, r.mult_aim, r.mult_stand, r.mult_walk, r.mult_run, r.mult_air,
		r.mult_sprint, r.mult_slide, r.mult_crouch, r.walk_speed, r.run_speed, r.recovery_per_tick(rate), r.max_spread,
	])


## [param ctx] as the native posture row, written into [param row] (9 long, the one row the behaviour keeps).
static func posture_into(ctx: GSWeaponContext, row: PackedFloat64Array) -> PackedFloat64Array:
	row[0] = ctx.speed
	row[1] = 1.0 if ctx.airborne else 0.0
	row[2] = 1.0 if ctx.crouched else 0.0
	row[3] = 1.0 if ctx.aiming else 0.0
	row[4] = 1.0 if ctx.sliding else 0.0
	row[5] = 1.0 if ctx.sprinting else 0.0
	row[6] = 1.0 if ctx.wall_running else 0.0
	row[7] = ctx.tick
	row[8] = ctx.hurt_tick
	return row


## Idle gate 2 on [param h]: what the arsenal handed in must be what idle_row reads, and a gate that [param held] must
## leave [code]_native_ready[/code] nothing to send. A miss counts in [member GSWeaponBehaviour.idle_gate_misses].
static func verify_gate(h: GSWeaponHitscan, held: bool, rules: GSWeaponSpreadRules, cone: bool, rate: int) -> void:
	var read_rules := h._rules_object()
	var read_cone := read_rules != null and bool(h.arsenal.get(&"crosshair_cone"))
	var miss := ""
	if read_rules != rules or read_cone != cone or h.running_tick_rate() != rate:
		miss = "the arsenal handed rules %s cone %s rate %d, idle_row reads %s %s %d" % [
			rules, cone, rate, read_rules, read_cone, h.running_tick_rate()
		]
	elif held:
		var before := _cache(h)
		var b := h._ballistics()
		if b == null or not h._native_ready(b, read_rules, read_cone):
			miss = "the gate held but the native rows are not ready"
		elif _cache(h) != before:
			miss = "the gate held but _native_ready re-sent a row: %s -> %s" % [before, _cache(h)]
	if miss != "":
		GSWeaponBehaviour.idle_gate_misses += 1
		push_error("gs-weapon idle gate (%s): %s" % [h.def.id if h.def != null else &"", miss])


static func _cache(h: GSWeaponHitscan) -> Array:
	return [
		h._native_b, h._native_b_rev, h._native_def, h._native_rate, h._native_interval, h._native_authored,
		h._native_class, h._native_framed, h._native_rules, h._native_rules_rev, h._native_cone, h._native_frame_rate,
		h._class_key_set, h._class_key, h._class_id, h._class,
	]
