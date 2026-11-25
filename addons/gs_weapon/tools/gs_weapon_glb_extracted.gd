extends SceneTree
## The image files Godot extracted beside a GLB (by path, no `class_name`). A GLB imported with
## gltf/embedded_image_handling=1 renders those files, not its own images, and Godot never rewrites one that exists,
## so a rebaked GLB keeps its old textures until they are rewritten. A pack suite calls [method stale]; after a bake run
##   godot --headless --path . --script res://addons/gs_weapon/tools/gs_weapon_glb_extracted.gd -- [--fix] res://dir...

const EXTRACT := "gltf/embedded_image_handling=1"


func _init() -> void:
	var fix := false
	var dirs := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a == "--fix":
			fix = true
		else:
			dirs.append(a)
	var bad := PackedStringArray()
	for d in dirs:
		bad.append_array(stale(d, fix))
	for line in bad:
		print(("fixed " if fix else "STALE ") + line)
	print("%d extracted image(s) %s in %s" % [bad.size(), "rewritten" if fix else "stale", ", ".join(dirs)])
	quit(1 if bad.size() > 0 and not fix else 0)


## Every extracted image under [param dir] (recursive) that is missing or differs from its GLB's bytes, as
## "path: why". With [param fix] each one is rewritten from the GLB instead.
static func stale(dir: String, fix := false) -> PackedStringArray:
	var out := PackedStringArray()
	for glb in extracting(dir):
		for img: Dictionary in extracted(glb):
			var path: String = img.path
			var want: PackedByteArray = img.bytes
			var why := ""
			if not FileAccess.file_exists(path):
				why = "missing"
			elif FileAccess.get_file_as_bytes(path) != want:
				why = "differs from %s image %d" % [glb.get_file(), img.index]
			if why.is_empty():
				continue
			out.append("%s: %s" % [path, why])
			if fix:
				var f := FileAccess.open(path, FileAccess.WRITE)
				if f == null:
					push_error("cannot write %s" % path)
				else:
					f.store_buffer(want)
	return out


## The embedded images of [param glb] as {index, path, bytes}, path named the way the importer names an extracted
## file: <glb>_<image name or index>, then _<index> on a repeat, .jpg for JPEG and .png for the rest.
static func extracted(glb: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := FileAccess.get_file_as_bytes(glb)
	if b.size() < 20 or b.decode_u32(0) != 0x46546C67:
		return out
	var jlen := b.decode_u32(12)
	var doc = JSON.parse_string(b.slice(20, 20 + jlen).get_string_from_utf8())
	if not doc is Dictionary:
		return out
	var bin_at := 20 + jlen + 8
	var base := glb.get_basename()
	var seen := {}
	var images: Array = doc.get("images", [])
	var views: Array = doc.get("bufferViews", [])
	for i in images.size():
		var im: Dictionary = images[i]
		if not im.has("bufferView"):
			continue
		var view: Dictionary = views[int(im.bufferView)]
		var at := bin_at + int(view.get("byteOffset", 0))
		var label := str(im.get("name", ""))
		var stem := base.get_base_dir().path_join(("%s_%s" % [base.get_file(), label if label != "" else str(i)]).validate_filename())
		if seen.has(stem):
			stem += "_%d" % i
		seen[stem] = true
		var ext := ".jpg" if str(im.get("mimeType", "")) == "image/jpeg" else ".png"
		out.append({"index": i, "path": stem + ext, "bytes": b.slice(at, at + int(view.byteLength))})
	return out


## The GLBs under [param dir] (recursive) whose import extracts their images.
static func extracting(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.get_extension().to_lower() == "glb" and FileAccess.get_file_as_string(path + ".import").contains(EXTRACT):
			out.append(path)
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(extracting(dir.path_join(d)))
	return out
