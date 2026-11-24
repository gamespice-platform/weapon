extends RefCounted

## The scope-view rules a view model shares with every other: lens or full screen, the camera's
## field of view, the walking clear. Preloaded by path, no `class_name`. A view model keeps its
## `scope_mode`, `scope_walk_clear` and `scope_walk_speed` fields (a game sets them) and calls these.

## The scope as a lens on a normal screen, and the scope filling it.
const LENS := 1
const FULL := 2


## The view the player [param wanted] (clamped to LENS or FULL), or [param forced] when the server's rule pins one (above 0).
static func resolve(wanted: int, forced: int = 0) -> int:
	return forced if forced > 0 else clampi(wanted, LENS, FULL)


## Whether the scope is a lens: the camera stays at the hip's field of view and the overlay's own camera zooms.
static func is_lens(mode: int, has_scope: bool) -> bool:
	return mode == LENS and has_scope


## The multiplier the main camera takes: 1 with the scope as a lens, else [param aim_scale].
static func fov_scale(lens: bool, aim_scale: float) -> float:
	return 1.0 if lens else aim_scale


## How much of the scope's picture is clear because the player moves: 0 standing, [param walk_clear] at [param walk_speed] m/s.
static func clear(has_scope: bool, walk_clear: float, walk_speed: float, speed: float) -> float:
	if not has_scope or walk_speed <= 0.0:
		return 0.0
	return walk_clear * smoothstep(0.3, walk_speed, speed)


## The hip field of view zoom levels in degrees are measured against (Counter-Strike's 90).
const HIP_FOV := 90.0


## The camera multipliers for a scope's zoom levels given in field-of-view [param degrees] (widest first, e.g. 40 then 10),
## against [param hip_fov]. Entries at or below 0 are dropped.
static func level_scales(degrees: Array, hip_fov: float = HIP_FOV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in degrees:
		if float(d) > 0.0:
			out.append(clampf(float(d) / maxf(hip_fov, 1.0), 0.01, 1.0))
	return out


## The level after [param level] among [param count] levels: the next one, wrapping to the first. A scope with no levels stays at 0.
static func next_level(level: int, count: int) -> int:
	return 0 if count <= 1 else (level + 1) % count


## The multiplier at [param level] (clamped into [param scales]), or [param fallback] with no levels.
static func scale_at(scales: PackedFloat32Array, level: int, fallback: float) -> float:
	if scales.is_empty():
		return fallback
	return scales[clampi(level, 0, scales.size() - 1)]
