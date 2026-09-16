extends Node3D

# The creator: loads the baked ANNY asset at runtime, builds three slider panels, and on every
# change writes the coefficient vector to the blend shapes and the joint tables to the skeleton.

const ASSETS := "res://assets"

var tables: AnnyTables
var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var skin: Skin
var coeffs := PackedFloat32Array()
var phenotype := {"gender": 0.5, "age": 0.5, "muscle": 0.5, "weight": 0.5, "height": 0.5, "proportions": 0.5}
var local := {}
var facial := {}
var status: Label
var timer := 0.0
var dirty := false
var frames := 0


func _ready() -> void:
	tables = AnnyTables.load_dir(ASSETS)
	if tables == null:
		push_error("run `pixi run -e bake bake` first; assets/ is empty")
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ASSETS.path_join("anny_base.glb"), state)
	if err != OK:
		push_error("anny_base.glb failed to load: %d" % err)
		return
	var scene := doc.generate_scene(state)
	add_child(scene)
	mesh_instance = _find(scene, "MeshInstance3D")
	skeleton = _find(scene, "Skeleton3D")
	skin = mesh_instance.skin
	if skin == null:
		skin = skeleton.create_skin_from_rest_transforms()
		mesh_instance.skin = skin
	coeffs.resize(tables.target_count)
	_build_world()
	_build_ui()
	_recompute(true)


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for ch in node.get_children():
		var r := _find(ch, cls)
		if r:
			return r
	return null


func _build_world() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 0.1, 2.4)
	cam.look_at(Vector3(0.0, -0.05, 0.0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.custom_minimum_size = Vector2(420, 0)
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	status = Label.new()
	status.text = "ANNY creator"
	vbox.add_child(status)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	var body := _scroll(tabs, "Body")
	for axis in AnnyCoeffs.AXES:
		_slider(body, axis, 0.0, 1.0, phenotype[axis], func(v: float) -> void: phenotype[axis] = v; _mark())

	var face := _scroll(tabs, "Face")
	for f in tables.meta["facial"]:
		var name: String = f["name"]
		_slider(face, name, 0.0, 1.0, 0.0, func(v: float) -> void: facial[name] = v; _mark())

	var dials := _scroll(tabs, "Dials")
	var by_group := {}
	for d in tables.meta["local_dials"]:
		by_group.get_or_add(d["group"], []).append(d["name"])
	var groups: Array = by_group.keys()
	groups.sort()
	for g in groups:
		var head := Label.new()
		head.text = "— %s —" % g
		dials.add_child(head)
		for name in by_group[g]:
			var n: String = name
			_slider(dials, n, -1.0, 1.0, 0.0, func(v: float) -> void: local[n] = v; _mark())

	var export := Button.new()
	export.text = "Export glTF (pure data)"
	export.pressed.connect(_export)
	vbox.add_child(export)


func _scroll(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box


func _slider(parent: Control, label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	l.clip_text = true
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	parent.add_child(row)


func _mark() -> void:
	dirty = true


func _process(delta: float) -> void:
	timer += delta
	frames += 1
	if frames == 90 and "--screenshot" in OS.get_cmdline_user_args():
		phenotype["muscle"] = 0.9
		phenotype["weight"] = 0.2
		facial["au26_jaw_drop"] = 0.6
		_recompute(false)
	if frames == 120 and "--screenshot" in OS.get_cmdline_user_args():
		get_viewport().get_texture().get_image().save_png("user://creator.png")
		print("screenshot -> ", OS.get_user_data_dir().path_join("creator.png"))
		_export()
		print(status.text)
	if dirty and timer > 0.03:
		timer = 0.0
		dirty = false
		_recompute(false)


func _recompute(first: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var c := AnnyCoeffs.coefficients(tables, phenotype, local, facial)
	for t in tables.target_count:
		if first or c[t] != coeffs[t]:
			mesh_instance.set_blend_shape_value(t, c[t])
	coeffs = c
	var globals := AnnyRig.rest_globals(tables, c)
	AnnyRig.apply(skeleton, skin, tables, globals)
	var us := Time.get_ticks_usec() - t0
	var stature := 0.0
	for i in tables.bone_count:
		stature = maxf(stature, globals[i].origin.y)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	status.text = "update %d us; highest joint %.3f m above the origin; video memory %.0f MB" % [us, stature, vram]
	if first:
		print(status.text)


func _export() -> void:
	var out := AnnyExport.build_scene(mesh_instance, skeleton, tables, coeffs, "anny_character")
	add_child(out)
	var path := "user://anny_character.vrm"
	var err := AnnyExport.write(out, path, true, "ANNY character")
	out.queue_free()
	status.text = "export %s -> %s" % ["ok" if err == OK else "failed %d" % err, ProjectSettings.globalize_path(path)]
