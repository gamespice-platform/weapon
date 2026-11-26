extends SceneTree

## The command-line shell of a pack's sidecar bake, by path (API 57): a pack's tools/export_anim_tracks.gd extends this and overrides [method _bake_all].
## Args: `out_dir` (or `-` to print one SIDECAR<TAB>asset<TAB>json line each to stdout, for runs offloaded to a box whose files the caller cannot read) and an optional comma list of ids.
## Files are named `<asset>.anim.json`, the name Nightly's viewer looks for beside the asset.
## godot --headless --path . --script res://tools/export_anim_tracks.gd -- out_dir rifle,pistol

## The directory the sidecars go to, or "-" for stdout.
var out := ""
var failed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: export_anim_tracks.gd -- out_dir [ids]")
		quit(2)
		return
	out = args[0]
	if out != "-":
		DirAccess.make_dir_recursive_absolute(out)
	var wanted: PackedStringArray = args[1].split(",") if args.size() > 1 and args[1] != "" else PackedStringArray()
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	_bake_all(host, wanted)
	quit(1 if failed > 0 else 0)


## Overridden: bake what [param wanted] names (everything when empty) under [param host] and hand each sidecar to [method emit].
func _bake_all(_host: Node3D, _wanted: PackedStringArray) -> void:
	push_error("_bake_all is not overridden")
	failed += 1


## Writes [param sidecar] (or prints it when out is "-"). A failed write counts toward the exit code.
func emit(sidecar: Dictionary) -> void:
	if out == "-":
		print("SIDECAR\t%s\t%s" % [sidecar.asset, JSON.stringify(sidecar)])
		return
	var path := "%s/%s.anim.json" % [out, sidecar.asset]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		failed += 1
		return
	f.store_string(JSON.stringify(sidecar))
	f.close()
	var n := 0
	for c: Dictionary in sidecar.clips:
		n += (c.tracks as Array).size()
	print("BAKED %s -> %s (%d clips, %d tracks)" % [sidecar.weapon, path, (sidecar.clips as Array).size(), n])
