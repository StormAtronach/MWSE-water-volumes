# Water Volumes: placing water in the Construction Set

This guide takes you from an empty spot to a pond or river that actors swim in. You do not
write any Lua.

## Before you start

- The Water Volumes mod is installed: `Meshes\wv\` holds the kit meshes and
  `MWSE\mods\waterVolumes\` the scripts.
- The mod's plugin `MWSE\lib\watervolumes.dll` is installed with it. Without it the mod logs
  "MWSE/lib/watervolumes.dll was not found" and does nothing.
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
| `wv_corner_512`, `wv_corner_1024` | Quarter disc, a rounded corner for a pond made of squares | radius 512, 1024 | 512 |
| `wv_riv_512x1024`, `wv_riv_1024x2048` | Level river stretch | 512 by 1024, 1024 by 2048 | 256 |
| `wv_riv_512x1024_f64`, `wv_riv_512x1024_f128` | River stretch whose surface falls | 512 by 1024, falling 64 or 128 | 256 |
| `wv_riv_1024x2048_f128`, `wv_riv_1024x2048_f256` | The same, larger | 1024 by 2048, falling 128 or 256 | 256 |
| `wv_riv_512_bend_e`, `wv_riv_512_bend_w` | Quarter turn to the east or west | 512 wide, radius 512 | 256 |
| `wv_riv_512_bend_e_f64`, `wv_riv_512_bend_w_f64` | Quarter turn that falls | the same, falling 64 | 256 |
| `wv_riv_1024_bend_e`, `wv_riv_1024_bend_w` | Quarter turn | 1024 wide, radius 1024 | 256 |
| `wv_riv_1024_bend_e_f128`, `wv_riv_1024_bend_w_f128` | Quarter turn that falls | the same, falling 128 | 256 |
| `wv_riv_512_sway_e`, `wv_riv_512_sway_w` | Curve that moves the stream sideways and keeps its direction | 512 wide, 1024 long, 256 sideways | 256 |
| `wv_riv_1024_sway_e`, `wv_riv_1024_sway_w` | The same, larger | 1024 wide, 2048 long, 512 sideways | 256 |
| `wv_riv_taper_512_1024` | Stretch that widens | 512 to 1024 wide, 1024 long | 256 |
| `wv_riv_512_end`, `wv_riv_1024_end` | Rounded end of a stream | 512, 1024 wide | 256 |

Each piece is a closed body of water: the surface on top, and a blue box for its sides and
bottom. The box is the water. What you see in the render window is where actors will swim.
In the game the box is not drawn; only the surface is.

- Scaling a reference scales the body: at 0.5 a piece is half as wide and half as deep.
  Scaled pieces no longer fit the grid described below.
- Use a shallow piece where something under the water must stay dry, such as a pool on an
  upper floor.

## Pieces that snap together

The Construction Set does not snap corners to corners. It snaps the origin of a reference to
a grid, and the kit is built for that: with the settings below, pieces that look joined are
joined exactly, corner on corner.

1. File > Preferences: set **Grid Snap** to 64 and **Angle Snap** to 90.
2. Turn on Snap to Grid and Snap to Angle in the toolbar, or hold Ctrl while you drag.
3. Move and turn the pieces only with the snaps on. For the height, hold Z and drag.

Where the origin of each piece is:

- **Squares and discs:** the middle. Their edges lie 256, 512 or 1024 from it.
- **Corners:** the corner itself, the middle of the circle.
- **River pieces:** the middle of the end the water comes in at, on the surface. Unturned,
  a piece runs south from its origin. Its far end is a whole number of steps away: 256
  level, 64 down.

To lay a river, put the first piece down, then drop the next piece and drag it until its
origin sits on the far end of the piece before. The snap puts it there exactly. Turn it in
steps of 90 degrees to follow the stream. `_e` and `_w` say which way a piece turns or moves
when it is unturned and the water runs south. A piece that falls sends its water out 64, 128
or 256 lower than it came in, so the next piece goes that much lower.

Pieces of different widths join through the taper. A stream ends in an end piece, in a pond,
or in the sea.

Limits:

- Turns are quarter turns. A piece turned 45 degrees does not end on the grid.
- With the `plain` option the mesh's own texture turns with the piece, so the pattern
  changes direction at a joint between pieces that are turned differently. With the water
  shading of MGE XE there is nothing to see at a joint.

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

1. Use the river pieces that fall (`_f64`, `_f128`, `_f256`) and chain them as described
   under "Pieces that snap together". They keep every joint on the grid.
2. For a slope the kit does not have, open a piece's reference dialog and set Rotation X or
   Rotation Y to a few degrees. The surface slopes and the water level follows it. Such a
   piece is off the grid: fit its ends by eye, or let them overlap the next piece a little.
3. For a real drop, end one piece, place the next one lower, and cover the step with a
   waterfall mesh.

A kit piece holds exactly the water inside it at any tilt, so steep stretches work. For the
fall itself, and for fountains, use a mesh tagged `WaterVolume noswim`: it looks like water
and nobody swims in it. The water has no current, the kit texture does not flow, and under water
MGE XE shows one level surface at the camera's height.

## Draining, flooding and rising water

The water follows its reference:

- a disabled reference has no water, an enabled one has it again;
- a reference that moves takes the water with it.

With more than 64 pieces of water loaded at once, such a change shows after a few frames
rather than on the next one.

To do this from a script, make the object an Activator instead of a Static (same mesh), give
the placed reference its own ID and tick References Persist, then use `Disable`, `Enable` or
`SetPos` on it as usual.

## Your own mesh

Any mesh can be water. It needs one thing: the tag `WaterVolume`. There are two ways to give
it, and either is enough:

- **By name.** Name any object in the mesh so that its name starts with `WaterVolume`. This
  is the way for Blender: name the surface object `WaterVolume`.
- **As a text entry.** In NifSkope, add a NiStringExtraData block with the text `WaterVolume`
  to the root node. The kit pieces are made this way.

A mesh that has a `WaterBody` (see below) is water even without the tag.

Options go after the tag, in the name or in the text entry:

- `depth=300` for a depth other than 512, in a mesh without a `WaterBody`;
- `plain` to keep the mesh's own texture. Without it, MGE XE draws the surface with its water
  shading and ignores the texture. Rapids, foam and lava want `plain`;
- `skyonly` to keep MGE's water shading but reflect only the sky, not the things on screen;
- `noswim` for water nobody swims in, such as a waterfall or the jet of a fountain.

So a surface object can be named `WaterVolume`, `WaterVolume plain` or
`WaterVolume depth=300 skyonly`. Blender's own endings such as `.001` do no harm.

Nobody walks on water: the mod switches the collision of every water mesh off. An `NCO`
text entry on the root does the same and is not needed.

The water is the area under the mesh's triangles, at the height of the mesh at each spot.

To give the water a body, as the kit pieces have, add a shape named `WaterBody` for its sides
and bottom. Surface and body together must be a closed mesh. The water is then exactly what
is inside it, whatever its form: stepped or sloped bottom, leaning sides, overhangs. The mod
hides the body in the game. Without a `WaterBody` the water reaches the depth in the tag
below the surface.

## Making a piece in Blender

This is written for the Morrowind Blender Plugin (`io_scene_mw`). Nothing but Blender is
needed: no NifSkope, no Lua. What the exporter writes was read from its source, and a mesh
built the same way (no text entries, every object a group of shapes) was tested in the game.
No mesh was exported from Blender itself while this guide was written.

1. **Mind the scale.** With the plugin's default Scale Correction of 0.01, one Blender unit
   is 100 game units. A piece 512 wide is 5.12 wide in Blender.
2. **Model the water as one closed solid.** The top is the surface, the rest is the sides and
   the bottom. It may be any form, also hollowed or with overhangs.
3. **Make sure it is closed.** In Edit Mode run Mesh > Clean Up > Merge by Distance, then
   Select > Select All by Trait > Non Manifold. Nothing may be selected. Remove faces inside
   the solid and faces that lie on top of one another.
4. **Split off the surface and name the two objects.** Select the top faces and press
   P > Selection. Name the new object `WaterVolume`, with options if you want them, for
   example `WaterVolume plain`. Name the rest `WaterBody`. Names that only start that way,
   such as `WaterBody.001`, also count. Do not move vertices after the split: the rim of
   the surface and the rim of the body must stay on the same points.
5. **Materials.** The body is never drawn in the game. Give it a see-through colour so that
   the Construction Set shows the water without hiding what is in it. The surface's own
   texture shows only with the `plain` option; give it an alpha blend then. An object may
   have several materials.
6. **Put the origin where the piece should snap.** To join kit river pieces, end your piece
   with their cross-section, 512 or 1024 wide and 256 deep, with its middle on a grid point:
   a multiple of 0.64 Blender units from the origin. See "Pieces that snap together".
7. **Export.** File > Export > Morrowind (.nif), into a folder under `Meshes`. Make a Static
   with the mesh in the Construction Set and place it.

Rules that keep a piece working:

- **Keep it simple.** The body is only a boundary, so a few dozen triangles are enough. The
  surface needs no fine mesh either: the water shading of MGE XE does not move vertices.
- **No more than about 30 walls over one another.** Where a vertical line crosses the mesh
  32 times or more, the piece falls back to the simpler rule for meshes without a body.
- **One piece, one cell.** A reference is loaded and unloaded with the cell its origin is
  in. Keep a piece well under a cell (8192 units) and do not let it reach far across a cell
  border.
- **Water nobody swims in needs no body.** For a waterfall or a fountain jet, model only
  what is seen and name it `WaterVolume noswim`.
- **Everything in a water mesh is passable.** The mod switches collision off for the whole
  mesh. Keep the stone rim of a fountain or the rocks of a waterfall in a mesh of their own.

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
