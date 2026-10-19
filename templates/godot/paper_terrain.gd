class_name PaperTerrain
extends RefCounted
## The land of one sheet of the map, built from its region file (`terrain`): flat terraces with
## cliffs between them, the mountain rising in a corner, the river cut through, the woods along the edges.
## Everything is in the sheet's own pixels (the places' and roads' coordinates); M metres to a pixel in 3D.
## Where a road runs, the ground is smoothed so the road ramps up a cliff instead of stepping.

const M := 0.25  # metres in a pixel of the sheet
const STEP := 2  # sheet pixels between height samples
const ROAD_HALF := 4.0  # sheet pixels: half a road's width
const RAMP := 32  # sheet pixels: how far a road's smoothing reaches (the length of its ramps)
const TREE_EVERY := 9.0  # sheet pixels between trees in a wood
const CLEAR := 10.0  # sheet pixels kept free of trees round a road or a place
const MARGIN := 80  # sheet pixels of land beyond the sheet's edges: it rises into a wooded rim, so the land never ends in view
const RIM_RISE := 0.07  # metres the rim rises a sheet pixel out from the edge

var region: PaperRegion
var w := 0  # samples across
var h := 0  # samples down
var heights := PackedFloat32Array()
var road_mask: Image  # one texel a sheet pixel: r = road, g = water
var trees: Array[Vector2] = []  # where the woods' trees stand (sheet pixels)
var scattered: Array[Dictionary] = []  # {sprite, at}: grass, stones and the like strewn over the open ground
var blockers: Array[Dictionary] = []  # {at, r} (sheet pixels): what the walker cannot walk through — buildings, trees, rocks
## From the region file's `terrain`: `solid` — sprite -> radius (sheet pixels) the walker cannot pass;
## `dress` — building sprite -> the small props set beside it.
var solid := {}
var dress := {}
var _road_d := PackedFloat32Array()  # a sheet pixel's distance to the nearest road or stair (capped)
var _river_d := PackedFloat32Array()  # ... to the river's middle
var _sw := 0
var _sh := 0


static func build(r: PaperRegion) -> PaperTerrain:
	var t := PaperTerrain.new()
	t.region = r
	t.w = (int(r.size.x) + MARGIN * 2) / STEP + 1
	t.h = (int(r.size.y) + MARGIN * 2) / STEP + 1
	t._sw = int(r.size.x) + 1
	t._sh = int(r.size.y) + 1
	t.solid = r.terrain.get("solid", {})
	t.dress = r.terrain.get("dress", {})
	t._road_d = t._field(t.ways(), RAMP + 4.0)
	var river: Dictionary = r.terrain.get("river", {})
	var rl: Array[PackedVector2Array] = [_line(river.get("line", []))]
	t._river_d = t._field(rl, float(river.get("width", 0)) + 8.0)
	t._heights()
	t._mask()
	t._woods()
	t._scatter()
	t._solids()
	return t


## What stands in the walker's way: each building's walls (just behind the point he goes in at), the
## trees, rocks and lanterns strewn about. The woods themselves are kept out by `walkable`.
func _solids() -> void:
	for pc in region.terrain.get("pieces", []):
		var at := Vector2(float(pc["at"][0]), float(pc["at"][1]))
		if PaperHouse.is_house(pc["sprite"]):  # a building's walls (its front wall stands on `at`)
			var sz := PaperHouse.size_of(pc["sprite"]) / M
			blockers.append({"rect": Rect2(at.x - sz.x * 0.5, at.y - sz.z, sz.x, sz.z).grow(1.0)})
			continue
		var r: float = solid.get(pc["sprite"], 9.0)
		blockers.append({"at": at - Vector2(0, r * 0.6) if r > 5.0 else at, "r": r})
	for s in scattered:
		if solid.has(s["sprite"]):
			blockers.append({"at": s["at"], "r": solid[s["sprite"]]})


## Whether the walker can stand at a point of the sheet: on the sheet, not up a cliff, not in the river
## (the causeways are road), not in the woods away from a road, not inside a building or a tree.
func walkable(p: Vector2) -> bool:
	if p.x < 3 or p.y < 3 or p.x > region.size.x - 3 or p.y > region.size.y - 3:
		return false
	var e := 1.5
	var here := height_at(p)
	for d in [Vector2(e, 0), Vector2(-e, 0), Vector2(0, e), Vector2(0, -e)]:
		if absf(height_at(p + d) - here) > 0.6:
			return false
	var on_road := _field_at(_road_d, p) < ROAD_HALF + 2.0
	var river: Dictionary = region.terrain.get("river", {})
	if not on_road and not river.is_empty() and _field_at(_river_d, p) < float(river["width"]) * 0.5 - 1.0:
		return false
	if _field_at(_road_d, p) > 8.0:
		for poly in region.terrain.get("forests", []):
			if Geometry2D.is_point_in_polygon(p, _line(poly)):
				return false
	for b in blockers:
		if b.has("rect"):
			if (b["rect"] as Rect2).has_point(p):
				return false
		elif p.distance_to(b["at"]) < float(b["r"]):
			return false
	return true


## The sheet point of a height sample.
func _at(x: int, y: int) -> Vector2:
	return Vector2(x * STEP - MARGIN, y * STEP - MARGIN)


## Every line drawn as ground to walk on: the roads, and the stairs that are only scenery.
func ways() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for rd in region.roads:
		out.append(rd["pts"])
	for s in region.terrain.get("stairs", []):
		out.append(_line(s))
	return out


func _heights() -> void:
	var tr: Dictionary = region.terrain
	var levels: Array = tr.get("levels", [])
	var polys: Array[PackedVector2Array] = []
	for lv in levels:
		polys.append(_line(lv["poly"]))
	var mt: Dictionary = tr.get("mountain", {})
	var mpoly := _line(mt.get("poly", []))
	var river: Dictionary = tr.get("river", {})
	var raw := PackedFloat32Array()
	raw.resize(w * h)
	for y in h:
		for x in w:
			var p := _at(x, y)
			var z := 0.0
			for i in polys.size():
				var inside := _inside_by(p, polys[i])  # sheet pixels inside the edge (negative: outside)
				if inside > -9.0:
					z = maxf(z, float(levels[i]["h"]) * smoothstep(-3.0, 3.0, inside + _wobble(p * 0.06) * 5.0))
			if mpoly.size() > 2:
				var into := _inside_by(p, mpoly)
				if into > -4.0:
					var k := smoothstep(-2.0, 1.5, into + _wobble(p * 0.07) * 2.5)
					var up := minf(float(mt["h"]) + float(mt["rise"]) * maxf(into, 0.0) + _wobble(p * 0.06) * 2.0, float(mt["top"]))
					z = maxf(z, up * k)
			if not river.is_empty():
				var d := _field_at(_river_d, p)
				var half := float(river["width"]) * 0.5
				if d < half + 3.0:
					z -= float(river["depth"]) * (1.0 - smoothstep(half - 2.0, half + 3.0, d))
			z += _wobble(p * 0.04) * 0.25  # the plain is never quite flat
			var out := maxf(maxf(-p.x, p.x - region.size.x), maxf(-p.y, p.y - region.size.y))
			if out > 0.0:  # past the sheet's edge: a wooded rim rising
				z = maxf(z, out * RIM_RISE * (1.0 + 0.4 * _wobble(p * 0.05)))
			raw[y * w + x] = z
	# the roads: the ground along them is smoothed, so a road crossing a cliff becomes a ramp
	var smooth := _blur(raw, RAMP / STEP)
	smooth = _blur(smooth, RAMP / STEP)
	heights = raw.duplicate()
	for y in h:
		for x in w:
			var d := _field_at(_road_d, _at(x, y))
			if d < RAMP:
				var i := y * w + x
				if raw[i] < -0.4:  # the river: left as it is, but for a causeway just the road's width
					heights[i] = lerpf(raw[i], maxf(smooth[i], -0.3), 1.0 - smoothstep(ROAD_HALF, ROAD_HALF + 2.0, d))
				else:
					heights[i] = lerpf(raw[i], smooth[i], 1.0 - smoothstep(ROAD_HALF + 9.0, RAMP, d))
	for k in 3:
		_defin()


## A sliver of high ground a sample or two wide (left between two roads' ramps) stands up like a fin:
## brought down to the ground round it.
func _defin() -> void:
	var out := heights.duplicate()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var n := [heights[i - 1], heights[i + 1], heights[i - w], heights[i + w]]
			var lower := 0
			var sum := 0.0
			for v in n:
				sum += v
				if heights[i] - v > 0.8:
					lower += 1
			if lower >= 3 or (heights[i] - n[0] > 0.8 and heights[i] - n[1] > 0.8) or (heights[i] - n[2] > 0.8 and heights[i] - n[3] > 0.8):
				out[i] = sum / 4.0
	heights = out


func _mask() -> void:
	road_mask = Image.create(int(region.size.x), int(region.size.y), false, Image.FORMAT_RGBA8)
	var river: Dictionary = region.terrain.get("river", {})
	for y in int(region.size.y):
		for x in int(region.size.x):
			var p := Vector2(x, y)
			var road := 1.0 - smoothstep(ROAD_HALF - 1.0, ROAD_HALF + 1.0, _road_d[y * _sw + x] + _wobble(p * 0.25) * 0.8)
			var water := 0.0
			if not river.is_empty():
				water = 1.0 - smoothstep(float(river["width"]) * 0.5 - 3.0, float(river["width"]) * 0.5 - 1.0, _river_d[y * _sw + x])
			road_mask.set_pixel(x, y, Color(road, water * (1.0 - road), 0.0, 1.0))


func _woods() -> void:
	var keep: Array[Vector2] = []
	for pid in region.order:
		keep.append(region.places[pid]["at"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region.id)
	_rim_woods(rng)
	var river: Dictionary = region.terrain.get("river", {})
	for poly in region.terrain.get("forests", []):
		var pts := _line(poly)
		var box := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			box = box.expand(q)
		var y := box.position.y
		while y <= box.end.y:
			var x := box.position.x + (TREE_EVERY * 0.5 if int(y / TREE_EVERY) % 2 == 1 else 0.0)
			while x <= box.end.x:
				var p := Vector2(x, y) + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
				x += TREE_EVERY
				if not Geometry2D.is_point_in_polygon(p, pts) or p.x < 0 or p.y < 0 or p.x > region.size.x or p.y > region.size.y:
					continue
				var free := _field_at(_road_d, p) >= CLEAR
				for k in keep:
					if free and p.distance_to(k) < CLEAR * 1.6:
						free = false
				if free and not river.is_empty() and _field_at(_river_d, p) < float(river["width"]) * 0.5 + 2.0:
					free = false
				if free:
					trees.append(p)
			y += TREE_EVERY


## The rim beyond the sheet's edges, wooded all round (where no road leaves the sheet).
func _rim_woods(rng: RandomNumberGenerator) -> void:
	var y := -float(MARGIN)
	while y <= region.size.y + MARGIN:
		var x := -float(MARGIN) + (TREE_EVERY * 0.5 if int(y / TREE_EVERY) % 2 == 1 else 0.0)
		while x <= region.size.x + MARGIN:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
			x += TREE_EVERY
			var out := maxf(maxf(-p.x, p.x - region.size.x), maxf(-p.y, p.y - region.size.y))
			if out > -4.0 and _field_at(_road_d, p) >= CLEAR:
				trees.append(p)
		y += TREE_EVERY


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region.id) + 7
	var woods: Array[PackedVector2Array] = []
	for poly in region.terrain.get("forests", []):
		woods.append(_line(poly))
	var river: Dictionary = region.terrain.get("river", {})
	var taken: Array[Vector2] = []
	for pid in region.order:
		taken.append(region.places[pid]["at"])
	for pc in region.terrain.get("pieces", []):
		taken.append(_line([pc["at"]])[0])
	for pc in region.terrain.get("pieces", []):  # beside and before each building, a few of its things
		var kinds: Array = dress.get(pc["sprite"], [])
		var at := Vector2(float(pc["at"][0]), float(pc["at"][1]))
		var wide := 14.0
		if PaperHouse.is_house(pc["sprite"]):
			wide = PaperHouse.size_of(pc["sprite"]).x / M * 0.5 + 4.0
		for kind in kinds:
			for tries in 12:
				var p := at + Vector2(rng.randf_range(-wide, wide), rng.randf_range(-6.0, 6.0))
				if absf(p.x - at.x) < wide - 8.0 and p.y < at.y + 2.0:
					continue  # not inside it, not in front of its door
				if _open(p, woods, river, taken, 3.5):
					taken.append(p)
					scattered.append({"sprite": kind, "at": p})
					break
	var want: Dictionary = region.terrain.get("scatter", {})
	for sprite in want:  # in clumps of a few, as things grow, leaving open ground between
		var n := 0
		var tries := 0
		while n < int(want[sprite]) and tries < 4000:
			tries += 1
			var c := Vector2(rng.randf_range(8, region.size.x - 8), rng.randf_range(8, region.size.y - 8))
			if not _open(c, woods, river, taken, 8.0):
				continue
			if sprite == "reeds" and (river.is_empty() or _field_at(_river_d, c) > float(river["width"]) * 0.5 + 9.0):
				continue  # reeds grow along the river's banks
			for k in rng.randi_range(3, 7):
				var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 11.0)
				if n < int(want[sprite]) and _open(p, woods, river, taken, 3.0):
					taken.append(p)
					scattered.append({"sprite": sprite, "at": p})
					n += 1


## Whether a point of open ground is free for a strewn thing: off the roads and the river, out of the woods,
## not on a slope, and `room` sheet pixels from anything already standing.
func _open(p: Vector2, woods: Array[PackedVector2Array], river: Dictionary, taken: Array[Vector2], room: float) -> bool:
	if p.x < 4 or p.y < 4 or p.x > region.size.x - 4 or p.y > region.size.y - 4:
		return false
	if _field_at(_road_d, p) < 6.0:
		return false
	if not river.is_empty() and _field_at(_river_d, p) < float(river["width"]) * 0.5 + 4.0:
		return false
	for wd in woods:
		if Geometry2D.is_point_in_polygon(p, wd):
			return false
	if steep(p):
		return false
	for q in taken:
		if p.distance_to(q) < room:
			return false
	return true


## Whether the ground slopes hard at a point of the sheet (a cliff, a ramp's side).
func steep(p: Vector2) -> bool:
	var e := float(STEP)
	return absf(height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0))) > 0.45 or absf(height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))) > 0.45


## The ground's height (metres) under a point of the sheet.
func height_at(p: Vector2) -> float:
	var fx := clampf((p.x + MARGIN) / STEP, 0.0, w - 1.001)
	var fy := clampf((p.y + MARGIN) / STEP, 0.0, h - 1.001)
	var x := int(fx)
	var y := int(fy)
	var ax := fx - x
	var ay := fy - y
	var a := lerpf(heights[y * w + x], heights[y * w + x + 1], ax)
	var b := lerpf(heights[(y + 1) * w + x], heights[(y + 1) * w + x + 1], ax)
	return lerpf(a, b, ay)


## A point of the sheet in the 3D world, standing on the ground.
func world(p: Vector2) -> Vector3:
	return Vector3(p.x * M, height_at(p), p.y * M)


func mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in h:
		for x in w:
			var p := _at(x, y)
			st.set_uv(p / region.size)
			var n := _normal(x, y)
			st.set_normal(n)
			st.add_vertex(Vector3(p.x * M, heights[y * w + x], p.y * M))
	for y in h - 1:
		for x in w - 1:
			var i := y * w + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + w)
			st.add_index(i + 1)
			st.add_index(i + w + 1)
			st.add_index(i + w)
	return st.commit()


func _normal(x: int, y: int) -> Vector3:
	var l := heights[y * w + maxi(x - 1, 0)]
	var r := heights[y * w + mini(x + 1, w - 1)]
	var u := heights[maxi(y - 1, 0) * w + x]
	var d := heights[mini(y + 1, h - 1) * w + x]
	return Vector3(l - r, 2.0 * STEP * M, u - d).normalized()


## Each sheet pixel's distance to the nearest of some lines, up to `cap`: stamped a segment at a time.
func _field(lines: Array[PackedVector2Array], cap: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(_sw * _sh)
	f.fill(cap)
	for l in lines:
		for i in l.size() - 1:
			var a := l[i]
			var b := l[i + 1]
			var x0 := maxi(int(minf(a.x, b.x) - cap), 0)
			var x1 := mini(int(maxf(a.x, b.x) + cap), _sw - 1)
			var y0 := maxi(int(minf(a.y, b.y) - cap), 0)
			var y1 := mini(int(maxf(a.y, b.y) + cap), _sh - 1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var p := Vector2(x, y)
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					if d < f[y * _sw + x]:
						f[y * _sw + x] = d
	return f


func _field_at(f: PackedFloat32Array, p: Vector2) -> float:
	return f[clampi(int(p.y + 0.5), 0, _sh - 1) * _sw + clampi(int(p.x + 0.5), 0, _sw - 1)]


func _blur(src: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:  # across, then down: a box blur
		var acc := 0.0
		for x in range(-r, r + 1):
			acc += src[y * w + clampi(x, 0, w - 1)]
		for x in w:
			tmp[y * w + x] = acc / (2 * r + 1)
			acc += src[y * w + clampi(x + r + 1, 0, w - 1)] - src[y * w + clampi(x - r, 0, w - 1)]
	var out := PackedFloat32Array()
	out.resize(w * h)
	for x in w:
		var acc := 0.0
		for y in range(-r, r + 1):
			acc += tmp[clampi(y, 0, h - 1) * w + x]
		for y in h:
			out[y * w + x] = acc / (2 * r + 1)
			acc += tmp[clampi(y + r + 1, 0, h - 1) * w + x] - tmp[clampi(y - r, 0, h - 1) * w + x]
	return out


## How far a point is inside a polygon's edge (sheet pixels; negative outside).
static func _inside_by(p: Vector2, poly: PackedVector2Array) -> float:
	var d := _dist_line(p, poly, true)
	return d if Geometry2D.is_point_in_polygon(p, poly) else -d


static func _dist_line(p: Vector2, pts: PackedVector2Array, closed := false) -> float:
	var best := 1e9
	var n := pts.size()
	for i in (n if closed else n - 1):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


static func _line(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in a:
		out.append(Vector2(float(v[0]), float(v[1])))
	return out


## Smooth value noise in -1 .. 1 (no texture, the same on every machine).
static func _wobble(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y) * 2.0 - 1.0


static func _hash(p: Vector2) -> float:
	var s := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return s - floor(s)
