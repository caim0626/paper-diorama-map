class_name PaperRegion
extends RefCounted
## One sheet of the map (a JSON file, see the kit's README): the places and the roads between them, on a
## flat plan of `size` sheet pixels (PaperTerrain.M metres each), and the land under them (`terrain`).
## A road is a line through its `via` points.
##
## Places: {id, kind, name, at}; any other keys are the game's own and kept as they are.

var id := ""
var name := ""
var size := Vector2(768, 432)
var start := ""
var places := {}  # id -> place
var order: Array[String] = []  # places in the file's order
var roads: Array[Dictionary] = []  # {a, b, pts (a .. b), length}
var terrain := {}  # the land under it (PaperTerrain): terraces, the mountain, the river, the woods
var errors: Array[String] = []


static func load_file(path: String) -> PaperRegion:
	var r := PaperRegion.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		r.errors.append("%s: not a region" % path)
		return r
	r.id = data.get("id", "")
	r.name = data.get("name", "")
	r.size = _v(data.get("size", [768, 432]))
	r.start = data.get("start", "")
	r.terrain = data.get("terrain", {})
	for p in data.get("places", []):
		var place: Dictionary = p.duplicate(true)
		place["at"] = _v(p["at"])
		r.places[place["id"]] = place
		r.order.append(place["id"])
	for road in data.get("roads", []):
		if not r.places.has(road["a"]) or not r.places.has(road["b"]):
			r.errors.append("road %s-%s: no such place" % [road["a"], road["b"]])
			continue
		var pts := PackedVector2Array([r.places[road["a"]]["at"]])
		for v in road.get("via", []):
			pts.append(_v(v))
		pts.append(r.places[road["b"]]["at"])
		r.roads.append({"a": road["a"], "b": road["b"], "pts": pts, "length": _length(pts)})
	if not r.places.has(r.start):
		r.errors.append("no start place")
	return r


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## The roads leaving a place: [{road (index), to, dir (unit vector of the first stretch)}].
func roads_from(pid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in roads.size():
		var r: Dictionary = roads[i]
		if r["a"] != pid and r["b"] != pid:
			continue
		var pts := line(i, pid)
		out.append({"road": i, "to": r["b"] if r["a"] == pid else r["a"], "dir": (pts[1] - pts[0]).normalized()})
	return out


## A road's line starting from the place `from`.
func line(road: int, from: String) -> PackedVector2Array:
	var pts: PackedVector2Array = roads[road]["pts"]
	if roads[road]["a"] == from:
		return pts
	var back := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		back.append(pts[i])
	return back


## The point `s` map pixels along a road from its `a` end, and which way the road runs there (toward `b`).
func at(road: int, s: float) -> Vector2:
	return _walk_to(road, s)[0]


func heading(road: int, s: float) -> Vector2:
	return _walk_to(road, s)[1]


func _walk_to(road: int, s: float) -> Array:
	var pts: PackedVector2Array = roads[road]["pts"]
	var left := clampf(s, 0.0, float(roads[road]["length"]))
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			var dir := (pts[i + 1] - pts[i]).normalized()
			return [pts[i] + dir * minf(left, seg), dir]
		left -= seg
	return [pts[pts.size() - 1], Vector2.RIGHT]


## Every place can be reached from the start (hidden ones included): the sheet is whole.
func connected() -> bool:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var p: String = todo.pop_back()
		for r in roads_from(p):
			if not seen.has(r["to"]):
				seen[r["to"]] = true
				todo.append(r["to"])
	for pid in order:
		if places[pid]["kind"] != "heard" and not seen.has(pid):
			return false
	return true
