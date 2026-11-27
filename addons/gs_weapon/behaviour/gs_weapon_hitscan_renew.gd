## [GSWeaponHitscan]'s members back to their initial values, for [method GSWeaponHitscan._renew] (API 56). Split out
## for file size; preloaded by path (no class_name). A member added to the hitscan and missed here fails the selftest
## (each member is compared with a new instance).
extends RefCounted

const _Rows := preload("gs_weapon_hitscan_native_rows.gd")


## Whether [param h] is the stock hitscan, not a subclass (which may declare members this does not know); caches it in [code]_plain[/code].
static func plain(h: GSWeaponHitscan) -> bool:
	var script := h.get_script() as Script
	h._plain = 1 if script != null and script.resource_path.get_file() == "gs_weapon_hitscan.gd" else 0
	return h._plain == 1


## Renews [param h] when it is the stock hitscan; false (nothing touched) for a subclass.
static func renew(h: GSWeaponHitscan) -> bool:
	if not (h._plain == 1 if h._plain >= 0 else plain(h)):
		return false
	reset(h)
	return true


static func reset(h: GSWeaponHitscan) -> void:
	h._class_key = ""
	h._class_id = &""
	h._class_key_set = false
	h._class = ""
	h._pre_hip = 0.0
	h._pre_slide = 1.0
	h._pre_sprint = 1.0
	h._pre_flinch = 0.0
	h._pre_crouch = 1.0
	h._pre_aim = 1.0
	h._pre_settle = 0.0
	h._pre_recoil_aim = 1.0
	h._pre_recoil_crouch = 1.0
	h._pre_recoil_move = 1.0
	h._shown = -1.0
	h._shown_stale = false
	h._settled = null
	h._native = null
	h._native_b = null
	h._native_b_rev = -1
	h._native_def = null
	h._native_interval = 0
	h._native_authored = 0
	h._native_class = ""
	h._native_rate = 0
	h._native_framed = false
	h._native_rules = null
	h._native_rules_rev = -1
	h._native_cone = false
	h._native_frame_rate = 0
	h._native_row = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	h._native_sent = _Rows.tuning_row()
	h._native_check = _Rows.tuning_row()
	h._native_kept = 0
	h._native_idle = -1
	h._steady = false
	h._steady_b = null
	h._steady_rules = null
	h._steady_cone = false
	h._steady_airborne = false
	h._steady_crouched = false
	h._steady_aiming = false
	h._steady_sliding = false
	h._steady_sprinting = false
	h._steady_wall = false
	h._steady_motion = 0.0
	h._steady_bloom = 0.0
	h._steady_write_now = false
	h._steady_shown = 0.0
	h._steady_enabled = false
	h._steady_scale = 1.0
	h._steady_max = 0.0
	h._steady_factor = 1.0
	h._steady_class = ""
	h._steady_tuning = PackedFloat64Array()
	h._plain = -1
