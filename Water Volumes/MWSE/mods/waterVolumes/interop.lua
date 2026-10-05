--[[
    Water Volumes interop.

    The mesh of a static or an activator becomes water in one of two ways:
      1. Something in the mesh has a name that starts with "WaterVolume". Options follow in
         the same name, for example "WaterVolume depth=300 plain". A mesh that has a shape or
         node named "WaterBody" is water without such a name.
      2. A mod registers the object id here, for meshes it cannot edit:
           local waterVolumes = include("waterVolumes.interop")
           if waterVolumes then waterVolumes.registerObject("my_pond_static", { depth = 300 }) end

    Where both apply, the registration decides and the names are not looked at.

    Options:
      depth  for a mesh that is only the surface: how far the water reaches below it. Default
             512. The surface must be one sheet, with no part of it over another. A mesh with
             a shape named WaterBody does not use it: its water is what is inside the closed
             mesh. With depth 0 a mesh without a WaterBody is taken as closed as it is.
      noswim  the mesh looks like water and holds none: nobody swims in it. For waterfalls.
             In registerObject the key is noSwim.
      plain  keep the mesh's own texture and material. Without it, a renderer that supports
             water volumes (MGE XE) draws the surface with its water shading. Use plain for
             rapids, foam, lava or anything else that should look the way it was textured.
      skyonly  with the renderer's water shading, reflect the sky but not what is on screen.
             Cheaper, and steadier where on-screen reflections look wrong. In registerObject
             the key is skyOnly.

    The colour of the water is not an option in the name. It is the emissive colour of the
    material of the surface; black, which most materials have, is water of the usual colour.
    For a mesh that cannot be edited, registerObject takes color: "4a6b3c", or
    { 0.29, 0.42, 0.24 }. The renderer's water shading shows the colour, and so does the view
    from under the surface.
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

--- Raised by one for every registration. The mod then looks at the loaded references again.
interop.revision = 0

--- A colour as three numbers from 0 to 1, from "RRGGBB", "#RRGGBB" or three numbers. Nil for
--- anything else.
--- @param color string|number[]|nil
--- @return number? red, number? green, number? blue
function interop.parseColor(color)
    if type(color) == "string" then
        local r, g, b = color:match("^#?(%x%x)(%x%x)(%x%x)$")
        if r then
            return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
        end
    elseif type(color) == "table" then
        local r, g, b = tonumber(color.r or color[1]), tonumber(color.g or color[2]), tonumber(color.b or color[3])
        if r and g and b then
            return math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1)
        end
    end
end

--- @param id string
--- @param settings { depth: number?, plain: boolean?, skyOnly: boolean?, noSwim: boolean?, color: string|number[]|nil }?
function interop.registerObject(id, settings)
    interop.objects[id:lower()] = settings or {}
    interop.revision = interop.revision + 1
end

--
-- The native plugin. It holds the water and answers the engine's questions about it. Water
-- always belongs to a placed reference: to make water from a script, place a reference of a
-- water mesh with tes3.createReference, and move, disable or delete it like any other.
--

--- The table of watervolumes.dll, or nil when the DLL is missing.
interop.native = include("watervolumes")

--- True once the plugin's engine hooks are in place. Without them there is no water.
interop.supported = false
--- Why the hooks are not in place, when they are not.
--- @type string?
interop.problem = nil
if interop.native then
    interop.supported, interop.problem = interop.native.install()
else
    interop.problem = "MWSE/lib/watervolumes.dll was not found."
end

local function component(value, key, index)
    return value[key] or value[index]
end

--- Gives the water of the cell a colour: the sea, or the water of an interior. It is apart
--- from the water volumes, which have their colours in their meshes. Nil or black gives the
--- usual colour back. The renderer's water shading (MGE XE) shows the colour. It lasts until
--- it is changed or the game is closed, so set it when a save is loaded or a cell is entered.
--- The view from under that water has a colour of its own, which the game keeps:
--- tes3.worldController.weatherController.underwaterColor.
--- @param color string|number[]|nil "RRGGBB", three numbers from 0 to 1, or nil
function interop.setWorldWaterColor(color)
    local red, green, blue = interop.parseColor(color)
    local material = tes3.dataHandler.waterController.waterPlane.materialProperty
    if material then
        material.emissive = niColor.new(red or 0, green or 0, blue or 0)
    end
end

--- The height of the surface of the water a position is in or over, or nil.
--- @param position tes3vector3|number[]
--- @return number? surface
function interop.getVolumeSurfaceAt(position)
    if not interop.supported then
        return nil
    end
    return interop.native.surfaceAt(component(position, "x", 1), component(position, "y", 2), component(position, "z", 3))
end

return interop
