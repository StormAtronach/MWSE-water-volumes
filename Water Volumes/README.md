# Water Volumes

Water you can place anywhere: a pond on a hill, a pool in a cellar, a flooded pit. Actors swim
in it, the breath bar runs, and with MGE XE the underwater view applies.

Requires a build of MWSE with water volume support. Without it the mod does nothing.

## Using it in the Construction Set

1. Make a Static (or Activator) that uses one of the kit meshes in `meshes\wv\`:
   `wv_square_512`, `wv_square_1024`, `wv_square_2048`, `wv_disc_512`, `wv_disc_1024`,
   `wv_disc_2048`. The number is the width in game units.
2. Place it in the cell at the height the water surface should have.
3. Sink the edges into terrain or walls. The mesh has a hard edge.

The water is everything under the mesh, down to 512 units below it.

Scripts can use the reference like any other: `Disable` drains the water, `Enable` brings it
back, moving the reference moves the water. The mod looks at 64 pieces of water per frame, so
where more than that are loaded at once the change shows after a few frames.

## Your own mesh

Any mesh can be water. Name an object in it `WaterVolume` (in Blender: the surface object),
or add `WaterVolume` as a text entry (NiStringExtraData) on the root node. Options follow the
tag, for example `WaterVolume depth=300`. The mod switches the collision of a water mesh
off, so no `NCO` entry is needed. The guide has a section on making a piece in Blender.

The footprint is the area under the mesh's triangles, so the shape is yours to model.

The surface may slope. The water level at any spot is the height of the mesh there, so a river
can run downhill, and a kit piece can simply be rotated in the Construction Set. A mesh with a
shape named `WaterBody` (every kit piece has one) is a closed body: its water is exactly what
is inside the mesh, at any tilt, so a steep stretch of river works as it is placed. Keep
slopes gentle where the view under water matters: under water MGE XE draws one level surface at the camera's height, the water does not
push anything downstream, and the kit texture does not flow. For a big drop use flat steps
joined by a waterfall mesh.

A waterfall, a fountain jet or any other water that nobody should swim in gets `noswim` in its
tag: `WaterVolume noswim`. It is drawn as water and holds none, so it costs nothing when the
game asks where the water is.

A mesh whose texture is the game's own water surface (`water00` and so on) is animated.

## How the surface looks

With MGE XE (a build that supports water volumes) the surface is drawn with MGE's water
shading: you see the bottom through it, deep water darkens, ripples move and the sky and sun
reflect, along with the things around the pond that are on screen. The mesh's own texture is
not used then.

To keep the mesh's own texture and material instead, add `plain` to the tag:
`WaterVolume plain`, or `WaterVolume depth=300 plain`. Use it for rapids, foam, lava or
anything else that should look the way you textured it. Swimming works the same either way.
Without MGE XE every surface is drawn with its own texture.

To keep MGE's water shading but reflect only the sky, add `skyonly`: `WaterVolume skyonly`.
The surface then does not mirror what is on screen. Use it where those reflections look wrong
for your scene, or for many small surfaces.

| Tag | Look with MGE XE |
| --- | --- |
| `WaterVolume` | MGE water, reflects the sky and what is on screen |
| `WaterVolume skyonly` | MGE water, reflects the sky only |
| `WaterVolume plain` | The mesh's own texture |

## A mesh you cannot edit

From MWSE Lua, before the save loads:

```lua
local waterVolumes = include("waterVolumes.interop")
if waterVolumes then
    waterVolumes.registerObject("my_pond_static", { depth = 300, plain = false, skyOnly = false })
end
```

## Limits

- Interior cells that have no water of their own do not work yet.
- Reflections show only what is on screen. Something behind the camera or hidden behind a
  nearer object is not reflected.
