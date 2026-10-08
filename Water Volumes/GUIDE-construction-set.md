# True Water: placing water in the Construction Set

This guide takes you from an empty spot to a pond or river that actors swim in. You do not
write any Lua.

## Before you start

- The Water Volumes mod is installed: `Meshes\wv\` holds the kit meshes and
  `MWSE\mods\waterVolumes\` the scripts.
- The mod's plugin `MWSE\lib\watervolumes.dll` is installed with it. Without it the mod logs
  "MWSE/lib/watervolumes.dll was not found" and does nothing.
- MGE XE G7 in a build with water volume support. It draws the surfaces as water and gives
  the view under water.
- The Construction Set can see `Data Files\Meshes\wv\`. With Mod Organizer, start the
  Construction Set from Mod Organizer.

## The kit

`Water Volumes Kit.esm` is a master file. Tick it in the Construction Set together with your own plugin. It adds
one Static per piece, with ids that start with `wv_`, and places nothing. Your plugin then
depends on it.

| Static | Shape | Size | Depth |
| --- | --- | --- | --- |
| `wv_square_512`, `wv_square_1024`, `wv_square_2048` | Square | 512, 1024, 2048 wide | 512 |
| `wv_disc_512`, `wv_disc_1024`, `wv_disc_2048` | Disc | 512, 1024, 2048 across | 512 |
| `wv_square_1024_d64`, `wv_disc_1024_d64` | Square, disc, for wading | 1024 | 64 |
| `wv_square_1024_d150`, `wv_disc_1024_d150` | Square, disc, shallow water to swim in | 1024 | 150 |
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
| `wv_sphere_1024` | Sphere of water that stands free | radius 1024, origin at its centre | all of it |
| `wv_cube_1024` | Cube of water | side 1024, origin at the middle of its base | all of it |
| `wv_pyramid_1024` | Pyramid of water | base 1024 by 1024, 1024 high, origin at the middle of its base | all of it |
| `wv_octa_1024` | Octahedron of water | corners 1024 from its centre, origin at its centre | all of it |

Each piece is a closed body of water: the surface on top, and a blue box for its sides and
bottom. The box is the water. What you see in the render window is where actors will swim.
In the game the box is not drawn; only the surface is.

The last four are solids. A solid is one closed shape that is drawn as water on every side,
and the water is what is inside it. Its shape is named `WaterVolume depth=0`: the mesh is
taken as it is. Put one anywhere, also in the air.

- Scaling a reference scales the body: at 0.5 a piece is half as wide and half as deep.
  Scaled pieces no longer fit the grid described below.
- Use a shallow piece where something under the water must stay dry, such as a pool on an
  upper floor. An actor swims in water deeper than nine tenths of its height: 120 units
  for a person of ordinary height. In the 64 deep pieces everybody wades. The 150 deep
  pieces are the shallowest in which the tallest races swim as well.

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
8. **Check the depth.** The water is what is inside the blue body of the piece.
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

The change shows on the next frame.

To do this from a script, make the object an Activator instead of a Static (same mesh), give
the placed reference its own ID and tick References Persist, then use `Disable`, `Enable` or
`SetPos` on it as usual.

Water is always a placed reference. A Lua mod that wants water at run time places one with
`tes3.createReference` and handles it like any other reference.

A Lua mod can also let the mod move the water over a time, for a tide, a lock or a cistern
that fills:

```lua
local waterVolumes = include("waterVolumes.interop")
waterVolumes.animateLevel(reference, { by = 250, seconds = 8, callback = function(reference) end })
```

`to` gives the new height of the reference in place of `by`. The move is smooth at both ends;
`easing = "linear"` makes it even. It stands still while the game is paused, and
`stopLevel(reference)` stops it. At the end the mod calls the callback and sends the event
`waterVolumes:levelReached`. The actors in the water go up and down with it.

## Scripts: who is in the water

The mod sends MWSE events, which a Lua mod takes with `event.register` as any other event.
The filter of each is the reference of the actor.

| Event | When | What it carries |
| --- | --- | --- |
| `waterVolumes:enter` | the feet of an actor go into the water of a piece | `reference`, `mobile` (the actor), `volume` (the water reference), `surface` (its height there) |
| `waterVolumes:leave` | the feet come out, or the actor or the water is gone | `reference`, `mobile`, `volume` |
| `waterVolumes:cameraEnter`, `waterVolumes:cameraLeave` | the camera goes under or comes out | `volume` |
| `waterVolumes:levelReached` | a move of `animateLevel` ends | `reference` (the water, also the filter), `level` |

```lua
event.register("waterVolumes:enter", function(e)
    if e.volume.baseObject.id == "my_lava_pool" then
        -- start to burn e.mobile
    end
end)
```

An actor that goes from one piece straight into the next gets a leave and an enter. The mod
looks ten times a second, so an event can come a tenth of a second after the step. These are
the water volumes only: the sea and the water of an interior send nothing.

`waterVolumes.waterAt(position)` gives the water at any point: `{ reference, surface, floor }`,
or nil.

## How the surface looks

MGE XE draws the surface with its water shading: you see the bottom through it, deep water
darkens, ripples move and the sky and sun reflect, along with the things around the water that
are on screen. The mesh's own texture is not used then.

| Name of the surface object | Look |
| --- | --- |
| `WaterVolume` | MGE water, reflects the sky and what is on screen |
| `WaterVolume skyonly` | MGE water, reflects the sky only |
| `WaterVolume plain` | The mesh's own texture and material |

- Use `plain` for rapids, foam, lava or anything else that should look the way you textured
  it. Swimming works the same either way.
- Use `skyonly` where the reflections of things on screen look wrong for your scene, or for
  many small surfaces.
- Reflections show only what is on screen. Something behind the camera or hidden behind a
  nearer object is not reflected.

### The look line

The rest of how a surface looks is one line of text in the mesh: a `NiStringExtraData` on
the root or on the surface object, which starts with `wv:` and holds `key=value` pairs:

```
wv: flow=0,120 speed=1.5 scale=0.8
```

| Key | Values | What it does |
| --- | --- | --- |
| `flow` | `x,y`, in the axes of the mesh, in units per second | The ripples drift that way, and so does anyone in the water: the flow is a current. A river flows; a pond does not |
| `carry` | 0 to 1, default 1, or `depth` | How much of the flow carries an actor in the water. 0 for water that only looks like it flows. `depth` grows from nothing at the surface to the whole flow at the depth where the actor swims: wading is easy, swimming is not. The current works on `plain` meshes too, and without MGE XE |
| `speed` | a number, 1 is the standard | How fast the ripples move. 0 holds them still |
| `scale` | a number, 1 is the standard | The size of the ripples. Small for a basin, large for a lake |
| `glow` | 0 to 1 | The surface gives light of its own, in the colour of the water, by night as by day |
| `opacity` | 0 to 1, or `vertex` | How much of the water shows. Lower shows what is behind the surface. `vertex` takes the alpha of the vertex colours of the mesh |
| `clarity` | units of water, 800 is the standard | How much water it takes to hide what is under the surface. Small for murky water: at 100 a pond shows its bed only at the bank. 0 shows nothing under the surface, the water is opaque. Water of a colour takes that colour faster as well |
| `tint` | `vertex` | The vertex colours of the mesh tint the water: one mesh can go from clear to muddy |
| `sky` | a colour: `RRGGBB`, or three numbers from 0 to 1 | What the water reflects where it reflects nothing on screen. Without it that is the sky outdoors, and the light of the room in an interior. Give it for a pool in a cave or a cistern that should be darker, lighter or of another colour than its room |
| `reflect` | `scene` or `sky` | The same as the name words: what the surface reflects |
| `shader` | a name | A water shader that a mod ships for MGE XE, `Data Files\shaders\water\<name>.fx`: foam, lava, anything. It gets the base texture of the mesh. Without the file the surface has the standard look |
| `p0` to `p3` | up to four numbers each | Free values for such a shader |

Write a pair without spaces: `opacity=vertex`, not `opacity = vertex`. A pair with a space
beside the equals sign is not read, and `MWSE.log` names the line.
A key the mod does not know is noted once in `MWSE.log`. In NifSkope,
add the string data with Block > Insert > NiStringExtraData, set its string, and link it in
the Extra Data of the root. `registerObject` takes the same line as `look`, or a table with
the same keys, for a mesh you cannot edit.

`tint=vertex` and `opacity=vertex` are asked for, not assumed: many meshes carry vertex
colours for their look without MGE XE. The kit's own surfaces do.

Far away, in distant land, a surface has the look line of its mesh too: MGE XE copies it
when it builds the distant land. A water shader draws the far surface as well. What does not
go far: `tint=vertex`, and a look that a script gives while the game runs.

A script can change a look: `waterVolumes.setLook("object_id", "glow=0.5")` for every
reference of an object, and `waterVolumes.setLookOf(reference, { glow = 0.5 })` for one
reference, which lasts until a save is loaded. Nil takes the look away again. Each different
look is kept for the session, so change a look on an occasion and not every frame; a look
that moves is the work of a water shader.

A current moves every actor whose feet are under the surface, at the speed of the flow,
on top of its own movement. Swimming against a current of 60 is easy; a current of 300 wins.
The engine moves the actor by its velocity, as it does in the wind on the sea, so collision
and the shore work as always: the current stops where the actor climbs out.

### Ripples of your own: a normal map, a flow map

A water shader does not have to draw the water itself. It can give only the ripples and
leave the rest to MGE XE: the colour, the depth, the reflections. The shader works out a
ripple normal, from a normal map or from one that it moves along a flow map, and hands it to
`shadeWaterVolumeRippled`. The mesh carries the textures: its base texture and its second
texture (a decal, on the second texture coordinates) reach the shader as `sampMesh0` and
`sampMesh1`. The showcase "True Water - Flow Map" is such a shader with its mesh, its two
textures and the tool that makes them; start from it.

Two rules for every water shader:

- Call the standard shading one time. `shadeWaterVolume` and `shadeWaterVolumeRippled` are
  most of a water shader, and each call is a copy of it. A shader with two calls, one for
  near water and one for far, can become too large when the player turns the light options
  on, and then MGE XE turns the water shaders of all mods off. Work out what differs first,
  and call once.
- Far away the mesh has no second texture. Use the standard ripples there (`look.distant`).

The contract is in MGE XE's `docs/water-shaders.md`.

### Light on the water

The player can turn on three things for water volumes in MGE XE, all off unless set:
the shadows of distant land on the surface, the glint of lamps and fires near the water,
and caustics on what is under the surface. A mesh needs nothing for them. They are part
of the standard shading, so a water shader that calls it has them too. A lamp must be close
to the water to glint: its light falls off as the game's light does.

## Water of a colour

The kit comes again in three colours. Each has a Static for every piece, with the name of
the colour after `wv_`: `wv_square_1024` is `wv_swamp_square_1024` in the swamp colour.

| Palette | Colour | Statics |
| --- | --- | --- |
| swamp | murky green, `4a6b3c` | `wv_swamp_...` |
| mud | brown, `7a5a38` | `wv_mud_...` |
| blood | dark red, `8a1010` | `wv_blood_...` |

What a colour does, with MGE XE:

- Deep water of a colour tends to that colour. What you see through it loses the other
  colours, more with depth: a pond 60 deep has a tint, a pond 500 deep is the colour.
- Far away the piece has the same colour.
- Under the surface the view has the colour, as dark as the game's own underwater colour.

In your own mesh, the colour of the water is the emissive colour of the material of the
surface shape. Black, which a material has unless you change it, is the usual water. The
colour is not a word in the name. For another palette of the kit, add a line to `PALETTES`
in `tools/make_kit.py` of the repository and run the script.

The water of the cell, the sea or the water of an interior, can have a colour as well. It is
apart from the pieces: a Lua mod sets it, and no piece changes with it.

```lua
local waterVolumes = include("waterVolumes.interop")
if waterVolumes then
    waterVolumes.setWorldWaterColor("2e8b57")   -- or { 0.18, 0.55, 0.34 }; nil for the usual colour
end
```

It lasts until it is changed or the game is closed, so set it when a save is loaded or a
cell is entered. The view from under that water keeps the game's own colour,
`tes3.worldController.weatherController.underwaterColor`, which a mod can set too.

## Your own mesh

Any mesh can be water. It needs one thing: the tag `WaterVolume`, as a name. Name any object
in the mesh so that its name starts with `WaterVolume`. In Blender, and in the kit pieces, it
is the surface object that has this name.

A mesh that has a `WaterBody` (see below) is water even without the tag.

Options go after the tag, in the same name:

- `depth=300` for a depth other than 512, in a mesh that is only a surface (see below).
  Write it without spaces, as every pair of a name or of a look line: `depth = 300` is
  not read, and `MWSE.log` names the mesh;
- `plain` to keep the mesh's own texture. Without it, MGE XE draws the surface with its water
  shading and ignores the texture. Rapids, foam and lava want `plain`;
- `skyonly` to keep MGE's water shading but reflect only the sky, not the things on screen;
- `noswim` for water nobody swims in, such as a waterfall or the jet of a fountain.

So a surface object can be named `WaterVolume`, `WaterVolume plain` or
`WaterVolume depth=300 skyonly`. Blender's own endings such as `.001` do no harm.

Nobody walks on water: the mod switches the collision of every water mesh off. An `NCO`
text entry on the root does the same and is not needed.

There is one rule for where the water is: the water is what is inside a closed mesh. A mesh
can be closed in two ways.

- **With a body, as the kit pieces have.** Add a shape named `WaterBody` for the sides and the
  bottom. Surface and body together must be a closed mesh. The water is exactly what is
  inside it, whatever its form: stepped or sloped bottom, leaning sides, overhangs. The mod
  hides the body in the game.
- **A surface alone.** A mesh without a `WaterBody` is taken as the surface of the water, and
  the mod closes it: the bottom is the same surface, `depth` lower (512 unless the tag says
  otherwise). The surface must be one sheet. It may slope, but no part of it may lie over
  another part. A mesh that carries its surface twice, one a little over the other, or water
  in steps over one another, does not work this way: give it a body, or make one mesh per
  sheet. A surface made for both sides, with every face a second time in the same place, is
  one sheet and works.
- **Water in a mesh that is more than water.** When something in the mesh is named
  `WaterVolume`, only that object, and what is under it if it is a node, is water. The other
  shapes of the mesh are left as they are: a well keeps its posts, its roof and its stones.
  A mesh with no such name in it, which a Lua mod made water by its id, is water as a whole.
- **Water behind a mask.** The water keeps the stencil test and the depth test that the mesh
  gives it (`NiStencilProperty`, `NiZBufferProperty`). So the old trick for a well works with
  the water shading of MGE XE: a shape at the mouth writes a mask, and the water and the
  shaft, deep under the ground, are drawn only through it. Water that is drawn without the
  depth test cannot show its bed or reflect what is on screen; it is drawn as deep water.

- **A dry space in the water.** A closed shape named `WaterMask` is the opposite of water:
  inside it there is none, whatever water the place is in, the sea or a volume. The hold of
  a boat whose floor lies under the water line is the use for it: make the mask the inside
  of the hull, closed at the top at the height of the rim. Nobody in it swims or is under
  water, the camera in it has no underwater view, and with MGE XE no water and no caustics
  are drawn in it. The mod hides the shape. A mesh can be a mask and nothing else, or have
  a mask besides its water. Give a mesh with a mask a collision of its own
  (`RootCollisionNode`), or the mask is a wall. `waterVolumes.isDry(position)` tells a
  script whether a place is in a dry space. A boat that moves can take along who stands in
  it: name the shape `WaterMask carries`, or give `carries = true` in `registerObject`.
  When a script then moves the reference, every actor in its dry space gets the same
  movement, by the velocity that the game gives an actor, so walls and floors still stop
  them. Without the word an actor on a floor that sinks is left in the air until it takes
  a step, because the game looks for the ground under an actor only when the actor moves.
  A step of more than 64 units in one frame counts as a new place, and carries nobody.
  A point must be over the floor face of the shape to be in the dry space: put that face a
  little under the floor that actors stand on.
  Far away a dry space works as well: MGE XE keeps the shape in its distant land data and
  cuts the water in a boat that is beyond the loaded cells (see "Water far away").
  Two limits: looked at from inside a dry space, the water outside it is not drawn as a
  wall of water; and while the camera passes a face of a mask, the caustics on the bed can
  show inside for a few frames. The water itself does not.

Where a mesh is not closed there is no water. With `depth=0` the mod adds no bottom and takes
a mesh without a `WaterBody` as it is; use that for a closed mesh you cannot rename.

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
  32 times or more, there is no water.
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

## A mesh you cannot edit

A Lua mod can make any Static or Activator water by its id. Do it before the save loads: a
registration made later changes the swimming at once, but the look of a mesh that is already
loaded stays until its cell loads again.

```lua
local waterVolumes = include("waterVolumes.interop")
if waterVolumes then
    waterVolumes.registerObject("my_pond_static", { depth = 300, plain = false, skyOnly = false, noSwim = false, color = "4a6b3c" })
end
```

`color` gives the water a colour, as `"RRGGBB"` or as three numbers from 0 to 1; leave it
out for the colour the mesh has. `look` gives it a look line, as text or as a table. Far away
the mesh is drawn from the distant land data, which a script cannot reach: give the same
colour there with `water_color`, and the same look with `wv`, in the metadata file of the
plugin (see "Water far away").

The same rule holds as for your own mesh: the mesh must be closed, or be one sheet that the
mod closes `depth` below. A mesh that carries its surface twice, one over the other, does not work. The water of
the Palace of Vivec is such a mesh; for it, and for any mesh that the rule does not fit, put
a mesh of your own in the place of the game's, with the names from "Your own mesh".

## Water over the water of the cell

A piece that lies over the sea, or over the water of an interior, must be drawn before that
water, or MGE XE takes the sea for the bed of the piece and the piece looks milky. Give its
surface no NiAlphaProperty, and a NiZBufferProperty that tests and writes depth (flags 3).
The kit pieces are made for dry ground and have an alpha property; use a mesh of your own
for a river that runs into the sea or a canal over it.

## Limits

- A piece is water to swim in while its cell is one of the loaded cells around the player.
  Keep each piece inside one cell. Far away it is still drawn as water; see "Water far away".
- Water has no sides of its own. Where a piece stands free of terrain and walls, the player
  and walking creatures can step out of its side and fall. Fish stay in.
- The kit texture does not flow. A current and a flow of the ripples come from the look
  line (see "The look line").
- Under water MGE XE shows one level surface, at the camera's height. Keep slopes gentle
  where the view under water matters.
- Walking creatures do not follow into the water. Rats stay out, as they do at the sea.
- Scripts that read the water level get the level of the cell, not of a piece.

## Water far away

MGE XE draws things far away from its distant land data, which it builds when the game
starts. MGE XE knows a water mesh by the names in it, so a piece far away is drawn as water
too, and not with its own texture.

- A mesh whose surface is named `WaterVolume`, or that has a `WaterBody`, needs nothing more.
  The words `plain` and `skyonly` in the name count far away as well.
- A shape named `WaterMask` is a dry space far away too: the sea and the water volumes are
  not drawn in a boat that is beyond the loaded cells. The shape itself is never drawn. To
  turn this off for one mesh, give its line in the metadata file `dry_space = false`. A boat
  that a script moves is cut where it is while its cell is loaded; far away it is drawn, and
  cut, where it was when the distant land was built.
- A mesh that a Lua mod made water by its id has no such name. Put a line for it into the
  metadata file of the plugin that places it (`<plugin name>-metadata.toml`, beside the
  plugin):

  ```toml
  [tools.mge-xe.distantland.statics]
  'x\ex_my_pond.nif' = { water = true }
  ```

  A colour that the Lua mod gave it goes into the same line, as three numbers from 0 to 1,
  and a look line as text:
  `{ water = true, water_color = [0.29, 0.42, 0.24], wv = "flow=0,-140 glow=0.3" }`.

- Far water reflects the sky. Out to 8 cells from the player it also reflects what is on
  screen; `distant_land.water.volume_reflection_cells` in the MGE XE settings changes that
  distance, and 0 turns it off.
- The distant land leaves a small piece out, as it does every small thing. The same line
  makes it keep the piece: `{ type = "very_far" }`. A piece that is in the distant land is
  drawn as far as the largest things, whatever its size.
- Nobody swims in far water, and it does not take part in the reflection on the sea.

## When it does not work

| What you see | Likely cause |
| --- | --- |
| Actors walk on the surface, or the blue body shows in the game | The Water Volumes mod is not active, or its plugin could not start. Look for `[Water Volumes]` in `MWSE.log` |
| The surface shows but nobody swims | The same; or the mesh is not closed: it has neither a `WaterBody` nor a single sheet as its surface |
| The surface shows its own texture, not water | MGE XE is not the build with water volume support, or the name has `plain` |
| Nobody swims although the water looks deep | The basin under the mesh is shallower than about 120 units |
| Actors swim in the air beside the pond | The piece reaches past the basin over lower ground. Use a smaller piece, or a mesh shaped to the basin |
| My texture does not show, the surface looks like the sea | That is MGE XE's water shading. Add `plain` to the tag to keep your texture |

## What has been tested

A plugin that places `wv_disc_1024` in an exterior cell was loaded in the game: the reference
became water and the player swam in it. The same was done for disabling, enabling, moving and
tilting a placed reference.
