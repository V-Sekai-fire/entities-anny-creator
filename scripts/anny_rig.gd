class_name AnnyRig
extends RefCounted

# Joints from the coefficient vector: a head is a linear blend, an orientation is the nearest
# rotation to a linearly blended matrix (polar iteration), and the result is written as bone
# rests plus matching skin bind poses so the mesh stays on the skeleton.


static func nearest_rotation(m: Basis) -> Basis:
	var x := m
	for _i in 30:
		var it := x.inverse().transposed()
		var y := Basis(0.5 * (x.x + it.x), 0.5 * (x.y + it.y), 0.5 * (x.z + it.z))
		var moved := (y.x - x.x).length() + (y.y - x.y).length() + (y.z - x.z).length()
		x = y
		if moved < 1e-10:
			break
	return x


static func rest_globals(tables: AnnyTables, c: PackedFloat32Array) -> Array[Transform3D]:
	var J := tables.bone_count
	var T := tables.target_count
	var out: Array[Transform3D] = []
	out.resize(J)
	var active := PackedInt32Array()
	for t in T:
		if c[t] != 0.0:
			active.append(t)
	for j in J:
		var h := Vector3(tables.heads0[j * 3], tables.heads0[j * 3 + 1], tables.heads0[j * 3 + 2])
		var m := PackedFloat32Array()
		m.resize(9)
		for k in 9:
			m[k] = tables.m0[j * 9 + k]
		for t in active:
			var w := c[t]
			var hb := (t * J + j) * 3
			h += w * Vector3(tables.heads[hb], tables.heads[hb + 1], tables.heads[hb + 2])
			var mb := (t * J + j) * 9
			for k in 9:
				m[k] += w * tables.dm[mb + k]
		var basis := Basis(Vector3(m[0], m[3], m[6]), Vector3(m[1], m[4], m[7]), Vector3(m[2], m[5], m[8]))
		out[j] = Transform3D(nearest_rotation(basis), h)
	return out


static func apply(skeleton: Skeleton3D, skin: Skin, tables: AnnyTables, globals: Array[Transform3D]) -> void:
	for j in tables.bone_count:
		var bone := skeleton.find_bone(tables.bone_labels[j])
		if bone < 0:
			push_error("bone missing on skeleton: " + tables.bone_labels[j])
			return
		var p := tables.bone_parents[j]
		var local := globals[j] if p < 0 else globals[p].affine_inverse() * globals[j]
		skeleton.set_bone_rest(bone, local)
		skeleton.set_bone_pose(bone, local)
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		var j := tables.bone_labels.find(skeleton.get_bone_name(bone))
		if j >= 0:
			skin.set_bind_pose(b, globals[j].affine_inverse())
	skeleton.force_update_all_bone_transforms()
