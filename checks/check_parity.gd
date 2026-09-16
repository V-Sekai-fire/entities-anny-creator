extends SceneTree

# The ported math against the Python model: for every seeded case, vertices from the coefficient
# vector applied to the baked targets, and joint globals from the joint tables, within a stated
# tolerance of what ANNY itself answered. `-- --plant` mis-orders the age anchors and must fail.

const TOL_M := 0.0002 # 0.2 mm, about a quarter of a credit card
const ASSETS := "res://assets"


func _init() -> void:
	var plant := "--plant" in OS.get_cmdline_user_args()
	var tables := AnnyTables.load_dir(ASSETS)
	if tables == null:
		printerr("FAIL: tables did not load")
		quit(2)
		return
	if plant:
		tables.anchors["age"] = [1.0, 0.6666, 0.3333, 0.0, -0.3333]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ASSETS.path_join("anny_base.glb"), state)
	if err != OK:
		printerr("FAIL: glb load err=", err)
		quit(2)
		return
	var scene := doc.generate_scene(state)
	var mi := _find_mesh(scene)
	if mi == null:
		printerr("FAIL: no blend-shaped mesh in glb")
		quit(2)
		return
	var mesh: ArrayMesh = mi.mesh
	var base: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
	var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	print("mesh: %d verts, %d blend shapes, mode %s" % [base.size(), shapes.size(), "relative" if relative else "normalized"])
	if base.size() != tables.meta["vertex_count"] or shapes.size() != tables.target_count:
		printerr("FAIL: counts disagree with tables")
		quit(1)
		return

	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS.path_join("parity_cases.json")))
	var stride := int(cases["stride"])
	var f := FileAccess.open(ASSETS.path_join("parity_expected.f32"), FileAccess.READ)
	var expected := f.get_buffer(f.get_length()).to_float32_array()
	var V := base.size()
	var J := tables.bone_count
	var worst_v := 0.0
	var worst_j := 0.0
	var worst_r := 0.0
	var fails := 0
	var n := 0
	for case in cases["cases"]:
		var c := AnnyCoeffs.coefficients(tables, case["phenotype"], case["local"], case["facial"])
		var verts := base.duplicate()
		for t in tables.target_count:
			if c[t] == 0.0:
				continue
			var sv: PackedVector3Array = shapes[t][Mesh.ARRAY_VERTEX]
			var w := c[t]
			for i in V:
				var d := sv[i] if relative else sv[i] - base[i]
				verts[i] += w * d
		var off := n * stride
		var ev := 0.0
		for i in V:
			var e := Vector3(expected[off + i * 3], expected[off + i * 3 + 1], expected[off + i * 3 + 2])
			ev = maxf(ev, (verts[i] - e).length())
		var globals := AnnyRig.rest_globals(tables, c)
		var ej := 0.0
		var er := 0.0
		for j in J:
			var o := off + V * 3 + j * 16
			var g := Transform3D(
				Basis(Vector3(expected[o], expected[o + 4], expected[o + 8]),
					Vector3(expected[o + 1], expected[o + 5], expected[o + 9]),
					Vector3(expected[o + 2], expected[o + 6], expected[o + 10])),
				Vector3(expected[o + 3], expected[o + 7], expected[o + 11]))
			ej = maxf(ej, (globals[j].origin - g.origin).length())
			var dr := (globals[j].basis.inverse() * g.basis).get_rotation_quaternion().get_angle()
			er = maxf(er, dr)
		worst_v = maxf(worst_v, ev)
		worst_j = maxf(worst_j, ej)
		worst_r = maxf(worst_r, er)
		var ok := ev <= TOL_M and ej <= TOL_M and er <= 0.001
		if not ok:
			fails += 1
		print("case %2d: verts %.4f mm, joints %.4f mm, rot %.5f rad %s" % [n, ev * 1000.0, ej * 1000.0, er, "ok" if ok else "FAIL"])
		n += 1
	print("worst: verts %.4f mm, joints %.4f mm, rot %.5f rad; tolerance %.2f mm (a quarter of a credit card)" % [worst_v * 1000.0, worst_j * 1000.0, worst_r, TOL_M * 1000.0])
	if plant:
		if fails == 0:
			printerr("FAIL: planted anchor disorder passed")
			quit(1)
		else:
			print("planted control failed as it must (%d of %d cases)" % [fails, n])
			quit(0)
		return
	print("PARITY DONE: %d cases, %d failure(s)" % [n, fails])
	quit(mini(fails, 125))


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.get_blend_shape_count() > 0:
		return node
	for ch in node.get_children():
		var r := _find_mesh(ch)
		if r:
			return r
	return null
