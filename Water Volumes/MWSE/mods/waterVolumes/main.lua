--[[
    Water Volumes

    Turns placed references into water. A reference counts when its mesh is tagged or its
    object id is registered through interop.lua. The water covers the area under the mesh's
    triangles, from the mesh height down to the configured depth.

    The volume follows the reference: moving, scaling, disabling, enabling or unloading it
    updates or removes the water.
]]

local interop = require("waterVolumes.interop")

--- @type table<tes3reference, table>
local tracked = {}
local flip = nil

local function log(fmt, ...)
    mwse.log("[Water Volumes] " .. fmt, ...)
end

local function getController()
    return interop.getController()
end

--- Settings per object id: a table for water, false for anything else. The tag is on the mesh,
--- so every reference of an object has the same answer and the mesh is looked at once.
local settingsByObject = {}
local settingsRevision = 0

--- The settings for a reference, or nil if it is not water.
--- depth: how far the water reaches below the surface.
--- plain: keep the mesh's own look instead of the renderer's water shading.
--- skyOnly: with the renderer's water shading, reflect the sky but not what is on screen.
local function getSettings(reference)
    local object = reference.baseObject
    if not object then
        return nil
    end
    if settingsRevision ~= interop.revision then
        settingsByObject = {}
        settingsRevision = interop.revision
    end
    local id = object.id:lower()
    local known = settingsByObject[id]
    if known ~= nil then
        return known or nil
    end

    local registered = interop.objects[id]
    if registered then
        known = { depth = registered.depth or interop.defaultDepth, plain = registered.plain == true, skyOnly = registered.skyOnly == true }
    else
        local node = reference.sceneNode
        if not node then
            -- Not decided yet: the mesh is not there to look at.
            return nil
        end
        local data = node:getStringDataStartingWith(interop.tag)
        if data then
            local text = data.string:lower()
            known = {
                depth = tonumber(text:match("depth%s*=%s*([%d%.]+)")) or interop.defaultDepth,
                plain = text:find("%f[%a]plain%f[%A]") ~= nil,
                skyOnly = text:find("%f[%a]skyonly%f[%A]") ~= nil,
            }
        else
            known = false
        end
    end
    settingsByObject[id] = known
    return known or nil
end

--
-- The renderer's water shading. MGE XE draws a surface whose material carries this marker
-- with its water shader: refraction, depth colour, ripples and reflection. One marker asks for
-- reflections of what is on screen, the other for the sky only. A renderer that does not know
-- the markers draws the mesh as it is.
--

--- A shape named WaterBody gives the sides and the bottom of the water. The Construction Set
--- shows it, so that the whole body of water can be seen and placed. The game must not.
local function isWaterBody(object)
    return object.name ~= nil and object.name:lower():find("^waterbody") ~= nil
end

local function hideBodies(node)
    for object in table.traverse{ node } do
        if isWaterBody(object) then
            object.appCulled = true
        end
    end
end

local function markSurfaces(node, marker)
    for object in table.traverse{ node } do
        if object:isInstanceOfType(ni.type.NiTriShape) and not isWaterBody(object) then
            -- A material of its own, so that other users of the mesh keep theirs.
            local material = object.materialProperty
            material = material and material:clone() or niMaterialProperty.new()
            material.shininess = marker
            object.materialProperty = material
            object:updateProperties()
        end
    end
end

--
-- Surface animation for meshes that use the engine's water surface frames.
--

local function getFlip()
    if flip then
        return flip
    end
    local controller = tes3.dataHandler.waterController
    local base = controller.surfaceTexturePath
    flip = { frames = {}, fps = controller.surfaceFPS, index = 0, prefix = base:lower():match("([^\\/]+)$") }
    for i = 0, controller.surfaceFrameCount - 1 do
        local texture = niSourceTexture.createFromPath(string.format("%s%02d.tga", base, i))
        if texture then
            flip.frames[#flip.frames + 1] = texture
        end
    end
    return flip
end

local function collectAnimatedProperties(node, out)
    local f = getFlip()
    for object in table.traverse{ node } do
        local property = object.texturingProperty
        local texture = property and property.baseMap and property.baseMap.texture
        local fileName = texture and texture.fileName
        if fileName and fileName:lower():match("([^\\/]+)$"):find("^" .. f.prefix .. "%d%d") then
            out[#out + 1] = property
        end
    end
end

local function animate()
    local f = flip
    if not f or #f.frames == 0 then
        return
    end
    local index = math.floor(os.clock() * f.fps) % #f.frames + 1
    if index == f.index then
        return
    end
    f.index = index
    local texture = f.frames[index]
    for _, entry in pairs(tracked) do
        for _, property in ipairs(entry.properties) do
            property.baseMap.texture = texture
        end
    end
end

--
-- Interiors without water. The engine asks for a water level only in a cell that is flagged as
-- having water, so such a cell gets the flag while it holds a water reference, with the cell's
-- own water far below everything. The flag is taken away again before a save is written.
--

local SUNKEN_LEVEL = -100000

--- @type table<tes3cell, number>
local flaggedCells = {}

local function needsFlag(cell)
    return cell and cell.isInterior and not cell.behavesAsExterior and not cell.hasWater
end

local function flagCell(cell)
    if flaggedCells[cell] then
        flaggedCells[cell] = flaggedCells[cell] + 1
    elseif needsFlag(cell) then
        cell.hasWater = true
        cell.waterLevel = SUNKEN_LEVEL
        flaggedCells[cell] = 1
    end
end

local function unflagCell(cell)
    local count = flaggedCells[cell]
    if not count then
        return
    end
    if count > 1 then
        flaggedCells[cell] = count - 1
    else
        flaggedCells[cell] = nil
        cell.hasWater = false
    end
end

local function setFlagsForSave(saving)
    for cell in pairs(flaggedCells) do
        cell.hasWater = not saving
        if not saving then
            cell.waterLevel = SUNKEN_LEVEL
        end
    end
end

--
-- Tracking.
--

local function isActive(cell)
    for _, active in ipairs(tes3.getActiveCells()) do
        if active == cell then
            return true
        end
    end
    return false
end

local function track(reference)
    if tracked[reference] or not reference.sceneNode then
        return
    end
    local settings = getSettings(reference)
    if not settings then
        return
    end
    local entry = { depth = settings.depth, id = nil, key = nil, properties = {}, cell = reference.cell }
    flagCell(entry.cell)
    collectAnimatedProperties(reference.sceneNode, entry.properties)
    hideBodies(reference.sceneNode)
    if not settings.plain then
        markSurfaces(reference.sceneNode, settings.skyOnly and interop.surfaceMarkerSkyOnly or interop.surfaceMarker)
    end
    tracked[reference] = entry
end

local function untrack(reference)
    local entry = tracked[reference]
    if not entry then
        return
    end
    if entry.id then
        local controller = getController()
        if controller then
            controller:removeVolume(entry.id)
        end
    end
    unflagCell(entry.cell)
    tracked[reference] = nil
end

local function placementKey(reference)
    local p, o = reference.position, reference.orientation
    return string.format("%.2f,%.2f,%.2f|%.4f,%.4f,%.4f|%.3f", p.x, p.y, p.z, o.x, o.y, o.z, reference.scale)
end

local function sync()
    local controller = getController()
    if not controller then
        return
    end
    for reference, entry in pairs(tracked) do
        local node = reference.sceneNode
        if reference.deleted or not node then
            untrack(reference)
        elseif reference.disabled then
            if entry.id then
                controller:removeVolume(entry.id)
                entry.id = nil
                entry.key = nil
            end
        else
            local key = placementKey(reference)
            if key ~= entry.key then
                if entry.id then
                    controller:removeVolume(entry.id)
                end
                node:update()
                -- The depth is given for the mesh as modelled, so it scales with the reference.
                entry.id = controller:addVolume{ node = node, depth = entry.depth * reference.scale }
                entry.key = key
            end
        end
    end
end

local function scanActiveCells()
    for _, cell in ipairs(tes3.getActiveCells()) do
        for reference in cell:iterateReferences{ tes3.objectType.static, tes3.objectType.activator } do
            if reference.sceneNode then
                track(reference)
            end
        end
    end
end

event.register("initialized", function()
    if not getController() then
        log(interop.native and "The engine hooks of watervolumes.dll could not be installed; see WaterVolumes.log. The mod is inactive."
            or "MWSE/lib/watervolumes.dll was not found. The mod is inactive.")
        return
    end

    event.register("referenceActivated", function(e)
        track(e.reference)
    end)
    event.register("referenceSceneNodeCreated", function(e)
        if isActive(e.reference.cell) then
            track(e.reference)
        end
    end)
    event.register("referenceDeactivated", function(e)
        untrack(e.reference)
    end)
    event.register("load", function()
        for reference in pairs(tracked) do
            untrack(reference)
        end
    end)
    event.register("loaded", scanActiveCells)
    event.register("save", function() setFlagsForSave(true) end, { priority = -1000 })
    event.register("saved", function() setFlagsForSave(false) end)
    event.register("enterFrame", function()
        sync()
        animate()
    end)
    log("Initialized.")
end)
