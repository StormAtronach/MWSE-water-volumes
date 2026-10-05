# Vivec Palace Water

Makes the water on the four tiers of the Palace of Vivec real water, deep enough to swim in,
and gives the waterfalls of Vivec the water shading. It needs the Water Volumes mod. It is
four mesh files and nothing else: no plugin, no script.

It is also the example of how to make water of a mesh of the game that is not one sheet and
not closed.

## What it changes

- `meshes\x\Ex_Vivec_P_water_01.nif`, the water of the palace. In the game it is four flat
  sheets, one for each tier, each carried twice, 8 to 21 above the floor of the channels. The
  new mesh has one closed body of water for each tier. It fills the channel between the
  sloped wall and the parapet, 135 deep, so the surface is 114 to 126 higher than in the
  game and about 26 below the top of the parapet. A person swims in water deeper than 0.9 of
  their height, which is near 120 for most and near 132 for the tallest.
- `meshes\x\Ex_Vivec_waterfall_01.nif`, `_03` and `_05`, the waterfalls of Vivec, at the
  palace and at every canton. They are the game's meshes with one shape named
  `WaterVolume noswim`: MGE XE draws them with its water shading, and they hold no water.

## What you see at the palace

- The edge of each body is in the middle of the parapet, hidden in the stone.
- On the three upper tiers the parapet has two openings each, through which the waterfalls
  leave. There the water ends between the two prongs of the spout, and its side shows.
- The troughs that carry the waterfalls across the channels are 42 to 54 high, so they are
  under the water now. The waterfalls are where the game put them: they leave the openings
  at the height of the troughs, about 90 below the new surface.

## How it was made

`tools/make_palace_water.py` writes the four meshes from the game's own. The outlines of the
tiers are in `tools/palace_outlines.json`. `tools/palace_outlines_from_scan.py` worked them
out from height maps of the palace, which the scenario `palacescan` of `tests/harness`
measures in the game: the height of the first solid below a point, every 8 units. The edge
is the line as far from the water as from the open air.

```pwsh
python tools\make_palace_water.py "<Data Files>"
```

## Limits

- The mesh fits the palace of the game. A mod that replaces the palace needs outlines of its own.
- Another mod that replaces one of the four meshes wins or loses as a whole file.
- Not tested: how a swimmer leaves a channel. The water is too deep to stand in, and the
  top of the parapet is 26 above it.
- The mist at the foot of each waterfall is where the game put it, under the new surface.
