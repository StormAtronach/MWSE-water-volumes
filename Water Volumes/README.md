# True Water - MWSE Water Volumes

Water you can place anywhere: a pond on a hill, a river that runs downhill, a pool in a
cellar. Actors swim in it, the breath bar runs, and the view goes under water.

## Requirements

- MWSE. The mod brings its own plugin, `MWSE\lib\watervolumes.dll`; MWSE itself needs no
  change.
- MGE XE G7 in a build with water volume support. It draws the surfaces as water and gives
  the view under water.

The plugin checks the game's executable before it changes anything. If the executable is not
the one it knows, the mod does nothing and says why in `MWSE.log`, on a line that starts with
`[Water Volumes]`.

## Using it

`Water Volumes Kit.esm` has a Static for each of the 37 kit meshes: squares, discs, corners,
river pieces that join without a gap, and four solids (sphere, cube, pyramid, octahedron).
It has them again in three colours of water: swamp, mud and blood.
Place a piece in the Construction Set at the height
the water should have. Each placed piece is an ordinary reference: disable it, enable it or
move it, from a script or from Lua, and the water follows.

Everything else is in `GUIDE-construction-set.md`: the kit, how the pieces snap together, a
pond and a river step by step, how the surface looks, your own mesh, making a piece in
Blender, a mesh you cannot edit, water far away, and the limits.
