class_name PaperHouse
extends RefCounted
## A paper-box building on the map (`PaperHouse.setup(houses.json, art folder)`): a box of walls painted
## with flat elevation drawings (<art>/house_<name>_front / _side / _back.png, cut by
## scripts/slice_assets.py), a gable roof of a tiled texture (roof_tile / roof_thatch) overhanging them,
## and its edges drawn as square ink beams (eaves, verges, ridge, corners): the thick outline. Its front faces
## south (+z); the camera can go all the way round it.

const OVERHANG := 0.3  # metres the roof reaches past the walls
const ROOF_TILE := 2.5  # metres a roof tile covers
const OUTLINE := 0.22  # metres thick, the ink beams along its edges

static var _specs := {}
static var _mats := {}
static var art := "res://paper_map/art"
static var specs_path := "res://paper_map/houses.json"


## Where the buildings' sizes (houses.json) and their drawings are.
static func setup(houses_json: String, art_dir: String) -> void:
	specs_path = houses_json
	art = art_dir
	_specs = {}
	_mats = {}


static func specs() -> Dictionary:
	if _specs.is_empty() and FileAccess.file_exists(specs_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(specs_path))
		if d is Dictionary:
			_specs = d
	return _specs


static func is_house(sprite: String) -> bool:
	return specs().has(sprite) and ResourceLoader.exists("%s/house_%s_front.png" % [art, sprite])


## Its footprint in metres (width across, depth front to back) and its height to the ridge.
static func size_of(sprite: String) -> Vector3:
	var s: Dictionary = specs()[sprite]
	return Vector3(float(s["w"]), float(s["h"]) + float(s["rise"]), float(s["d"]))


## The building as a node: its origin at the middle of its front wall's foot.
static func build(sprite: String, fog: Vector2) -> Node3D:
	var s: Dictionary = specs()[sprite]
	var w := float(s["w"])
	var d := float(s["d"])
	var h := float(s["h"])
	var rise := float(s["rise"])
	var node := Node3D.new()
	var walls := ArrayMesh.new()
	_walls(walls, w, d, h, rise)
	var roof := _roof(w, d, h, rise)
	var body := MeshInstance3D.new()
	body.mesh = walls
	for i in 3:
		body.set_surface_override_material(i, _mat("%s/house_%s_%s.png" % [art, sprite, ["front", "side", "back"][i]], fog))
	body.position = Vector3(0, 0, -d * 0.5)
	node.add_child(body)
	var top := MeshInstance3D.new()
	top.mesh = roof
	top.material_override = _mat("%s/roof_%s.png" % [art, s["roof"]], fog)
	top.position = body.position
	node.add_child(top)
	var ink := MeshInstance3D.new()  # its edges in ink
	ink.mesh = _edges(w, d, h, rise)
	ink.material_override = _ink()
	ink.position = body.position
	node.add_child(ink)
	return node


static func _mat(path: String, fog: Vector2) -> ShaderMaterial:
	if not _mats.has(path):
		var m := ShaderMaterial.new()
		m.shader = load("res://paper_map/shaders/house.gdshader")
		m.set_shader_parameter("tex", load(path))
		m.set_shader_parameter("fog_near", fog.x)
		m.set_shader_parameter("fog_far", fog.y)
		_mats[path] = m
	return _mats[path]


static func _ink() -> ShaderMaterial:
	if not _mats.has("ink"):
		var m := ShaderMaterial.new()
		m.shader = load("res://paper_map/shaders/outline.gdshader")
		_mats["ink"] = m
	return _mats["ink"]


## The building's edges as square ink beams: the eaves and the verges of the roof, its ridge, the four
## corners of the walls and their foot.
static func _edges(w: float, d: float, h: float, rise: float) -> ArrayMesh:
	var hw := w * 0.5
	var hd := d * 0.5
	var slope := rise / hd
	var ew := hw + OVERHANG
	var ez := hd + OVERHANG
	var ey := h - OVERHANG * slope
	var top := h + rise
	var lines := [
		[Vector3(-ew, ey, ez), Vector3(ew, ey, ez)], [Vector3(-ew, ey, -ez), Vector3(ew, ey, -ez)],  # eaves
		[Vector3(-ew, top, 0), Vector3(ew, top, 0)],  # ridge
		[Vector3(-ew, ey, ez), Vector3(-ew, top, 0)], [Vector3(ew, ey, ez), Vector3(ew, top, 0)],  # verges
		[Vector3(-ew, ey, -ez), Vector3(-ew, top, 0)], [Vector3(ew, ey, -ez), Vector3(ew, top, 0)],
		[Vector3(-hw, 0, hd), Vector3(-hw, h, hd)], [Vector3(hw, 0, hd), Vector3(hw, h, hd)],  # corners
		[Vector3(-hw, 0, -hd), Vector3(-hw, h, -hd)], [Vector3(hw, 0, -hd), Vector3(hw, h, -hd)],
		[Vector3(-hw, 0.05, hd), Vector3(hw, 0.05, hd)], [Vector3(-hw, 0.05, -hd), Vector3(hw, 0.05, -hd)],  # feet
		[Vector3(-hw, 0.05, hd), Vector3(-hw, 0.05, -hd)], [Vector3(hw, 0.05, hd), Vector3(hw, 0.05, -hd)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l in lines:
		_beam(st, l[0], l[1], OUTLINE)
	return st.commit()


## A square beam `t` thick from a to b (all six faces).
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, t: float) -> void:
	var along := (b - a).normalized()
	var u := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized() * t * 0.5
	var v := along.cross(u).normalized() * t * 0.5
	a -= along * t * 0.5
	b += along * t * 0.5
	var c := [a - u - v, a + u - v, a + u + v, a - u + v, b - u - v, b + u - v, b + u + v, b - u + v]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c[f[i]])


## Three surfaces: the front wall, the two gable ends, the back wall (centred on the footprint).
static func _walls(mesh: ArrayMesh, w: float, d: float, h: float, rise: float) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)  # front, facing +z
	_quad(st, Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(hw, h, hd), Vector3(-hw, h, hd), Vector3(0, 0, 1))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)  # the gable ends: the wall and its triangle up to the ridge, one drawing
	var g := rise / (h + rise)  # where the eaves line falls on the drawing (from the top)
	for side: float in [-1.0, 1.0]:
		var x := hw * side
		var n := Vector3(side, 0, 0)
		var a := Vector3(x, 0, hd * side)
		var b := Vector3(x, 0, -hd * side)
		_quad(st, a, b, Vector3(x, h, -hd * side), Vector3(x, h, hd * side), n, g)
		for p in [[Vector3(x, h, hd * side), Vector2(0, g)], [Vector3(x, h + rise, 0), Vector2(0.5, 0)], [Vector3(x, h, -hd * side), Vector2(1, g)]]:
			st.set_normal(n)
			st.set_uv(p[1])
			st.add_vertex(p[0])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)  # back, facing -z
	_quad(st, Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3(0, 0, -1))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())


## The two slopes of the roof, overhanging the walls all round, the tiles running down the slope.
static func _roof(w: float, d: float, h: float, rise: float) -> ArrayMesh:
	var hw := w * 0.5 + OVERHANG
	var hd := d * 0.5
	var slope := rise / hd
	var eave_z := hd + OVERHANG
	var eave_y := h - OVERHANG * slope
	var ridge := Vector3(0, h + rise, 0)
	var run := Vector2(eave_z, h + rise - eave_y).length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:
		var n := Vector3(0, eave_z, side * (h + rise - eave_y)).normalized()
		var e0 := Vector3(-hw * side, eave_y, eave_z * side)
		var e1 := Vector3(hw * side, eave_y, eave_z * side)
		var r1 := Vector3(hw * side, ridge.y, 0)
		var r0 := Vector3(-hw * side, ridge.y, 0)
		var u := w / ROOF_TILE
		var v := run / ROOF_TILE
		for p in [[e0, Vector2(0, v)], [r1, Vector2(u, 0)], [e1, Vector2(u, v)], [e0, Vector2(0, v)], [r0, Vector2(0, 0)], [r1, Vector2(u, 0)]]:
			st.set_normal(n)
			st.set_uv(p[1])
			st.add_vertex(p[0])
	return st.commit()


## A wall quad a, b (feet, left to right seen from outside), c, d (tops), its drawing from `top` down.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, top := 0.0) -> void:
	for p in [[a, Vector2(0, 1)], [c, Vector2(1, top)], [b, Vector2(1, 1)], [a, Vector2(0, 1)], [d, Vector2(0, top)], [c, Vector2(1, top)]]:  # clockwise: Godot's front
		st.set_normal(n)
		st.set_uv(p[1])
		st.add_vertex(p[0])
