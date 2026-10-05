--[[
    Water Volumes

    Turns placed references into water. A reference counts when it is a static or an activator
    and its mesh is marked as water or its object id is registered through interop.lua. The
    water is what is inside the mesh. A mesh that is only a surface is closed with a bottom the
    configured depth below it.

    The mod finds the references and prepares their meshes. The plugin, watervolumes.dll, holds
    the water and keeps it in line with each reference: moving, scaling, disabling, enabling or
    deleting the reference moves or removes the water by the next frame. Nothing is done per
    reference in Lua per frame.
]]

local interop = require("waterVolumes.interop")

local STATIC = tes3.objectType.static
local ACTIVATOR = tes3.objectType.activator

--- @type table<tes3reference, table>
local tracked = {}
--- The tracked references by the id of their volume in the plugin.
--- @type table<number, tes3reference>
local byId = {}
--- The base maps to animate, for the references that have any. Each list also holds the
--- properties the maps belong to, under "owners", so that the maps stay alive.
--- @type table<tes3reference, table>
local animated = {}
local flip = nil
--- A reference had its collision switched off and the game has not taken it up yet.
local collisionsStale = false

local function log(fmt, ...)
    mwse.log("[Water Volumes] " .. fmt, ...)
end

--- Settings per object id: a table for water, false for anything else. The tag is on the mesh,
--- so every reference of an object has the same answer and the mesh is looked at once.
local settingsByObject = {}
local settingsRevision = 0

--- The text that makes a mesh water, in lower case, or nil if it is not water: the name of the
--- first object in the mesh whose name starts with the tag, options included. A mesh with a
--- WaterBody is water without it.
local function tagText(node)
    local tag = interop.tag:lower()
    local named, body = nil, false
    local function look(object)
        local name = object.name
        if name then
            name = name:lower()
            if name:sub(1, #tag) == tag then
                named = name
                return
            end
            body = body or name:sub(1, 9) == "waterbody"
        end
        local children = object.children
        if children then
            for _, child in ipairs(children) do
                if child and not named then
                    look(child)
                end
            end
        end
    end
    look(node)
    return named or (body and tag) or nil
end

--- The settings for an object, or nil if it is not water. The node is that of one of its references.
--- depth: how far the water reaches below the surface.
--- marker: the material marker for the renderer's water shading, or nil to keep the mesh's own look.
--- swim: false for a mesh that only looks like water.
--- solid: the mesh does not say that it has no collision, so the mod has to switch it off.
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

    local depth, plain, skyOnly, noSwim
    local registered = interop.objects[id:lower()]
    if registered then
        depth, plain, skyOnly, noSwim = registered.depth, registered.plain == true, registered.skyOnly == true, registered.noSwim == true
    else
        local text = tagText(node)
        if text then
            depth = tonumber(text:match("depth%s*=%s*([%d%.]+)"))
            plain = text:find("%f[%a]plain%f[%A]") ~= nil
            skyOnly = text:find("%f[%a]skyonly%f[%A]") ~= nil
            noSwim = text:find("%f[%a]noswim%f[%A]") ~= nil
        else
            settingsByObject[id] = false
            return nil
        end
    end

    known = { depth = depth or interop.defaultDepth, swim = not noSwim, solid = not node:hasStringDataStartingWith("NCO") }
    if not plain then
        known.marker = skyOnly and interop.surfaceMarkerSkyOnly or interop.surfaceMarker
    end
    settingsByObject[id] = known
    return known
end

--
-- Surface animation for meshes that use the engine's water surface frames.
--

local surfacePrefix = nil

--- What the file names of the engine's water surface frames start with, in lower case.
local function getSurfacePrefix()
    if not surfacePrefix then
        surfacePrefix = tes3.dataHandler.waterController.surfaceTexturePath:lower():match("([^\\/]+)$")
    end
    return surfacePrefix
end

--- The frames are loaded when the first mesh that uses them is taken up.
local function loadFlip()
    if flip then
        return
    end
    local controller = tes3.dataHandler.waterController
    local base = controller.surfaceTexturePath
    flip = { frames = {}, fps = controller.surfaceFPS, index = 0 }
    for i = 0, controller.surfaceFrameCount - 1 do
        local texture = niSourceTexture.createFromPath(string.format("%s%02d.tga", base, i))
        if texture then
            flip.frames[#flip.frames + 1] = texture
        end
    end
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
    for _, maps in pairs(animated) do
        for i = 1, #maps do
            maps[i].texture = texture
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

--- Hides the bodies, marks the surfaces for the renderer, and returns the base maps to
--- animate. Everything under a WaterBody is body: an exporter may write one object as a group
--- of shapes, one per material.
local function prepareNode(node, marker)
    local prefix = getSurfacePrefix()
    local maps = { owners = {} }
    local function walk(object)
        if isWaterBody(object) then
            object.appCulled = true
            return
        end
        if marker and object:isInstanceOfType(ni.type.NiTriShape) then
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
            maps[#maps + 1] = property.baseMap
            maps.owners[#maps] = property
        end

        local children = object.children
        if children then
            for _, child in ipairs(children) do
                if child then
                    walk(child)
                end
            end
        end
    end
    walk(node)
    return maps
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

--- A save holds the game as it would be without the mod: the cells without the flag, and the
--- references with their collision. Both are put back as soon as the save is written.
local function setFlagsForSave(saving)
    for cell, flag in pairs(flaggedCells) do
        if saving then
            restoreWater(cell, flag.level)
        else
            sinkWater(cell)
        end
    end
    for reference, entry in pairs(tracked) do
        if entry.madePassable then
            reference:setNoCollisionFlag(not saving, false)
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

--- Takes up the mesh of a tracked reference: the one it has now, which is not the one it had
--- if the mesh was loaded anew.
local function prepare(reference, entry, node)
    local maps = prepareNode(node, entry.settings.marker)
    if #maps > 0 then
        loadFlip()
        animated[reference] = maps
    else
        animated[reference] = nil
    end
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

    local entry = { settings = settings, cell = reference.cell, id = 0 }
    tracked[reference] = entry
    if settings.swim then
        flagCell(entry.cell)
    end
    -- Nobody walks on water. A mesh that does not say so itself is told here; the game takes
    -- it up when the collisions are next worked out, which is asked for once.
    if settings.solid and not reference.hasNoCollision then
        reference:setNoCollisionFlag(true, false)
        entry.madePassable = true
        collisionsStale = true
    end
    prepare(reference, entry, node)

    -- From here on the plugin keeps the water in line with the reference. A mesh that only
    -- looks like water holds none, and is followed for its mesh alone.
    entry.id = interop.native.addReference(mwse.memory.convertFrom.tes3object(reference), settings.depth, settings.swim)
    if entry.id ~= 0 then
        byId[entry.id] = reference
    end
end

local function untrack(reference)
    local entry = tracked[reference]
    if not entry then
        return
    end
    if entry.id ~= 0 then
        interop.native.remove(entry.id)
        byId[entry.id] = nil
    end
    if entry.settings.swim then
        unflagCell(entry.cell)
    end
    -- What the mod changed on the reference is changed back.
    if entry.madePassable then
        reference:setNoCollisionFlag(false, false)
    end
    tracked[reference] = nil
    animated[reference] = nil
end

local function untrackAll()
    for reference in pairs(tracked) do
        untrack(reference)
    end
end

--- Once per frame. The plugin looks at every tracked reference; a reference whose mesh was
--- loaded anew comes back, and its new mesh is prepared.
local function update()
    if collisionsStale then
        collisionsStale = false
        tes3.dataHandler:updateCollisionGroupsForActiveCells()
    end

    local renewed = interop.native.update()
    if renewed then
        for i = 1, #renewed do
            local reference = byId[renewed[i]]
            local node = reference and reference.sceneNode
            if node then
                prepare(reference, tracked[reference], node)
            end
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
    if not interop.supported then
        log("The mod is inactive. %s", interop.problem or "The engine hooks of watervolumes.dll could not be installed.")
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
    local seenRevision = interop.revision
    event.register("enterFrame", function()
        activeCells = nil
        -- A save that failed never said it was done.
        if restoredForSave then
            setFlagsForSave(false)
        end
        -- A mod registered an object: what is loaded is looked at again with the new settings.
        if seenRevision ~= interop.revision then
            seenRevision = interop.revision
            untrackAll()
            scanActiveCells()
        end
        update()
        animate()
    end)
    log("Initialized.")
end)
