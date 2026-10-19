class_name PaperMapView
extends Control
## A paper-diorama map on screen: the region as a small 3D land (PaperTerrain) with paper cut-outs standing on
## it, paper-box buildings (PaperHouse), and a walker the player moves freely with WASD; the camera follows
## from above and behind, Q / E turn it round, the wheel zooms. Top right a corner map; M opens the whole map,
## where a click on a visited place goes there. The game listens to `near_changed` (a place the walker stands
## by: show "J go in") and `interact` (J pressed there), and keeps its own state; this node only shows and walks.
##
## Files it reads (all under `root`, default res://paper_map):
##   art/<sprite>.png + art/sprites.json   cut-outs and their pixel sizes (scripts/slice_assets.py)
##   art/ground|road|cliff|meadow.png      ground tiles; art/house_* and art/roof_* for PaperHouse
##   kinds.json   {"kinds": {sprite: {"tall": metres, "sway": metres}}, "woods": [sprite, ...],
##                 "walker": {"png": "art/walker.png", "frames": 4, "tall": 4.2}}   (walker strip: down, up, left, right)
##   houses.json  PaperHouse's building sizes

signal near_changed(place: String)  # "" when he walks away from it
signal interact(place: String)

const PAPER := Color("f3ead6")
const INK := Color("1d1b1e")
const RED := Color("c2321f")
const PITCH := 38.0  # degrees the camera looks down
const FOV := 40.0
const ZOOM := Vector2(16.0, 44.0)  # metres from the walker, nearest .. furthest
const FOG := Vector2(30.0, 80.0)
const TURN := PI / 4.0
const SPEED := 30.0  # sheet pixels a second
const NEAR_PX := 16.0  # sheet pixels from a place within which it is "near"
const MAP_SIZE := Vector2i(1600, 900)
const MAP_PITCH := 58.0
const MINI := Rect2(1500, 40, 380, 240)

@export var root := "res://paper_map"
@export var enterable := ["building", "sight"]  # place kinds the walker can go into

var region: PaperRegion
var terrain: PaperTerrain
var at := Vector2.ZERO  # the walker, in sheet pixels
var near := ""
var visited := {}
var zoom := 30.0
var yaw := 0.0  # 0: the camera south of him, looking north
var map_open := false
var _yaw_to := 0.0
var _kinds := {}
var _woods: Array = []
var _sizes := {}
var _walker_cfg := {}
var _vp: SubViewport
var _cam: Camera3D
var _map_vp: SubViewport
var _map_cam: Camera3D
var _map_tex: Texture2D
var _root3d: Node3D
var _quad: QuadMesh
var _mats := {}
var _blob: ShaderMaterial
var _walker: MeshInstance3D
var _walker_mat: ShaderMaterial
var _facing := 0  # row: down, up, left, right
var _stride := 0.0
var _focus := Vector3.ZERO
var _snap := true
var _tops := {}  # place -> where its name slip hangs (world)
var _font: Font


func _ready() -> void:
	size = Vector2(1920, 1080)
	_font = ThemeDB.fallback_font
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(root + "/kinds.json"))
	if cfg is Dictionary:
		_kinds = cfg.get("kinds", {})
		_woods = cfg.get("woods", [])
		_walker_cfg = cfg.get("walker", {})
	var meta = JSON.parse_string(FileAccess.get_file_as_string(root + "/art/sprites.json"))
	if meta is Dictionary:
		_sizes = meta
	PaperHouse.setup(root + "/houses.json", root + "/art")
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.world_3d = World3D.new()
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = PAPER
	_vp.add_child(env)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 200.0
	_vp.add_child(_cam)
	_map_vp = SubViewport.new()
	_map_vp.size = MAP_SIZE
	_map_vp.world_3d = _vp.world_3d
	_map_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_map_vp)
	_map_cam = Camera3D.new()
	_map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_cam.cull_mask = 1  # not the walker (layer 2)
	_map_cam.far = 600.0
	_map_vp.add_child(_map_cam)
	_quad = QuadMesh.new()
	_quad.center_offset = Vector3(0, 0.5, 0)
	_blob = ShaderMaterial.new()
	_blob.shader = load(root + "/shaders/blob.gdshader")


## Builds the land of a region file and puts the walker at one of its places.
func open(region_json: String, start := "") -> void:
	region = PaperRegion.load_file(region_json)
	for e in region.errors:
		push_error(e)
	terrain = PaperTerrain.build(region)
	if _root3d:
		_root3d.queue_free()
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	_mats.clear()
	_tops.clear()
	_build()
	warp(start if start != "" else region.start)


## Straight to a place (the big map's click, a door out of another sheet).
func warp(pid: String) -> void:
	at = region.places[pid]["at"]
	visited[pid] = true
	map_open = false
	_snap = true
	_set_near(pid)


func _build() -> void:
	var ground := MeshInstance3D.new()
	ground.mesh = terrain.mesh()
	var gm := ShaderMaterial.new()
	gm.shader = load(root + "/shaders/terrain.gdshader")
	for t in ["ground", "road", "cliff", "meadow"]:
		gm.set_shader_parameter(t, load("%s/art/%s.png" % [root, t]))
	gm.set_shader_parameter("mask", ImageTexture.create_from_image(terrain.road_mask))
	gm.set_shader_parameter("size_m", region.size * PaperTerrain.M)
	gm.set_shader_parameter("fog_near", FOG.x)
	gm.set_shader_parameter("fog_far", FOG.y)
	ground.material_override = gm
	_root3d.add_child(ground)
	if region.terrain.has("river"):
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = (region.size + Vector2.ONE * PaperTerrain.MARGIN * 2) * PaperTerrain.M
		water.mesh = plane
		water.position = Vector3(plane.size.x * 0.5, -0.9, plane.size.y * 0.5)
		var wm := ShaderMaterial.new()
		wm.shader = load(root + "/shaders/water.gdshader")
		wm.set_shader_parameter("fog_near", FOG.x)
		wm.set_shader_parameter("fog_far", FOG.y)
		water.material_override = wm
		_root3d.add_child(water)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region.id)
	for p in terrain.trees:
		if not _woods.is_empty():
			_stand(_woods[rng.randi() % _woods.size()], p, rng.randf_range(0.85, 1.2), rng.randf() < 0.5)
	for s in terrain.scattered:
		_stand(s["sprite"], s["at"], rng.randf_range(0.8, 1.15), rng.randf() < 0.5)
	for pc in region.terrain.get("pieces", []):
		var p := Vector2(pc["at"][0], pc["at"][1])
		var sprite: String = pc["sprite"]
		if PaperHouse.is_house(sprite):
			var house := PaperHouse.build(sprite, FOG)
			house.position = terrain.world(p)
			_root3d.add_child(house)
			if pc.has("for"):
				var sz := PaperHouse.size_of(sprite)
				_tops[pc["for"]] = house.position + Vector3(0, sz.y, -sz.z * 0.5)
		elif _stand(sprite, p) and pc.has("for"):
			_tops[pc["for"]] = terrain.world(p) + Vector3(0, _tall(sprite), 0)
	_walker_mat = ShaderMaterial.new()
	_walker_mat.shader = load(root + "/shaders/card.gdshader")
	var strip: Texture2D = load(root + "/" + str(_walker_cfg.get("png", "art/walker.png")))
	_walker_mat.set_shader_parameter("tex", strip)
	_walker_mat.set_shader_parameter("near_fade", Vector2(0.1, 0.3))
	_walker_mat.set_shader_parameter("fog_near", FOG.x)
	_walker_mat.set_shader_parameter("fog_far", FOG.y)
	var frames := int(_walker_cfg.get("frames", 4)) * 4
	var tall := float(_walker_cfg.get("tall", 4.2))
	_walker = _card(_walker_mat, Vector2(tall * strip.get_width() / frames / strip.get_height(), tall))
	_walker.layers = 2
	_take_map()


func _tall(sprite: String) -> float:
	return float(_kinds.get(sprite, {}).get("tall", 2.0))


## A cut-out standing on the ground at a point of the sheet.
func _stand(sprite: String, p: Vector2, scale := 1.0, flip := false) -> MeshInstance3D:
	if not _sizes.has(sprite):
		return null
	if not _mats.has(sprite):
		var m := ShaderMaterial.new()
		m.shader = load(root + "/shaders/card.gdshader")
		m.set_shader_parameter("tex", load("%s/art/%s.png" % [root, sprite]))
		m.set_shader_parameter("fog_near", FOG.x)
		m.set_shader_parameter("fog_far", FOG.y)
		m.set_shader_parameter("near_fade", Vector2(0.2, 0.8))
		m.set_shader_parameter("sway", float(_kinds.get(sprite, {}).get("sway", 0.0)))
		_mats[sprite] = m
	var px: Array = _sizes[sprite]
	var tall := _tall(sprite) * scale
	var wide := tall * float(px[0]) / float(px[1])
	var node := _card(_mats[sprite], Vector2(wide, tall), flip)
	node.position = terrain.world(p)
	if not terrain.steep(p):  # on a slope a flat shadow would cut into the ground
		var sh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(wide * 0.55, wide * 0.2)
		sh.mesh = plane
		sh.material_override = _blob
		sh.position = node.position + Vector3(0, 0.06, 0)
		_root3d.add_child(sh)
	return node


func _card(mat: Material, size_m: Vector2, flip := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.scale = Vector3(-size_m.x if flip else size_m.x, size_m.y, 1.0)
	_root3d.add_child(mi)
	return mi


## The whole sheet from high up, once, with the fog lifted: the big map and the corner map.
func _take_map() -> void:
	var size_m := region.size * PaperTerrain.M
	var pitch := deg_to_rad(MAP_PITCH)
	var centre := Vector3(size_m.x * 0.5, 2.0, size_m.y * 0.5)
	_map_cam.size = maxf(size_m.y * sin(pitch) + 12.0, (size_m.x + 4.0) * float(MAP_SIZE.y) / float(MAP_SIZE.x))
	_map_cam.position = centre + Vector3(0, sin(pitch), cos(pitch)) * 200.0
	_map_cam.look_at(centre, Vector3.UP)
	if DisplayServer.get_name() == "headless":
		return
	var mats: Array = []  # every material on the land: the ground and the water too
	for n in _root3d.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ms: Array = [mi.material_override]
		for i in mi.get_surface_override_material_count():
			ms.append(mi.get_surface_override_material(i))
		for m in ms:
			if m is ShaderMaterial and not mats.has(m) and m != _blob and m.shader.resource_path.get_file() != "outline.gdshader":
				mats.append(m)
	for m in mats:
		m.set_shader_parameter("fog_near", 5000.0)
		m.set_shader_parameter("fog_far", 6000.0)
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_map_tex = ImageTexture.create_from_image(_map_vp.get_texture().get_image())
	for m in mats:
		m.set_shader_parameter("fog_near", FOG.x)
		m.set_shader_parameter("fog_far", FOG.y)


# ------------------------------------------------------------------ input and every frame

func _unhandled_input(event: InputEvent) -> void:
	if region == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				map_open = not map_open and _map_tex != null
			KEY_ESCAPE:
				map_open = false
			KEY_Q:
				_yaw_to += TURN
			KEY_E:
				_yaw_to -= TURN
			KEY_J, KEY_SPACE, KEY_ENTER:
				if near != "" and not map_open:
					interact.emit(near)
	elif event is InputEventMouseButton and event.pressed:
		if map_open and event.button_index == MOUSE_BUTTON_LEFT:
			var pid := map_pick(event.position)
			if pid != "":
				warp(pid)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom - 2.0, ZOOM.x)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom + 2.0, ZOOM.y)


func _process(delta: float) -> void:
	if region == null:
		return
	var stick := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if stick != Vector2.ZERO and not map_open:
		roam(stick, delta)
	var me := terrain.world(at)
	_walker.position = me
	var per := int(_walker_cfg.get("frames", 4))
	var frame := _facing * per + (int(_stride / 7.0) % per if stick != Vector2.ZERO else 0)
	_walker_mat.set_shader_parameter("region", Vector4(float(frame) / (per * 4), 0.0, 1.0 / (per * 4), 1.0))
	var goal := me + Vector3(0, 1.2, 0)
	_focus = goal if _snap else _focus.lerp(goal, 1.0 - exp(-5.0 * delta))
	_snap = false
	yaw = lerp_angle(yaw, _yaw_to, 1.0 - exp(-9.0 * delta))
	var pitch := deg_to_rad(PITCH)
	_cam.position = _focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * zoom
	_cam.look_at(_focus, Vector3.UP)
	var eye := _cam.unproject_position(me + Vector3(0, 2.0, 0))  # what stands in front of him thins out
	var hole := Vector3(eye.x, eye.y, _cam.global_position.distance_to(me))
	for m in _mats.values() + PaperHouse._mats.values():
		m.set_shader_parameter("hole", hole)
		m.set_shader_parameter("hole_r", 170.0)
	queue_redraw()


## Walks `delta` seconds: `stick` is the way on the screen (x right, y down), turned by the camera; he stops
## at cliffs, water, buildings and woods, sliding along them.
func roam(stick: Vector2, delta: float) -> void:
	var way := Vector2(cos(yaw) * stick.x + sin(yaw) * stick.y, -sin(yaw) * stick.x + cos(yaw) * stick.y)
	var step := way.limit_length(1.0) * SPEED * delta
	var to := at + step
	if not terrain.walkable(to):
		to = at + Vector2(step.x, 0.0)
		if not terrain.walkable(to):
			to = at + Vector2(0.0, step.y)
			if not terrain.walkable(to):
				to = at
	_facing = (3 if stick.x > 0 else 2) if absf(stick.x) > absf(stick.y) else (0 if stick.y > 0 else 1)
	_stride += at.distance_to(to)
	at = to
	var best := ""
	var d := NEAR_PX
	for pid in region.order:
		var p: Dictionary = region.places[pid]
		if p["kind"] in enterable and at.distance_to(p["at"]) < d:
			d = at.distance_to(p["at"])
			best = pid
	_set_near(best)


func _set_near(pid: String) -> void:
	if pid != near:
		near = pid
		if pid != "":
			visited[pid] = true
		near_changed.emit(pid)


# ------------------------------------------------------------------ drawing over the land

func _on_map(p: Vector2) -> Vector2:
	return _map_cam.unproject_position(terrain.world(p))


func _map_rect() -> Rect2:
	var w := 1700.0
	return Rect2(Vector2((1920.0 - w) * 0.5, 120.0), Vector2(w, w * float(MAP_SIZE.y) / float(MAP_SIZE.x)))


## The visited place under a point of the screen on the big map ("" none).
func map_pick(screen: Vector2) -> String:
	var r := _map_rect()
	var best := ""
	var d := 36.0
	for pid in visited:
		var q := r.position + _on_map(region.places[pid]["at"]) * r.size.x / float(MAP_SIZE.x)
		if q.distance_to(screen) < d:
			d = q.distance_to(screen)
			best = pid
	return best


func _draw() -> void:
	if region == null:
		return
	draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	if near != "":  # the place he stands by: its name over it, a ring on the ground
		var top: Vector3 = _tops.get(near, terrain.world(region.places[near]["at"]) + Vector3(0, 4, 0))
		_slip(_cam.unproject_position(top) - Vector2(0, 54), str(region.places[near]["name"]), true)
		var c := _cam.unproject_position(terrain.world(region.places[near]["at"]))
		var pts := PackedVector2Array()
		for s in 41:
			pts.append(c + Vector2(cos(s * TAU / 40.0), sin(s * TAU / 40.0) * 0.55) * 50.0)
		draw_polyline(pts, RED, 4.0)
	if _map_tex and not map_open:  # the corner map round him
		var me := _on_map(at)
		var src := Rect2(me - MINI.size * 0.5, MINI.size)
		src.position = src.position.clamp(Vector2.ZERO, Vector2(MAP_SIZE) - src.size)
		draw_rect(MINI.grow(10), PAPER)
		draw_texture_rect_region(_map_tex, MINI, src)
		draw_rect(MINI.grow(10), INK, false, 4.0)
		var p := MINI.position + me - src.position
		var ahead := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-ahead.y, ahead.x)
		draw_colored_polygon(PackedVector2Array([p + ahead * 14.0, p - ahead * 8.0 + side * 9.0, p - ahead * 8.0 - side * 9.0]), RED)
	if map_open:  # the whole map: visited places named, a click goes there
		draw_rect(Rect2(Vector2.ZERO, size), Color(PAPER, 0.97))
		var r := _map_rect()
		draw_texture_rect(_map_tex, r, false)
		draw_rect(r.grow(6), INK, false, 5.0)
		var k := r.size.x / float(MAP_SIZE.x)
		for pid in visited:
			_slip(r.position + _on_map(region.places[pid]["at"]) * k + Vector2(0, 8), str(region.places[pid]["name"]), false)
		draw_circle(r.position + _on_map(at) * k, 9.0, RED)


func _slip(p: Vector2, text: String, picked: bool) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 28.0
	var box := Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 46))
	draw_rect(box, Color(PAPER, 0.94))
	draw_rect(box, RED if picked else INK, false, 4.0)
	draw_string(_font, box.position + Vector2(14, 33), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, RED if picked else INK)
