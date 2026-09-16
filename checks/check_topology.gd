extends SceneTree

# The asset is the `anny` topology: 13,718 vertices, 27,420 triangles, 104 bones, and the
# target count the tables declare. `-- --plant` demands the SMPL-X vertex count and must fail.

const ASSETS := "res://assets"
const ANNY_VERTS := 13718
const ANNY_TRIS := 27420
const ANNY_BONES := 104
const SMPLX_VERTS := 10475


func _init() -> void:
	var plant := "--plant" in OS.get_cmdline_user_args()
	var want_verts := SMPLX_VERTS if plant else ANNY_VERTS
	var tables := AnnyTables.load_dir(ASSETS)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if tables == null or doc.append_from_file(ASSETS.path_join("anny_base.glb"), state) != OK:
		printerr("FAIL: asset or tables missing")
		quit(2)
		return
	var scene := doc.generate_scene(state)
	var mi: MeshInstance3D = _find(scene, "MeshInstance3D")
	var sk: Skeleton3D = _find(scene, "Skeleton3D")
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: int = arrays[Mesh.ARRAY_VERTEX].size()
	var tris: int = arrays[Mesh.ARRAY_INDEX].size() / 3
	var fails := 0
	if verts != want_verts:
		printerr("FAIL: %d vertices, wanted %d" % [verts, want_verts])
		fails += 1
	if tris != ANNY_TRIS:
		printerr("FAIL: %d triangles, wanted %d" % [tris, ANNY_TRIS])
		fails += 1
	if sk.get_bone_count() != ANNY_BONES:
		printerr("FAIL: %d bones, wanted %d" % [sk.get_bone_count(), ANNY_BONES])
		fails += 1
	if mi.get_blend_shape_count() != tables.target_count:
		printerr("FAIL: %d blend shapes, tables say %d" % [mi.get_blend_shape_count(), tables.target_count])
		fails += 1
	print("topology: %d verts, %d tris, %d bones, %d targets" % [verts, tris, sk.get_bone_count(), mi.get_blend_shape_count()])
	if plant:
		if fails == 0:
			printerr("FAIL: the SMPL-X count passed")
			quit(1)
		else:
			print("planted control failed as it must")
			quit(0)
		return
	print("TOPOLOGY DONE: %d failure(s)" % fails)
	quit(mini(fails, 125))


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for ch in node.get_children():
		var r := _find(ch, cls)
		if r:
			return r
	return null
