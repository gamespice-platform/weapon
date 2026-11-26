extends "sections_native.gd"

## The animation sidecar writer: transforms, rounding, the recorder's backfill and padding, and the document's shape.
func _test_anim_sidecar() -> void:
	_section("animation sidecar")
	var S := preload("res://addons/gs_weapon/view/gs_weapon_anim_sidecar.gd")
	var t7 := S.t7(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1, 2, 3)))
	_check(t7.size() == 7 and t7[0] == 1.0 and t7[2] == 3.0 and is_equal_approx(t7[4], sin(PI / 4.0)) and is_equal_approx(t7[6], cos(PI / 4.0)), "a transform is position then quaternion")
	_check(S.t7(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3.ZERO))[6] == 1.0, "a scaled basis is orthonormalised before the quaternion")
	var rd := S.rounded([0.123456789, -0.000004, 1.0])
	_check(rd.size() == 3 and is_equal_approx(rd[0], 0.12346) and is_zero_approx(rd[1]) and rd[2] == 1.0, "values round to 0.00001")
	var r := S.new()
	r.begin()
	r.put("weapon", "transform", [0, 0, 0, 0, 0, 0, 1])
	r.put("part.visible", "visible", [1.0])
	r.put("hand", "position", [1.0, 2.0, 3.0])
	r.frame_done()
	r.put("weapon", "transform", [0, 0, 1, 0, 0, 0, 1])
	r.put("late", "position", [4.0, 5.0, 6.0])
	r.put("late.visible", "visible", [1.0], [0.0])
	r.frame_done()
	var c := r.finish("fire", false)
	var by := {}
	for tr: Dictionary in c.tracks:
		by[tr.target] = tr
	_check(c.frames == 2 and c.length == 0.033 and c.name == "fire" and not c.loop, "a clip carries its frame count, a length to the millisecond and its name")
	_check(by.weapon.values.size() == 14 and _near(by.late.values, [4.0, 5.0, 6.0, 4.0, 5.0, 6.0]), "a late track is backfilled with its first values")
	_check(_near(by["late.visible"].values, [0.0, 1.0]), "a late visible track is backfilled with the hidden value")
	_check(_near(by.hand.values, [1.0, 2.0, 3.0, 1.0, 2.0, 3.0]) and _near(by["part.visible"].values, [1.0, 0.0]), "a track that stops holds its last values, a visible one goes hidden")
	r.begin()
	_check(r.frames == 0 and r.finish("idle", true).tracks.is_empty(), "begin forgets the last clip")
	var doc := S.sidecar("rifle", "rifle", S.asset_of("pack", "res://assets/guns/rifle.glb"), S.lens_identity(), "slide", "", [c], {"third_person": {"pose": "rifle"}})
	_check(doc.asset == "pack__assets__guns__rifle" and doc.version == 1 and doc.fps == 60 and doc.nodes == {"bolt": "slide", "magazine": ""} and doc.third_person.pose == "rifle", "the document names its asset, nodes and extras")
	_check(JSON.parse_string(JSON.stringify(doc)).clips[0].tracks.size() == 5, "the document survives JSON")
	_check(S.lens(54.0, 90.0).viewmodel_fov_h == 54.0 and S.lens(54.0, 90.0).depth_comp == 1.0, "a lens block reads the GSViewLens constants")
	_done()


func _near(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if not is_equal_approx(got[i], want[i]):
			return false
	return true
