extends "sections_knives.gd"

## GSWeaponHitscan.native_tick: a context tick through GameSpice Sim's GSSimWeaponSpread must leave what the GDScript tick
## leaves, bit for bit. Random weapons tick twice, once each way, on shared tuning, rules and arsenal objects edited
## mid-run (each edit must reach the cached native rows); then the rest streams run with the native tick on one arsenal.
## Without GameSpice Sim loaded every check passes as a skip, so the count stays fixed.

const _NATIVE_CASES := 200
const _NATIVE_TICKS := 160


class NativeArsenal:
	extends RefCounted
	var spread_rules: Variant = null
	var crosshair_cone: bool = false
	var tick_rate: Variant = 0
	var recoil_rules: Variant = null


func _test_native_tick() -> void:
	_section("the native spread tick matches the GDScript tick")
	var present := ClassDB.class_exists(&"GSSimWeaponSpread")
	var native_was := GSWeaponHitscan.native_tick
	if not present:
		# The case checks, twice each rest stream's (the bridge check but for explicit_still, the skip, the steady skip of
		# a cone mode) and the streams' agreement (the native tick, then the idle row), and the missing-class fallback.
		# Then the idle gate's four, the framed tick's two, the seeded uses' three and the recoil posture's one.
		for i in range(4 + 1 + (_MODES.size() * 2 - 1 + _CONE_MODES.size() + 1) * 2 + 1 + 4 + 2 + 2 + 1 + 1):
			_check(true, "skip: GSSimWeaponSpread not loaded")
		_done()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	var ticks := 0
	var shown_ticks := 0
	var edits := 0
	var native_ran := true
	var script_clean := true
	var steady_off := true
	var first_miss := ""
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hn: GSWeaponHitscan = w[0]
		var hs: GSWeaponHitscan = w[1]
		var ctx := GSWeaponContext.new()
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs)
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.04:
				edits += _native_edit(rng, w)
			if rng.randf() < 0.05:
				# A use between ticks: both states take the same writes.
				var bloom := float(hs.state.get(&"bloom", 0.0)) + rng.randf_range(0.0, 1.5)
				for d: Dictionary in [hn.state, hs.state]:
					d[&"since_use"] = 0
					d[&"bloom"] = bloom
			var none := rng.randf() < 0.1
			GSWeaponHitscan.native_tick = true
			hn._tick(null if none else ctx)
			GSWeaponHitscan.native_tick = false
			hs._tick(null if none else ctx)
			ticks += 1
			if not none:
				shown_ticks += 1
				if hn._native == null:
					native_ran = false
				if hn._steady:
					steady_off = false
			var miss := _native_state_diff(hs.state, hn.state)
			if miss == "" and hn._shown != hs._shown:
				miss = "shown script %s native %s" % [hs._shown, hn._shown]
			if miss != "" and first_miss == "":
				first_miss = "case %d tick %d: %s" % [i, t, miss]
		if hs._native != null:
			script_clean = false
	GSWeaponHitscan.native_tick = native_was

	_check(first_miss == "", "%d ticks of %d random weapons: state and cone match the GDScript tick, key for key and bit for bit" % [ticks, _NATIVE_CASES], first_miss)
	_check(native_ran and steady_off, "every context tick of the native twin ran natively and kept no steady fixed point (%d)" % shown_ticks)
	_check(script_clean, "with native_tick off a behaviour never builds the native twin")
	_check(edits > 200, "the tuning, rules, class, rate and crosshair edits that must refresh the native rows happened", str(edits))

	_check_native_aim_scaling(native_was)
	_check_native_rest_streams(native_was)
	_check_native_row_streams(native_was)
	_check_native_missing_class(native_was)
	_check_idle_gate(native_was)
	_check_tick_framed(native_was)
	_check_native_use(native_was)
	_check_recoil_posture()
	_done()


## Aim down sights as a game does it (FC's rig): the ballistics scaled for one tick and put back after, so every aimed
## tick bumps the revision with numbers the twin already holds. The twin keeps its row then (no re-send), and still
## agrees with the script tick bit for bit; a ramp that is still closing, and edits between, must re-send.
func _check_native_aim_scaling(native_was: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	var first_miss := ""
	var kept := 0
	var aimed_ticks := 0
	for i in range(40):
		var w := _native_case(rng)
		var hn: GSWeaponHitscan = w[0]
		var hs: GSWeaponHitscan = w[1]
		var b: GSWeaponBallistics = w[2]
		var ctx := GSWeaponContext.new()
		var aim_ticks := 0
		var ramp_ticks := rng.randi_range(1, 12)
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs)
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.02:
				_native_edit(rng, w)
			if rng.randf() < 0.03:
				aim_ticks = 0 if aim_ticks > 0 else 1
			if rng.randf() < 0.05:
				b.spread = b.spread
			var kept_spread := b.spread
			var kept_moving := b.spread_moving
			var kept_airborne := b.spread_airborne
			var kept_bloom := b.bloom
			if aim_ticks > 0:
				var k := lerpf(1.0, 0.35, minf(float(aim_ticks) / float(ramp_ticks), 1.0))
				b.spread *= k
				b.spread_moving *= k
				b.spread_airborne *= k
				b.bloom *= k
				aim_ticks += 1
				aimed_ticks += 1
			GSWeaponHitscan.native_tick = true
			hn._tick(ctx)
			GSWeaponHitscan.native_tick = false
			hs._tick(ctx)
			b.spread = kept_spread
			b.spread_moving = kept_moving
			b.spread_airborne = kept_airborne
			b.bloom = kept_bloom
			var miss := _native_state_diff(hs.state, hn.state)
			if miss == "" and hn._shown != hs._shown:
				miss = "shown script %s native %s" % [hs._shown, hn._shown]
			if miss != "" and first_miss == "":
				first_miss = "case %d tick %d: %s" % [i, t, miss]
		kept += hn._native_kept
	GSWeaponHitscan.native_tick = native_was
	_check(first_miss == "" and kept > aimed_ticks / 2, "aim scaling put back every tick: the twin kept its tuning row on %d of %d aimed ticks and matched the script tick bit for bit" % [kept, aimed_ticks], first_miss)


## The rest streams: the native tick and the script tick agree on one arsenal.
func _check_native_rest_streams(native_was: bool) -> void:
	_rest_native = true
	var all_same := true
	var detail := ""
	for mode: String in _MODES:
		var res := _rest_stream(mode)
		if not res["same"] or not res["spread_same"]:
			all_same = false
			detail = res["detail"]
	_rest_native = false
	GSWeaponHitscan.native_tick = native_was
	GSWeaponHitscan.steady_skip = true
	_check(all_same, "the rest streams agree with the native tick on one arsenal: outcomes, snapshots, state and cone", detail)


## The rest streams again, with that arsenal's idle ticks as one native call from a posture row (idle_tick_row). The
## idle gate runs its verify mode here (GSWeaponBehaviour.idle_gate 2): _check_idle_gate counts what it found.
func _check_native_row_streams(native_was: bool) -> void:
	_rest_native = true
	_rest_row = true
	_gate_row_misses = GSWeaponBehaviour.idle_gate_misses
	var gate_was := GSWeaponBehaviour.idle_gate
	GSWeaponBehaviour.idle_gate = 2
	var all_same := true
	var detail := ""
	for mode: String in _MODES:
		var res := _rest_stream(mode)
		if not res["same"] or not res["spread_same"]:
			all_same = false
			detail = res["detail"]
	_rest_row = false
	_rest_native = false
	GSWeaponBehaviour.idle_gate = gate_was
	_gate_row_misses = GSWeaponBehaviour.idle_gate_misses - _gate_row_misses
	GSWeaponHitscan.native_tick = native_was
	GSWeaponHitscan.steady_skip = true
	_check(all_same, "the rest streams agree with the idle row on one arsenal: outcomes, snapshots, state and cone", detail)


var _gate_row_misses := 0


## GSWeaponBehaviour.idle_gate: the gated idle row (1) and its verify mode (2) leave what the plain one (0) leaves, bit
## for bit, over three behaviours on one random weapon edited mid-run (tuning, rules, class, rate, crosshair) with uses and
## script ticks between rows; then a posed tick_needs_context answers as the plain one for every kind of weapon.
func _check_idle_gate(native_was: bool) -> void:
	var gate_was := GSWeaponBehaviour.idle_gate
	var misses_was := GSWeaponBehaviour.idle_gate_misses
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var rows := 0
	var held := 0
	var first_miss := ""
	GSWeaponHitscan.native_tick = true
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hs: Array[GSWeaponHitscan] = [w[0], w[1], GSWeaponHitscan.new()]
		hs[2].setup(w[3], w[4])
		var arsenal: NativeArsenal = w[4]
		var ctx := GSWeaponContext.new()
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs[0])
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.04:
				_native_edit(rng, w)
			if rng.randf() < 0.05:
				var bloom := float(hs[0].state.get(&"bloom", 0.0)) + rng.randf_range(0.0, 1.5)
				for h in hs:
					h.state[&"since_use"] = 0
					h.state[&"bloom"] = bloom
			if rng.randf() < 0.05:
				# A script context tick between rows: it may leave a steady fixed point the rows must decline on.
				GSWeaponHitscan.native_tick = false
				for h in hs:
					h._tick(ctx)
				GSWeaponHitscan.native_tick = true
			var row := PackedFloat64Array([ctx.speed, float(ctx.airborne), float(ctx.crouched), float(ctx.aiming),
					float(ctx.sliding), float(ctx.sprinting), float(ctx.wall_running), ctx.tick, ctx.hurt_tick])
			var rest := rng.randf() < 0.5
			var rules: GSWeaponSpreadRules = arsenal.spread_rules
			var rate: int = arsenal.tick_rate
			var took: Array[int] = []
			for g in range(3):
				GSWeaponBehaviour.idle_gate = g
				if g == 1 and hs[1]._idle_gate_holds(rules, arsenal.crosshair_cone and rules != null, rate):
					held += 1
				took.append(hs[g].idle_row_framed(row, rest, rules, arsenal.crosshair_cone, rate))
			rows += 1
			for g in [1, 2]:
				var miss := _native_state_diff(hs[0].state, hs[g].state)
				if miss == "" and (took[g] != took[0] or hs[g]._shown != hs[0]._shown or hs[g]._shown_stale != hs[0]._shown_stale or hs[g]._steady != hs[0]._steady):
					miss = "took %s shown %s/%s stale %s/%s" % [took, hs[0]._shown, hs[g]._shown, hs[0]._shown_stale, hs[g]._shown_stale]
				if miss != "" and first_miss == "":
					first_miss = "gate %d case %d tick %d: %s" % [g, i, t, miss]
	GSWeaponBehaviour.idle_gate = gate_was
	GSWeaponHitscan.native_tick = native_was
	var misses := GSWeaponBehaviour.idle_gate_misses - misses_was
	_check(first_miss == "", "%d idle rows of %d random weapons: gate 1 and its verify mode leave what gate 0 leaves, key for key and bit for bit" % [rows, _NATIVE_CASES], first_miss)
	_check(held > rows / 2 and misses == 0, "the gate held on most rows (%d of %d) and its verify mode found nothing" % [held, rows], "held %d misses %d" % [held, misses])
	_check(_gate_row_misses == 0, "the rest streams' idle rows under the verify mode: the arsenal's frame is the one idle_row reads, the gate never stale", str(_gate_row_misses))

	var cat := _catalogue()
	var a := _arsenal(cat)
	var ctx := GSWeaponContext.new()
	a.idle_posture = func() -> GSWeaponContext: return ctx
	var differ := ""
	for id in cat.ids():
		var made := cat.instantiate(id, a)
		var b: GSWeaponBehaviour = made.value if made.ok else null
		if b == null or b.tick_needs_context_posed() != b.tick_needs_context():
			differ += "%s " % id
	_drop(a)
	_check(differ == "", "with a posture, tick_needs_context_posed answers as tick_needs_context for every weapon in the catalogue", differ)


## The arsenal's context tick under the gate: tick_framed (gates 1 and 2) leaves what the plain tick (gate 0) leaves on
## random weapons, edits, script ticks and uses between, and the gate holds on most ticks with nothing found by verify.
func _check_tick_framed(native_was: bool) -> void:
	var gate_was := GSWeaponBehaviour.idle_gate
	var misses_was := GSWeaponBehaviour.idle_gate_misses
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	var ticks := 0
	var held := 0
	var first_miss := ""
	GSWeaponHitscan.native_tick = true
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hs: Array[GSWeaponHitscan] = [w[0], w[1], GSWeaponHitscan.new()]
		hs[2].setup(w[3], w[4])
		var arsenal: NativeArsenal = w[4]
		var ctx := GSWeaponContext.new()
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs[0])
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.04:
				_native_edit(rng, w)
			if rng.randf() < 0.05:
				var bloom := float(hs[0].state.get(&"bloom", 0.0)) + rng.randf_range(0.0, 1.5)
				for h in hs:
					h.state[&"since_use"] = 0
					h.state[&"bloom"] = bloom
			if rng.randf() < 0.05:
				GSWeaponHitscan.native_tick = false
				for h in hs:
					h._tick(ctx)
				GSWeaponHitscan.native_tick = true
			var rules: GSWeaponSpreadRules = arsenal.spread_rules
			var rate: int = arsenal.tick_rate
			for g in range(3):
				GSWeaponBehaviour.idle_gate = g
				if g == 0:
					hs[0].tick(ctx)
				else:
					if g == 1 and hs[1]._tick_gate_holds(rules, arsenal.crosshair_cone and rules != null, rate):
						held += 1
					hs[g].tick_framed(ctx, rules, arsenal.crosshair_cone, rate)
			ticks += 1
			for g in [1, 2]:
				var miss := _native_state_diff(hs[0].state, hs[g].state)
				if miss == "" and (hs[g]._shown != hs[0]._shown or hs[g]._shown_stale != hs[0]._shown_stale or hs[g]._steady != hs[0]._steady):
					miss = "shown %s/%s stale %s/%s steady %s/%s" % [hs[0]._shown, hs[g]._shown, hs[0]._shown_stale, hs[g]._shown_stale, hs[0]._steady, hs[g]._steady]
				if miss != "" and first_miss == "":
					first_miss = "gate %d case %d tick %d: %s" % [g, i, t, miss]
	GSWeaponBehaviour.idle_gate = gate_was
	GSWeaponHitscan.native_tick = native_was
	var misses := GSWeaponBehaviour.idle_gate_misses - misses_was
	_check(first_miss == "", "%d context ticks of %d random weapons: tick_framed and its verify mode leave what the plain tick leaves, bit for bit" % [ticks, _NATIVE_CASES], first_miss)
	_check(held > ticks / 2 and misses == 0, "the framed gate held on most ticks (%d of %d) and its verify mode found nothing" % [held, ticks], "held %d misses %d" % [held, misses])


## The same seeded shots through use() with the native cones and with the GDScript ones: twins on shared tuning, rules
## and recoil rules, ticked each way between, fire at random postures; every outcome (cone, directions, pellets, recoil)
## and the state and shown cone after must match bit for bit, with gates 0 and 1.
const _NativeShot := preload("res://addons/gs_weapon/behaviour/gs_weapon_hitscan_native_shot.gd")


func _check_native_use(native_was: bool) -> void:
	var gate_was := GSWeaponBehaviour.idle_gate
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	var uses := 0
	var native_uses := 0
	var kicked := 0
	var first_miss := ""
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hn: GSWeaponHitscan = w[0]
		var hs: GSWeaponHitscan = w[1]
		var b: GSWeaponBallistics = w[2]
		var arsenal: NativeArsenal = w[4]
		b.pellets = 1 if rng.randf() < 0.7 else rng.randi_range(2, 9)
		b.recoil_pitch = rng.randf_range(0.0, 3.0)
		b.recoil_yaw = rng.randf_range(-1.0, 1.0)
		for f: StringName in [&"recoil_aim", &"recoil_crouch", &"recoil_move"]:
			b.set(f, -1.0 if rng.randf() < 0.5 else rng.randf_range(0.3, 1.5))
		b.fixed_pattern = rng.randf() < 0.2
		b.recoil_seed = 0 if rng.randf() < 0.5 else rng.randi_range(1, 0x7fffffff)
		b.recoil_build = rng.randf_range(0.0, 0.3)
		b.recoil_build_max = rng.randf_range(0.0, 1.0)
		b.recoil_recovery = rng.randf_range(0.0, 12.0)
		b.recoil_camera = -1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 1.0)
		var rr: GSWeaponRecoilRules = null
		if rng.randf() < 0.6:
			rr = GSWeaponRecoilRules.new()
			rr.enabled = rng.randf() < 0.85
			for f: StringName in [&"scale", &"vertical", &"horizontal", &"recovery", &"punch", &"follow", &"build",
					&"mult_aim", &"mult_crouch", &"mult_move", &"mult_air"]:
				rr.set(f, rng.randf_range(0.0, 2.0))
			rr.reset = rng.randf_range(0.05, 1.0)
			arsenal.recoil_rules = rr
		GSWeaponBehaviour.idle_gate = rng.randi_range(0, 1)
		var ctx := GSWeaponContext.new()
		ctx.entity = rng.randi_range(1, 64)
		for t in range(_NATIVE_TICKS):
			if rng.randf() < 0.2:
				_native_posture_roll(rng, ctx, hs)
			ctx.tick = t
			if rng.randf() < 0.03:
				_native_edit(rng, w)
			GSWeaponHitscan.native_tick = true
			hn._tick(ctx)
			GSWeaponHitscan.native_tick = false
			hs._tick(ctx)
			if rng.randf() < 0.25:
				ctx.origin = Vector3(rng.randf_range(-50.0, 50.0), rng.randf_range(0.0, 5.0), rng.randf_range(-50.0, 50.0))
				ctx.direction = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)).normalized()
				ctx.index = t
				GSWeaponHitscan.native_tick = true
				var on := hn.use(ctx)
				GSWeaponHitscan.native_tick = false
				var off := hs.use(ctx)
				uses += 1
				if rr != null and rr.enabled:
					kicked += 1
				if hn._native != null:
					native_uses += 1
				var miss := _native_outcome_diff(off, on)
				if miss == "":
					miss = _native_state_diff(hs.state, hn.state)
				if miss == "" and hn._shown != hs._shown:
					miss = "shown script %s native %s" % [hs._shown, hn._shown]
				if miss != "" and first_miss == "":
					first_miss = "case %d tick %d: %s" % [i, t, miss]
	GSWeaponBehaviour.idle_gate = gate_was
	GSWeaponHitscan.native_tick = native_was
	_check(first_miss == "", "%d seeded shots of %d random weapons: use() with the native cones matches the GDScript use bit for bit" % [uses, _NATIVE_CASES], first_miss)
	_check(native_uses == uses and uses > 1000, "every native-side shot ran with the native twin built (%d of %d)" % [native_uses, uses])
	_check(kicked > 300 and GSWeaponHitscan.native_shot and _NativeShot._has == 1, "%d of them kicked by random recoil rules: gs-sim's recoil and scatter match apply() and GSShot.scatter() bit for bit (state keys, view kick, bullet direction, pellets)" % kicked)


## "" when two use outcomes fired the same shots and recoil, else the first difference.
func _native_outcome_diff(want: GSWeaponOutcome, got: GSWeaponOutcome) -> String:
	if want.shots.size() != got.shots.size():
		return "shots script %d native %d" % [want.shots.size(), got.shots.size()]
	if want.recoil != got.recoil or want.recoil_recovery != got.recoil_recovery or want.recoil_signed != got.recoil_signed:
		return "recoil script %s %s %s native %s %s %s" % [want.recoil, want.recoil_recovery, want.recoil_signed, got.recoil, got.recoil_recovery, got.recoil_signed]
	for k in range(want.shots.size()):
		var a := want.shots[k]
		var c := got.shots[k]
		if a.spread != c.spread:
			return "spread script %s native %s" % [a.spread, c.spread]
		if a.direction != c.direction or a.pellets != c.pellets:
			return "direction script %s %s native %s %s" % [a.direction, a.pellets, c.direction, c.pellets]
	return ""


## recoil_posture reads the field or the class preset as the ballistics' accuracy() does, for every class and posture.
func _check_recoil_posture() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	var first_miss := ""
	for i in range(400):
		var b := GSWeaponBallistics.new()
		b.accuracy_class = _native_class_roll(rng)
		for f: StringName in [&"recoil_aim", &"recoil_crouch", &"recoil_move"]:
			b.set(f, -1.0 if rng.randf() < 0.5 else rng.randf_range(0.3, 1.5))
		var def := GSWeaponDef.new()
		def.id = StringName(["ak", "mp5", "awp", "deagle", "m3", "x"][rng.randi_range(0, 5)])
		def.tuning = b
		var h := GSWeaponHitscan.new()
		h.setup(def, null)
		var ctx := GSWeaponContext.new()
		ctx.aiming = rng.randf() < 0.5
		ctx.crouched = rng.randf() < 0.5
		ctx.airborne = rng.randf() < 0.3
		ctx.speed = rng.randf_range(0.0, 1.0)
		h.recoil_posture(b, ctx)
		if rng.randf() < 0.3:
			# A class edit after the presets were cached must reach them.
			b.accuracy_class = _native_class_roll(rng)
		var klass := GSWeaponAccuracyClass.resolve(b.accuracy_class, def.tags, def.id)
		var want := 1.0
		if ctx.aiming:
			want *= b.accuracy("recoil_aim", klass)
		if ctx.crouched:
			want *= b.accuracy("recoil_crouch", klass)
		if ctx.airborne or ctx.speed >= 0.5:
			want *= b.accuracy("recoil_move", klass)
		var got := h.recoil_posture(b, ctx)
		if got != want and first_miss == "":
			first_miss = "case %d class %s: accuracy %s posture %s" % [i, b.accuracy_class, want, got]
	_check(first_miss == "", "recoil_posture equals the ballistics' accuracy() product for every class, field and posture", first_miss)


## A missing native class leaves the GDScript tick.
func _check_native_missing_class(native_was: bool) -> void:
	var cat := _catalogue()
	var a := _arsenal(cat)
	a.give(&"rifle")
	var h := a.current().behaviour as GSWeaponHitscan
	var present_was := GSWeaponHitscan._native_present
	GSWeaponHitscan._native_present = 0
	GSWeaponHitscan.native_tick = true
	h._tick(_ctx(0))
	_check(h._native == null and h.state.has(&"since_use"), "without the class the GDScript tick runs")
	GSWeaponHitscan._native_present = present_was
	GSWeaponHitscan.native_tick = native_was
	_drop(a)



## A random weapon on a stub arsenal, as GameSpice Sim's parity test builds it: [native behaviour, script behaviour, ballistics,
## def, arsenal]. Both behaviours share the def, tuning and arsenal, so an edit reaches both.
func _native_case(rng: RandomNumberGenerator) -> Array:
	var b := GSWeaponBallistics.new()
	b.spread = rng.randf_range(0.0, 3.0)
	b.spread_moving = rng.randf_range(0.0, 8.0)
	b.spread_speed_ref = [0.1, 3.0, 6.0, rng.randf_range(0.5, 12.0)][rng.randi_range(0, 3)]
	b.spread_airborne = rng.randf_range(0.0, 10.0)
	b.spread_crouched = rng.randf_range(0.2, 1.0)
	b.bloom = 0.0 if rng.randf() < 0.15 else rng.randf_range(0.05, 1.0)
	b.bloom_max = rng.randf_range(0.5, 6.0)
	b.bloom_recovery = rng.randf_range(0.01, 0.5)
	b.accuracy_class = _native_class_roll(rng)
	b.bloom_delay_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 20)
	b.settle_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 12)
	for f: StringName in [&"spread_aim", &"spread_hip", &"spread_sprint", &"spread_slide", &"spread_flinch", &"bloom_crouch"]:
		b.set(f, -1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 2.0))
	var def := GSWeaponDef.new()
	def.id = StringName(["ak", "mp5", "awp", "deagle", "m3", "x"][rng.randi_range(0, 5)])
	def.tuning = b
	def.authored_tick_rate = [0, 64, 128][rng.randi_range(0, 2)]
	def.use_interval_ticks = rng.randi_range(0, 20)
	var arsenal := NativeArsenal.new()
	arsenal.tick_rate = [0, 33, 64, 128][rng.randi_range(0, 3)]
	arsenal.crosshair_cone = rng.randf() < 0.5
	var pick := rng.randi_range(0, 2)
	if pick > 0:
		arsenal.spread_rules = _native_rules_roll(rng, pick == 2)
	var hn := GSWeaponHitscan.new()
	hn.setup(def, arsenal)
	var hs := GSWeaponHitscan.new()
	hs.setup(def, arsenal)
	return [hn, hs, b, def, arsenal]


func _native_class_roll(rng: RandomNumberGenerator) -> String:
	return ["", "rifle", "smg", "lmg", "sniper", "shotgun", "pistol"][rng.randi_range(0, 6)]


func _native_rules_roll(rng: RandomNumberGenerator, enabled: bool) -> GSWeaponSpreadRules:
	var r := GSWeaponSpreadRules.new()
	r.enabled = enabled
	r.scale = rng.randf_range(0.5, 2.0)
	for f: StringName in [&"mult_hip", &"mult_aim", &"mult_stand", &"mult_walk", &"mult_run", &"mult_air", &"mult_sprint", &"mult_slide", &"mult_crouch"]:
		r.set(f, rng.randf_range(0.3, 2.5))
	r.walk_speed = rng.randf_range(0.1, 2.0)
	r.run_speed = rng.randf_range(2.0, 6.0)
	r.recovery = 0.0 if rng.randf() < 0.1 else rng.randf_range(0.5, 12.0)
	r.max_spread = 0.0 if rng.randf() < 0.2 else rng.randf_range(2.0, 20.0)
	return r


## One edit the cached native rows must see: a ballistics field, the class, the def's tick fields, the arsenal's rate,
## crosshair or rules (a field, on/off, a new object or none). Returns 1.
func _native_edit(rng: RandomNumberGenerator, w: Array) -> int:
	var b: GSWeaponBallistics = w[2]
	var def: GSWeaponDef = w[3]
	var arsenal: NativeArsenal = w[4]
	match rng.randi_range(0, 11):
		0: b.spread = rng.randf_range(0.0, 3.0)
		1: b.spread_moving = rng.randf_range(0.0, 8.0)
		2: b.bloom_recovery = rng.randf_range(0.01, 0.5)
		3: b.set([&"spread_aim", &"spread_hip", &"spread_sprint", &"spread_slide", &"spread_flinch", &"bloom_crouch"][rng.randi_range(0, 5)], -1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 2.0))
		4: b.accuracy_class = _native_class_roll(rng)
		5: b.settle_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 12)
		6: def.use_interval_ticks = rng.randi_range(0, 20)
		7: arsenal.tick_rate = [0, 33, 64, 128][rng.randi_range(0, 3)]
		8: arsenal.crosshair_cone = not arsenal.crosshair_cone
		9:
			if arsenal.spread_rules != null:
				var r: GSWeaponSpreadRules = arsenal.spread_rules
				match rng.randi_range(0, 3):
					0: r.mult_stand = rng.randf_range(0.3, 2.5)
					1: r.recovery = rng.randf_range(0.5, 12.0)
					2: r.max_spread = 0.0 if rng.randf() < 0.2 else rng.randf_range(2.0, 20.0)
					3: r.enabled = not r.enabled
		10: arsenal.spread_rules = null if rng.randf() < 0.3 else _native_rules_roll(rng, rng.randf() < 0.7)
		11: b.bloom_delay_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 20)
	return 1


## A random posture: often still, at the rules' thresholds, or flinching.
func _native_posture_roll(rng: RandomNumberGenerator, ctx: GSWeaponContext, h: GSWeaponHitscan) -> void:
	var r := h._rules_object()
	var speeds := [0.0, 0.0, rng.randf_range(0.0, 10.0), rng.randf_range(0.0, 1.0)]
	if r != null:
		speeds.append_array([r.walk_speed, r.run_speed])
	ctx.speed = speeds[rng.randi_range(0, speeds.size() - 1)]
	ctx.airborne = rng.randf() < 0.2
	ctx.crouched = rng.randf() < 0.25
	ctx.aiming = rng.randf() < 0.3
	ctx.sliding = rng.randf() < 0.1
	ctx.sprinting = rng.randf() < 0.2
	ctx.wall_running = rng.randf() < 0.05
	ctx.hurt_tick = ctx.tick - rng.randi_range(-2, 40) if rng.randf() < 0.3 else -1


## "" when the two states hold the same keys with the same types and values, else the first difference.
func _native_state_diff(want: Dictionary, got: Dictionary) -> String:
	if want.size() != got.size():
		return "keys script %s native %s" % [want.keys(), got.keys()]
	for k: Variant in want:
		if not got.has(k):
			return "native has no %s" % k
		if typeof(want[k]) != typeof(got[k]) or want[k] != got[k]:
			return "%s script %s (%s) native %s (%s)" % [k, want[k], type_string(typeof(want[k])), got[k], type_string(typeof(got[k]))]
	return ""
