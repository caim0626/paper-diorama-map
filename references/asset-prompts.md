# Generating the assets

Every prompt is written by a separate model call from **one brief** = the format guide below + the shared
context + this job's inputs, and nothing else. Your job is to fill the inputs and check the output against
the guide. Use any image model that does text-to-image with a transparent background and image-to-image edits.

Replace `{GAME}` and `{STYLE}` once for the project, e.g. `{STYLE}` = "an ink-wash (sumi-e) pixel-art style:
rice-paper cream, ink black and greys, muted grey-green, pale ochre, weathered brown wood, vermilion used
sparingly". Keep the outline sentence as is: it is what makes generated parts from different calls match.

## The brief

```
You are writing ONE image-generation prompt in English for an image model. Output only the prompt body.

## Format guide
- Describe directly the picture you want and what it is for; avoid "no …" / "don't …" negations and
  restriction lists — say what IS there.
- Open with a concrete professional identity and purpose (who is drawing, for whom, what spec), then use
  industry terms; dense information beats vague adjectives.
- Parts placed into a scene one by one are made on a transparent background ("isolated on a transparent
  background").
- Small parts of the same kind come in one image as a grid: rows × columns, one item per cell, even spacing,
  same view and same light for all, each item bottom-centred in its cell with clear empty space around it.
- Tiling textures: "seamless tileable texture", edges continuing into each other, even density with no focal
  point, no lighting gradient across the tile.

## The game
"{GAME}" is drawn in {STYLE}. Its region map is a real-time 3D world: one heightmap terrain textured with a
few small tiling textures blended by slope, flat upright pixel-art cut-outs standing on it, simple box
buildings with painted walls, seen from about 40° above. Every cut-out has a bold, even, near-black outline
about 3–4 art pixels wide. The look stays calm and clean: ground textures are quiet and low-contrast so the
sprites read on them; sprites are simple, chunky and few in colours.

## This job
<one of the inputs below>
```

## Inputs

**Ground tile** (1024², opaque) — "A seamless tileable ground texture, pixel art with chunky square pixels (a
128×128 art-pixel tile), viewed straight down, flat light: <base surface> with soft mottling in two close
tones, a sparse scatter of <small marks>. Low contrast; it covers most of the map, so it must be quiet."
Make: `ground`, `road` (packed earth, a few outlined pebbles, lighter and warmer than ground), `cliff` (seen
face-on: horizontal rock strata in 3–4 greys, crack lines along the layers, a little moss on ledges),
`meadow` (dense short grass in two close values, a few tiny flower dots, the ground showing through).

**Prop grid** (1536×1024, transparent) — "A sprite sheet of <nature / village> props, a grid of 4 columns ×
3 rows … all seen from the same slightly-raised front view (camera about 30° above the horizon). Each item
stands on its own base line, bottom-centred in its cell, with no ground patch around its base." then
"Row 1: …; Row 2: …; Row 3: …" naming 12 items. Nature: tree kinds, shrub, grass tuft, tall grass, boulder,
stones, reeds, flowers, stump. Village: barrel, crates, well, notice board, laundry pole, bales, small shrine,
statue, lantern, fence.

**Building sprites** (1536×1024 grid, transparent) — each building once in three-quarter view from about 40°
above, corner toward the viewer, standing on a small flat base patch. These are the flat cut-outs for
landmarks and the references for the wall drawings.

**Wall drawings** (1536×1024, transparent, image-to-image with that building's sprite as the only reference)
— "A wall-texture sheet for one building: three orthographic elevation panels in one row, evenly spaced with
clear empty space between them, each drawn flat-on with no perspective, the bottom of every wall on one ground
line: 1. left, the FRONT wall (the long side with the entrance), about 3:2; 2. middle, the GABLE END (its
rectangle of wall topped by the triangular gable up to the ridge), about 1:1; 3. right, the BACK wall, the
same size as the front, plainer. Walls only — the roof is a separate model — so draw up to the eaves line
(and the gable triangle) and nothing above. Keep the materials, colours, details and signs of the reference."
+ one sentence describing the building. The model still often draws a roof band over the long walls; the
slicer cuts it off.

**Roof tile** (1024², opaque) — tile rows or thatch running top to bottom, flat-on, 3–4 close values.

## Checking a result

Tiles: tile it 2×2 and look at the seams and for a focal point. Sheets: composite on magenta and check every
cell has exactly its item, cleanly separated, with a dark outline all round. Walls: the three panels are
separate, flat (no perspective), same height, signs readable. Redo at most twice, each time saying what was
wrong in the brief, not in a list of "don'ts".

## Cutting

`scripts/slice_assets.py manifest.json` — see its docstring. Each sheet's drawn islands go to the grid cell
their middle falls in (a tree leaning over a cell edge stays whole), cropped with hard alpha; tiles are
resized to 256 px; walls are split into the three thirds and any roof band over a long wall is cut away.
