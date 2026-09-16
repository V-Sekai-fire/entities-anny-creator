class_name AnnyExport
extends RefCounted

# The character a person takes away: the body shape baked into the vertices, the 52 facial
# actions kept as morph targets, the skeleton at its recomputed rest, one skin, and the VRM 1.0
# humanoid map. Pure data: nothing in the file runs.

const FACIAL_PREFIXES := ["au", "ad", "m6", "lips_"]

# ANNY bone label -> VRM 1.0 humanoid bone. Toes stay unmapped: ANNY has one chain per digit.
const HUMANOID := {
	"hips": "root", "spine": "spine05", "chest": "spine03", "upperChest": "spine01",
	"neck": "neck01", "head": "head", "leftEye": "eye.L", "rightEye": "eye.R",
	"leftShoulder": "clavicle.L", "leftUpperArm": "upperarm01.L", "leftLowerArm": "lowerarm01.L", "leftHand": "wrist.L",
	"rightShoulder": "clavicle.R", "rightUpperArm": "upperarm01.R", "rightLowerArm": "lowerarm01.R", "rightHand": "wrist.R",
	"leftUpperLeg": "upperleg01.L", "leftLowerLeg": "lowerleg01.L", "leftFoot": "foot.L",
	"rightUpperLeg": "upperleg01.R", "rightLowerLeg": "lowerleg01.R", "rightFoot": "foot.R",
	"leftThumbMetacarpal": "finger1-1.L", "leftThumbProximal": "finger1-2.L", "leftThumbDistal": "finger1-3.L",
	"leftIndexProximal": "finger2-1.L", "leftIndexIntermediate": "finger2-2.L", "leftIndexDistal": "finger2-3.L",
	"leftMiddleProximal": "finger3-1.L", "leftMiddleIntermediate": "finger3-2.L", "leftMiddleDistal": "finger3-3.L",
	"leftRingProximal": "finger4-1.L", "leftRingIntermediate": "finger4-2.L", "leftRingDistal": "finger4-3.L",
	"leftLittleProximal": "finger5-1.L", "leftLittleIntermediate": "finger5-2.L", "leftLittleDistal": "finger5-3.L",
	"rightThumbMetacarpal": "finger1-1.R", "rightThumbProximal": "finger1-2.R", "rightThumbDistal": "finger1-3.R",
	"rightIndexProximal": "finger2-1.R", "rightIndexIntermediate": "finger2-2.R", "rightIndexDistal": "finger2-3.R",
	"rightMiddleProximal": "finger3-1.R", "rightMiddleIntermediate": "finger3-2.R", "rightMiddleDistal": "finger3-3.R",
	"rightRingProximal": "finger4-1.R", "rightRingIntermediate": "finger4-2.R", "rightRingDistal": "finger4-3.R",
	"rightLittleProximal": "finger5-1.R", "rightLittleIntermediate": "finger5-2.R", "rightLittleDistal": "finger5-3.R",
}

# VRM preset expressions over FACS morph names, weight 1 unless stated.
const EXPRESSIONS := {
	"aa": ["au26_jaw_drop"],
	"blink": ["au45_blink_l", "au45_blink_r"],
	"blinkLeft": ["au45_blink_l"],
	"blinkRight": ["au45_blink_r"],
	"happy": ["au12_lip_corner_puller_l", "au12_lip_corner_puller_r", "au06_cheek_raiser_l", "au06_cheek_raiser_r"],
	"angry": ["au04_brow_lowerer_l", "au04_brow_lowerer_r", "au24_lip_presser_l", "au24_lip_presser_r"],
	"sad": ["au15_lip_corner_depressor_l", "au15_lip_corner_depressor_r", "au01_inner_brow_raiser"],
	"surprised": ["au01_inner_brow_raiser", "au02_outer_brow_raiser_l", "au02_outer_brow_raiser_r", "au05_upper_lid_raiser_l", "au05_upper_lid_raiser_r", "au26_jaw_drop"],
	"lookUp": ["m63_eyes_up_l", "m63_eyes_up_r"],
	"lookDown": ["m64_eyes_down_l", "m64_eyes_down_r"],
	"lookLeft": ["m61_eyes_left_l", "m61_eyes_left_r"],
	"lookRight": ["m62_eyes_right_l", "m62_eyes_right_r"],
}


static func shaped_vertices(mesh: ArrayMesh, tables: AnnyTables, c: PackedFloat32Array) -> PackedVector3Array:
	var base: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
	var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var verts := base.duplicate()
	for t in tables.target_count:
		if c[t] == 0.0 or tables.meta["targets"][t]["kind"] == "facial":
			continue
		var sv: PackedVector3Array = shapes[t][Mesh.ARRAY_VERTEX]
		var w := c[t]
		for i in verts.size():
			verts[i] += w * (sv[i] if relative else sv[i] - base[i])
	return verts


static func area_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(verts.size())
	n.fill(Vector3.ZERO)
	for f in range(0, indices.size(), 3):
		var a := indices[f]
		var b := indices[f + 1]
		var c := indices[f + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		n[a] += fn
		n[b] += fn
		n[c] += fn
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 0.0 else Vector3.UP
	return n


static func build_scene(source_mesh: MeshInstance3D, skeleton: Skeleton3D, tables: AnnyTables,
		c: PackedFloat32Array, character_name: String) -> Node3D:
	var mesh: ArrayMesh = source_mesh.mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
	var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var verts := shaped_vertices(mesh, tables, c)

	var bones_v = arrays[Mesh.ARRAY_BONES]
	var eight: bool = bones_v != null and bones_v.size() == verts.size() * 8
	var shaped_arrays := []
	shaped_arrays.resize(Mesh.ARRAY_MAX)
	shaped_arrays[Mesh.ARRAY_VERTEX] = verts
	shaped_arrays[Mesh.ARRAY_NORMAL] = area_normals(verts, arrays[Mesh.ARRAY_INDEX])
	shaped_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	shaped_arrays[Mesh.ARRAY_BONES] = arrays[Mesh.ARRAY_BONES]
	shaped_arrays[Mesh.ARRAY_WEIGHTS] = arrays[Mesh.ARRAY_WEIGHTS]
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		shaped_arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]

	var blend_arrays: Array[Array] = []
	var blend_names: PackedStringArray = []
	for t in tables.target_count:
		if tables.meta["targets"][t]["kind"] != "facial":
			continue
		var sv: PackedVector3Array = shapes[t][Mesh.ARRAY_VERTEX]
		var target := PackedVector3Array()
		target.resize(verts.size())
		for i in verts.size():
			target[i] = verts[i] + (sv[i] if relative else sv[i] - base[i])
		var ba := []
		ba.resize(Mesh.ARRAY_MAX)
		ba[Mesh.ARRAY_VERTEX] = target
		ba[Mesh.ARRAY_NORMAL] = shaped_arrays[Mesh.ARRAY_NORMAL]
		blend_arrays.append(ba)
		blend_names.append(tables.meta["targets"][t]["name"])

	var out_mesh := ArrayMesh.new()
	out_mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for n in blend_names:
		out_mesh.add_blend_shape(n)
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight else 0
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shaped_arrays, blend_arrays, {}, flags)

	var root := Node3D.new()
	root.name = character_name
	# The armature node is what the bone hierarchy hangs from in the file; a Skeleton3D directly
	# under the export root would leave its joints without a parent node and lose the skin.
	var armature := Node3D.new()
	armature.name = "Armature"
	root.add_child(armature)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	armature.add_child(skel)
	for b in skeleton.get_bone_count():
		skel.add_bone(skeleton.get_bone_name(b))
	for b in skeleton.get_bone_count():
		skel.set_bone_parent(b, skeleton.get_bone_parent(b))
		skel.set_bone_rest(b, skeleton.get_bone_rest(b))
		skel.set_bone_pose(b, skeleton.get_bone_rest(b))
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = out_mesh
	skel.add_child(mi)
	mi.skeleton = NodePath("..") # a MeshInstance3D made in code has no skeleton path; the exporter needs one
	var skin := skel.create_skin_from_rest_transforms()
	for b in skin.get_bind_count():
		skin.set_bind_name(b, skel.get_bone_name(skin.get_bind_bone(b)))
	mi.skin = skin
	armature.owner = root
	skel.owner = root
	mi.owner = root
	return root


static func write(root: Node3D, path: String, vrm: bool, meta_name: String) -> Error:
	var doc := GLTFDocument.new()
	doc.root_node_mode = GLTFDocument.ROOT_NODE_MODE_MULTI_ROOT
	var ext: GLTFDocumentExtension = null
	if vrm:
		ext = VrmWriter.new()
		ext.meta_name = meta_name
		GLTFDocument.register_gltf_document_extension(ext, true)
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	# GLTFDocument writes binary only for a .glb suffix, so a .vrm is written as .glb and renamed.
	var tmp := path if path.ends_with(".glb") else path + ".tmp.glb"
	if err == OK:
		err = doc.write_to_filesystem(state, tmp)
	if err == OK and tmp != path:
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if ext != null:
		GLTFDocument.unregister_gltf_document_extension(ext)
	return err


class VrmWriter:
	extends GLTFDocumentExtension
	var meta_name := "ANNY character"

	func _export_post(state: GLTFState) -> Error:
		var json: Dictionary = state.json
		var node_index := {}
		var nodes: Array = json.get("nodes", [])
		for i in nodes.size():
			node_index[String(nodes[i].get("name", ""))] = i
		var bones := {}
		for vrm_bone in HUMANOID:
			var label: String = HUMANOID[vrm_bone]
			var idx = node_index.get(label, node_index.get(label.replace(".", "_")))
			if idx != null:
				bones[vrm_bone] = {"node": idx}
		var morph_index := {}
		var meshes: Array = json.get("meshes", [])
		for m in meshes:
			var names: Array = m.get("extras", {}).get("targetNames", [])
			for k in names.size():
				morph_index[String(names[k])] = k
		var mesh_node := -1
		for i in nodes.size():
			if nodes[i].has("mesh"):
				mesh_node = i
		var presets := {}
		for preset in EXPRESSIONS:
			var binds := []
			for morph in EXPRESSIONS[preset]:
				if morph_index.has(morph):
					binds.append({"node": mesh_node, "index": morph_index[morph], "weight": 1.0})
			if not binds.is_empty():
				presets[preset] = {"morphTargetBinds": binds, "isBinary": false, "overrideBlink": "none", "overrideLookAt": "none", "overrideMouth": "none"}
		var vrm := {
			"specVersion": "1.0",
			"meta": {
				"name": meta_name, "version": "0.1", "authors": ["anny-creator"],
				"licenseUrl": "https://vrm.dev/licenses/1.0/",
				"avatarPermission": "everyone", "allowExcessivelyViolentUsage": false,
				"allowExcessivelySexualUsage": false, "commercialUsage": "personalProfit",
				"allowPoliticalOrReligiousUsage": true, "allowAntisocialOrHateUsage": false,
				"creditNotation": "unnecessary", "allowRedistribution": true, "modification": "allowModificationRedistribution",
			},
			"humanoid": {"humanBones": bones},
			"expressions": {"preset": presets},
		}
		var extensions: Dictionary = json.get("extensions", {})
		extensions["VRMC_vrm"] = vrm
		json["extensions"] = extensions
		var used: Array = json.get("extensionsUsed", [])
		if not used.has("VRMC_vrm"):
			used.append("VRMC_vrm")
		json["extensionsUsed"] = used
		state.json = json
		return OK
