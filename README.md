# Water Volumes

Bodies of water at any height in Morrowind: ponds on hills, rivers that run downhill, pools in
interiors. Actors swim in them, the breath meter runs, and the camera goes under water. The
water is independent of the cell's own water level.

This repository holds the whole mod:

- `src/`: the native plugin, `watervolumes.dll`. It holds the volumes and patches the engine
  so that every question about the water level is answered per actor. `Geometry.cpp` decides
  where the water is and knows nothing of the game; `WaterVolumes.cpp` holds the registry and
  the hooks.
- `Water Volumes/`: the mod folder as it is installed. The Lua mod that finds water meshes and
  hands them to the plugin, the kit meshes, `Water Volumes Kit.esp`, and the guide for the
  Construction Set.
- `tools/`: the scripts that write the kit and the demo plugins.
- `tests/`: the tests of the geometry, which run without the game, and a copy of the
  scenarios that run in the game.
- `demo/`: a river of kit pieces along a stretch of Foyada Mamaea, written by
  `tools/make_river_demo.py`. Load it after `Water Volumes Kit.esp`.
- `docs/runs/`: the output of the test runs.

## Requirements

- Morrowind with MWSE. The plugin is loaded by MWSE's Lua loader with `include("watervolumes")`.
  MWSE itself needs no change. The newest MWSE function the mod calls dates from April 2021
  (`setNoCollisionFlag`); the mod was tested only with a current build.
- MGE XE G7 with water volume support (branch `feature/water-volumes` of the fork; it is not
  in an MGE XE release). It is required: it draws the surfaces as water and gives the view
  under water.

## Which executable

The plugin changes 82 places in `Morrowind.exe`. Before it changes any, it compares the bytes
at every one of them with the bytes it expects. If one differs it changes nothing, the mod
does nothing, and `MWSE.log` names the places on a line that starts with `[Water Volumes]`.

- The places were checked on one executable, the one of the test install. No other has been
  tried. A different executable, or a patch that changes one of these places first, turns the
  mod off.
- Something that patches the same places after the plugin takes them away without notice.
  `hookStatus()` returns how many of the 82 still lead to the plugin.
- For 26 engine functions the plugin replaces the return address on the stack while the
  function runs. A crash dump taken inside one of them shows a small stub of the plugin where
  the caller should be. The real caller is in the frame list of the plugin (`frames` in
  `WaterVolumes.cpp`).

## How it fits together

1. `Water Volumes/MWSE/mods/waterVolumes/interop.lua` loads the DLL and calls `install()`.
2. `main.lua` finds references whose mesh is marked as water by a name in it, or whose id a
   mod registered, prepares their meshes, and gives each reference to the plugin while its
   cell is active. The top of `interop.lua` says how a mesh is marked.
3. The plugin reads the triangles of the mesh. A shape named `WaterBody` gives the sides and
   bottom of the water; the Construction Set shows it, the game hides it.
4. Once per frame the mod calls the plugin, which looks at every reference it was given:
   where it is, whether it is disabled or deleted, which mesh it has. The water follows.
   Nothing is done per reference in Lua per frame, and the call makes no garbage.

Water always belongs to a placed reference. A mod that wants water places a reference of a
water mesh and handles it like any other reference. Mods use `waterVolumes.interop`:
`registerObject` for a mesh they cannot edit, `getVolumeSurfaceAt`, `supported`. The table of
the DLL itself is `interop.native`.

The plugin has no log of its own. What it has to say comes back to the mod, which writes it to
`MWSE.log`. Two messages come from inside the engine hooks and go to the debugger output: a
reference handed over from another thread, and the notice before the plugin stops the game
because a hooked function returned with no record of its caller.

## Building

As the msoc plugin, which this project is modelled on:

```pwsh
cmake --preset win32-release
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  build\win32-release\water-volumes-plugin.sln -t:Build -p:Configuration=Release -p:Platform=Win32
```

The DLL lands in `Water Volumes\MWSE\lib\watervolumes.dll`.

The plugin compiles against MWSE's engine headers and LuaJIT. Both come from the submodule
at `deps/mwse-upstream`, pinned to the MWSE commit the plugin was built and checked against.
After cloning:

```pwsh
git submodule update --init --recursive
```

LuaJIT ships as source inside that submodule (`deps/mwse-upstream/deps/rubic0n/src`) and has
to be built once, from a Visual Studio x86 developer prompt in that directory:

```bat
msvcbuild.bat lua52compat
```

It produces `lua51.lib`, which the plugin links against; at run time MWSE supplies
`lua51.dll`. To build against another MWSE checkout, configure with `-DMWSE_ROOT=<path>`.

`CMakeLists.txt` lists the MWSE source files that are compiled into the DLL. If the linker
reports an unresolved `NI::` symbol after the submodule moves, add the file that defines it.

## The kit

`tools/make_kit.py` is the one place where the kit pieces are defined. It writes the meshes,
the plugin, and `kit.json`, the list of the pieces with their sizes and joints. The demo
script and the tests read that list.

```pwsh
python tools\make_kit.py "<Data Files>\Morrowind.esm"
python tools\make_river_demo.py "<Data Files>" "demo\Water Volumes River Demo.esp"
```

After a change to a piece, run both and commit what they write.

## Tests

Without the game: the build makes `wv_geometry_test.exe`, which checks where the water is for
a box, a sheet closed below, a sloped sheet, a mesh that is not closed, bodies over one
another, a closed body at many tilts, shared edges, and
the lookup grid against a search of every triangle.

```pwsh
ctest --test-dir build\win32-release -C Release
```

In the game: `tests/harness/` holds the scenarios and says how they are run.

## Not together with a patched MWSE

The same patch once lived inside MWSE (branch `feature/water-volumes` of the MWSE fork). An
MWSE.dll built from that branch has already changed the places the plugin patches, so the
plugin refuses to install and says so in its log. Use one or the other.

## Licence

The files of this repository are under the MIT licence. See `LICENSE`.

The built DLL contains code of MWSE, which is under the GNU General Public License, version 2.
A built DLL is therefore distributed under that licence, together with its source. `LICENSE`
states this and `COPYING-GPL-2.0.txt` holds the text.
