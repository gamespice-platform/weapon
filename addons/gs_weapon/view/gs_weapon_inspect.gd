extends RefCounted

## The look-over a first-person weapon plays when the player inspects it: a progress that runs over
## `seconds`, and a weight that fades it out when something else (a shot, an aim, a reload, a sprint, a
## switch) takes the hand. A pose keeps one, asks `start` and `advance` each frame, and samples its own
## keys at `fraction` scaled by `shown`. Preloaded by path, no `class_name`. Pure arithmetic, no clock.

## Lifted and turned so the left side and the top come to the eye (0.16-0.42), across to show the right
## side (0.56-0.86), back into the hand. Never toward the eye, so a long gun's stock keeps its distance
## from the near plane. Rows are [time, position metres, rotation degrees].
const KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.16, Vector3(-0.03, 0.03, -0.02), Vector3(6.0, 14.0, -30.0)],
	[0.42, Vector3(-0.04, 0.036, -0.03), Vector3(8.0, 18.0, -44.0)],
	[0.56, Vector3(-0.015, 0.02, -0.03), Vector3(3.0, 4.0, -8.0)],
	[0.72, Vector3(0.015, 0.012, -0.02), Vector3(-3.0, -9.0, 28.0)],
	[0.86, Vector3(0.016, 0.006, -0.012), Vector3(-2.0, -8.0, 25.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## How long a look-over takes, in seconds.
var seconds: float = 2.6

## Seconds a cancelled look-over takes to ease back into the hand, so a shot or an aim never snaps it.
var cancel_seconds: float = 0.2

var _fraction: float = 1.0
var _weight: float = 0.0


## Starts a look-over when [param at_rest]. False (and nothing changes) when the weapon is not resting in
## the hand, or one is still playing or easing out: starting again from 0 there would jump.
func start(at_rest: bool) -> bool:
	if not at_rest or _fraction < 1.0:
		return false
	_fraction = 0.0
	_weight = 1.0
	return true


## Eases a playing look-over back into the hand; it holds the place it was cancelled at and fades.
func cancel() -> void:
	if _fraction < 1.0:
		_weight = minf(_weight, 0.999)


## Drops it at once, for a respawn or a teleport.
func reset() -> void:
	_fraction = 1.0
	_weight = 0.0


## Moves [param step] seconds on; [param at_rest] false while the hand is busy cancels a playing one.
func advance(step: float, at_rest: bool) -> void:
	if _fraction >= 1.0:
		return
	if _weight >= 1.0 and not at_rest:
		cancel()
	if _weight >= 1.0:
		_fraction = minf(1.0, _fraction + step / maxf(0.1, seconds))
	else:
		_weight = maxf(0.0, _weight - step / maxf(0.01, cancel_seconds))
		if _weight <= 0.0:
			_fraction = 1.0
	if _fraction >= 1.0:
		_weight = 0.0


## Whether one is playing (not cancelled and not finished).
func playing() -> bool:
	return _fraction < 1.0 and _weight >= 1.0


## How far through it, 0 to 1; 1 when none is playing or easing out.
func fraction() -> float:
	return _fraction


## How much of the keyed pose is shown, 0 to 1, smoothed: 1 while it plays, easing to 0 after a cancel.
func shown() -> float:
	var w := clampf(_weight, 0.0, 1.0)
	return w * w * (3.0 - 2.0 * w)
