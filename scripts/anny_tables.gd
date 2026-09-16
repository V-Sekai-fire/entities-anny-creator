class_name AnnyTables
extends RefCounted

# The baked tables beside anny_base.glb: axis anchors, per-target slot lists, dial and bone
# metadata, and the four float32 joint tables in morph-target order.

var meta: Dictionary
var target_count: int
var bone_count: int
var free_slots: PackedStringArray
var axis_slots: Dictionary
var anchors: Dictionary
var target_slots: Array
var heads0: PackedFloat32Array
var heads: PackedFloat32Array
var m0: PackedFloat32Array
var dm: PackedFloat32Array
var bone_labels: PackedStringArray
var bone_parents: PackedInt32Array


static func load_dir(dir: String) -> AnnyTables:
	var t := AnnyTables.new()
	var text := FileAccess.get_file_as_string(dir.path_join("anny_tables.json"))
	if text.is_empty():
		push_error("anny_tables.json missing under " + dir)
		return null
	t.meta = JSON.parse_string(text)
	t.target_count = int(t.meta["target_count"])
	t.bone_count = int(t.meta["bone_count"])
	t.free_slots = PackedStringArray(t.meta["free_slots"])
	t.axis_slots = t.meta["axis_slots"]
	t.anchors = t.meta["anchors"]
	t.target_slots = []
	for entry in t.meta["targets"]:
		t.target_slots.append(entry["slots"])
	t.bone_labels = PackedStringArray(t.meta["bone_labels"])
	t.bone_parents = PackedInt32Array(t.meta["bone_parents"])
	t.heads0 = _f32(dir.path_join("heads0.f32"), t.bone_count * 3)
	t.heads = _f32(dir.path_join("heads.f32"), t.target_count * t.bone_count * 3)
	t.m0 = _f32(dir.path_join("M0.f32"), t.bone_count * 9)
	t.dm = _f32(dir.path_join("dM.f32"), t.target_count * t.bone_count * 9)
	if t.heads.is_empty() or t.dm.is_empty():
		return null
	return t


static func _f32(path: String, expected: int) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return PackedFloat32Array()
	var arr := f.get_buffer(f.get_length()).to_float32_array()
	if arr.size() != expected:
		push_error("%s holds %d floats, expected %d" % [path, arr.size(), expected])
		return PackedFloat32Array()
	return arr
