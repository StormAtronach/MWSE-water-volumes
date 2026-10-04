--[[
    Water Volumes interop.

    The mesh of a static or an activator becomes water in one of two ways:
      1. Its NIF root carries a NiStringExtraData that starts with "WaterVolume".
         Options follow in the same string, for example "WaterVolume depth=300 plain".
      2. A mod registers the object id here, for meshes it cannot edit:
           local waterVolumes = include("waterVolumes.interop")
           if waterVolumes then waterVolumes.registerObject("my_pond_static", { depth = 300 }) end

    Options:
      depth  how far the water reaches below the surface. Default 512. A mesh with a shape
             named WaterBody does not use it: its water is what is inside the closed mesh.
      noswim  the mesh looks like water and holds none: nobody swims in it. For waterfalls.
             In registerObject the key is noSwim.
      plain  keep the mesh's own texture and material. Without it, a renderer that supports
             water volumes (MGE XE) draws the surface with its water shading. Use plain for
             rapids, foam, lava or anything else that should look the way it was textured.
      skyonly  with the renderer's water shading, reflect the sky but not what is on screen.
             Cheaper, and steadier where on-screen reflections look wrong. In registerObject
             the key is skyOnly.
]]

local interop = {}

interop.tag = "WaterVolume"
interop.defaultDepth = 512

-- Material shininess that tells the renderer to draw a surface with its water shading:
-- reflecting what is on screen, or the sky only.
interop.surfaceMarker = 99998
interop.surfaceMarkerSkyOnly = 99997

--- Object ids registered from Lua, lower case, to their settings.
interop.objects = {}

--- Raised by one for every registration, so that the mod drops what it remembered about objects.
interop.revision = 0

--- @param id string
--- @param settings { depth: number?, plain: boolean?, skyOnly: boolean?, noSwim: boolean? }?
function interop.registerObject(id, settings)
    interop.objects[id:lower()] = settings or {}
    interop.revision = interop.revision + 1
end

--
-- The native plugin. It holds the volumes and answers the engine's questions about water.
--

--- The table of watervolumes.dll, or nil when the DLL is missing.
interop.native = include("watervolumes")

--- True once the plugin's engine hooks are in place.
interop.supported = false
if interop.native then
    interop.supported = interop.native.install() == true
end

local function component(value, key, index)
    return value[key] or value[index]
end

--- The volumes, with the methods a water controller would have.
local controller = { volumesSupported = interop.supported }

--- @param params { node: niAVObject?, depth: number?, min: tes3vector3|number[]?, max: tes3vector3|number[]? }
--- @return number id The id of the volume, or 0 if none was made.
function controller:addVolume(params)
    if params.node then
        return interop.native.addNode(mwse.memory.convertFrom.niObject(params.node), params.depth or interop.defaultDepth)
    end
    local a, b = params.min, params.max
    return interop.native.addBox(component(a, "x", 1), component(a, "y", 2), component(a, "z", 3), component(b, "x", 1), component(b, "y", 2), component(b, "z", 3))
end

function controller:removeVolume(id)
    return interop.native.remove(id)
end

function controller:clearVolumes()
    interop.native.clear()
end

--- The height of the surface of the water a position is in or over, or nil.
--- @param position tes3vector3|number[]
function controller:getVolumeSurfaceAt(position)
    return interop.native.surfaceAt(component(position, "x", 1), component(position, "y", 2), component(position, "z", 3))
end

-- Anything else is read from the game's own water controller: the water plane, the surface
-- texture. Properties only; its methods cannot be called through this table.
setmetatable(controller, { __index = function(_, key)
    local real = tes3.dataHandler and tes3.dataHandler.waterController
    return real and real[key]
end })

--- The controller, or nil while water volumes are not available.
function interop.getController()
    return interop.supported and controller or nil
end

return interop
