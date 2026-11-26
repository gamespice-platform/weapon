class_name GSWeaponBehaviour
extends RefCounted

## The base every weapon extends. Guns, bows, melee, thrown, beams, and whatever a game
## writes that none of those describe.
##
## [b]Nothing in this addon should ever require a fork.[/b] A game adds a weapon by
## writing a script that extends this, pointing a [GSWeaponDef] at its path, and adding
## the row to a catalogue. It does not subclass the arsenal, it does not edit an enum
## here, and it does not need this addon to have anticipated it.
##
## [codeblock]
## extends "res://addons/gs_weapon/behaviour/gs_weapon_behaviour.gd"
##
## func _use(ctx: GSWeaponContext) -> GSWeaponOutcome:
##     var out := GSWeaponOutcome.of(GSWeaponOutcome.KIND_SPAWN)
##     var arrow := GSWeaponSpawn.make(&"arrow", ctx.origin, ctx.direction * lerpf(
##         20.0, def.param_float(&"max_speed", 90.0), ctx.charge
##     ), ctx.entity)
##     arrow.damage = lerpf(12.0, 60.0, ctx.charge)
##     arrow.gravity_scale = 1.0
##     out.add_spawn(arrow)
##     return out
## [/codeblock]
##
## [b]Four rules, and they are the ones that break quietly rather than loudly.[/b]
##
## [b]1. Be a pure function of the context.[/b] A predicted weapon is simulated at least
## twice — once on the firing client, once on the server — and once more for every
## reconciliation replay after a correction. A behaviour that reads a wall clock, a
## node, an input device or a random stream produces a different answer on each of those
## runs, nothing errors, and the symptom is "hit registration feels bad". Use
## [member GSShot.spread], which GameSpice Combat's [method GSShot.scatter] turns into directions, for anything that needs to scatter.
##
## [b]2. Apply nothing.[/b] Return a [GSWeaponOutcome]; let GameSpice Combat resolve the
## shots and let the game spawn the spawns. A behaviour that reached into a [GSHealth]
## would be a client deciding who dies.
##
## [b]3. Keep state in [member state], not in a member.[/b] The arsenal serialises
## [member state] across the wire and rolls it back on a correction. A field written
## directly on the behaviour survives neither.
##
## [b]4. Check [member GSWeaponContext.replayed] before anything visible.[/b] The
## simulation must re-run; a sound, an effect and a statistic must not.

## The row this behaviour was built for. Never null after [method setup].
var def: GSWeaponDef = null

## The arsenal carrying it, for a behaviour that needs to ask about ammunition or the
## other weapons. Null in a unit test that drives the behaviour directly.
var arsenal: Object = null

## Per-weapon state that survives a holster and travels on the wire.
##
## [b]Put every mutable thing here.[/b] The arsenal copies this dictionary into its
## snapshot, sends it, and restores it on a correction, which is what makes a bow's
## draw and a beam's heat survive the same reconciliation a magazine count does. A
## behaviour that keeps its charge in a plain member loses it on the first correction
## and nothing reports that it did.
var state: Dictionary = {}


# --- Called by the arsenal --------------------------------------------------

## Binds the behaviour to its row. Called once, before any other method.
func setup(p_def: GSWeaponDef, p_arsenal: Object = null) -> void:
	def = p_def
	arsenal = p_arsenal
	_setup()


## Returns this behaviour to what its script's [code]new()[/code] makes, unbound, so [method setup] can bind it
## again; false when its script cannot vouch for that and a new one must be built. API 56: with
## [member GSWeaponArsenal.reuse_behaviours] a respawn's re-give reuses a renewed behaviour instead of building one.
func renew() -> bool:
	if not _renew():
		return false
	def = null
	arsenal = null
	state = {}
	_needs_context = -1
	return true


## Resets every member the script itself declares and returns true. The default vouches only for the stock scripts
## that declare none; any other script (a subclass with members of its own) is rebuilt unless it overrides this.
func _renew() -> bool:
	var script := get_script() as Script
	return script != null and _MEMBERLESS.has(script.resource_path)


const _MEMBERLESS: PackedStringArray = [
	"res://addons/gs_weapon/behaviour/gs_weapon_beam.gd",
	"res://addons/gs_weapon/behaviour/gs_weapon_melee.gd",
	"res://addons/gs_weapon/behaviour/gs_weapon_projectile.gd",
	"res://addons/gs_weapon/behaviour/gs_weapon_thrown.gd",
]


## Brought up and now usable.
func deploy(ctx: GSWeaponContext) -> void:
	_deploy(ctx)


## Put away; anything held is let go of here. [b]Always called before a switch completes[/b],
## including one caused by death, a correction or a loadout change, so a behaviour holding
## something has exactly one place to release it.
func holster(ctx: GSWeaponContext) -> void:
	_holster(ctx)


## Whether a use may happen at all, beyond the ammunition and cadence the arsenal has
## already checked.
##
## A bow below its minimum draw, a repair tool aimed at nothing, a deployable with none
## left. Returning a failure means the arsenal charges nothing and starts no cooldown.
func can_use(ctx: GSWeaponContext) -> GSResult:
	return _can_use(ctx)


## The use itself.
func use(ctx: GSWeaponContext) -> GSWeaponOutcome:
	var out := _use(ctx)
	return out if out != null else GSWeaponOutcome.nothing("The behaviour returned null.")


## One simulation tick while this weapon is deployed, used or not: where a charge builds, a beam
## heats, a cooldown that is not the arsenal's own runs down, and a held object is dragged along.
func tick(ctx: GSWeaponContext) -> void:
	_tick(ctx)


## Whether [method _tick] may read its context. False for a behaviour whose `_tick` is the empty
## one or [GSWeaponHitscan]'s (bloom recovery, no context), so an idle arsenal ticks it with none.
func tick_needs_context() -> bool:
	if _needs_context < 0:
		_needs_context = 0
		var script := get_script() as Script

		while script != null:
			var file := script.resource_path.get_file()

			if file != "gs_weapon_behaviour.gd" and file != "gs_weapon_hitscan.gd":
				for method in script.get_script_method_list():
					if method["name"] == "_tick":
						_needs_context = 1

			script = script.get_base_script()

	return _needs_context == 1


## Takes an idle tick without a posture when the weapon is at rest and [param still] says the carrier is; true if taken.
## The base has state a tick may change, so it says false. See [member GSWeaponArsenal.idle_still].
func rest_tick(_still: Callable) -> bool:
	return false


## What [method idle_row] did: declined (nothing changed), ticked with the row's posture, or took the rest tick.
const IDLE_ROW_DECLINED := 0
const IDLE_ROW_TICKED := 1
const IDLE_ROW_RESTED := 2


## The whole idle tick from a posture row ([code][speed, airborne, crouched, aiming, sliding, sprinting, wall_running,
## tick, hurt_tick][/code], the [member GSWeaponArsenal.idle_posture] context's fields) in one native call: the rest tick
## when [param rest] (the carrier is settled and the arsenal skips rest ticks) and the weapon is at rest, else the tick
## with that posture. [constant IDLE_ROW_TICKED] or [constant IDLE_ROW_RESTED] if taken; [constant IDLE_ROW_DECLINED]
## changes nothing, and the arsenal runs [method GSWeaponArsenal.idle_tick]. The base has no native tick, so it declines.
func idle_row(_row: PackedFloat64Array, _rest: bool) -> int:
	return IDLE_ROW_DECLINED


## How an idle arsenal ticks: 1 (default) hands the behaviour its rules, crosshair and rate ([method idle_row_framed],
## [method tick_needs_context_posed]) so cached rows that provably hold are reused; 0 takes the plain calls (same bits,
## an A/B switch); 2 does both and counts each disagreement in [member idle_gate_misses] with an error.
static var idle_gate: int = 1
## Disagreements [member idle_gate] 2 found since start: 0 unless a cached row went stale unseen.
static var idle_gate_misses: int = 0


## [method idle_row] handed what the arsenal already holds: its [param rules] ([member GSWeaponArsenal.spread_rules]),
## [param crosshair] ([member GSWeaponArsenal.crosshair_cone]) and [param rate] ([member GSWeaponArsenal.tick_rate]).
## Must do exactly what [method idle_row] does; the base has nothing to save, so it is [method idle_row].
func idle_row_framed(row: PackedFloat64Array, rest: bool, _rules: GSWeaponSpreadRules, _crosshair: bool, _rate: int) -> int:
	return idle_row(row, rest)


## [method tick] with a context, handed what the arsenal already holds (as [method idle_row_framed] is): its
## [param rules], [param crosshair] and [param rate]. The arsenal calls it while [member idle_gate] is not 0. Must do
## exactly what [method tick] does; the base has nothing to save, so it is [method tick].
func tick_framed(ctx: GSWeaponContext, _rules: GSWeaponSpreadRules, _crosshair: bool, _rate: int) -> void:
	tick(ctx)


## The native twin an idle tick may join a batch with (API 57): gs-sim's [code]GSSimWeaponIdleBatch[/code] runs, for
## each joined weapon, exactly the call [method idle_row_framed] would make now, then hands the answer to
## [method idle_native_took]. Non-null only when that call is provably what [method idle_row_framed] would do this tick
## (the stock hitscan with its gate holding); null keeps the plain path. The base has no twin.
func idle_native(_rules: GSWeaponSpreadRules, _crosshair: bool, _rate: int) -> Object:
	return null


## What a batched native idle call answered for this weapon (never -1, a decline, which changes nothing): applied as
## [method idle_row_framed] would apply it. The base never joins a batch.
func idle_native_took(_shown: float) -> void:
	pass


## [method tick_needs_context] when the arsenal has an [member GSWeaponArsenal.idle_posture]; must answer the same.
## The base reads no posture, so it is [method tick_needs_context].
func tick_needs_context_posed() -> bool:
	return tick_needs_context()


## The spread cone half-angle this weapon would fire with at its last tick, in degrees, for a crosshair.
func spread_now() -> float:
	return 0.0


## The use button was released.
##
## Called for every fire mode, not only [constant GSWeaponDef.Fire.CHARGE], because a
## beam that has to stop and a thrown charge that has to leave the hand are the same
## event.
func release(ctx: GSWeaponContext) -> GSWeaponOutcome:
	var out := _release(ctx)
	return out if out != null else GSWeaponOutcome.nothing("")


## A reload finished. A behaviour that tracks its own loaded state syncs it here.
func reloaded(rounds: int) -> void:
	_reloaded(rounds)


# --- Subclass interface -----------------------------------------------------
#
# Override these. Every one has a default that does nothing, so a behaviour that only
# shoots overrides exactly one.

func _setup() -> void:
	pass


func _deploy(_ctx: GSWeaponContext) -> void:
	pass


func _holster(_ctx: GSWeaponContext) -> void:
	pass


func _can_use(_ctx: GSWeaponContext) -> GSResult:
	return GSResult.success(null)


func _use(_ctx: GSWeaponContext) -> GSWeaponOutcome:
	return GSWeaponOutcome.nothing("This weapon does nothing when used.")


var _needs_context: int = -1


func _tick(_ctx: GSWeaponContext) -> void:
	pass


func _release(_ctx: GSWeaponContext) -> GSWeaponOutcome:
	return GSWeaponOutcome.nothing("")


func _reloaded(_rounds: int) -> void:
	pass


# --- Helpers for subclasses -------------------------------------------------

## The tick rate the arsenal runs at, or zero when there is no arsenal to ask (a unit test
## driving the behaviour directly), which leaves every count as written. Duck-typed:
## [member arsenal] is an [Object] so a test can hand in anything.
func running_tick_rate() -> int:
	if arsenal == null:
		return 0
	var v: Variant = arsenal.get(&"tick_rate")
	return int(v) if v is int else 0


## [param authored_ticks], a count from this weapon's tuning, as a count at the running
## tick rate. See [member GSWeaponDef.authored_tick_rate].
##
## [b]For a count that leaves this behaviour[/b]: a spawn's fuse and life, which the game
## flies at its own rate, and anything compared with [member GSWeaponContext.held_ticks],
## which the arsenal counts at its own. A cooldown handed back in
## [member GSWeaponOutcome.cooldown_ticks] is NOT scaled here; the arsenal does that.
func scaled_ticks(authored_ticks: int) -> int:
	if def == null:
		return authored_ticks
	return def.ticks_at(authored_ticks, running_tick_rate())


## [param amount], applied once per tick at the authored rate, per tick at the running one.
## A bloom recovery of 0.15 degrees a tick at 64 Hz is 0.075 a tick at 128.
func scaled_per_tick(amount: float) -> float:
	if def == null:
		return amount
	return def.per_tick_at(amount, running_tick_rate())


## Reads a tuning field from [member GSWeaponDef.tuning] if it has one, then from
## [member GSWeaponDef.params], then the fallback. The typed resource comes first because
## it is the more specific of the two; see [GSWeaponTuning].
func tune(key: StringName, fallback: Variant = null) -> Variant:
	if def == null:
		return fallback

	if def.tuning != null:
		var name := String(key)
		if name in def.tuning:
			var v: Variant = def.tuning.get(name)
			if v != null:
				return v

	return def.params.get(key, fallback)


func tune_float(key: StringName, fallback: float = 0.0) -> float:
	var v: Variant = tune(key, fallback)
	return float(v) if v is float or v is int else fallback


func tune_int(key: StringName, fallback: int = 0) -> int:
	var v: Variant = tune(key, fallback)
	return int(v) if v is float or v is int else fallback


func tune_bool(key: StringName, fallback: bool = false) -> bool:
	var v: Variant = tune(key, fallback)
	return bool(v) if v is bool else fallback


## What a console command or a bug report dumps for this weapon.
##
## Override it to add the behaviour's own state; call the base and merge.
func describe() -> Dictionary:
	return {
		"weapon": String(def.id) if def != null else "",
		"behaviour": get_script().resource_path if get_script() != null else "",
		"state": state.duplicate(),
	}


func _to_string() -> String:
	return "GSWeaponBehaviour(%s)" % (String(def.id) if def != null else "unbound")
