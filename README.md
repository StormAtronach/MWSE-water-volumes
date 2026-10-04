# Water Volumes

Bodies of water at any height in Morrowind: ponds on hills, rivers that run downhill, pools in
interiors. Actors swim in them, the breath meter runs, and the camera goes under water. The
water is independent of the cell's own water level.

This repository holds the whole mod:

- `src/`: the native plugin, `watervolumes.dll`. It holds the volumes and patches the engine
  so that every question about the water level is answered per actor.
- `Water Volumes/`: the mod folder as it is installed. The Lua mod that finds water meshes and
  hands them to the plugin, the kit meshes, `Water Volumes Kit.esp`, and the guide for the
  Construction Set.
- `tools/`: the scripts that write the plugins.

## Requirements

- Morrowind with MWSE. The plugin is loaded by MWSE's Lua loader with `include("watervolumes")`.
  MWSE itself needs no change.
- MGE XE G7 with water volume support for the water look on the surfaces
  (branch `feature/water-volumes` of the fork). Without it the surfaces keep their own texture.

## How it fits together

1. `Water Volumes/MWSE/mods/waterVolumes/interop.lua` loads the DLL and calls `install()`.
   The plugin checks every byte it is about to replace and changes nothing if one differs.
2. `main.lua` watches references whose mesh carries the `WaterVolume` tag, or whose id a mod
   registered, and gives their scene node to the plugin while their cell is active.
3. The plugin reads the triangles of the node. A shape named `WaterBody` gives the sides and
   bottom of the water; the Construction Set shows it, the game hides it.

The Lua surface of the DLL: `install()`, `addNode(address, depth)`, `addBox(minX, minY, minZ,
maxX, maxY, maxZ)`, `remove(id)`, `clear()`, `surfaceAt(x, y, z)`, `count()`,
`hookStatus()`, `flushLog()`. Mods should use `waterVolumes.interop` rather than the DLL.

The plugin writes `WaterVolumes.log` next to `Morrowind.exe`.

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

## Not together with a patched MWSE

The same patch once lived inside MWSE (branch `feature/water-volumes` of the MWSE fork). An
MWSE.dll built from that branch has already changed the places the plugin patches, so the
plugin refuses to install and says so in its log. Use one or the other.

## Licence

MIT. See `LICENSE`.
