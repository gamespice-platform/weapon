## The rows [GSWeaponHitscan] trades with gs-sim's [code]GSSimWeaponSpread[/code] (never named: ClassDB), and the idle
## gate's verify mode. Preloaded by path (no class_name), so a pack that loads gs_weapon by path parses it too.
extends RefCounted


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
