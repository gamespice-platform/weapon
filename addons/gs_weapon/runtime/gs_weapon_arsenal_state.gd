@tool
extends Node

## State, signals and read-only queries for [GSWeaponArsenal]; kept apart so the state machine stays small.

## A use produced an outcome. Carries the whole outcome so a listener can tell a swing
## from a shot without inspecting it.
signal used(outcome: GSWeaponOutcome)

## A use was attempted with nothing to spend.
signal dry_used(slot: int)

signal reload_started(slot: int)
signal reload_finished(slot: int, rounds: int)

## A charged weapon reached full draw. For a sound and a HUD tick, nothing else.
signal charge_full(slot: int)

signal switched(from: int, to: int)

## The held gun's fire mode changed; [param mode] is a [enum GSWeaponDef.Fire].
signal fire_mode_changed(slot: int, mode: int)
signal ammo_changed(pool: StringName, amount: int)
signal carried_changed()

const _Io := preload("gs_weapon_arsenal_io.gd")

@export_group("Simulation")

## Ticks per second the simulation runs at. A definition with an [member GSWeaponDef.authored_tick_rate] is scaled to
## this through [method ticks_for]; one with none is used as written. Set it identically on client and server:
## deadlines are absolute ticks and travel in [method snapshot] as ticks, so two rates predict different reload ends.
@export_range(1, 240, 1) var tick_rate: int = 64

## Seconds a semi-auto press made during the cooldown stays queued (`sv_fire_buffer`). 0 drops it, negative keeps it
## until the cooldown ends. A weapon's own [member GSWeaponDef.fire_buffer_seconds] overrides this.
@export var fire_buffer_seconds: float = 0.15

@export_range(1, 16, 1, "or_greater") var max_slots: int = 8

@export_group("Content")

## Every weapon this carrier could hold. Required before [method setup].
@export var catalogue: GSWeaponCatalogue = null

## The attachment catalogue. Null means nothing can be fitted. Plain var: it is a RefCounted.
## Must be the same on every machine (see [GSWeaponAttachments]).
var attachments: GSWeaponAttachments = null

## Weight and slot-capacity rules, shared by every arsenal of a game. Null: no limit, one weapon per slot.
var carry: GSWeaponCarry = null

## Backpack tier this carrier wears (0: none); see [method GSWeaponCarry.limit_for].
var backpack_tier: int = 0

## Movement-dependent spread (`sv_spread_*`); null or disabled leaves every gun's own spread.
var spread_rules: GSWeaponSpreadRules = null

## Whether an idle carrier's crosshair cone is kept current (spread rules attached). A machine nobody
## watches, such as a server's stand-in, sets it false so its untouched weapon ticks with no context.
var crosshair_cone: bool = true

## Returns a [GSWeaponContext] holding only the carrier's posture (speed, airborne, crouched,
## sliding, sprinting, and tick and hurt_tick if the flinch should count). Set, an idle tick
## with spread rules feeds that to the behaviour instead of a full context, far cheaper.
var idle_posture: Callable = Callable():
	set(value):
		idle_posture = value
		_derive_idle_still()

## Whether the carrier's posture is the settled one (speed 0, grounded, not crouched, sliding, wall running, sprinting or
## hurt), asked of an idle weapon at rest so its tick is skipped without [member idle_posture]. Must agree with it.
## A [method GSWeaponPlayerBridge.posture_for] bound to a player in [member idle_posture] sets [method GSWeaponPlayerBridge.still_for].
var idle_still: Callable = Callable()

## False runs every idle tick through [member idle_posture] as before; the result is identical, it only costs more.
var idle_rest_skip: bool = true

var _still_derived: bool = false


func _derive_idle_still() -> void:
	if idle_still.is_valid() and not _still_derived:
		return
	_still_derived = false
	idle_still = Callable()
	if not idle_posture.is_valid() or idle_posture.get_method() != &"posture_for":
		return
	# By path, not by name: the bridge names the arsenal, and a script loop stays in memory for good (Godot 4.7).
	var bridge: Script = load("res://addons/gs_weapon/bridge/gs_weapon_player.gd")
	if idle_posture.get_object() == bridge:
		var bound := idle_posture.get_bound_arguments()
		if bound.size() == 1 and bound[0] is Node:
			idle_still = Callable(bridge, &"still_for").bind(bound[0])
			_still_derived = true

## Per-weapon recoil patterns (`sv_recoil_*`); null or disabled leaves every gun's flat kick.
var recoil_rules: GSWeaponRecoilRules = null

## Global ballistics switch (`sv_ballistics`); null or off keeps every gun hitscan. Set on both sides.
var ballistics_rules: GSWeaponBallisticsRules = null

## Loaded round per weapon id (see [GSWeaponAmmoTypes]); server side only, not in snapshots.
var loaded_ammo: Dictionary = {}

## The game's ammo profiles; [method GSWeaponArsenal.round_for] reads them. Null: no ammo types.
var ammo_types: GSWeaponAmmoTypes = null

@export_group("Rules")

## Switches away from a weapon that has run out entirely.
@export var auto_switch_on_empty: bool = true

## Refuses everything. For a dead player, a cutscene, a freeze time.
@export var disabled: bool = false

## True on the machine that decides; handed to every [GSWeaponContext]. A behaviour applies nothing when false
## and GameSpice Combat resolves no damage; a client still runs everything, for prediction.
@export var authority: bool = false

var _slots: Dictionary = {}          ## int -> GSWeaponSlot (the one in hand of that slot)
var _shelf: Dictionary = {}          ## int -> Array[GSWeaponSlot], stowed behind the active one
var _ammo := GSWeaponAmmo.new()
## The change counter behind [method revision]: one int in an Array the slots and the reserve share by reference.
var _revision_box: Array = [0]
var _current: int = 0
var _previous: int = 0

## Last tick a press made during the cooldown still fires on. -1: none pending.
var _buffer_until: int = -1

## Tick the current weapon may next be used on.
var _next_use_tick: int = 0

## Switching: the slot being switched to, and the tick the switch completes on.
var _switch_to: int = 0
var _switch_done_tick: int = -1
var _holstering: bool = false

## Reloading: the tick the reload (or the next round of it) completes on.
var _reload_done_tick: int = -1
var _reloading: bool = false

## Burst: uses left in the burst, and the tick the next one is due.
var _burst_left: int = 0

## Charge: the tick the use button went down on. -1 when it is not down.
var _charge_started: int = -1
var _charge_announced: bool = false

## Ticks the use button has been held, for a HOLD weapon.
var _held_ticks: int = 0

## Uses so far, so two uses on one tick scatter differently.
var _use_index: int = 0

## Set while re-running inputs after a correction.
var _replaying: bool = false

var _ready_for_use: bool = false


## [param authored_ticks] off [param def] as a count at [member tick_rate]. Public so a layer over the arsenal
## times its own half by the same numbers instead of reading the raw field and drifting at another rate.
func ticks_for(def: GSWeaponDef, authored_ticks: int) -> int:
	if def == null:
		return authored_ticks
	return def.ticks_at(authored_ticks, tick_rate)


## [param def]'s charge after [param ticks_held] ticks at [member tick_rate].
func charge_for(def: GSWeaponDef, ticks_held: int) -> float:
	if def == null:
		return 1.0
	return def.charge_at(ticks_held, tick_rate)


func carries(id: StringName) -> bool:
	for slot: GSWeaponSlot in _slots.values():
		if slot.id() == id:
			return true
	return _shelf_has(0, id)


func has_slot(slot: int) -> bool:
	return _slots.has(slot)


func slot_at(slot: int) -> GSWeaponSlot:
	return _slots.get(slot, null)


func current_slot() -> int:
	return _current


func current() -> GSWeaponSlot:
	return _slots.get(_current, null)


func current_def() -> GSWeaponDef:
	var slot := current()
	return slot.def if slot != null else null


func slots() -> Array[int]:
	var out: Array[int] = []
	for key: int in _slots.keys():
		out.append(key)
	out.sort()
	return out


func ammo() -> GSWeaponAmmo:
	return _ammo


func _init() -> void:
	_ammo.revision_box = _revision_box
	carried_changed.connect(_bump_revision)


## API 51. A number that moves whenever what this carrier holds may have changed (a weapon given, taken, dropped, cycled
## or refitted, a magazine or reserve count or cap, a restore), so a reader (a bot's loadout, a HUD) rebuilds only on a
## change. It does not follow the selected slot, cooldowns or reload timers.
func revision() -> int:
	return int(_revision_box[0])


func _bump_revision() -> void:
	_revision_box[0] += 1


## Weapons one slot may hold.
func slot_capacity() -> int:
	return carry.slot_capacity if carry != null else 1


## Every weapon in [param slot], the one in hand first.
func weapons_in(slot: int) -> Array[GSWeaponSlot]:
	var out: Array[GSWeaponSlot] = []
	if _slots.has(slot):
		out.append(_slots[slot])
		out.append_array(_shelf_of(slot))
	return out


## Total weight carried now.
func carried_weight() -> float:
	if carry == null:
		return 0.0
	var total := 0.0
	for s: int in _slots:
		for w in weapons_in(s):
			total += carry.weight_of(w.def)
	return total


## The most this carrier may carry now; INF with no carry rules.
func capacity() -> float:
	return carry.limit_for(backpack_tier) if carry != null else INF


## Weight over [method capacity], 0 when under.
func over_by() -> float:
	return maxf(carried_weight() - capacity(), 0.0)


## Speed multiplier for the weight carried (1 unless the carry rule is SLOW and this is over).
func speed_scale() -> float:
	return carry.speed_scale(carried_weight(), capacity()) if carry != null else 1.0


## Wears a backpack of [param tier] if it is bigger than the one worn. False when it is not an upgrade.
func equip_backpack(tier: int) -> bool:
	if carry == null or tier <= backpack_tier or tier > carry.max_backpack_tier():
		return false
	backpack_tier = tier
	carried_changed.emit()
	return true


func _shelf_of(slot: int) -> Array:
	if not _shelf.has(slot):
		_shelf[slot] = []
	return _shelf[slot]


func _shelf_has(slot: int, id: StringName) -> bool:
	for s: int in _shelf:
		if slot != 0 and s != slot:
			continue
		for w: GSWeaponSlot in _shelf[s]:
			if w.id() == id:
				return true
	return false


func _shelf_drop(slot: int, id: StringName) -> void:
	var behind := _shelf_of(slot)
	for i in behind.size():
		if (behind[i] as GSWeaponSlot).id() == id:
			behind.remove_at(i)
			return
