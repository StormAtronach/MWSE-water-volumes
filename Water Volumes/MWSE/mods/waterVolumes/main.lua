--[[
    Water Volumes

    Turns placed references into water. A reference counts when it is a static or an activator
    and its mesh is tagged or its object id is registered through interop.lua. The water covers
    the area under the mesh's triangles, from the mesh height down to the configured depth.

    The volume follows the reference: moving, scaling, disabling, enabling or unloading it
    updates or removes the water. A new reference becomes water on the next frame. After that
    the references are looked at in turn, a fixed number per frame, so with many pieces of
    water in the loaded cells a change to one of them takes a few frames to be noticed.
]]

local interop = require("waterVolumes.interop")

local STATIC = tes3.objectType.static
local ACTIVATOR = tes3.objectType.activator

--- How many tracked references are looked at per frame.
local SYNC_PER_FRAME = 64

--- @type table<tes3reference, table>
local tracked = {}
--- The tracked references as a list, to look at them in turn. entry.index is the place in it.
--- @type tes3reference[]
local order = {}
local cursor = 0
--- References tracked since the last frame.
--- @type tes3reference[]
local pending = {}
--- The texturing properties to animate, for the references that have any.
--- @type table<tes3reference, niTexturingProperty[]>
local animated = {}
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

--- The settings for an object, or nil if it is not water. The node is that of one of its references.
--- depth: how far the water reaches below the surface.
--- marker: the material marker for the renderer's water shading, or nil to keep the mesh's own look.
local function getSettings(object, node)
    if settingsRevision ~= interop.revision then
        settingsByObject = {}
        settingsRevision = interop.revision
    end
    local id = object.id
    local known = settingsByObject[id]
    if known ~= nil then
        return known or nil
    end

    local depth, plain, skyOnly
    local registered = interop.objects[id:lower()]
    if registered then
        depth, plain, skyOnly = registered.depth, registered.plain == true, registered.skyOnly == true
    else
        local data = node:getStringDataStartingWith(interop.tag)
        if data then
            local text = data.string:lower()
            depth = tonumber(text:match("depth%s*=%s*([%d%.]+)"))
            plain = text:find("%f[%a]plain%f[%A]") ~= nil
            skyOnly = text:find("%f[%a]skyonly%f[%A]") ~= nil
        else
            settingsByObject[id] = false
            return nil
        end
    end

    known = { depth = depth or interop.defaultDepth }
    if not plain then
        known.marker = skyOnly and interop.surfaceMarkerSkyOnly or interop.surfaceMarker
    end
    settingsByObject[id] = known
    return known
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

--- True for a texture file that is one of the engine's water surface frames.
local function isSurfaceFrame(fileName, prefix)
    local name = fileName:lower():match("([^\\/]+)$")
    return name ~= nil and name:sub(1, #prefix) == prefix and name:find("^%d%d", #prefix + 1) ~= nil
end

local function animate()
    local f = flip
    if not f or #f.frames == 0 or next(animated) == nil then
        return
    end
    local index = math.floor(os.clock() * f.fps) % #f.frames + 1
    if index == f.index then
        return
    end
    f.index = index
    local texture = f.frames[index]
    for _, properties in pairs(animated) do
        for i = 1, #properties do
            properties[i].baseMap.texture = texture
        end
    end
end

--
-- The mesh of a water reference.
--
-- The renderer's water shading: MGE XE draws a surface whose material carries a marker with
-- its water shader: refraction, depth colour, ripples and reflection. One marker asks for
-- reflections of what is on screen, the other for the sky only. A renderer that does not know
-- the markers draws the mesh as it is.
--

--- A shape named WaterBody gives the sides and the bottom of the water. The Construction Set
--- shows it, so that the whole body of water can be seen and placed. The game must not.
local function isWaterBody(object)
    return object.name ~= nil and object.name:lower():find("^waterbody") ~= nil
end

--- Hides the bodies, marks the surfaces for the renderer, and returns the texturing properties
--- to animate.
local function prepareNode(node, marker)
    local prefix = getFlip().prefix
    local properties = {}
    for object in table.traverse{ node } do
        local body = isWaterBody(object)
        if body then
            object.appCulled = true
        elseif marker and object:isInstanceOfType(ni.type.NiTriShape) then
            -- A material of its own, so that other users of the mesh keep theirs.
            local material = object.materialProperty
            material = material and material:clone() or niMaterialProperty.new()
            material.shininess = marker
            object.materialProperty = material
            object:updateProperties()
        end

        local property = object.texturingProperty
        local texture = property and property.baseMap and property.baseMap.texture
        local fileName = texture and texture.fileName
        if fileName and isSurfaceFrame(fileName, prefix) then
            properties[#properties + 1] = property
        end
    end
    return properties
end

--
-- Interiors without water. The engine asks for a water level only in a cell that is flagged as
-- having water, so such a cell gets the flag while it holds a water reference, with the cell's
-- own water far below everything. The cell is put back as it was while a save is written.
--

local SUNKEN_LEVEL = -100000

--- The flagged cells, with how many water references each holds and the level it had.
--- @type table<tes3cell, { count: number, level: number }>
local flaggedCells = {}
local restoredForSave = false

local function needsFlag(cell)
    return cell and cell.isInterior and not cell.behavesAsExterior and not cell.hasWater
end

-- The level of a cell can be read and written only while the cell is flagged.
local function sinkWater(cell)
    cell.hasWater = true
    cell.waterLevel = SUNKEN_LEVEL
end

local function restoreWater(cell, level)
    if level then
        cell.waterLevel = level
    end
    cell.hasWater = false
end

local function flagCell(cell)
    local flag = flaggedCells[cell]
    if flag then
        flag.count = flag.count + 1
    elseif needsFlag(cell) then
        cell.hasWater = true
        flaggedCells[cell] = { count = 1, level = cell.waterLevel }
        sinkWater(cell)
    end
end

local function unflagCell(cell)
    local flag = flaggedCells[cell]
    if not flag then
        return
    end
    if flag.count > 1 then
        flag.count = flag.count - 1
    else
        flaggedCells[cell] = nil
        restoreWater(cell, flag.level)
    end
end

local function setFlagsForSave(saving)
    for cell, flag in pairs(flaggedCells) do
        if saving then
            restoreWater(cell, flag.level)
        else
            sinkWater(cell)
        end
    end
    restoredForSave = saving
end

--
-- Tracking.
--

--- The active cells as a set. Made when asked for and dropped every frame and cell change.
local activeCells = nil

local function isActive(cell)
    if not activeCells then
        activeCells = {}
        for _, active in ipairs(tes3.getActiveCells()) do
            activeCells[active] = true
        end
    end
    return activeCells[cell] == true
end

local function addressOf(node)
    return mwse.memory.convertFrom.niObject(node)
end

--- Takes up the mesh of a tracked reference: the one it has now, which is not the one it had
--- if the mesh was loaded anew.
local function prepare(reference, entry, node)
    entry.node = addressOf(node)
    local properties = prepareNode(node, entry.settings.marker)
    animated[reference] = #properties > 0 and properties or nil
end

--- @param reference tes3reference
--- @param onlyIfActive boolean? Leave the reference alone unless its cell is active.
local function track(reference, onlyIfActive)
    if tracked[reference] then
        return
    end
    local object = reference.baseObject
    local objectType = object and object.objectType
    if objectType ~= STATIC and objectType ~= ACTIVATOR then
        return
    end
    local node = reference.sceneNode
    if not node then
        return
    end
    local settings = getSettings(object, node)
    if not settings or (onlyIfActive and not isActive(reference.cell)) then
        return
    end

    local index = #order + 1
    local entry = { settings = settings, cell = reference.cell, index = index, id = nil, node = nil }
    order[index] = reference
    tracked[reference] = entry
    pending[#pending + 1] = reference
    flagCell(entry.cell)
    prepare(reference, entry, node)
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

    -- The last of the list takes the place of this one.
    local last = #order
    local moved = order[last]
    order[entry.index] = moved
    tracked[moved].index = entry.index
    order[last] = nil

    tracked[reference] = nil
    animated[reference] = nil
end

local function untrackAll()
    for i = #order, 1, -1 do
        untrack(order[i])
    end
    pending = {}
    cursor = 0
end

--- Brings the water of one reference in line with the reference.
local function syncReference(controller, reference)
    local entry = tracked[reference]
    if not entry then
        return
    end
    local node = reference.sceneNode
    if reference.deleted or not node then
        untrack(reference)
        return
    end
    local renewed = addressOf(node) ~= entry.node
    if renewed then
        prepare(reference, entry, node)
    end
    if reference.disabled then
        if entry.id then
            controller:removeVolume(entry.id)
            entry.id = nil
        end
        return
    end

    local p, o, scale = reference.position, reference.orientation, reference.scale
    local px, py, pz, ox, oy, oz = p.x, p.y, p.z, o.x, o.y, o.z
    if entry.id and not renewed
        and px == entry.px and py == entry.py and pz == entry.pz
        and ox == entry.ox and oy == entry.oy and oz == entry.oz
        and scale == entry.scale then
        return
    end

    if entry.id then
        controller:removeVolume(entry.id)
    end
    node:update()
    -- The depth is given for the mesh as modelled, so it scales with the reference.
    entry.id = controller:addVolume{ node = node, depth = entry.settings.depth * scale }
    entry.px, entry.py, entry.pz, entry.ox, entry.oy, entry.oz, entry.scale = px, py, pz, ox, oy, oz, scale
end

local function sync()
    local controller = getController()
    if not controller then
        return
    end

    if #pending > 0 then
        local list = pending
        pending = {}
        for i = 1, #list do
            syncReference(controller, list[i])
        end
    end

    for _ = 1, math.min(#order, SYNC_PER_FRAME) do
        if cursor >= #order then
            cursor = 0
        end
        cursor = cursor + 1
        local reference = order[cursor]
        if reference then
            syncReference(controller, reference)
        end
    end
end

local function scanActiveCells()
    for _, cell in ipairs(tes3.getActiveCells()) do
        for reference in cell:iterateReferences{ STATIC, ACTIVATOR } do
            track(reference)
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
        track(e.reference, true)
    end)
    event.register("referenceDeactivated", function(e)
        untrack(e.reference)
    end)
    event.register("cellChanged", function()
        activeCells = nil
    end)
    event.register("load", untrackAll)
    event.register("loaded", function()
        activeCells = nil
        scanActiveCells()
    end)
    event.register("save", function() setFlagsForSave(true) end, { priority = -1000 })
    event.register("saved", function() setFlagsForSave(false) end)
    event.register("enterFrame", function()
        activeCells = nil
        -- A save that failed never said it was done.
        if restoredForSave then
            setFlagsForSave(false)
        end
        sync()
        animate()
    end)
    log("Initialized.")
end)
