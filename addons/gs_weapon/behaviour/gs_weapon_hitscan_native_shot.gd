## A use's recoil and pellets from gs-sim's [code]GSSimWeaponSpread[/code] (its [code]recoil[/code] and
## [code]scatter[/code], twins of [method GSWeaponRecoilRules.apply] with
## [method GSWeaponRecoilRules.offset_direction] and of [method GSShot.scatter]): bit-exact, same state keys.
## Preloaded by path (no class_name), so a pack that loads gs_weapon by path parses it too.
extends RefCounted


## Whether the loaded library has [code]recoil[/code] and [code]scatter[/code]: -1 before the first ask,
## 0 for a gs-sim build older than them (the script path runs), 1 for one that has them.
static var _has: int = -1
## [method GSWeaponRecoilRules.seed_for]'s by-id seed, per weapon id (it walks the id's bytes).
static var _seeds: Dictionary = {}
static var _row := PackedFloat64Array()


## Kicks and scatters [param shot] for the current use of hitscan [param h] (whose [code]_native_row[/code]
## holds this use's posture): what [method GSWeaponHitscan._use]'s script path does with [param rr] and
## [method GSShot.scatter]. False when the library cannot, and nothing was changed.
static func aim(h: Variant, out: GSWeaponOutcome, shot: GSShot, b: GSWeaponBallistics, rr: GSWeaponRecoilRules) -> bool:
	var native: Object = h._native
	if _has < 0:
		_has = 1 if native.has_method(&"recoil") and native.has_method(&"scatter") else 0
	if _has == 0:
		return false
	if rr != null:
		var r: PackedFloat64Array = native.call(&"recoil", h.state, h._native_row, recoil_row(h, b, rr, shot.weapon_id), shot.direction)
		if r.size() < 5:
			return false
		out.recoil = Vector2(r[0], r[1])
		out.recoil_recovery = b.recoil_recovery * rr.recovery
		out.recoil_signed = true
		shot.direction = Vector3(r[2], r[3], r[4])
	shot.pellets = native.call(&"scatter", shot.direction, shot.spread, shot.attacker, shot.tick, shot.index, shot.pellet_count, shot.fixed_pattern)
	return true


## The 18-value row of [code]recoil[/code]: rate, reset, recovery, build, build max, pitch, yaw, share, follow,
## seed, the rules' posture (scale, aim, crouch, air, move) and the weapon's (aim, crouch, move), each after its
## fallbacks, so the kernel only multiplies.
static func recoil_row(h: Variant, b: GSWeaponBallistics, rr: GSWeaponRecoilRules, id: StringName) -> PackedFloat64Array:
	if _row.size() != 18:
		_row.resize(18)
	h._class_of(b)
	var seed_value := b.recoil_seed
	if seed_value == 0:
		seed_value = _seeds.get(id, 0)
		if seed_value == 0:
			seed_value = GSWeaponRecoilRules.seed_for(null, id)
			_seeds[id] = seed_value
	_row[0] = float(h.running_tick_rate())
	_row[1] = rr.reset
	_row[2] = b.recoil_recovery * rr.recovery
	_row[3] = b.recoil_build * rr.build
	_row[4] = b.recoil_build_max * rr.build
	_row[5] = b.recoil_pitch * rr.vertical
	_row[6] = b.recoil_yaw * rr.horizontal
	_row[7] = b.recoil_camera if b.recoil_camera >= 0.0 else rr.punch
	_row[8] = rr.follow
	_row[9] = float(seed_value)
	_row[10] = rr.scale
	_row[11] = rr.mult_aim
	_row[12] = rr.mult_crouch
	_row[13] = rr.mult_air
	_row[14] = rr.mult_move
	_row[15] = b.recoil_aim if b.recoil_aim >= 0.0 else float(h._pre_recoil_aim)
	_row[16] = b.recoil_crouch if b.recoil_crouch >= 0.0 else float(h._pre_recoil_crouch)
	_row[17] = b.recoil_move if b.recoil_move >= 0.0 else float(h._pre_recoil_move)
	return _row
