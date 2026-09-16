class_name AnnyCoeffs
extends RefCounted

# Sliders to the coefficient vector every target shares: a phenotype axis value becomes weights
# over its anchors, a macro target's weight is the product over the slots its name carries, a
# local dial splits into its positive and negative halves, a facial action passes through.

const AXES := ["gender", "age", "muscle", "weight", "height", "proportions"]


static func interp(value: float, anchors: Array) -> PackedFloat32Array:
	var n := anchors.size()
	var w := PackedFloat32Array()
	w.resize(n)
	var idx := 1
	while idx < n - 1 and float(anchors[idx]) < value:
		idx += 1
	var lo := float(anchors[idx - 1])
	var hi := float(anchors[idx])
	var alpha := clampf((value - lo) / (hi - lo), 0.0, 1.0)
	w[idx - 1] = 1.0 - alpha
	w[idx] = alpha
	return w


static func slot_values(tables: AnnyTables, phenotype: Dictionary) -> PackedFloat32Array:
	var phens := PackedFloat32Array()
	phens.resize(tables.free_slots.size())
	for axis in AXES:
		var v: float = float(phenotype.get(axis, 0.5))
		var w := interp(v, tables.anchors[axis])
		var slots: Array = tables.axis_slots[axis]
		for k in slots.size():
			phens[int(slots[k])] = w[k]
	return phens


static func coefficients(tables: AnnyTables, phenotype: Dictionary, local: Dictionary,
		facial: Dictionary) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(tables.target_count)
	var phens := slot_values(tables, phenotype)
	for t in tables.target_count:
		var slots = tables.target_slots[t]
		if slots == null:
			continue
		var w := 1.0
		for s in slots:
			w *= phens[int(s)]
		c[t] = w
	for dial in tables.meta["local_dials"]:
		var v: float = float(local.get(dial["name"], 0.0))
		c[int(dial["pos"])] = maxf(v, 0.0)
		c[int(dial["neg"])] = maxf(-v, 0.0)
	for f in tables.meta["facial"]:
		c[int(f["index"])] = float(facial.get(f["name"], 0.0))
	return c
