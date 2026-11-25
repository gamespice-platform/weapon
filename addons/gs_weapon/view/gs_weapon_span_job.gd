extends "gs_weapon_slice_job.gd"

## [method IronSight.spans] as a job that can stop part way and go on in a later frame (see gs_weapon_slice_job.gd): the same answers,
## `{low, high, length}` or `{}` for each of the fractions. A 40k-triangle rifle was one 45-80 ms call. No `class_name`: preloaded by path.

## How much wider than a triangle's own footprint a ray's x and z may sit and still be tried.
const FOOTPRINT_SLACK := 0.0001

## The answers, in the order of the fractions; filled when [method step] reports done (or [method run] returns).
var result: Array = []

var _faces: PackedVector3Array
var _forward: Vector3
var _fractions: Array
var _f: Vector3
var _side: Vector3
var _t_min := INF
var _t_max := -INF
var _y_min := INF
var _y_max := -INF
var _centre := 0.0
var _width := 0.0
var _length := 0.0
var _rays: Array = []
var _boxes: Array[Rect2] = []
var _near: Array[PackedInt32Array] = []
var _feet: Array[PackedFloat32Array] = []


func _init(faces: PackedVector3Array, forward: Vector3, fractions: Array) -> void:
	_faces = faces
	_forward = forward
	_fractions = fractions


func _work() -> void:
	for _i in _fractions:
		result.append({})
	_f = _forward.normalized()
	if _f == Vector3.ZERO or absf(_f.dot(Vector3.UP)) > 0.5 or _faces.is_empty():
		return
	_side = Vector3.UP.cross(_f).normalized()
	await _extent()
	_length = _t_max - _t_min
	if _length <= 0.0:
		return
	_plan()
	await _bin()
	for k in _fractions.size():
		await _cast(k)


## The faces' extent along the aim, sideways and up.
func _extent() -> void:
	var s_min := INF
	var s_max := -INF
	var n := 0
	for p: Vector3 in _faces:
		n += 1
		if n % CHECK_EVERY == 0:
			await _yield_if_spent()
		var t := p.dot(_f)
		var sd := p.dot(_side)
		_t_min = minf(_t_min, t)
		_t_max = maxf(_t_max, t)
		s_min = minf(s_min, sd)
		s_max = maxf(s_max, sd)
		_y_min = minf(_y_min, p.y)
		_y_max = maxf(_y_max, p.y)
	_centre = (s_min + s_max) * 0.5
	_width = s_max - s_min


## Per fraction the 15 rays and the x-z box they stand in.
func _plan() -> void:
	for k in _fractions.size():
		var at_k: Array[Vector3] = []
		var box := Rect2()
		for shift: float in [0.0, -0.02, 0.02, -0.04, 0.04]:
			for lateral: float in [0.0, -0.15, 0.15]:
				var at := _f * (lerpf(_t_min, _t_max, float(_fractions[k])) + shift * _length) + _side * (_centre + lateral * _width)
				box = Rect2(at.x, at.z, 0.0, 0.0) if at_k.is_empty() else box.expand(Vector2(at.x, at.z))
				at_k.append(at)
		_rays.append(at_k)
		# Grown a hair so float rounding cannot drop a triangle the ray's own test below would keep.
		_boxes.append(box.grow(0.00001))
		_near.append(PackedInt32Array())
		_feet.append(PackedFloat32Array())


## A vertical ray can only meet a triangle whose x-z footprint (a hair wider) holds it, so one pass keeps per fraction the
## triangles under its 15 rays' box and the rays walk only those: the same Geometry3D test as a ray per triangle, same answers
## (each ray walking every triangle was ~35 ms a weapon of hand reach).
func _bin() -> void:
	for t in _faces.size() / 3:
		if t % CHECK_EVERY == 0:
			await _yield_if_spent()
		var a := _faces[t * 3]
		var b := _faces[t * 3 + 1]
		var c := _faces[t * 3 + 2]
		var lo_x := minf(a.x, minf(b.x, c.x)) - FOOTPRINT_SLACK
		var hi_x := maxf(a.x, maxf(b.x, c.x)) + FOOTPRINT_SLACK
		var lo_z := minf(a.z, minf(b.z, c.z)) - FOOTPRINT_SLACK
		var hi_z := maxf(a.z, maxf(b.z, c.z)) + FOOTPRINT_SLACK
		for k in _boxes.size():
			var box := _boxes[k]
			if box.end.x < lo_x or box.position.x > hi_x or box.end.y < lo_z or box.position.y > hi_z:
				continue
			_near[k].append(t)
			_feet[k].append_array([lo_x, hi_x, lo_z, hi_z])


## The vertical rays of fraction [param k] against the triangles binned to it.
func _cast(k: int) -> void:
	var low := INF
	var high := -INF
	var list := _near[k]
	var foot := _feet[k]
	for at: Vector3 in _rays[k]:
		var from_below := at + Vector3.DOWN * (at.y - _y_min + 1.0)
		var from_above := at + Vector3.UP * (_y_max - at.y + 1.0)
		for i in list.size():
			if i % CHECK_EVERY == 0:
				await _yield_if_spent()
			if at.x < foot[i * 4] or at.x > foot[i * 4 + 1] or at.z < foot[i * 4 + 2] or at.z > foot[i * 4 + 3]:
				continue
			var t := list[i] * 3
			var up: Variant = Geometry3D.ray_intersects_triangle(from_below, Vector3.UP, _faces[t], _faces[t + 1], _faces[t + 2])
			if up != null:
				low = minf(low, (up as Vector3).y)
			var down: Variant = Geometry3D.ray_intersects_triangle(from_above, Vector3.DOWN, _faces[t], _faces[t + 1], _faces[t + 2])
			if down != null:
				high = maxf(high, (down as Vector3).y)
	if low != INF and high != -INF:
		result[k] = {"low": low, "high": high, "length": _length}
