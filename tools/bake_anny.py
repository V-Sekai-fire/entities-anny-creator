"""A runner wrapping a model: bakes the ANNY asset the Godot creator loads. Nothing at runtime imports this.

Writes, under assets/:
  anny_base.glb        mesh + skeleton + skin + every shape as a morph target, Y-up metres
  anny_tables.json     axis anchors, macro row masks, dial and bone metadata, FACS names
  heads0.f32 heads.f32 M0.f32 dM.f32   joint tables, float32, row-major
  parity_cases.json + parity_expected.f32   seeded parameter vectors and the Python model's answer

Run:  pixi run -e bake bake
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import struct

import numpy as np
import torch
from anny import Anny
from anny.models.model_data import PHENOTYPE_VARIATIONS
import anny.paths
import pygltflib as gl

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

FREE_AXES = ["gender", "age", "muscle", "weight", "height", "proportions"]
# Z-up metres (ANNY) -> Y-up metres (glTF): (x, y, z) -> (x, z, -y)
C = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], dtype=np.float64)


def zup_to_yup(v):
    return v @ C.T


def conj(m):
    return C @ m @ C.T


def slot_names():
    return [k for keys in PHENOTYPE_VARIATIONS.values() for k in keys]


def build_model():
    model = Anny(rig="anny", topology="anny", local_changes="default",
                 facial_actions="all", phenotypes="default", skinning_method="lbs")
    model.eval()
    assert model.rest_orientation_refiner is None
    assert not model.root_identity_orientation
    return model


def collapse_macros(model):
    """Fold the constant slots (race, cupsize, firmness) into the macro rows and merge rows that
    share a free-slot pattern. Returns (rows, keys) with rows a list of (weight, source index)."""
    names = slot_names()
    mask = model.stacked_phenotype_blend_shapes_mask.numpy().astype(bool)
    free = [i for i, n in enumerate(names) if any(n in PHENOTYPE_VARIATIONS[a] for a in FREE_AXES)]
    const_value = {}
    for r in PHENOTYPE_VARIATIONS["race"]:
        const_value[names.index(r)] = 1.0 / 3.0
    for axis in ("cupsize", "firmness"):
        for k, n in enumerate(PHENOTYPE_VARIATIONS[axis]):
            const_value[names.index(n)] = 1.0 if k == 1 else 0.0
    merged = {}
    for row in range(mask.shape[0]):
        factor = 1.0
        for j, v in const_value.items():
            if mask[row, j]:
                factor *= v
        if factor == 0.0:
            continue
        key = tuple(int(j) for j in free if mask[row, j])
        block = model.blendshape_labels[row].split(":")[0]
        merged.setdefault((block, key), []).append((factor, row))
    keys = sorted(merged, key=lambda k: (["universal", "race", "height", "proportions"].index(k[0]), k[1]))
    return [merged[k] for k in keys], keys, names, free


def top8(indices, weights):
    order = np.argsort(-weights, axis=1)[:, :8]
    idx = np.take_along_axis(indices, order, axis=1)
    w = np.take_along_axis(weights, order, axis=1)
    dropped = 1.0 - w.sum(axis=1)
    w = w / w.sum(axis=1, keepdims=True)
    return idx, w, dropped


def vertex_normals(v, f):
    n = np.zeros_like(v)
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


class GlbBuilder:
    def __init__(self):
        self.doc = gl.GLTF2(asset=gl.Asset(version="2.0", generator="anny-creator bake"))
        self.blob = bytearray()

    def view(self, data: bytes, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        off = len(self.blob)
        self.blob += data
        bv = gl.BufferView(buffer=0, byteOffset=off, byteLength=len(data), target=target)
        self.doc.bufferViews.append(bv)
        return len(self.doc.bufferViews) - 1

    def accessor(self, arr, ctype, atype, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        bv = self.view(arr.tobytes(), target)
        acc = gl.Accessor(bufferView=bv, componentType=ctype, count=int(arr.shape[0]), type=atype)
        if minmax:
            acc.min = [float(x) for x in arr.min(axis=0)]
            acc.max = [float(x) for x in arr.max(axis=0)]
        self.doc.accessors.append(acc)
        return len(self.doc.accessors) - 1

    def sparse_vec3(self, delta, count):
        nz = np.nonzero(np.any(delta != 0, axis=1))[0].astype(np.uint32)
        if len(nz) == 0:
            nz = np.array([0], dtype=np.uint32)
        vals = delta[nz].astype(np.float32)
        if len(nz) > count * 0.5:
            return self.accessor(delta.astype(np.float32), gl.FLOAT, gl.VEC3, minmax=True)
        ibv = self.view(nz.tobytes())
        vbv = self.view(vals.tobytes())
        acc = gl.Accessor(componentType=gl.FLOAT, count=count, type=gl.VEC3,
                          min=[float(x) for x in delta.min(axis=0)],
                          max=[float(x) for x in delta.max(axis=0)],
                          sparse=gl.Sparse(count=int(len(nz)),
                                           indices=gl.AccessorSparseIndices(bufferView=ibv, componentType=gl.UNSIGNED_INT),
                                           values=gl.AccessorSparseValues(bufferView=vbv)))
        self.doc.accessors.append(acc)
        return len(self.doc.accessors) - 1

    def finish(self, path):
        self.doc.buffers.append(gl.Buffer(byteLength=len(self.blob)))
        self.doc.set_binary_blob(bytes(self.blob))
        self.doc.save_binary(str(path))


def mat_to_trs(m):
    t = m[:3, 3]
    r = m[:3, :3]
    q = rot_to_quat(r)
    return [float(x) for x in t], [float(x) for x in q]


def rot_to_quat(r):
    tr = np.trace(r)
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        return np.array([(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, 0.25 * s])
    i = int(np.argmax(np.diag(r)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = np.sqrt(1.0 + r[i, i] - r[j, j] - r[k, k]) * 2
    q = np.zeros(4)
    q[i] = 0.25 * s
    q[j] = (r[j, i] + r[i, j]) / s
    q[k] = (r[k, i] + r[i, k]) / s
    q[3] = (r[k, j] - r[j, k]) / s
    return q


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "assets")
    ap.add_argument("--cases", type=int, default=20)
    ap.add_argument("--seed", type=int, default=2253)
    a = ap.parse_args(argv)
    a.out.mkdir(parents=True, exist_ok=True)

    model = build_model()
    V = model.template_vertices.shape[0]
    J = len(model.bone_labels)
    bs = model.blendshapes.numpy()
    heads_bs = model.bone_heads_blendshapes.numpy()
    dM_bs = model.bone_orientation_blendshapes.numpy()
    labels = list(model.blendshape_labels)
    n_macro = sum(1 for l in labels if not l.startswith(("facial_action:", "local_change:")))
    n_fa = sum(1 for l in labels if l.startswith("facial_action:"))
    assert (n_macro, n_fa, len(labels)) == (624, 52, 1184), (n_macro, n_fa, len(labels))

    rows, keys, names, free = collapse_macros(model)
    free_names = [names[j] for j in free]
    facs = json.load(open(HERE / "facs_au.json"))

    # Target list: (name, delta[V,3], head_delta[J,3], dM_delta[J,3,3], free-slot indices or None)
    targets = []
    for (block, key), row in zip(keys, rows):
        d = sum(f * bs[r] for f, r in row)
        hd = sum(f * heads_bs[r] for f, r in row)
        md = sum(f * dM_bs[r] for f, r in row)
        comps = "-".join(names[j] for j in key)
        targets.append((f"mac_{block}_{comps}", d, hd, md, [free.index(j) for j in key]))
    for r in range(n_macro, n_macro + n_fa):
        src = labels[r].split(":", 1)[1]
        targets.append((facs[src], bs[r], heads_bs[r], dM_bs[r], None))
    local_names = []
    local_pairs = []
    for r in range(n_macro + n_fa, len(labels)):
        nm = labels[r].split(":", 1)[1]
        sign = "pos" if (r - n_macro - n_fa) % 2 == 0 else "neg"
        targets.append((f"lc_{sign}_{nm}", bs[r], heads_bs[r], dM_bs[r], None))
        if sign == "pos":
            local_names.append(nm)
            local_pairs.append([nm, len(targets) - 1, None])
        else:
            local_pairs[-1][2] = len(targets) - 1
    assert local_names == list(model.local_change_labels)
    T = len(targets)

    # Dial groups from target.json: directory key per positive dial name.
    tj = json.load(open(os.path.join(anny.paths.get_anny_root_dir(), "data/mpfb2/targets/target.json")))
    group_of = {}
    for key, meta in tj.items():
        for cat in meta["categories"]:
            for side in ("left", "right", "unsided"):
                opp = cat.get("opposites", {})
                pos = opp.get(f"positive-{side}", "")
                if pos:
                    group_of[pos] = key

    # Geometry in Y-up.
    verts = zup_to_yup(model.template_vertices.numpy())
    faces = model.faces.numpy().astype(np.uint32)
    normals = vertex_normals(verts, faces)

    # Rest skeleton at the default coefficients.
    zero_kw = {k: 0.5 for k in model.phenotype_labels}
    pp, ph, lc, fa = model.get_tensor_inputs(None, zero_kw, None, None)
    coeffs0 = model._get_phenotype_blendshape_coefficients(ph, lc, fa)
    rest = model.get_rest_model(coeffs0)
    globals_z = rest["rest_bone_poses"][0].numpy()
    globals_y = np.zeros_like(globals_z)
    for j in range(J):
        globals_y[j, :3, :3] = conj(globals_z[j, :3, :3])
        globals_y[j, :3, 3] = zup_to_yup(globals_z[j, :3, 3])
        globals_y[j, 3, 3] = 1.0
    parents = list(model.bone_parents)

    # Skin: top 8 of 9 influences, renormalised; the dropped mass is reported.
    idx, w, dropped = top8(model.vertex_bone_indices.numpy(), model.vertex_bone_weights.numpy())
    print("skin: %d of %d vertices lose a 9th influence; max dropped weight %.4f, mean %.5f" % (
        int((dropped > 1e-9).sum()), V, float(dropped.max()), float(dropped.mean())))

    g = GlbBuilder()
    pos_acc = g.accessor(verts.astype(np.float32), gl.FLOAT, gl.VEC3, gl.ARRAY_BUFFER, minmax=True)
    nrm_acc = g.accessor(normals.astype(np.float32), gl.FLOAT, gl.VEC3, gl.ARRAY_BUFFER)
    idx_acc = g.accessor(faces.reshape(-1), gl.UNSIGNED_INT, gl.SCALAR, gl.ELEMENT_ARRAY_BUFFER)
    j0 = g.accessor(idx[:, :4].astype(np.uint16), gl.UNSIGNED_SHORT, gl.VEC4, gl.ARRAY_BUFFER)
    j1 = g.accessor(idx[:, 4:8].astype(np.uint16), gl.UNSIGNED_SHORT, gl.VEC4, gl.ARRAY_BUFFER)
    w0 = g.accessor(w[:, :4].astype(np.float32), gl.FLOAT, gl.VEC4, gl.ARRAY_BUFFER)
    w1 = g.accessor(w[:, 4:8].astype(np.float32), gl.FLOAT, gl.VEC4, gl.ARRAY_BUFFER)

    morphs = []
    names_out = []
    for name, d, _, _, _ in targets:
        morphs.append(gl.Attributes(POSITION=g.sparse_vec3(zup_to_yup(d), V)))
        names_out.append(name)

    prim = gl.Primitive(attributes=gl.Attributes(POSITION=pos_acc, NORMAL=nrm_acc, JOINTS_0=j0, JOINTS_1=j1,
                                                 WEIGHTS_0=w0, WEIGHTS_1=w1),
                        indices=idx_acc, targets=morphs)
    mesh = gl.Mesh(name="anny", primitives=[prim], weights=[0.0] * T, extras={"targetNames": names_out})
    g.doc.meshes.append(mesh)

    # Nodes: 0 = scene root, 1 = mesh node, 2.. = bones in ANNY order (parents precede children).
    g.doc.nodes.append(gl.Node(name="ANNY", children=[1, 2]))
    g.doc.nodes.append(gl.Node(name="anny_mesh", mesh=0, skin=0))
    bone_node = [2 + j for j in range(J)]
    ibm = np.zeros((J, 4, 4), dtype=np.float32)
    for j in range(J):
        p = parents[j]
        local = globals_y[j] if p < 0 else np.linalg.inv(globals_y[p]) @ globals_y[j]
        t, q = mat_to_trs(local)
        g.doc.nodes.append(gl.Node(name=model.bone_labels[j], translation=t, rotation=q, children=[]))
        ibm[j] = np.linalg.inv(globals_y[j]).T  # column-major for glTF
        if p >= 0:
            g.doc.nodes[bone_node[p]].children.append(bone_node[j])
    ibm_acc = g.accessor(ibm.reshape(J, 16), gl.FLOAT, gl.MAT4)
    g.doc.skins.append(gl.Skin(name="anny_skin", joints=bone_node, skeleton=bone_node[0], inverseBindMatrices=ibm_acc))
    g.doc.scenes.append(gl.Scene(nodes=[0]))
    g.doc.scene = 0
    g.finish(a.out / "anny_base.glb")

    # Joint tables in Y-up, one row per target, parallel to the morph target order.
    heads0 = zup_to_yup(model.template_bone_heads.numpy()).astype(np.float32)
    heads = np.stack([zup_to_yup(hd) for _, _, hd, _, _ in targets]).astype(np.float32)
    M0 = np.stack([conj(m) for m in model.bone_template_orientation_matrices.numpy()]).astype(np.float32)
    dM = np.stack([np.stack([conj(m) for m in md]) for _, _, _, md, _ in targets]).astype(np.float32)
    for fname, arr in (("heads0.f32", heads0), ("heads.f32", heads), ("M0.f32", M0), ("dM.f32", dM)):
        (a.out / fname).write_bytes(np.ascontiguousarray(arr).tobytes())

    anchors = {k: [float(x) for x in model.anchors[k].numpy()] for k in ["age", "gender", "muscle", "weight", "height", "proportions"]}
    tables = {
        "vertex_count": int(V), "face_count": int(faces.shape[0]), "bone_count": int(J), "target_count": int(T),
        "free_axes": FREE_AXES,
        "free_slots": free_names,
        "axis_slots": {ax: [free_names.index(n) for n in PHENOTYPE_VARIATIONS[ax]] for ax in FREE_AXES},
        "anchors": anchors,
        "targets": [{"name": n, "kind": ("macro" if s is not None else ("facial" if not n.startswith("lc_") else "local")),
                     "slots": s} for n, _, _, _, s in targets],
        "local_dials": [{"name": nm, "group": group_of.get(nm, "other"), "pos": pi, "neg": ni}
                        for nm, pi, ni in local_pairs],
        "facial": [{"source": src, "name": facs[src], "index": names_out.index(facs[src])} for src in model.facial_action_labels],
        "bone_labels": list(model.bone_labels), "bone_parents": [int(p) for p in parents],
        "skin_dropped_max": float(dropped.max()),
    }
    (a.out / "anny_tables.json").write_text(json.dumps(tables, indent=1))

    # Parity cases: the Python model's rest answer for seeded parameter vectors.
    rng = np.random.default_rng(a.seed)
    cases = []
    expected = []
    for _ in range(a.cases):
        ph_kw = {k: float(rng.uniform(0, 1)) for k in FREE_AXES}
        lc_kw = {local_names[i]: float(rng.uniform(-1, 1)) for i in rng.choice(len(local_names), 10, replace=False)}
        fa_kw = {model.facial_action_labels[i]: float(rng.uniform(0, 1)) for i in rng.choice(52, 5, replace=False)}
        pp, ph, lc, fa = model.get_tensor_inputs(None, ph_kw, lc_kw, fa_kw)
        co = model._get_phenotype_blendshape_coefficients(ph, lc, fa)
        r = model.get_rest_model(co)
        v = zup_to_yup(r["rest_vertices"][0].numpy()).astype(np.float32)
        gz = r["rest_bone_poses"][0].numpy()
        gy = np.zeros((J, 4, 4), dtype=np.float32)
        for j in range(J):
            gy[j, :3, :3] = conj(gz[j, :3, :3])
            gy[j, :3, 3] = zup_to_yup(gz[j, :3, 3])
            gy[j, 3, 3] = 1.0
        cases.append({"phenotype": ph_kw, "local": lc_kw,
                      "facial": {facs[k]: val for k, val in fa_kw.items()}})
        expected.append(np.concatenate([v.reshape(-1), gy.reshape(-1)]))
    (a.out / "parity_cases.json").write_text(json.dumps({"cases": cases, "stride": int(V * 3 + J * 16)}, indent=1))
    (a.out / "parity_expected.f32").write_bytes(np.stack(expected).astype(np.float32).tobytes())

    print("verts %d faces %d bones %d targets %d (macro %d, facial %d, local %d)" % (
        V, faces.shape[0], J, T, len(keys), n_fa, len(labels) - n_macro - n_fa))
    print("wrote", a.out / "anny_base.glb", "%.1f MB" % ((a.out / "anny_base.glb").stat().st_size / 1e6))


if __name__ == "__main__":
    main()
