@tool
class_name GSWeaponArsenal
extends "gs_weapon_arsenal_reload.gd"

## What one carrier holds, and the state machine that drives it.
##
## [b]It decides that a use happened. It never decides what the use hit.[/b] That is
## GameSpice Combat's job, and the split is the same one GameSpice Combat draws internally: this
## runs on the owning client [i]and[/i] on the server, and both reach the same
## [GSWeaponOutcome] from the same command. Collapsing the two gives you a client that
## decides who dies.
##
## [b]It is a pure function of the commands it is given.[/b] No device, no wall clock,
## no node lookups, no randomness, so a client can predict, a server re-run and a
## reconciliation replay re-run it to the same answer. See gs-combat's [GSSpread].
##
## [b]Every weapon-specific decision belongs to a [GSWeaponBehaviour].[/b] This file
## knows about slots, cadence, ammunition, reloading and switching, and deliberately
## knows nothing about pellets, arrows, arcs or beams. A game adding a weapon writes a
## behaviour; it does not touch this.


## Validates the catalogue and makes the arsenal usable. [b]Validates rather than trusts:[/b] a duplicate id
## hands a player the wrong weapon silently, so the check happens once, at boot, where somebody is watching.
func setup() -> GSResult:
	if catalogue == null:
		return GSResult.fail(
			GSError.CODE_INVALID, "An arsenal needs a catalogue before it can be set up."
		)

	var res := catalogue.validate()
	if not res.ok:
		return res.wrap("The weapon catalogue is not valid.")

	_ready_for_use = true
	return GSResult.success(null)


func is_ready() -> bool:
	return _ready_for_use


## Loads round [param ammo] into weapon [param weapon_id]; an empty id goes back to the weapon's own.
func load_ammo(weapon_id: StringName, ammo: StringName) -> void:
	if ammo == &"":
		loaded_ammo.erase(weapon_id)
	else:
		loaded_ammo[weapon_id] = ammo


## The round [param weapon_id] fires: the one loaded, else the profile that lists the gun, else the default one. Null without [member ammo_types].
func round_for(weapon_id: StringName) -> GSWeaponAmmoType:
	if ammo_types == null:
		return null
	var loaded := ammo_of(weapon_id)
	var t := ammo_types.get_type(loaded) if loaded != &"" else null
	return t if t != null else ammo_types.type_for_weapon(weapon_id)


## The round loaded in [param weapon_id], or empty.
func ammo_of(weapon_id: StringName) -> StringName:
	return loaded_ammo.get(weapon_id, &"")


## Gives the carrier a weapon, in the slot its definition names. [param full] fills the magazine and
## tops the reserve pool up to [member GSWeaponDef.reserve]; a pickup off the floor usually wants it false.
func give(id: StringName, full: bool = true) -> GSResult:
	if not _ready_for_use:
		return GSResult.fail(GSError.CODE_STATE, "setup() has not been called.")

	var made := _behaviour_for(id)
	if not made.ok:
		return made

	var def := catalogue.get_def(id)

	if def.slot > max_slots:
		return GSResult.fail(
			GSError.CODE_INVALID,
			"%s wants slot %d but this arsenal has %d." % [
				String(id), def.slot, max_slots
			],
			String(id)
		)

	var slot := GSWeaponSlot.make(def, made.value)
	slot.revision_box = _revision_box
	slot.magazine = def.magazine if full else 0

	var held: GSWeaponSlot = _slots.get(def.slot, null)
	var stow := held != null and held.id() != id and weapons_in(def.slot).size() < slot_capacity() \
		and not _shelf_has(def.slot, id)
	var gone := held if (held != null and not stow) else null
	if carry != null and carry.enabled:
		var after: float = carried_weight() + carry.weight_of(def) - (carry.weight_of(gone.def) if gone != null else 0.0)
		if after > capacity() and carry.weight_of(def) > carry.weight_of(gone.def if gone != null else null):
			return GSResult.fail(
				GSError.CODE_QUOTA,
				"Too heavy: %s weighs %.1f and you carry %.1f of %.1f." % [
					def.display_name if def.display_name != "" else String(id),
					carry.weight_of(def), carried_weight(), capacity()
				],
				String(id)
			)

	if stow:
		_shelf_of(def.slot).append(held)
	elif held != null:
		_shelf_drop(def.slot, id)
	_slots[def.slot] = slot

	if def.ammo_type != &"":
		if _ammo.cap(def.ammo_type) <= 0 and def.reserve_cap() > 0:
			_ammo.set_cap(def.ammo_type, def.reserve_cap())
		if full and def.reserve > 0:
			var added := _ammo.add(def.ammo_type, def.reserve)
			if added > 0:
				ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))

	carried_changed.emit()

	if _current == 0:
		_force_select(def.slot)

	return GSResult.success(slot)


## Puts [param slot] in the hand at once, for a hand-out (spawn loadout). Unlike [method select] it works
## while [member disabled] (a round's freeze), so a spawn is not left holding the first weapon given.
func equip(slot: int) -> bool:
	if slot == _current or not _slots.has(slot):
		return false
	_force_select(slot)
	return true


## Begins a switch to [param slot]. Returns false if it cannot start.
##
## A switch is a holster followed by a deploy, and the weapon in hand stays usable
## until the holster finishes, which is what makes quick-switching a real technique
## rather than an instant teleport between weapons.
##
## [b]Asking again for the slot already being switched to is not a new switch.[/b] A command
## carries its slot every tick, and a switch restarted on each would push the holster
## deadline back for ever.
func select(slot: int, tick: int) -> bool:
	if disabled or slot == _current or not _slots.has(slot):
		return false

	if is_switching() and _switch_to == slot:
		return false

	var from := current()

	_switch_to = slot
	_holstering = true
	_switch_done_tick = tick + (ticks_for(from.def, from.def.holster_ticks) if from != null else 0)

	# A reload that survived a switch would finish into a magazine nobody is holding.
	_cancel_transient()

	return true


func select_next(tick: int) -> bool:
	var all := slots()
	if all.size() < 2:
		return false
	var at := all.find(_current)
	return select(all[(at + 1) % all.size()], tick)


func select_previous(tick: int) -> bool:
	var all := slots()
	if all.size() < 2:
		return false
	var at := all.find(_current)
	return select(all[(at - 1 + all.size()) % all.size()], tick)


func select_last(tick: int) -> bool:
	return select(_previous, tick) if _slots.has(_previous) else false


## Microseconds per part of [method simulate_tick] and [method idle_tick], summed while [member phase_timers] is on (a
## profiler's sub-spans); [member phase_calls] counts full ticks, idle ticks and idle ticks the rest skip ended.
const PHASES: Array[StringName] = [&"pre", &"behaviour", &"use", &"idle_rest", &"idle_tick"]
static var phase_us := PackedInt64Array([0, 0, 0, 0, 0])
static var phase_calls := PackedInt64Array([0, 0, 0])
static var phase_timers := false

var _idle_out: GSWeaponOutcome


## Runs one tick of one command. The only entry point a game needs.
##
## [param ctx] carries the carrier's origin, aim and posture for this tick; the arsenal
## fills in the tick, the index, the charge and the replay flag before handing it to a
## behaviour. Returns the outcome of a use, or a refusal with
## [member GSWeaponOutcome.used] false, which is the ordinary case on most ticks.
func simulate_tick(
	command: GSWeaponCommand,
	ctx: GSWeaponContext,
	previous: GSWeaponCommand = null
) -> GSWeaponOutcome:
	if not _ready_for_use:
		return GSWeaponOutcome.nothing("setup() has not been called.")

	ctx.replayed = _replaying
	ctx.authority = authority
	var sprint_blocked := ctx.sprinting and ctx.sprint_blocks_aim
	ctx.aiming = command.is_pressed(GSWeaponCommand.BUTTON_AIM) and not sprint_blocked

	if disabled:
		return GSWeaponOutcome.nothing("The arsenal is disabled.")

	var lap := Time.get_ticks_usec() if phase_timers else 0
	_advance_switch(ctx)
	_advance_reload(ctx.tick)

	var slot := current()
	if slot == null:
		return GSWeaponOutcome.nothing("Nothing in hand.")

	_apply_slot_request(command, ctx.tick)
	var wants_mode := command.is_pressed(GSWeaponCommand.BUTTON_FIRE_MODE)
	if wants_mode and not (previous != null and previous.is_pressed(GSWeaponCommand.BUTTON_FIRE_MODE)):
		var _changed := cycle_fire_mode()
	if lap != 0:
		lap = _lap(0, lap)
	_run_behaviour_tick(slot, ctx)
	if lap != 0:
		lap = _lap(1, lap)
		phase_calls[0] += 1

	if is_switching():
		return GSWeaponOutcome.nothing("Switching.")

	if command.is_pressed(GSWeaponCommand.BUTTON_RELOAD) and not sprint_blocked:
		begin_reload(ctx.tick)

	var out := _advance_use(slot, command, ctx, previous)
	if lap != 0:
		_lap(2, lap)
	return out


static func _lap(phase: int, since: int) -> int:
	var now := Time.get_ticks_usec()
	phase_us[phase] += now - since
	return now


## Whether [method simulate_tick] would only tick the weapon in hand: no button, no other slot
## asked for, nothing switching, reloading, charging or bursting, and a behaviour whose tick
## reads no context. A server asks it of every shooter to skip building a context.
func is_idle_for(command: GSWeaponCommand, previous: GSWeaponCommand) -> bool:
	if not _ready_for_use or disabled or command.buttons != 0 or (command.slot > 0 and command.slot != _current):
		return false

	if previous != null and previous.buttons != 0:
		return false

	if _switch_done_tick >= 0 or _reloading or _burst_left > 0 or _charge_started >= 0 or _buffer_until >= 0:
		return false

	var slot := current()
	if slot == null:
		return false
	# With a posture the behaviour need not look for one (GSWeaponBehaviour.idle_gate; 0 asks the plain way).
	var gate := GSWeaponBehaviour.idle_gate
	if gate == 0 or not idle_posture.is_valid():
		return not slot.behaviour.tick_needs_context()
	var needs := slot.behaviour.tick_needs_context_posed()
	if gate == 2 and needs != slot.behaviour.tick_needs_context():
		GSWeaponBehaviour.idle_gate_misses += 1
		push_error("gs-weapon idle gate (%s): tick_needs_context_posed says %s, tick_needs_context the opposite" % [slot.def.id, needs])
	return not needs


## Whether [method simulate_tick] with this command and context reads nothing of the context's aim: the attack is
## held on a weapon inside its cadence, with no switch, charge, burst or release that a behaviour would be handed it for.
## A rig asks it before working out where the barrel points, which costs physics rays on a tick no shot can leave.
func is_cooling_for(command: GSWeaponCommand, ctx: GSWeaponContext) -> bool:
	if not _ready_for_use or disabled or _switch_done_tick >= 0 or ctx.tick >= _next_use_tick:
		return false

	var wanted := GSWeaponCommand.BUTTON_ATTACK | GSWeaponCommand.BUTTON_FIRE_MODE
	if (command.buttons & wanted) != GSWeaponCommand.BUTTON_ATTACK or (ctx.sprinting and ctx.sprint_blocks_fire):
		return false

	var slot := current()
	if slot == null or slot.behaviour.tick_needs_context():
		return false

	var mode := slot.fire_mode()
	return mode != GSWeaponDef.Fire.CHARGE and mode != GSWeaponDef.Fire.BURST


## The spread cone half-angle the weapon in hand would fire with now, for a crosshair; 0 with none.
func spread_now() -> float:
	var slot := current()
	return slot.behaviour.spread_now() if slot != null else 0.0


## The crosshair gap scale of the weapon in hand (see [member GSWeaponBallistics.crosshair_scale]); 1 with none.
func crosshair_scale() -> float:
	var slot := current()
	if slot == null or slot.def == null:
		return 1.0
	if slot.def.crosshair_scale > 0.0:
		return slot.def.crosshair_scale
	if not (slot.def.tuning is GSWeaponBallistics):
		return 1.0
	return (slot.def.tuning as GSWeaponBallistics).crosshair_scale_for(slot.def.tags)


## The tick [method is_idle_for] promised: what [method simulate_tick] does for it, with no context
## (or the [member idle_posture] one).
func idle_tick() -> GSWeaponOutcome:
	_held_ticks = 0
	var behaviour := current().behaviour
	var lap := Time.get_ticks_usec() if phase_timers else 0
	if lap != 0:
		phase_calls[1] += 1

	# A weapon with nothing to recover on a settled carrier changes nothing by ticking: skip the posture and the tick.
	if idle_rest_skip and idle_still.is_valid() and behaviour.rest_tick(idle_still):
		if lap != 0:
			_lap(3, lap)
			phase_calls[2] += 1
		return _idle_nothing()
	if lap != 0:
		lap = _lap(3, lap)

	behaviour.tick(idle_posture.call() as GSWeaponContext if idle_posture.is_valid() else null)
	if lap != 0:
		_lap(4, lap)
	return _idle_nothing()


## [method idle_tick] with the [member idle_posture] context already a row ([method GSWeaponBehaviour.idle_row]) and
## [member idle_still]'s answer already in [param still]: both must be what those callables would say this tick. A
## behaviour with a native idle tick takes it in one call; any other runs [method idle_tick]. Same result either way.
func idle_tick_row(row: PackedFloat64Array, still: bool) -> GSWeaponOutcome:
	if not idle_posture.is_valid():
		return idle_tick()
	var lap := Time.get_ticks_usec() if phase_timers else 0
	var rest := still and idle_rest_skip and idle_still.is_valid()
	var took := current().behaviour.idle_row_framed(row, rest, spread_rules, crosshair_cone, tick_rate)
	if took == GSWeaponBehaviour.IDLE_ROW_DECLINED:
		return idle_tick()
	_held_ticks = 0
	if lap != 0:
		phase_calls[1] += 1
		if took == GSWeaponBehaviour.IDLE_ROW_RESTED:
			_lap(3, lap)
			phase_calls[2] += 1
		else:
			_lap(4, lap)
	return _idle_nothing()


## [method idle_tick_row] joined to a native batch (API 57): appends this arsenal's entry
## [code][twin, state, behaviour, k, rest_ok][/code] to [param entries] for gs-sim's [code]GSSimWeaponIdleBatch.run[/code]
## (posture row [param k] of the rows it is handed, the still flag at the row's [code][9][/code]) and returns the idle
## outcome, or null (nothing appended) when the behaviour has no twin that provably holds, phase timers are on or no
## [member idle_posture] is set: then call [method idle_tick_row]. An entry the batch declines must run [method idle_tick].
func idle_batch_add(entries: Array, k: int) -> GSWeaponOutcome:
	if phase_timers or not idle_posture.is_valid():
		return null
	var slot := current()
	if slot == null:
		return null
	var behaviour := slot.behaviour
	var twin := behaviour.idle_native(spread_rules, crosshair_cone, tick_rate)
	if twin == null:
		return null
	var cone := crosshair_cone and spread_rules != null
	entries.append_array([twin, behaviour.state, behaviour, k, idle_rest_skip and idle_still.is_valid() and not cone])
	_held_ticks = 0
	return _idle_nothing()


## The buttons a cooling tick ([method cooling_row_for]) must not hold: each one would make [method simulate_tick] do
## more than count the cadence down (a reload, a switch, a fire-mode change, the aim), or a rig read the aim.
const COOLING_REFUSED := GSWeaponCommand.BUTTON_ALT | GSWeaponCommand.BUTTON_RELOAD | GSWeaponCommand.BUTTON_USE \
		| GSWeaponCommand.BUTTON_NEXT | GSWeaponCommand.BUTTON_PREVIOUS | GSWeaponCommand.BUTTON_LAST \
		| GSWeaponCommand.BUTTON_DROP | GSWeaponCommand.BUTTON_AIM | GSWeaponCommand.BUTTON_FIRE_MODE


## Whether [method simulate_tick] with this command would only tick the weapon in hand with the [member idle_posture]
## context and count a held trigger inside its cadence (API 59): the attack held now and on [param previous] with no other
## arsenal button, no other slot asked for, nothing switching, charging or bursting, [param tick] before the next use, a
## carrier not stopped from firing by a sprint, and a behaviour whose tick reads no more than the posture. Then
## [method cooling_tick_row] (or [method cooling_batch_add]) does the same tick without a context.
func cooling_row_for(command: GSWeaponCommand, previous: GSWeaponCommand, tick: int, sprinting: bool, blocks_fire: bool) -> bool:
	if not _ready_for_use or disabled or _switch_done_tick >= 0 or tick >= _next_use_tick or not idle_posture.is_valid():
		return false
	if (command.buttons & (GSWeaponCommand.BUTTON_ATTACK | COOLING_REFUSED)) != GSWeaponCommand.BUTTON_ATTACK:
		return false
	if (command.slot > 0 and command.slot != _current) or previous == null \
			or not previous.is_pressed(GSWeaponCommand.BUTTON_ATTACK) or (sprinting and blocks_fire):
		return false
	if _charge_started >= 0 or _burst_left > 0:
		return false
	var slot := current()
	if slot == null:
		return false
	var mode := slot.fire_mode()
	if mode == GSWeaponDef.Fire.CHARGE or mode == GSWeaponDef.Fire.BURST:
		return false
	if GSWeaponBehaviour.idle_gate == 0:
		return not slot.behaviour.tick_needs_context()
	return not slot.behaviour.tick_needs_context_posed()


## The tick [method cooling_row_for] promised, with the [member idle_posture] context as a row (what it would say this
## [param tick]): a finished reload, the behaviour's tick (one gs-sim call on a native hitscan), the held count and the
## fire buffer's expiry, as [method simulate_tick] does them. Returns the empty outcome a use inside the cadence does.
func cooling_tick_row(tick: int, row: PackedFloat64Array) -> GSWeaponOutcome:
	_advance_reload(tick)
	var lap := Time.get_ticks_usec() if phase_timers else 0
	var slot := current()
	if slot.behaviour.idle_row_framed(row, false, spread_rules, crosshair_cone, tick_rate) == GSWeaponBehaviour.IDLE_ROW_DECLINED:
		_cooling_posed_tick(slot, tick)
	if lap != 0:
		phase_calls[0] += 1
		_lap(1, lap)
	_cooled(tick)
	return _idle_nothing()


## [method cooling_tick_row] joined to a native batch, as [method idle_batch_add] is for an idle tick (never resting):
## appends [code][twin, state, behaviour, k, false][/code] and does the rest of the tick, or returns null (nothing done)
## when the behaviour has no twin that provably holds, phase timers are on or a reload finishes this tick (its refill
## must come before the behaviour's tick): then call [method cooling_tick_row]. An entry the batch declines must run
## [method cooling_batch_declined].
func cooling_batch_add(entries: Array, k: int, tick: int) -> GSWeaponOutcome:
	if phase_timers or (_reloading and _reload_done_tick >= 0 and tick >= _reload_done_tick):
		return null
	var behaviour := current().behaviour
	var twin := behaviour.idle_native(spread_rules, crosshair_cone, tick_rate)
	if twin == null:
		return null
	entries.append_array([twin, behaviour.state, behaviour, k, false])
	_cooling_tick = tick
	_cooled(tick)
	return _idle_nothing()


## The script step for an entry [method cooling_batch_add] joined and the batch declined (a decline changed nothing):
## the behaviour's tick with the posture context and the held count it would have read.
func cooling_batch_declined() -> void:
	_held_ticks -= 1
	_cooling_posed_tick(current(), _cooling_tick)
	_held_ticks += 1


var _cooling_tick := -1


## The context tick [method simulate_tick] would run, with the posture for the context.
func _cooling_posed_tick(slot: GSWeaponSlot, tick: int) -> void:
	var ctx := idle_posture.call() as GSWeaponContext
	ctx.tick = tick
	ctx.replayed = _replaying
	ctx.authority = authority
	ctx.aiming = false
	_run_behaviour_tick(slot, ctx)


## [method _advance_use]'s writes for a held trigger inside the cadence.
func _cooled(tick: int) -> void:
	_held_ticks += 1
	if _buffer_until >= 0 and tick > _buffer_until:
		_buffer_until = -1


## [method idle_tick]'s empty outcome: one per arsenal, read before the next tick. A new one each idle player each tick
## was an object and three typed arrays; one a caller wrote to is replaced, never handed out again.
func _idle_nothing() -> GSWeaponOutcome:
	var o := _idle_out
	if o == null or o.used or o.kind != GSWeaponOutcome.KIND_NONE or not o.refusal.is_empty() or not o.shots.is_empty() \
			or not o.spawns.is_empty() or not o.events.is_empty() or o.ammo_used != -1 or o.cooldown_ticks != -1 \
			or o.recoil != Vector2.ZERO or o.recoil_recovery != -1.0 or o.recoil_signed:
		o = GSWeaponOutcome.nothing("")
		_idle_out = o
	return o


func _advance_switch(ctx: GSWeaponContext) -> void:
	if _switch_done_tick < 0 or ctx.tick < _switch_done_tick:
		return

	if _holstering:
		var from := current()
		if from != null:
			from.behaviour.holster(ctx)

		var previous_slot := _current
		_previous = _current
		_current = _switch_to
		_holstering = false

		var to := current()
		_switch_done_tick = ctx.tick + (ticks_for(to.def, to.def.deploy_ticks) if to != null else 0)
		switched.emit(previous_slot, _current)
		return

	# The deploy finished.
	_switch_done_tick = -1
	var deployed := current()
	if deployed != null:
		deployed.behaviour.deploy(ctx)
		_next_use_tick = maxi(_next_use_tick, ctx.tick)


func _apply_slot_request(command: GSWeaponCommand, tick: int) -> void:
	if command.slot > 0:
		select(command.slot, tick)
	elif command.is_pressed(GSWeaponCommand.BUTTON_NEXT):
		select_next(tick)
	elif command.is_pressed(GSWeaponCommand.BUTTON_PREVIOUS):
		select_previous(tick)
	elif command.is_pressed(GSWeaponCommand.BUTTON_LAST):
		select_last(tick)


func _run_behaviour_tick(slot: GSWeaponSlot, ctx: GSWeaponContext) -> void:
	ctx.charge = _charge_value(slot, ctx.tick)
	ctx.held_ticks = _held_ticks
	if GSWeaponBehaviour.idle_gate != 0:
		slot.behaviour.tick_framed(ctx, spread_rules, crosshair_cone, tick_rate)
	else:
		slot.behaviour.tick(ctx)


func _charge_value(slot: GSWeaponSlot, tick: int) -> float:
	if _charge_started < 0 or not slot.def.is_charged():
		return 1.0
	return charge_for(slot.def, tick - _charge_started)


func _advance_use(
	slot: GSWeaponSlot,
	command: GSWeaponCommand,
	ctx: GSWeaponContext,
	previous: GSWeaponCommand
) -> GSWeaponOutcome:
	var def := slot.def
	var down := command.is_pressed(GSWeaponCommand.BUTTON_ATTACK)
	if ctx.sprinting and ctx.sprint_blocks_fire:
		down = false
	var was_down := previous != null and previous.is_pressed(
		GSWeaponCommand.BUTTON_ATTACK
	)

	if down:
		_held_ticks += 1
	else:
		_held_ticks = 0

	if _buffer_until >= 0 and ctx.tick > _buffer_until:
		_buffer_until = -1

	match slot.fire_mode():
		GSWeaponDef.Fire.CHARGE:
			return _advance_charge(slot, ctx, down, was_down)
		GSWeaponDef.Fire.BURST:
			return _advance_burst(slot, ctx, down, was_down)
		GSWeaponDef.Fire.AUTO, GSWeaponDef.Fire.HOLD:
			if down:
				return _try_use(slot, ctx)
			if was_down:
				return slot.behaviour.release(ctx)
			return _idle_nothing()
		_:
			if down and not was_down:
				if ctx.tick < _next_use_tick and _arm_buffer(def, ctx.tick):
					return _idle_nothing()
				_buffer_until = -1
				return _try_use(slot, ctx)
			if _buffer_until >= ctx.tick and ctx.tick >= _next_use_tick:
				_buffer_until = -1
				return _try_use(slot, ctx)
			if was_down and not down:
				return slot.behaviour.release(ctx)
			return _idle_nothing()


## Remembers a press made inside the cooldown so it fires when the cooldown ends, if that is inside the window.
func _arm_buffer(def: GSWeaponDef, tick: int) -> bool:
	var seconds := def.fire_buffer_seconds if def.fire_buffer_seconds > -2.0 else fire_buffer_seconds
	if seconds == 0.0:
		return false
	_buffer_until = 0x7fffffff if seconds < 0.0 else tick + ceili(seconds * tick_rate)
	return true


func _advance_charge(
	slot: GSWeaponSlot, ctx: GSWeaponContext, down: bool, was_down: bool
) -> GSWeaponOutcome:
	var def := slot.def

	if down and not was_down:
		# Refused up front, not at release: a draw that then does nothing reads as a broken bow.
		if not _can_pay(slot):
			dry_used.emit(_current)
			return GSWeaponOutcome.nothing("Nothing to spend.")
		_charge_started = ctx.tick
		_charge_announced = false
		return _idle_nothing()

	if down:
		if (
			not _charge_announced
			and _charge_started >= 0
			and ctx.tick - _charge_started >= ticks_for(def, def.charge_ticks)
		):
			_charge_announced = true
			charge_full.emit(_current)
		return _idle_nothing()

	if not was_down or _charge_started < 0:
		return _idle_nothing()

	# Released.
	var charge := charge_for(def, ctx.tick - _charge_started)
	_charge_started = -1
	_charge_announced = false

	if def.charge_requires_min and charge < def.min_charge:
		return GSWeaponOutcome.nothing("Not drawn far enough.")

	ctx.charge = charge
	return _try_use(slot, ctx)


func _advance_burst(
	slot: GSWeaponSlot, ctx: GSWeaponContext, down: bool, was_down: bool
) -> GSWeaponOutcome:
	if down and not was_down and _burst_left <= 0:
		_burst_left = slot.def.burst_count

	if _burst_left <= 0:
		return _idle_nothing()

	var out := _try_use(slot, ctx)
	if out.used:
		_burst_left -= 1
		# The gap within a burst is its own; one interval for both makes a burst look automatic.
		if _burst_left > 0:
			_next_use_tick = ctx.tick + maxi(1, ticks_for(slot.def, slot.def.burst_interval_ticks))
	elif out.refusal != "":
		_burst_left = 0

	return out


## Whether the weapon can pay for one use right now.
func _can_pay(slot: GSWeaponSlot) -> bool:
	var def := slot.def

	if not def.uses_ammo():
		return true

	if def.uses_magazine():
		return slot.magazine >= def.cost_per_use

	return def.infinite_reserve or _ammo.has(def.ammo_type, def.cost_per_use)


func _try_use(slot: GSWeaponSlot, ctx: GSWeaponContext) -> GSWeaponOutcome:
	var def := slot.def

	if ctx.tick < _next_use_tick:
		return _idle_nothing()

	if not _can_pay(slot):
		dry_used.emit(_current)
		if def.auto_reload and def.uses_magazine():
			if not (ctx.sprinting and ctx.sprint_blocks_aim):
				begin_reload(ctx.tick)
		elif auto_switch_on_empty:
			_switch_off_empty(ctx.tick)
		return GSWeaponOutcome.nothing("Nothing to spend.")

	# Whether the weapon can pay is asked BEFORE the reload is cancelled: the other way round,
	# a held trigger on an empty weapon cancels its own reload every cadence and it never refills.
	if _reloading:
		cancel_reload()

	var allowed := slot.behaviour.can_use(ctx)
	if not allowed.ok:
		return GSWeaponOutcome.nothing(allowed.error.message)

	ctx.index = _use_index
	_use_index += 1

	var out := slot.behaviour.use(ctx)

	if not out.used:
		return out

	_spend(slot, out)

	# An outcome's own cooldown is counted in the definition's ticks, like the interval it
	# stands in for, so the behaviour that set it never needs to know the running rate.
	var cadence := out.cooldown_ticks if out.cooldown_ticks >= 0 else def.use_interval_ticks
	_next_use_tick = ctx.tick + maxi(1, ticks_for(def, cadence))

	used.emit(out)
	return out


func _spend(slot: GSWeaponSlot, out: GSWeaponOutcome) -> void:
	var def := slot.def

	if not def.uses_ammo():
		return

	var cost := out.ammo_used if out.ammo_used >= 0 else def.cost_per_use
	if cost <= 0:
		return

	if def.uses_magazine():
		slot.magazine = maxi(0, slot.magazine - cost)
	elif not def.infinite_reserve:
		_ammo.take(def.ammo_type, cost)
		ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))


func _switch_off_empty(tick: int) -> void:
	for s in slots():
		if s == _current:
			continue
		var other: GSWeaponSlot = _slots[s]
		if _can_pay(other):
			select(s, tick)
			return


## Everything that has to travel and everything a rollback has to restore, behaviours' own state included.
func snapshot() -> Dictionary:
	return _Io.snapshot(self)


## Restores a snapshot, rebuilding any weapon this carrier is not currently holding.
func restore(d: Dictionary) -> GSResult:
	_bump_revision()
	return _Io.restore(self, d)


func describe() -> Dictionary:
	return _Io.describe(self)


func describe_lines() -> PackedStringArray:
	return _Io.describe_lines(self)
