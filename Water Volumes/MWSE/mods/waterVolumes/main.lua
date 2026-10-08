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

    The mod also sends the events of interop.lua: ten times a second it asks the plugin, for
    each actor that is in the simulation, which water its feet are in.
]]

local interop = require("waterVolumes.interop")

local STATIC = tes3.objectType.static
local ACTIVATOR = tes3.objectType.activator

--- @type table<tes3reference, table>
local tracked = {}
--- The tracked references by the id of their volume in the plugin.
--- @type table<number, tes3reference>
local byId = interop.volumes
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
--- WaterBody is water without it. A mesh that has only a WaterMask, a dry space, gives
--- "watermask": it holds no water of its own.
local function tagText(node)
    local tag = interop.tag:lower()
    local named, body, mask = nil, false, false
    local function look(object)
        local name = object.name
        if name then
            name = name:lower()
            if name:sub(1, #tag) == tag then
                named = name
                return
            end
            body = body or name:sub(1, 9) == "waterbody"
            mask = mask or name:sub(1, 9) == "watermask"
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
    return named or (body and tag) or (mask and "watermask") or nil
end

--- The look line of a mesh: the text after "wv:" in the first string extra data that starts
--- with it, on the root or on any object under it. Nil if there is none.
local function lookText(node)
    local found
    local function look(object)
        local data = object.extraData
        while data and not found do
            local text = data.string
            if type(text) == "string" then
                local rest = text:match("^%s*[Ww][Vv]:%s*(.*)$")
                if rest then
                    found = rest
                end
            end
            data = data.next
        end
        local children = object.children
        if children then
            for _, child in ipairs(children) do
                if child and not found then
                    look(child)
                end
            end
        end
    end
    look(node)
    return found
end

--- The slot of a look, shared by every object with the same look. A new look gets the next
--- slot and is sent to the renderer.
local lookSlots, lookCount = {}, 0
local MAX_LOOKS = 4000
local function slotOf(look)
    local key = interop.lookKey(look)
    local slot = lookSlots[key]
    if slot then
        return slot
    end
    if lookCount >= MAX_LOOKS then
        if lookCount == MAX_LOOKS then
            lookCount = lookCount + 1
            mwse.log("[Water Volumes] More than %d different looks in one session. A new look is not shown.", MAX_LOOKS)
        end
        return nil
    end
    lookCount = lookCount + 1
    slot = lookCount
    lookSlots[key] = slot
    local sent = {
        reflectsScene = look.reflect ~= "sky",
        tintFromVertex = look.tint == "vertex",
        opacityFromVertex = look.opacity == "vertex",
        flow = type(look.flow) == "table" and look.flow or nil,
        speed = look.speed, scale = look.scale, glow = look.glow,
        opacity = type(look.opacity) == "number" and look.opacity or nil,
        clarity = tonumber(look.clarity),
        shader = look.shader,
        params = { look.p0, look.p1, look.p2, look.p3 },
        sky = look.sky and { interop.parseColor(look.sky) } or nil,
    }
    interop.native.setLook(slot, sent)
    return slot
end

--- Sets the material marker of settings from their look.
local function setMarker(settings)
    local look = settings.look
    settings.marker = nil
    if settings.plain then
        return
    end
    if settings.skyOnly and look then
        look.reflect = "sky"
    end
    local slot = look and interop.hasLooks and slotOf(look)
    if slot then
        settings.marker = interop.lookMarkerBase + slot
    else
        settings.marker = (settings.skyOnly or (look and look.reflect == "sky")) and interop.surfaceMarkerSkyOnly or interop.surfaceMarker
    end
end

--- The settings for an object, or nil if it is not water. The node is that of one of its references.
--- depth: how far the water reaches below the surface.
--- marker: the material marker for the renderer's water shading, or nil to keep the mesh's own look.
--- swim: false for a mesh that only looks like water.
--- solid: the mesh does not say that it has no collision, so the mod has to switch it off.
--- color: the colour a registration gives the water, in place of the one in the mesh.
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

    local depth, plain, skyOnly, noSwim, color, look
    local registered = interop.objects[id:lower()]
    if registered then
        depth, plain, skyOnly, noSwim = registered.depth, registered.plain == true, registered.skyOnly == true, registered.noSwim == true
        local red, green, blue = interop.parseColor(registered.color)
        color = red and niColor.new(red, green, blue)
        look = interop.parseLook(registered.look)
    else
        local text = tagText(node)
        if text then
            depth = tonumber(text:match("depth%s*=%s*([%d%.]+)"))
            plain = text:find("%f[%a]plain%f[%A]") ~= nil
            skyOnly = text:find("%f[%a]skyonly%f[%A]") ~= nil
            noSwim = text:find("%f[%a]noswim%f[%A]") ~= nil
            look = interop.parseLook(lookText(node))
        else
            settingsByObject[id] = false
            return nil
        end
    end
    local scripted = interop.objectLooks[id:lower()]
    if scripted ~= nil then
        look = interop.parseLook(scripted)
    end
    if look and look.extra then
        for key in pairs(look.extra) do
            mwse.log("[Water Volumes] %s: the look key '%s' is not one the mod knows. A water shader takes its values as p0 to p3.", id, key)
        end
    end

    known = { depth = depth or interop.defaultDepth, swim = not noSwim, solid = not node:hasStringDataStartingWith("NCO"), color = color,
        look = look, plain = plain, skyOnly = skyOnly }
    -- A mesh with a mask and no water is something else that keeps water out, a boat: it
    -- stays solid, and its cell needs no water flag for it.
    if not registered and tagText(node) == "watermask" then
        known.maskOnly = true
        known.solid = false
    end
    setMarker(known)
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
--- The same holds for a shape named WaterMask, the dry space of a mesh.
local function isWaterBody(object)
    if object.name == nil then
        return false
    end
    local name = object.name:lower()
    return name:find("^waterbody") ~= nil or name:find("^watermask") ~= nil
end

local function isWaterMask(object)
    return object.name ~= nil and object.name:lower():find("^watermask") ~= nil
end

--- Hides the bodies, marks the surfaces for the renderer, and returns the base maps to
--- animate. Everything under a WaterBody is body: an exporter may write one object as a group
--- of shapes, one per material. The colour of the water is the emissive colour of a marked
--- surface: the one given, or else the one the mesh has. It comes back as "color" in the maps
--- when it is not black.
local function prepareNode(node, marker, color)
    local prefix = getSurfacePrefix()
    local maps = { owners = {} }
    -- A mesh that names its water has water only there, and its other shapes are left as
    -- they are: a well has posts and a roof. A mesh with no such name is water as a whole.
    local tag = interop.tag:lower()
    local function isSurface(object)
        return object.name ~= nil and object.name:lower():sub(1, #tag) == tag
    end
    local function hasSurface(object)
        if isSurface(object) or isWaterMask(object) then
            return true
        end
        for _, child in ipairs(object.children or {}) do
            if child and hasSurface(child) then
                return true
            end
        end
        return false
    end
    local namedOnly = hasSurface(node)
    local function walk(object, inSurface)
        if isWaterBody(object) then
            object.appCulled = true
            return
        end
        inSurface = inSurface or isSurface(object)
        if namedOnly and not inSurface then
            -- Not water. Its children can be.
            for _, child in ipairs(object.children or {}) do
                if child then
                    walk(child, false)
                end
            end
            return
        end
        if marker and object:isInstanceOfType(ni.type.NiTriShape) then
            -- A material of its own, so that other users of the mesh keep theirs.
            local material = object.materialProperty
            material = material and material:clone() or niMaterialProperty.new()
            material.shininess = marker
            if color then
                material.emissive = color
            end
            object.materialProperty = material
            object:updateProperties()
            if not maps.color then
                local emissive = material.emissive
                if emissive.r > 0 or emissive.g > 0 or emissive.b > 0 then
                    maps.color = emissive
                end
            end
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
                    walk(child, inSurface)
                end
            end
        end
    end
    walk(node, false)
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
    local maps = prepareNode(node, entry.settings.marker, entry.settings.color)
    entry.color = maps.color
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
    -- A look of its own for this reference
    local own = interop.referenceLooks[reference]
    if own ~= nil then
        local copy = {}
        for key, value in pairs(settings) do
            copy[key] = value
        end
        copy.look = interop.parseLook(own)
        setMarker(copy)
        settings = copy
    end

    local entry = { settings = settings, cell = reference.cell, id = 0 }
    tracked[reference] = entry
    if settings.swim and not settings.maskOnly then
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
        local color = entry.color
        if color then
            interop.native.setColor(entry.id, color.r, color.g, color.b)
        end
        -- The flow of the look is a current for the actors in the water.
        local look = settings.look
        if look and type(look.flow) == "table" and look.flow[1] and look.flow[2] then
            local carry = look.carry
            local byDepth = carry == "depth"
            interop.native.setFlow(entry.id, look.flow[1], look.flow[2], type(carry) == "number" and carry or 1, byDepth)
        end
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
    if entry.settings.swim and not entry.settings.maskOnly then
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

--
-- Events: who is in which water.
--

--- The water reference each actor's feet are in, by the actor's reference.
--- @type table<tes3reference, tes3reference>
local inside = {}
local cameraInside = nil
local POLL_SECONDS = 0.1
local sincePoll = 0

local function send(name, actor, mobile, volume, surface)
    event.trigger(name, { reference = actor, mobile = mobile, volume = volume, surface = surface }, { filter = actor })
end

local function pollActor(mobile)
    local actor = mobile.reference
    if not actor then
        return
    end
    local position = actor.position
    local id, surface = interop.native.waterAt(position.x, position.y, position.z + 1)
    local volume = id and byId[id] or nil
    local before = inside[actor]
    if volume == before then
        return
    end
    if before then
        send("waterVolumes:leave", actor, mobile, before, nil)
    end
    inside[actor] = volume
    if volume then
        send("waterVolumes:enter", actor, mobile, volume, surface)
    end
end

local function pollActors()
    if interop.native.count() == 0 and next(inside) == nil then
        return
    end
    local player = tes3.mobilePlayer
    if player then
        pollActor(player)
    end
    for _, mobile in pairs(tes3.worldController.allMobileActors) do
        if mobile ~= player then
            pollActor(mobile)
        end
    end
end

local function pollCamera()
    local volume = nil
    if interop.native.count() > 0 then
        local position = tes3.getCameraPosition()
        local id = position and interop.native.waterAt(position.x, position.y, position.z)
        volume = id and byId[id] or nil
    end
    if volume == cameraInside then
        return
    end
    if cameraInside then
        event.trigger("waterVolumes:cameraLeave", { volume = cameraInside })
    end
    cameraInside = volume
    if volume then
        event.trigger("waterVolumes:cameraEnter", { volume = volume })
    end
end

--
-- A level that moves.
--

local function finishLevel(reference, animation)
    interop.levelAnimations[reference] = nil
    if animation.callback then
        animation.callback(reference)
    end
    event.trigger("waterVolumes:levelReached", { reference = reference, level = animation.to }, { filter = reference })
end

local function setLevel(reference, z)
    local position = reference.position
    reference.position = tes3vector3.new(position.x, position.y, z)
end

local function moveLevels(delta)
    local finished = nil
    for reference, animation in pairs(interop.levelAnimations) do
        animation.elapsed = animation.elapsed + delta
        local t = animation.seconds > 0 and math.min(animation.elapsed / animation.seconds, 1) or 1
        local eased = animation.linear and t or t * t * (3 - 2 * t)
        setLevel(reference, animation.from + (animation.to - animation.from) * eased)
        if t >= 1 then
            finished = finished or {}
            finished[reference] = animation
        end
    end
    if finished then
        for reference, animation in pairs(finished) do
            -- A callback of an earlier one in this list may have started a new move.
            if interop.levelAnimations[reference] == animation then
                finishLevel(reference, animation)
            end
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
        local reference = e.reference
        local animation = interop.levelAnimations[reference]
        if animation then
            setLevel(reference, animation.to)
            finishLevel(reference, animation)
        end
        local volume = inside[reference]
        if volume then
            inside[reference] = nil
            send("waterVolumes:leave", reference, reference.mobile, volume, nil)
        end
        untrack(reference)
    end)
    event.register("cellChanged", function()
        activeCells = nil
    end)
    event.register("load", function()
        untrackAll()
        inside, cameraInside = {}, nil
        interop.referenceLooks = {}
        interop.levelAnimations = {}
    end)
    event.register("simulate", function(e)
        if next(interop.levelAnimations) ~= nil then
            moveLevels(e.delta)
        end
        sincePoll = sincePoll + e.delta
        if sincePoll >= POLL_SECONDS and interop.native.waterAt then
            sincePoll = 0
            pollActors()
        end
    end)
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
        if interop.native.waterAt then
            pollCamera()
        end
    end)
    log("Initialized.")
end)
