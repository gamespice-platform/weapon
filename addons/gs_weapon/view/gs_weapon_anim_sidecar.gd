extends RefCounted

## The one writer of Nightly's animation sidecar (`<asset>.anim.json`, version 1) that weapon packs and games share; API 57, preloaded by path (no `class_name`).
## A pack drives its own view model and hands this class what it read back: frame by frame through [method put] and [method frame_done], then [method finish] for a clip, [method sidecar] for the file.
## The format is pinned in docs/anim-sidecar.md. In short, `weapon`, `hand.*` and `prop.*` tracks are in view (camera) space, `magazine` and `bolt` tracks in the weapon's own frame;
## a `<part>.visible` track is one float a frame; `nodes.bolt` and `nodes.magazine` name the GLB node the track drives, or "".

const VERSION := 1
const FPS := 60
const STEP := 1.0 / float(FPS)
## Values are rounded to this step; a clip's length to a millisecond.
const PRECISION := 0.00001
## Floats a frame per track path: a transform is position then quaternion.
const WIDTHS := {"transform": 7, "position": 3, "visible": 1, "vec2": 2}

## Frames recorded since [method begin].
var frames := 0
var _tracks: Dictionary = {}


## Starts a clip: forgets the tracks and the frame count.
func begin() -> void:
	_tracks = {}
	frames = 0


## Adds one frame's [param values] to the track [param key] (path: a key of [constant WIDTHS]). A track that starts late is backfilled with its first values, or with [param before]
## (a part that is hidden until it appears: pass its hidden value).
func put(key: String, path: String, values: Array, before: Array = []) -> void:
	if not _tracks.has(key):
		var back: Array = []
		for _i in frames:
			back.append_array(before if not before.is_empty() else values)
		_tracks[key] = {"path": path, "values": back}
	(_tracks[key].values as Array).append_array(values)


## Ends the frame the [method put] calls above described.
func frame_done() -> void:
	frames += 1


## The clip recorded since [method begin]. A track that stopped reporting (a part the game freed mid-clip) holds its last values, a visible track hidden.
func finish(name: String, loop: bool) -> Dictionary:
	var tracks: Array = []
	for key: String in _tracks:
		var t: Dictionary = _tracks[key]
		var width: int = WIDTHS[t.path]
		var vals: Array = t.values
		while vals.size() < width * frames:
			if t.path == "visible":
				vals.append(0.0)
			else:
				vals.append_array(vals.slice(vals.size() - width))
		tracks.append(track(key, t.path, vals))
	return clip(name, loop, frames, tracks)


## A transform as 7 floats: position, then the rotation quaternion.
static func t7(t: Transform3D) -> Array:
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	return [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]


## [param values] rounded to the sidecar's precision.
static func rounded(values: Array) -> Array:
	var out: Array = []
	for v: float in values:
		out.append(snappedf(v, PRECISION))
	return out


## A track, its values rounded.
static func track(target: String, path: String, values: Array) -> Dictionary:
	return {"target": target, "path": path, "values": rounded(values)}


## A clip of [param frames] frames over [param tracks] (see [method track]).
static func clip(name: String, loop: bool, frame_count: int, tracks: Array) -> Dictionary:
	return {"name": name, "length": snappedf(float(frame_count) / float(FPS), 0.001), "frames": frame_count, "loop": loop, "tracks": tracks}


## The `lens` block for a pack whose game applies GSViewLens at these horizontal fields of view (degrees).
static func lens(viewmodel_fov_h: float, world_fov_h: float) -> Dictionary:
	return {
		"viewmodel_fov_h": viewmodel_fov_h, "world_fov_h": world_fov_h,
		"reference_fov": GSViewLens.REFERENCE_FOV, "reference_depth": GSViewLens.REFERENCE_DEPTH,
		"max_pull_in": GSViewLens.MAX_PULL_IN, "depth_comp": 1.0,
	}


## The `lens` block of a pack with no hands lens: the viewer's lens is the identity.
static func lens_identity() -> Dictionary:
	return {"viewmodel_fov_h": 90.0, "world_fov_h": 90.0, "reference_fov": 90.0, "reference_depth": 0.5, "max_pull_in": 0.2, "depth_comp": 0.0}


## Nightly's asset name for a model: [param pack], then the path under res:// without its extension, "/" as "__".
static func asset_of(pack: String, model_path: String) -> String:
	return "%s__%s" % [pack, model_path.trim_prefix("res://").get_basename().replace("/", "__")]


## The sidecar document. [param extras] (third_person, props, ...) are merged in; the keys keep a stable order.
static func sidecar(weapon: String, model: String, asset: String, lens_block: Dictionary, bolt_node: String, magazine_node: String, clips: Array, extras: Dictionary = {}) -> Dictionary:
	var out := {"version": VERSION, "weapon": weapon, "model": model, "asset": asset, "fps": FPS, "lens": lens_block}
	out.merge(extras)
	out["nodes"] = {"bolt": bolt_node, "magazine": magazine_node}
	out["clips"] = clips
	return out
