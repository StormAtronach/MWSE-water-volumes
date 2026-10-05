# The scenarios that run in the game

`water.lua` holds every scenario the mod was tested with: about 5,000 lines, one function per
scenario. It is a copy. The scenarios run inside the Morrowind Test Harness, a separate MWSE
mod with a Python runner, which is not part of this repository. The harness starts the game,
loads a save, calls `require("harness.water").run(...)` with the name of a scenario, and
collects the lines the scenario reports.

The copy is here so that the tests are kept with the code they test. Without the harness it
still shows, for each behaviour of the mod, how it was checked and what was expected.

## Running a scenario

With the harness checked out and its mod installed in the test profile:

1. Copy `water.lua` to `mod/MWSE/mods/harness/water.lua` of the harness, if this copy is newer.
2. Install the `Water Volumes` folder of this repository in the same profile, with
   `Water Volumes Kit.esp` active.
3. From the `dump` folder of the harness:

```pwsh
py -3 run_dump.py --label my-run --water test --save quiksave.ess --answer-yes --announce --timeout 300
```

Nobody may use the mouse or the keyboard while a scenario runs: the game needs the foreground,
and several scenarios move the player and the camera.

`--water-plugin <esp>` adds a plugin for the run. The river demo scenarios need
`demo/Water Volumes River Demo.esp` that way.

## The scenarios

The ones to run after a change to the plugin or to the Lua mod:

| Scenario | What it checks |
| --- | --- |
| `test` | A kit disc placed as a reference: footprint, swimming, disable and enable, moving it, and that all hooks are in place |
| `marker` | The kit: all 33 flat pieces exist as statics, the body is hidden and only the surface carries the mark for the renderer, the depth is that of the body, scale, the shallow and the falling pieces |
| `joints` | Kit pieces placed end to end leave no gap in the water |
| `tilt` | A closed body holds exactly the water inside the mesh at many tilts |
| `blender` | A mesh as Blender exports it: tagged by name, grouped body, collision switched off by the mod, the save written without that switch, a registration made late |
| `saveload` | Volumes after a save and a load, in exteriors and in interiors |
| `interior` | A disc in an interior with water and in one without |
| `streamai` | Where slaughterfish and rats go in a stream, a pond, a raised pond and the sea. It reports what it saw and judges nothing: read the lines |
| `solids` | The four solids of the kit, placed by `demo/Water Volumes Solids Demo.esp`: water inside and none outside, the player swims inside each, pictures from 4,200 to 70,000 units away (far away they come from the distant land) |
| `palace` | The mod `demo/Vivec Palace Water`, installed as a mod: the palace water has the new mesh, the surface on every tier is the raised one, there is none of it outside the parapets or beyond their openings, the player swims in every channel, the waterfalls carry the mark for the renderer; pictures near and from far away |
| `colour` | Water of a colour, with `demo/Water Volumes Colours Demo.esp`: the cube in each palette has the colour on its surface, the view from inside has it as dark as the game's own underwater colour and the game's colour comes back outside, the water of the cell takes a colour from Lua while the cubes keep theirs, a registered colour is on its piece; pictures near, from inside and from 12,000 and 25,000 units away |
| `riverdemo` | The demo river: one chain of pieces, corners of joined pieces on the same points, water all the way down the middle and not under the land, the player swims |

The others measure cost (`stress`, `fishcost`, `citycost`, `mgecost` and its short form
`mgecostquick`, which time a frame at fixed views to set one build of the renderer against
another, and `refcost`, which places 5000
references of one kind per run: `refcost` none, `refcostplain` plain statics, `refcostnoswim`,
`refcostwater`, and with a 0 at the end the same without actors), take pictures (`look`), hold the
game open for a look by hand (the names that end in `hold`), measure a place (`palacescan`:
height maps of the tiers of the Palace of Vivec, from which the outlines of its water were
made; `probe`: runs a Lua file and logs what it returns), or cover one case each (`grid`,
`plugin`, `river`, `creatures`, `combat`, `ranged`, `swimdepth`, `fishair`). Each is described
at its function in `water.lua`.

`plugin` and `grid` need a plugin that `tools/make_demo_plugin.py` writes, given with
`--water-plugin`.

The scenarios that made whole vanilla buildings water (a canton, four cities, the shell of
Ald-ruhn) are removed. They were written when a mesh could be water by its layers; a
building is neither one sheet nor a closed mesh. The palace is back with a mesh of its own.

`docs/runs/` in this repository holds the output of runs. All logs but four are from the last
build of 2026-10-05: one rule for the water, water only as a placed reference, the plugin
follows the references. `city-cost`, `fish-cost`, `fish-raised-pond` and `stream-ai-before` are
from the morning of that day and were not run again.

One check fails, in `creatures`: the first time the player is put straight into water raised
over the sea, the player ends on the sea floor. The cause is not known. Everything else passes.
