@tool
extends "gs_weapon_arsenal_carry.gd"
## Reloads, the switch clock and replays for [GSWeaponArsenal]; a layer between carrying and the state machine so neither
## file grows past the size gate.


func is_switching() -> bool:
	return _switch_done_tick >= 0


## Whether the weapon tick at [param tick] finds the slot now in hand ([method current_slot]) usable: no switch pending, or only its
## deploy, ending by then (that tick finishes the deploy before it uses the weapon). A client naming the weapon its command fires
## with asks this for the command's tick rather than [method is_switching], which is still true on the tick a deploy ends.
func in_hand_by(tick: int) -> bool:
	return _switch_done_tick < 0 or (not _holstering and tick >= _switch_done_tick)


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


## Moves the cadence deadline ([method next_use_tick]) by [param delta] ticks (API 62). A server that fires a command
## late, on a tick after the one the client fired it on, counts the cadence from that command's own tick, as the client
## did: `rebase_next_use(command_tick - fired_tick)` right after the late use. Unmoved, every follow-up tap the client
## fired on time is refused for being as many ticks early as the late one was late. With no deadline yet (0) it does nothing.
func rebase_next_use(delta: int) -> void:
	if delta == 0 or _next_use_tick <= 0:
		return
	_next_use_tick = maxi(0, _next_use_tick + delta)


## The clock state a client's replay of its own ticks has to start from (API 62): the cadence, the use count and the
## held, burst, buffer and charge clocks, plus the in-hand weapon's behaviour state (bloom, settling motion). Small
## next to [method snapshot]: a predicting client saves it before every tick it simulates and hands the one saved
## for a replay's first tick to [method restore_rollback], so the replay sheds and piles bloom from where the first
## pass did. Replayed from the newest state instead, every replay re-ran the recovery ticks on top of a cone already
## recovered, and the cone the client drew a shot in drifted from the server's. Ammunition and the carried set are not
## in it: those are the server's word on a client (owner-only state), and a correction to them must stand.
func rollback_state() -> Dictionary:
	var slot := current()
	return {
		"current": _current,
		"next_use": _next_use_tick,
		"use_index": _use_index,
		"held": _held_ticks,
		"burst_left": _burst_left,
		"buffer": _buffer_until,
		"charge_started": _charge_started,
		"behaviour": slot.behaviour.state.duplicate(true) if slot != null and slot.behaviour != null else {},
	}


## Puts back a [method rollback_state]. False (nothing changed) when the slot in hand is not the one it was saved
## with: the replay then starts from the state there is, as before API 62.
func restore_rollback(d: Dictionary) -> bool:
	if d.is_empty() or int(d.get("current", -1)) != _current:
		return false
	_next_use_tick = int(d.get("next_use", _next_use_tick))
	_use_index = int(d.get("use_index", _use_index))
	_held_ticks = int(d.get("held", _held_ticks))
	_burst_left = int(d.get("burst_left", _burst_left))
	_buffer_until = int(d.get("buffer", _buffer_until))
	_charge_started = int(d.get("charge_started", _charge_started))
	var slot := current()
	if slot != null and slot.behaviour != null and d.has("behaviour"):
		slot.behaviour.state = (d["behaviour"] as Dictionary).duplicate(true)
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
