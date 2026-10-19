# paper-diorama-map

A skill (for Claude Code, Codex and other agents that read `SKILL.md`) and a how-to for building a walkable
**2.5D paper-diorama region map** in Godot 4: real-time heightmap terrain with terraces, cliffs, a river and a
wooded rim, textured with a handful of small tiles; flat pixel-art cut-outs that always face the camera;
paper-box buildings painted with generated wall elevations and outlined in thick ink; free WASD walking with
collision, Q/E camera turning, a corner minimap and an M map with click-to-travel.

The art is parts, not pictures — a few tiles, a sheet of props, three wall drawings per building — and the
layout is JSON, so a new region is data plus a short round of asset generation.

| | |
|---|---|
| [`SKILL.md`](SKILL.md) | the pipeline: sketch → region data → assets → Godot → acceptance on footage, and the pitfalls |
| [`references/data-format.md`](references/data-format.md) | the region file, `houses.json`, `kinds.json`, sizes that worked |
| [`references/asset-prompts.md`](references/asset-prompts.md) | how to brief an image model for tiles, prop grids, building elevations |
| [`references/implementation.md`](references/implementation.md) | how the land, buildings and view work; hooking it into a game; tests |
| [`references/example_region.json`](references/example_region.json) | a complete example region |
| [`templates/godot/`](templates/godot/) | GDScript classes and shaders to copy into `res://paper_map/` |
| [`scripts/slice_assets.py`](scripts/slice_assets.py) | cuts generated sheets into game files (Pillow, NumPy, SciPy) |

## Use it as a skill

Copy or clone this folder into your agent's skills directory (for Claude Code: `~/.claude/skills/paper-diorama-map`)
and ask for a region map in this style.

## Use the code directly

1. Copy `templates/godot/*.gd` to `res://paper_map/` and `templates/godot/shaders/` to `res://paper_map/shaders/`.
2. Put your art in `res://paper_map/art/` (generate it as in `references/asset-prompts.md`, cut it with
   `python scripts/slice_assets.py manifest.json`), and write `res://paper_map/kinds.json` and
   `res://paper_map/houses.json` (examples in `references/`).
3. Add a `PaperMapView` to a scene and call `open("res://your_region.json")`; connect `near_changed` and `interact`.

Tested with Godot 4.6 (Compatibility renderer). No art is included: the look comes from what you generate.

## License

MIT — see [LICENSE](LICENSE).
