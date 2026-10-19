"""Cut generated sheets into a paper-diorama map's game files (see the skill's SKILL.md, step 4).

    python slice_assets.py manifest.json

manifest.json:
  {"gen": "<folder of generated images>", "out": "<game asset folder>",
   "tiles": ["ground", "road", "cliff", "meadow", "roof_tile", "roof_thatch"],         # <gen>/<name>-v1.png
   "sheets": {"props": [4, 3, ["pine", "cedar", ...]], "buildings": [4, 3, [...]]},    # <gen>/<sheet>-v1.png
   "houses": "<houses.json>"}                                                          # <gen>/house_<name>-v1.png

- tiles: seamless textures, resized to 256 px.
- sheets: grids on a transparent background; every drawn island goes to the cell its middle falls in (a tree
  reaching over a cell's edge stays whole; a broken bridge's two halves stay one sprite); cropped, hard alpha.
  Writes <out>/sprites.json: name -> [width, height].
- houses: per building three elevations in a row (front, gable end, back) -> house_<name>_front/_side/_back.png;
  a roof band drawn over a long wall is cut away (the model has its own roof).
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

OUT = Path(".")
TILE = 256


def tile(src: Path, name: str) -> None:
    im = Image.open(src).convert("RGB").resize((TILE, TILE), Image.LANCZOS)
    im.save(OUT / f"{name}.png")


def cut(src: Path, cols: int, rows: int, names: list[str], sizes: dict) -> None:
    """The sheet's drawn islands, each given to the grid cell its middle falls in (a tree reaching over a
    cell's edge stays whole; a broken bridge's two halves stay one sprite)."""
    sheet = Image.open(src).convert("RGBA")
    solid = np.array(sheet.getchannel("A")) >= 128
    labels, n = ndimage.label(ndimage.binary_dilation(solid, iterations=2))
    centres = ndimage.center_of_mass(solid, labels, range(1, n + 1))
    areas = ndimage.sum(solid, labels, range(1, n + 1))
    cells: dict[int, list[int]] = {}
    for i, (cy, cx) in enumerate(centres):
        if areas[i] < 40:  # specks
            continue
        cell = min(int(cy / sheet.height * rows), rows - 1) * cols + min(int(cx / sheet.width * cols), cols - 1)
        cells.setdefault(cell, []).append(i + 1)
    for k, name in enumerate(names):
        if k not in cells:
            raise SystemExit(f"{src.name}: cell {k} ({name}) is empty")
        mine = np.isin(labels, cells[k]) & solid
        ys, xs = np.nonzero(mine)
        box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        part = sheet.crop(box)
        part.putalpha(Image.fromarray((mine[box[1]:box[3], box[0]:box[2]] * 255).astype(np.uint8)))
        part.save(OUT / f"{name}.png")
        sizes[name] = [part.width, part.height]


def roofless(part: Image.Image) -> Image.Image:
    """A long wall's elevation drawn with a band of its roof along the top (the model's walls carry their own
    roof): cut away the rows down to where the roof's colour gives way to the wall. A wall whose top is not
    roof-coloured (a painted beam) is left whole."""
    a = np.array(part.convert("RGBA")).astype(float)
    h = a.shape[0]
    rows = []
    for y in range(h):
        m = a[y, :, 3] >= 128
        rows.append(a[y, m, :3].mean(axis=0) if m.sum() > 4 else np.array([255.0, 255.0, 255.0]))
    top = np.median(rows[int(h * 0.06):int(h * 0.14) + 1], axis=0)
    if top[0] - max(top[1], top[2]) > 50:  # vermilion: a beam, not a roof
        return part
    end, misses = 0, 0  # thatch: rows the colour of the top
    for y in range(int(h * 0.06), int(h * 0.55)):
        if np.linalg.norm(rows[y] - top) < 38:
            end, misses = y, 0
        else:
            misses += 1
            if misses >= 4:
                break
    rgb = a[:, :, :3] / 255.0  # tiles: rows mostly dark grey (light and dark courses alternate, so over a few rows)
    v = rgb.max(axis=2)
    sat = np.where(v > 0, (v - rgb.min(axis=2)) / np.maximum(v, 1e-6), 0)
    dark = ((v < 0.58) & (sat < 0.25) & (a[:, :, 3] >= 128)).sum(axis=1) / np.maximum((a[:, :, 3] >= 128).sum(axis=1), 1)
    dark = np.convolve(dark, np.ones(7) / 7, mode="same")
    tiles = 0
    for y in range(int(h * 0.03), int(h * 0.6)):
        if dark[y] > 0.4:
            tiles = y
        elif tiles and dark[y] < 0.25:
            break
    solid = a[:, :, 3] >= 128  # any roof: its eaves stick out past the wall below
    spans = np.array([(np.nonzero(r)[0][-1] - np.nonzero(r)[0][0]) if r.any() else 0 for r in solid])
    wall = np.median(spans[int(h * 0.7):])
    eaves, seen, gap = 0, False, 0
    for y in range(int(h * 0.6)):
        if spans[y] > wall * 1.025:
            eaves, seen, gap = y, True, 0
        elif seen:
            gap += 1
            if gap >= 4:
                break
    end = max(end, tiles, eaves)
    if end < h * 0.1:
        return part
    return part.crop((0, end + 1, part.width, h))


def elevations(src: Path, name: str) -> None:
    """Three panels in a row: each island goes to the third its middle falls in; each third cropped to what
    is drawn there (hard alpha, at most 640 px tall)."""
    sheet = Image.open(src).convert("RGBA")
    solid = np.array(sheet.getchannel("A")) >= 128
    labels, n = ndimage.label(ndimage.binary_dilation(solid, iterations=2))
    centres = ndimage.center_of_mass(solid, labels, range(1, n + 1))
    areas = ndimage.sum(solid, labels, range(1, n + 1))
    thirds: dict[int, list[int]] = {}
    for i, (cy, cx) in enumerate(centres):
        if areas[i] >= 200:
            thirds.setdefault(min(int(cx / sheet.width * 3), 2), []).append(i + 1)
    for k, part_name in enumerate(["front", "side", "back"]):
        if k not in thirds:
            raise SystemExit(f"{src.name}: no {part_name} panel")
        mine = np.isin(labels, thirds[k]) & solid
        ys, xs = np.nonzero(mine)
        box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        part = sheet.crop(box)
        part.putalpha(Image.fromarray((mine[box[1]:box[3], box[0]:box[2]] * 255).astype(np.uint8)))
        if part_name != "side":
            part = roofless(part)
        if part.height > 640:
            part = part.resize((round(part.width * 640 / part.height), 640), Image.LANCZOS)
            part.putalpha(part.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
        part.save(OUT / f"house_{name}_{part_name}.png")


def main() -> None:
    global OUT
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    m = json.loads(Path(ap.parse_args().manifest).read_text(encoding="utf-8"))
    gen = Path(m["gen"])
    OUT = Path(m["out"])
    OUT.mkdir(parents=True, exist_ok=True)
    for name in m.get("tiles", []):
        tile(gen / f"{name}-v1.png", name)
    sizes: dict = {}
    for sheet, (cols, rows, names) in m.get("sheets", {}).items():
        cut(gen / f"{sheet}-v1.png", cols, rows, names, sizes)
    (OUT / "sprites.json").write_text(json.dumps(sizes, indent=1), encoding="utf-8")
    houses = json.loads(Path(m["houses"]).read_text(encoding="utf-8")) if m.get("houses") else {}
    for name in houses:
        elevations(gen / f"house_{name}-v1.png", name)
    print(f"{len(sizes)} sprites, {len(houses)} buildings' walls, {len(m.get('tiles', []))} tiles -> {OUT}")


if __name__ == "__main__":
    main()
