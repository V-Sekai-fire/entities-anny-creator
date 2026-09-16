extends SceneTree

# Export is pure data: the written glTF names only KHR_* and VRMC_* extensions, carries morph
# targets and a skin, and no node carries a script or extras. `-- --plant` adds a foreign
# extension to the state and must fail.

const ASSETS := "res://assets"
const OUT := "user://check_export.glb"


func _init() -> void:
	var plant := "--plant" in OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ASSETS.path_join("anny_base.glb"), state) != OK:
		printerr("FAIL: could not load the baked asset")
		quit(2)
		return
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	if out_doc.append_from_scene(scene, out_state) != OK:
		printerr("FAIL: append_from_scene")
		quit(2)
		return
	if plant:
		out_state.add_used_extension("EXT_planted_driver", true)
	if out_doc.write_to_filesystem(out_state, OUT) != OK:
		printerr("FAIL: write_to_filesystem")
		quit(2)
		return
	var fails := _audit(OUT)
	if plant:
		if fails == 0:
			printerr("FAIL: planted extension passed the audit")
			quit(1)
		else:
			print("planted control failed as it must")
			quit(0)
		return
	print("EXPORT DONE: %d failure(s)" % fails)
	quit(mini(fails, 125))


func _audit(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	f.get_32() # magic
	f.get_32() # version
	f.get_32() # length
	var chunk_len := f.get_32()
	f.get_32() # JSON chunk type
	var json := JSON.parse_string(f.get_buffer(chunk_len).get_string_from_utf8())
	var fails := 0
	for ext in json.get("extensionsUsed", []):
		if not (String(ext).begins_with("KHR_") or String(ext).begins_with("VRMC_")):
			printerr("FAIL: foreign extension ", ext)
			fails += 1
	for ext in json.get("extensionsRequired", []):
		if not (String(ext).begins_with("KHR_") or String(ext).begins_with("VRMC_")):
			printerr("FAIL: foreign required extension ", ext)
			fails += 1
	var meshes: Array = json.get("meshes", [])
	var targets := 0
	for m in meshes:
		for p in m.get("primitives", []):
			targets += p.get("targets", []).size()
	if targets == 0:
		printerr("FAIL: no morph targets in export")
		fails += 1
	if json.get("skins", []).is_empty():
		printerr("FAIL: no skin in export")
		fails += 1
	for n in json.get("nodes", []):
		if n.has("extras") and (n["extras"] as Dictionary).has("script"):
			printerr("FAIL: node carries a script: ", n.get("name", "?"))
			fails += 1
	print("export: %d morph targets, %d skins, extensions %s" % [targets, json.get("skins", []).size(), str(json.get("extensionsUsed", []))])
	return fails
