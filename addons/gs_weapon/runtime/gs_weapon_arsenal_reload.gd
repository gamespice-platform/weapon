@tool
extends "gs_weapon_arsenal_carry.gd"
## Reloads, the switch clock and replays for [GSWeaponArsenal]; a layer between carrying and the state machine so neither
## file grows past the size gate.


func is_switching() -> bool:
	return _switch_done_tick >= 0


## Puts [param slot] in hand ready to use now: [method bring_to_hand], and when it is already in hand, ends the switch
## still pending on it (its deploy, or a holster away from it). A server whose copy of a switch runs behind the client
## that fired settles the hand the shot was fired with before judging it. The cadence ([method next_use_tick]) is kept.
## False when [param slot] is not carried or was already in hand with no switch pending.
func settle_in_hand(slot: int) -> bool:
	if not _slots.has(slot):
		return false
	if slot != _current:
		_force_select(slot)
		return true
	if _switch_done_tick < 0:
		return false
	_switch_done_tick = -1
	_holstering = false
	return true


func is_reloading() -> bool:
	return _reloading


## Begins a reload. Returns false when there is nothing to do.
func begin_reload(tick: int) -> bool:
	var slot := current()

	if disabled or slot == null or _reloading or is_switching():
		return false

	if not slot.def.uses_magazine() or slot.magazine_space() <= 0:
		return false

	if slot.def.ammo_type != &"" and not _ammo.has(slot.def.ammo_type, 1):
		return false

	_reloading = true
	_reload_done_tick = tick + ticks_for(
		slot.def,
		slot.def.reload_start_ticks if slot.def.reload_per_round
		else slot.def.reload_ticks
	)
	reload_started.emit(_current)
	return true


func cancel_reload() -> void:
	_reloading = false
	_reload_done_tick = -1


func _finish_reload(tick: int) -> void:
	var slot := current()
	if slot == null:
		_reloading = false
		return

	var def := slot.def
	var want := def.magazine - slot.magazine

	if def.reload_per_round:
		want = 1

	var took := want
	if def.ammo_type != &"":
		took = _ammo.take(def.ammo_type, want) if not def.infinite_reserve else want
		if def.infinite_reserve:
			took = want

	if took <= 0:
		_reloading = false
		_reload_done_tick = -1
		return

	slot.magazine += took
	slot.behaviour.reloaded(took)

	if def.ammo_type != &"":
		ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))

	# A per-round reload keeps going until the magazine is full or the reserve is dry.
	if (
		def.reload_per_round
		and slot.magazine_space() > 0
		and (def.infinite_reserve or _ammo.has(def.ammo_type, 1) or def.ammo_type == &"")
	):
		_reload_done_tick = tick + ticks_for(def, def.reload_ticks)
	else:
		_reloading = false
		_reload_done_tick = -1
		reload_finished.emit(_current, slot.magazine)


## Marks the start of a reconciliation replay.
##
## Everything still simulates; what changes is that every context is marked
## [member GSWeaponContext.replayed], so a behaviour and a listener can decline to
## make a sound, spawn an effect or bill a statistic a second time.
func begin_replay() -> void:
	_replaying = true


func end_replay() -> void:
	_replaying = false


func is_replaying() -> bool:
	return _replaying


func _advance_reload(tick: int) -> void:
	if _reloading and _reload_done_tick >= 0 and tick >= _reload_done_tick:
		_finish_reload(tick)
