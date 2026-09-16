extends SceneTree

# The shaped export re-imports to the shape the sliders described: vertices within tolerance of
# the CPU shape, 52 morph targets, 104 joints, one skin, and VRMC_vrm with every required
# humanoid bone. `-- --plant` compares the shaped export against the default body and must fail.

const TOL_M := 0.0002 # 0.2 mm, about a quarter of a credit card
const ASSETS := "res://assets"
const OUT := "user://check_shaped.vrm"
const REQUIRED := ["hips", "spine", "head", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm",
	"rightLowerArm", "rightHand", "leftUpperLeg", "leftLowerLeg", "leftFoot", "rightUpperLeg", "rightLowerLeg", "rightFoot"]


func _init() -> void:
	var plant := "--plant" in OS.get_cmdline_user_args()
	var tables := AnnyTables.load_dir(ASSETS)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if tables == null or doc.append_from_file(ASSETS.path_join("anny_base.glb"), state) != OK:
		printerr("FAIL: asset or tables missing")
		quit(2)
		return
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	var mi: MeshInstance3D = _find(scene, "MeshInstance3D")
	var sk: Skeleton3D = _find(scene, "Skeleton3D")
	var skin: Skin = mi.skin
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS.path_join("parity_cases.json")))
	var case: Dictionary = cases["cases"][3]
	var c := AnnyCoeffs.coefficients(tables, case["phenotype"], case["local"], case["facial"])
	AnnyRig.apply(sk, skin, tables, AnnyRig.rest_globals(tables, c))
	var want := AnnyExport.shaped_vertices(mi.mesh, tables, c)
	if plant:
		var zero := PackedFloat32Array()
		zero.resize(tables.target_count)
		var cd := AnnyCoeffs.coefficients(tables, {}, {}, {})
		want = AnnyExport.shaped_vertices(mi.mesh, tables, cd)

	var out := AnnyExport.build_scene(mi, sk, tables, c, "check")
	root.add_child(out)
	var err := AnnyExport.write(out, OUT, true, "check")
	if err != OK:
		printerr("FAIL: write err=", err)
		quit(2)
		return

	var back_doc := GLTFDocument.new()
	var back := GLTFState.new()
	if back_doc.append_from_file(OUT, back) != OK:
		printerr("FAIL: re-import")
		quit(2)
		return
	var back_scene := back_doc.generate_scene(back)
	var bmi: MeshInstance3D = _find(back_scene, "MeshInstance3D")
	var bsk: Skeleton3D = _find(back_scene, "Skeleton3D")
	if bmi == null:
		printerr("FAIL: no mesh came back from the export")
		quit(1)
		return
	var verts: PackedVector3Array = bmi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var fails := 0
	var worst := 0.0
	if verts.size() != want.size():
		printerr("FAIL: %d vertices back, %d expected" % [verts.size(), want.size()])
		fails += 1
	else:
		for i in verts.size():
			worst = maxf(worst, (verts[i] - want[i]).length())
		if worst > TOL_M:
			printerr("FAIL: vertices off by %.3f mm" % (worst * 1000.0))
			fails += 1
	if bmi.get_blend_shape_count() != 52:
		printerr("FAIL: %d morph targets, wanted 52" % bmi.get_blend_shape_count())
		fails += 1
	if bsk == null or bsk.get_bone_count() != tables.bone_count:
		printerr("FAIL: bones back %s" % (str(bsk.get_bone_count()) if bsk else "none"))
		fails += 1
	var json: Dictionary = back.json
	var vrm: Dictionary = json.get("extensions", {}).get("VRMC_vrm", {})
	var human: Dictionary = vrm.get("humanoid", {}).get("humanBones", {})
	for b in REQUIRED:
		if not human.has(b):
			printerr("FAIL: humanoid bone missing: ", b)
			fails += 1
	print("shaped export: %d verts (worst %.4f mm), %d morphs, %d bones, %d humanoid bones, %d expressions, extensions %s" % [
		verts.size(), worst * 1000.0, bmi.get_blend_shape_count(), bsk.get_bone_count() if bsk else 0, human.size(),
		vrm.get("expressions", {}).get("preset", {}).size(), str(json.get("extensionsUsed", []))])
	if plant:
		if fails == 0:
			printerr("FAIL: the default body passed as the shaped export")
			quit(1)
		else:
			print("planted control failed as it must")
			quit(0)
		return
	print("SHAPED EXPORT DONE: %d failure(s); tolerance %.2f mm (a quarter of a credit card)" % [fails, TOL_M * 1000.0])
	quit(mini(fails, 125))


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for ch in node.get_children():
		var r := _find(ch, cls)
		if r:
			return r
	return null
