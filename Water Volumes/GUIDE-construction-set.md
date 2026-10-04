# Water Volumes: placing water in the Construction Set

This guide takes you from an empty spot to a pond or river that actors swim in. You do not
write any Lua.

## Before you start

- The Water Volumes mod is installed: `Meshes\wv\` holds the kit meshes and
  `MWSE\mods\waterVolumes\` the scripts.
- The game runs a build of MWSE with water volume support. Without it the mod logs
  "This build of MWSE has no water volume support" and does nothing.
- The Construction Set can see `Data Files\Meshes\wv\`. With Mod Organizer, start the
  Construction Set from Mod Organizer.

## The kit

Load `Water Volumes Kit.esp` in the Construction Set together with your own plugin. It adds
one Static per piece, with ids that start with `wv_`, and places nothing. Your plugin then
depends on it.

| Static | Shape | Size | Depth |
| --- | --- | --- | --- |
| `wv_square_512`, `wv_square_1024`, `wv_square_2048` | Square | 512, 1024, 2048 wide | 512 |
| `wv_disc_512`, `wv_disc_1024`, `wv_disc_2048` | Disc | 512, 1024, 2048 across | 512 |
| `wv_square_1024_shallow`, `wv_disc_1024_shallow` | Square, disc | 1024 | 128 |
| `wv_riv_512x1024`, `wv_riv_1024x2048` | Level river stretch | 512 by 1024, 1024 by 2048 | 256 |
| `wv_riv_512x1024_f64`, `wv_riv_512x1024_f128` | River stretch whose surface falls towards the south | 512 by 1024, falling 64 or 128 | 256 |
| `wv_riv_1024x2048_f128`, `wv_riv_1024x2048_f256` | The same, larger | 1024 by 2048, falling 128 or 256 | 256 |

Each piece is a closed body of water: the surface on top, and a blue box for its sides and
bottom. The box is the water. What you see in the render window is where actors will swim.
In the game the box is not drawn; only the surface is.

- Scaling a reference scales the body: at 0.5 a piece is half as wide and half as deep.
- Rotate a falling river stretch about the vertical axis to send the water another way.
- Use a shallow piece where something under the water must stay dry, such as a pool on an
  upper floor.

For scale: an exterior cell is 8192 units wide and an actor is about 130 units tall.

## A pond, step by step

1. **Load your plugin.** File > Data Files, tick the masters you need, set your plugin as the
   active file.
2. **Make the object.** In the Object Window open the Static tab, right-click the list and
   choose New. Give it an ID, for example `my_pond_disc`. Click Add Art File and pick
   `Meshes\wv\wv_disc_1024.nif`. Click Save.
3. **Open the cell.** In the Cell View window double-click the cell, so it shows in the Render
   Window.
4. **Place it.** Drag `my_pond_disc` from the Object Window into the Render Window.
5. **Set the height.** Double-click the placed object and type the water height into Position
   Z, or hold Z and drag to move it up and down. Do not press F: that drops it onto the ground.
6. **Fit it.** Move it so the mesh covers the basin. For a size between kit sizes, change
   3D Scale in the same dialog (0.5 to 2.0).
7. **Hide the edge.** The mesh has a hard edge, so its rim should end inside terrain, rocks or
   walls. Shape the land around it with the landscape editor (H) if needed.
8. **Check the depth.** The water is everything under the mesh down to 512 units below it.
   Actors start to swim where the water is deeper than about nine tenths of their height, so a
   basin needs roughly 120 units of depth for a person to swim.
9. **Save**, enable the plugin and walk in.

What you should see in game: wading at the edge, swimming in the deep part, the Breath bar
when the head goes under, and with MGE XE the underwater view.

## A river that runs downhill

1. Place a square piece and open its reference dialog.
2. Set Rotation X or Rotation Y to a few degrees. The surface now slopes and the water level
   follows it.
3. Chain pieces along the river bed, each one starting where the last one ends.
4. For a real drop, end one piece, place the next one lower, and cover the step with a
   waterfall mesh.

Keep slopes gentle. The water has no current, the kit texture does not flow, and under water
MGE XE shows one level surface at the camera's height.

## Draining, flooding and rising water

The water follows its reference:

- a disabled reference has no water, an enabled one has it again;
- a reference that moves takes the water with it.

To do this from a script, make the object an Activator instead of a Static (same mesh), give
the placed reference its own ID and tick References Persist, then use `Disable`, `Enable` or
`SetPos` on it as usual.

## Your own mesh

Any mesh can be water. In NifSkope, on the root node, add two NiStringExtraData blocks:

- `WaterVolume`, or `WaterVolume depth=300` for a depth other than 512;
- `NCO`, so that the surface has no collision.

Add `plain` to the first one (`WaterVolume plain`) to keep the mesh's own texture. Without it,
MGE XE draws the surface with its water shading and ignores the texture. Rapids, foam and lava
want `plain`.

Add `skyonly` instead (`WaterVolume skyonly`) to keep MGE's water shading but reflect only the
sky, not the things on screen.

The water is the area under the mesh's triangles, at the height of the mesh at each spot.

To give the water a body, as the kit pieces have, add a shape named `WaterBody` for its sides
and bottom. The shape can be anything; the lowest part of the mesh over a spot is the floor of
the water there, so a stepped or sloped bottom is a stepped or sloped `WaterBody`. Give it no
texture. The mod hides it in the game. Without a `WaterBody` the water reaches the depth in
the tag below the surface.

Keep the path of a mesh short: the game stores `wv\name.nif` in 31 characters, so a name in
`Meshes\wv` can be 24 characters long at most.

If the mesh's texture is the game's water surface (`water00.dds` and its siblings), the mod
animates it.

## When it does not work

| What you see | Likely cause |
| --- | --- |
| Actors walk on the surface | The mesh has no `NCO` tag |
| The surface shows but nobody swims | The Water Volumes mod is not active, or MWSE has no water volume support. Look for `[Water Volumes]` in `MWSE.log` |
| Nobody swims although the water looks deep | The basin under the mesh is shallower than about 120 units |
| Actors swim in the air beside the pond | The mesh reaches past the basin over lower ground. Use a smaller piece, or a mesh shaped to the basin |
| My texture does not show, the surface looks like the sea | That is MGE XE's water shading. Add `plain` to the tag to keep your texture |
| Nothing happens in an interior | Interior cells without water of their own are not supported yet |

## What has been tested

A plugin that places `wv_disc_1024` in an exterior cell was loaded in the game: the reference
became water and the player swam in it. The same was done for disabling, enabling, moving and
tilting a placed reference. The clicks inside the Construction Set and NifSkope described above
were written from how those tools work and were not run as part of that testing.
