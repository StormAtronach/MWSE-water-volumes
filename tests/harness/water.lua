---@diagnostic disable
-- Water volume scenarios, dispatched from dump.lua by spec.water.
--   "look"  takes screenshots of a placed disc with the renderer's water shading and with the plain option.
--   "stress" measures many actors, many volumes, many surfaces, a volume that moves every frame.
--   "grid"  ponds a plugin placed across four cells: which are loaded, which are water, how they look.
--   "interior" a disc over the player in an interior with water and in one without.
--   "river" pieces that meet at a cell border and a piece that lies across one.
--   "plugin" checks a reference that a plugin placed (run_dump.py adds the plugin for the run).
--   "test"  places a kit disc as an ordinary reference in an exterior basin near Vas and checks
--           that the Water Volumes mod turns it into water: footprint, swimming, disable and
--           enable, moving the reference. Needs the Water Volumes mod with its kit meshes.
--   The other modes are described at their functions.

local this = {}

-- A basin on the hill by the Telvanni tower near Vas, exterior cell (0, 22).
local SITE = { x = 7060, y = 186303, level = 620 }

-- The water volumes come from the Water Volumes mod. The scenarios were written against an
-- object with methods, so the mod's functions are given that form here.
local function waterController()
  local interop = require("waterVolumes.interop")
  return {
    volumesSupported = interop.supported,
    getVolumeSurfaceAt = function(_, position) return interop.getVolumeSurfaceAt(position) end,
  }
end

local function sequence(steps, say, after, finish)
  local index = 0
  local function nextStep()
    index = index + 1
    local step = steps[index]
    if not step then
      finish()
      return
    end
    after(step.wait or 1, function()
      say("step %d of %d: %s", index, #steps, step.name)
      step.run()
      nextStep()
    end)
  end
  nextStep()
end

local function groundAt(x, y)
  local hit = tes3.rayTest({
    position = tes3vector3.new(x, y, 100000), direction = tes3vector3.new(0, 0, -1), root = tes3.game.worldLandscapeRoot,
  })
  return hit and hit.intersection.z or nil
end

local function runDirectory(spec)
  return spec.dumpFile:match("^(.*)/")
end

-------------------------------------------------------------------------------
-- Kit
-------------------------------------------------------------------------------

--- The pieces of the kit, from the list that tools/make_kit.py of the Water Volumes repository
--- writes into the mod: name, depth, surface points, and for river pieces the number of points
--- in a row and the joint.
local kitList
local function kitPieces()
  if not kitList then
    local manifest = json.loadfile("mods\\waterVolumes\\kit")
    if not manifest then error("the Water Volumes mod has no list of kit pieces (kit.json)") end
    kitList = manifest.pieces
  end
  return kitList
end

--- Many pieces of water away from everything: references of a kit square in the eight active
--- cells around the player's cell, far under the ground, where nothing swims and nothing is
--- drawn. Each layer holds 2048 pieces side by side; more pieces go into further layers.
local farPieces = {}
local function addFarPieces(count, objectId)
  local interop = require("waterVolumes.interop")
  local object = tes3.getObject(objectId or "wv_square_512")
  if not object then error("the object for the far pieces is missing: " .. tostring(objectId or "wv_square_512")) end
  local home = tes3.player.cell
  if home.isInterior then error("far pieces need an exterior cell") end
  local before = interop.native.count()
  local placed, index = 0, #farPieces
  while placed < count do
    local layer = math.floor(index / 2048)
    local inLayer = index % 2048
    local cellIndex = math.floor(inLayer / 256)
    local inCell = inLayer % 256
    -- The eight cells around the middle one, in order.
    local slot = cellIndex >= 4 and cellIndex + 1 or cellIndex
    local gridX, gridY = home.gridX + slot % 3 - 1, home.gridY + math.floor(slot / 3) - 1
    local px = gridX * 8192 + 256 + (inCell % 16) * 512
    local py = gridY * 8192 + 256 + math.floor(inCell / 16) * 512
    local pz = -20000 - layer * 600
    farPieces[#farPieces + 1] = tes3.createReference({ object = object, position = { px, py, pz }, orientation = { 0, 0, 0 },
      cell = tes3.getCell({ position = tes3vector3.new(px, py, pz) }) })
    placed = placed + 1
    index = index + 1
  end
  return interop.native.count() - before
end
local function removeFarPieces()
  for _, piece in ipairs(farPieces) do piece:delete() end
  farPieces = {}
end

-------------------------------------------------------------------------------
-- Test
-------------------------------------------------------------------------------

local camera = nil
event.register("cameraControl", function(e)
  if not camera then return end
  local transform = e.cameraTransform
  local rotation = tes3matrix33.new()
  rotation:lookAt((camera.target - camera.position):normalized(), tes3vector3.new(0, 0, 1))
  transform.translation = camera.position
  transform.rotation = rotation
  e.cameraTransform = transform
end)

local function runTest(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local x, y, level = SITE.x, SITE.y, SITE.level
  local ground, reference
  local shots = 0

  local function surface(px, py, pz)
    return controller:getVolumeSurfaceAt({ px, py, pz })
  end
  local function expectSurface(name, px, py, pz, expected)
    local found = surface(px, py, pz)
    note(found == expected, name, string.format("surface %s, expected %s", tostring(found), tostring(expected)))
  end
  local function expectSwimming(name, expected)
    note(player.isSwimming == expected, name, string.format("z %.0f, swimming %s, underwater %s",
      tes3.player.position.z, tostring(player.isSwimming), tostring(player.underwater)))
    local ok, interop = pcall(require, "waterVolumes.interop")
    if ok and interop.native and interop.native.hookStatus then
      local intact, total = interop.native.hookStatus()
      say("plugin: %d of %d hooks in place; %d volumes", intact, total, interop.native.count())
    end
  end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%02d-%s.jpg", runDirectory(spec), shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end

  sequence({
    { name = "god mode on, player to the basin near Vas", wait = 1, run = function()
      if not controller.volumesSupported then
        error("this MWSE build has no water volume support")
      end
      tes3.mobilePlayer.vanityDisabled = true
      tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
      tes3.worldController.menuController.godModeEnabled = true
      tes3.worldController.hour.value = 13
      tes3.changeWeather({ id = 0, immediate = true })
      tes3.positionCell({ reference = tes3.player, position = { x, y, level + 150 } })
    end },
    { name = "place a kit disc as a reference", wait = 8, run = function()
      ground = groundAt(x, y)
      if not ground then error("no landscape under the test site") end
      say("ground %.0f, water level %d, depth %.0f", ground, level, level - ground)
      local object = tes3.getObject("wv_test_disc") or tes3.createObject({
        objectType = tes3.objectType.static, id = "wv_test_disc", mesh = "wv\\wv_disc_1024.nif",
      })
      reference = tes3.createReference({ object = object, position = { x, y, level }, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
    end },
    { name = "the mesh is tagged and the footprint is the disc", wait = 3, run = function()
      local node = reference.sceneNode
      note(node ~= nil and node:getObjectByName("WaterVolume") ~= nil, "tag", "a shape named WaterVolume in the reference's scene node")
      expectSurface("centre", x, y, level - 50, level)
      expectSurface("inside the disc near the rim", x + 480, y, level - 50, level)
      expectSurface("corner of the bounding box, outside the disc", x + 450, y + 450, level - 50, nil)
      expectSurface("outside the bounding box", x + 700, y, level - 50, nil)
      expectSurface("below the floor", x, y, level - 600, nil)
    end },
    { name = "player to the bottom of the pond, first person", wait = 1, run = function()
      tes3.force1stPerson()
      tes3.positionCell({ reference = tes3.player, position = { x, y, ground + 5 } })
    end },
    { name = "player swims and is underwater", wait = 5, run = function()
      expectSwimming("player in the pond", true)
      note(player.underwater == true, "underwater flag", tostring(player.underwater))
      shot("first-person-under")
    end },
    { name = "disable the reference: the water goes", wait = 2, run = function()
      reference:disable()
    end },
    { name = "no water while disabled", wait = 3, run = function()
      expectSurface("centre while disabled", x, y, level - 50, nil)
      expectSwimming("player while disabled", false)
      reference:enable()
    end },
    { name = "water is back after enable", wait = 3, run = function()
      expectSurface("centre after enable", x, y, level - 50, level)
      expectSwimming("player after enable", true)
      reference.position = tes3vector3.new(x, y, level + 100)
    end },
    { name = "the water follows the reference when it moves", wait = 2, run = function()
      expectSurface("centre after raising the reference by 100", x, y, level - 50, level + 100)
      tes3.force3rdPerson()
      camera = { position = tes3vector3.new(x - 700, y - 700, level + 600), target = tes3vector3.new(x, y, level + 100) }
    end },
    { name = "screenshot from above", wait = 2, run = function()
      shot("from-above")
    end },
    { name = "tilt the reference by 5 degrees: the surface slopes", wait = 1, run = function()
      camera = nil
      tes3.force1stPerson()
      reference.position = tes3vector3.new(x, y, level + 60)
      reference.orientation = tes3vector3.new(0, math.rad(5), 0)
    end },
    { name = "the level follows the slope", wait = 3, run = function()
      local level = level + 60
      local centre, plus, minus, across = surface(x, y, level - 50), surface(x + 400, y, level - 50), surface(x - 400, y, level - 50), surface(x, y + 400, level - 50)
      if not (centre and plus and minus and across) then
        note(false, "sloped surface", string.format("centre %s, +400 %s, -400 %s, across %s", tostring(centre), tostring(plus), tostring(minus), tostring(across)))
        return
      end
      local expected = 2 * 400 * math.tan(math.rad(5))
      note(math.abs(centre - level) < 1, "slope: centre keeps its height", string.format("%.1f, expected %d", centre, level))
      note(math.abs(math.abs(plus - minus) - expected) < 2, "slope: height differs across the tilt",
        string.format("+400: %.1f, -400: %.1f, difference %.1f, expected %.1f", plus, minus, math.abs(plus - minus), expected))
      note(math.abs(across - centre) < 1, "slope: level along the tilt axis", string.format("%.1f against %.1f", across, centre))

      -- The player's head at the centre's height: under water on the high side, above it on the low side.
      local high = plus > minus and 1 or -1
      local feet = level - 125
      local groundHigh, groundLow = groundAt(x + high * 300, y), groundAt(x - high * 300, y)
      say("slope: ground %.0f on the high side, %.0f on the low side, feet at %.0f", groundHigh or -1, groundLow or -1, feet)
      this.slope = { high = high, feet = feet, usable = groundHigh and groundLow and groundHigh < feet - 5 and groundLow < feet - 5 }
      if this.slope.usable then
        tes3.positionCell({ reference = tes3.player, position = { x + high * 300, y, feet } })
      else
        say("slope: the ground is too high at the side points for the player check, skipped")
      end
    end },
    { name = "player on the high side of the slope", wait = 3, run = function()
      if not this.slope.usable then return end
      note(player.underwater == true, "slope: head under water on the high side",
        string.format("z %.0f, surface there %.1f, underwater %s", tes3.player.position.z, surface(x + this.slope.high * 300, y, level - 50) or -1, tostring(player.underwater)))
      tes3.positionCell({ reference = tes3.player, position = { x - this.slope.high * 300, y, this.slope.feet } })
    end },
    { name = "player on the low side of the slope", wait = 3, run = function()
      if not this.slope.usable then return end
      note(player.underwater == false, "slope: head above water on the low side",
        string.format("z %.0f, surface there %.1f, underwater %s", tes3.player.position.z, surface(x - this.slope.high * 300, y, level - 50) or -1, tostring(player.underwater)))
    end },
    { name = "timing", wait = 1, run = function()
      local function bench(count, fn)
        local started = os.clock()
        for _ = 1, count do fn() end
        return (os.clock() - started) / count * 1e9
      end
      local inside, corner, outside = { x, y, level - 50 }, { x + 450, y + 450, level - 50 }, { x + 5000, y, level - 50 }
      say("timing: lookup from Lua, disc of 32 triangles: inside %.0f ns, bounding box corner %.0f ns, outside %.0f ns",
        bench(1000000, function() controller:getVolumeSurfaceAt(inside) end),
        bench(1000000, function() controller:getVolumeSurfaceAt(corner) end),
        bench(1000000, function() controller:getVolumeSurfaceAt(outside) end))

      -- The engine's own query for the player through the hooks, with the player in a volume and with no volume at all.
      local rest = { checkForEnemies = false, showMessage = false }
      tes3.positionCell({ reference = tes3.player, position = { x, y, ground + 5 } })
      local withVolume = bench(200000, function() tes3.canRest(rest) end)
      tes3.positionCell({ reference = tes3.player, position = { x + 1500, y, level + 300 } })
      local outsideVolume = bench(200000, function() tes3.canRest(rest) end)
      reference:disable()
      this.bench = { withVolume = withVolume, outsideVolume = outsideVolume, rest = rest, bench = bench }
    end },
    { name = "timing without any volume", wait = 3, run = function()
      local b = this.bench
      local without = b.bench(200000, function() tes3.canRest(b.rest) end)
      say("timing: engine query for the player through tes3.canRest: %.0f ns in a volume, %.0f ns outside it, %.0f ns with no volume registered",
        b.withVolume, b.outsideVolume, without)
      reference:enable()
    end },
    { name = "clean up", wait = 2, run = function()
      camera = nil
      reference:delete()
      tes3.worldController.menuController.godModeEnabled = true
    end },
  }, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Plugin: a reference that a plugin placed, as the Construction Set would
-------------------------------------------------------------------------------

local function runPlugin(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local x, y, level = SITE.x, SITE.y, SITE.level
  local reference

  sequence({
    { name = "god mode on, player to the basin near Vas", wait = 1, run = function()
      if not controller.volumesSupported then
        error("this MWSE build has no water volume support")
      end
      tes3.mobilePlayer.vanityDisabled = true
      tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
      tes3.worldController.menuController.godModeEnabled = true
      tes3.worldController.hour.value = 13
      tes3.changeWeather({ id = 0, immediate = true })
      tes3.positionCell({ reference = tes3.player, position = { x, y, level + 150 } })
    end },
    { name = "the plugin's reference is in the cell and is water", wait = 8, run = function()
      reference = tes3.getReference("wv_demo_disc")
      note(reference ~= nil, "reference placed by the plugin", reference and
        string.format("%s from %s at %.0f, %.0f, %.0f", reference.id, tostring(reference.sourceMod), reference.position.x, reference.position.y, reference.position.z)
        or "not found")
      if not reference then return end
      local node = reference.sceneNode
      note(node ~= nil and node:getObjectByName("WaterVolume") ~= nil, "tag", "a shape named WaterVolume in the reference's scene node")
      local p = reference.position
      local centre = controller:getVolumeSurfaceAt({ p.x, p.y, p.z - 50 })
      note(centre == p.z, "water at the reference", string.format("surface %s, reference height %.0f", tostring(centre), p.z))
      local corner = controller:getVolumeSurfaceAt({ p.x + 450, p.y + 450, p.z - 50 })
      note(corner == nil, "no water at the corner of the bounding box", string.format("surface %s", tostring(corner)))
      tes3.force1stPerson()
      tes3.positionCell({ reference = tes3.player, position = { p.x, p.y, (groundAt(p.x, p.y) or p.z - 160) + 5 } })
    end },
    { name = "player swims in the plugin's water", wait = 5, run = function()
      if not reference then return end
      note(player.isSwimming == true and player.underwater == true, "player in the plugin's water",
        string.format("z %.0f, swimming %s, underwater %s", tes3.player.position.z, tostring(player.isSwimming), tostring(player.underwater)))
      local path = runDirectory(spec) .. "/01-plugin-first-person-under.jpg"
      os.remove(path)
      mge.saveScreenshot({ path = path })
      say("screenshot %s", path)
    end },
    { name = "clean up", wait = 2, run = function()
      tes3.worldController.menuController.godModeEnabled = true
    end },
  }, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Look: screenshots of a placed kit disc, with the renderer's water shading and without it
-------------------------------------------------------------------------------

local function runLook(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end

  local x, y, level = SITE.x, SITE.y, SITE.level
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local ground, reference
  local shots = 0

  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end
  local function look(fromX, fromY, fromZ, toX, toY, toZ)
    camera = { position = tes3vector3.new(fromX, fromY, fromZ), target = tes3vector3.new(toX, toY, toZ) }
  end
  local function above()
    look(x - 700, y - 700, level + 600, x, y, level)
  end
  local function shininess()
    local material
    for object in table.traverse({ reference.sceneNode }) do
      -- The surface, not the body under it.
      if object:isInstanceOfType(ni.type.NiTriShape) and not tostring(object.name):lower():find("^waterbody") then material = object.materialProperty end
    end
    return material and material.shininess
  end
  local function place(id, plain)
    if plain then
      require("waterVolumes.interop").registerObject(id, { plain = true })
    end
    local object = tes3.getObject(id) or tes3.createObject({ objectType = tes3.objectType.static, id = id, mesh = "wv\\wv_disc_1024.nif" })
    return tes3.createReference({ object = object, position = { x, y, level }, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
  end
  local function playerAway()
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { x - 900, y - 900, level + 200 } })
  end

  local steps = {
    { name = "god mode on, player to the basin near Vas", wait = 1, run = function()
      tes3.mobilePlayer.vanityDisabled = true
      tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
      tes3.worldController.menuController.godModeEnabled = true
      tes3.worldController.hour.value = 13
      tes3.changeWeather({ id = 0, immediate = true })
      tes3.positionCell({ reference = tes3.player, position = { x, y, level + 150 } })
    end },
    { name = "place a kit disc", wait = 8, run = function()
      ground = groundAt(x, y)
      reference = place("wv_look_disc", false)
      playerAway()
    end },
  }

  -- A view is set up in one step and photographed in the next, because the capture is taken
  -- a frame after it is asked for.
  local function view(name, settle, setup)
    steps[#steps + 1] = { name = "set up: " .. name, wait = 1.5, run = setup }
    steps[#steps + 1] = { name = "photograph: " .. name, wait = settle, run = function() shot(name) end }
  end

  view("renderer water from above midday", 4, function()
    above()
  end)
  steps[#steps + 1] = { name = "the surface carries the renderer's marker", wait = 1, run = function()
    note(shininess() == 99998, "surface marker", "material shininess " .. tostring(shininess()))
  end }
  view("renderer water grazing angle", 2, function()
    look(x - 480, y - 330, level + 55, x + 250, y + 150, level)
  end)
  view("renderer water straight down", 2, function()
    look(x + 200, y - 60, level + 420, x + 200, y, level)
  end)
  view("renderer water from above sunset", 5, function()
    tes3.worldController.hour.value = 18.6
    above()
  end)
  view("renderer water from above night", 5, function()
    tes3.worldController.hour.value = 1
  end)
  view("renderer water from above rain", 7, function()
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 4, immediate = true })
  end)
  view("renderer water tilted 5 degrees", 5, function()
    tes3.changeWeather({ id = 0, immediate = true })
    reference.orientation = tes3vector3.new(0, math.rad(5), 0)
  end)
  view("renderer water from below first person", 5, function()
    reference.orientation = tes3vector3.new(0, 0, 0)
    camera = nil
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { x, y, ground + 5 } })
  end)
  view("plain option own texture from above", 5, function()
    playerAway()
    reference:delete()
    reference = place("wv_look_plain", true)
    above()
  end)
  steps[#steps + 1] = { name = "the plain option leaves the material alone", wait = 1, run = function()
    note(shininess() ~= 99998, "plain option", "material shininess " .. tostring(shininess()))
  end }
  view("plain option own texture grazing angle", 2, function()
    look(x - 480, y - 330, level + 55, x + 250, y + 150, level)
  end)
  steps[#steps + 1] = { name = "clean up", wait = 2, run = function()
    camera = nil
    reference:delete()
    tes3.worldController.menuController.godModeEnabled = true
  end }

  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Stress: many actors, many volumes, many surfaces, a volume that moves every frame,
-- and the player thrown in and out of the water
-------------------------------------------------------------------------------

local ffi = require("ffi")
pcall(ffi.cdef, [[
  int QueryPerformanceCounter(int64_t* count);
  int QueryPerformanceFrequency(int64_t* frequency);
]])
local qpcCount, qpcFrequency = ffi.new("int64_t[1]"), ffi.new("int64_t[1]")
ffi.C.QueryPerformanceFrequency(qpcFrequency)
local function seconds()
  ffi.C.QueryPerformanceCounter(qpcCount)
  return tonumber(qpcCount[0]) / tonumber(qpcFrequency[0])
end

-- While set, times the actor simulation of every frame (between the simulate and simulated
-- events) and the frame itself.
local probe = nil
local churn = nil
event.register("simulate", function()
  if probe then probe.simStarted = seconds() end
end, { priority = 1000000 })
event.register("simulated", function()
  if probe and probe.simStarted then
    local taken = seconds() - probe.simStarted
    probe.sim = probe.sim + taken
    probe.simMax = math.max(probe.simMax, taken)
    probe.simFrames = probe.simFrames + 1
    probe.simStarted = nil
    if probe.samples then probe.samples[#probe.samples + 1] = taken end
  end
end, { priority = -1000000 })
event.register("enterFrame", function()
  if probe then
    local t = seconds()
    if probe.frameStarted then
      local taken = t - probe.frameStarted
      probe.frame = probe.frame + taken
      probe.frameMax = math.max(probe.frameMax, taken)
      probe.frames = probe.frames + 1
    end
    probe.frameStarted = t
  end
  if churn then
    churn.frames = churn.frames + 1
    churn.reference.position = tes3vector3.new(churn.x, churn.y, churn.z + 20 * math.sin(churn.frames / 10))
  end
end)

local function runStress(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function measured(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("MEASURED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local x, y, level = SITE.x, SITE.y, 900
  local dryX, dryY = 6612, 184767
  local pond
  local actors, surfaces = {}, {}
  local steps = {}

  local function step(name, wait, run)
    steps[#steps + 1] = { name = name, wait = wait, run = run }
  end

  -- Starts a probe in one step and reports it in the next.
  local function measure(name, duration, extra)
    step("measure: " .. name, 1, function()
      probe = { sim = 0, simMax = 0, simFrames = 0, frame = 0, frameMax = 0, frames = 0 }
    end)
    step("report: " .. name, duration, function()
      local p = probe
      probe = nil
      local swimming = 0
      for _, reference in ipairs(actors) do
        if reference.mobile and reference.mobile.isSwimming then swimming = swimming + 1 end
      end
      measured(name, string.format("simulation %.3f ms mean, %.3f ms max over %d frames; frame %.2f ms mean, %.2f ms max; %d of %d actors swimming%s",
        p.simFrames > 0 and p.sim / p.simFrames * 1000 or -1, p.simMax * 1000, p.simFrames,
        p.frames > 0 and p.frame / p.frames * 1000 or -1, p.frameMax * 1000, swimming, #actors, extra and (", " .. extra()) or ""))
    end)
  end

  local function restQueryNs()
    local rest = { checkForEnemies = false, showMessage = false }
    local started = seconds()
    for _ = 1, 100000 do tes3.canRest(rest) end
    return (seconds() - started) / 100000 * 1e9
  end

  local function addFarBoxes(count)
    say("far pieces: %d placed, %d more volumes hold water", count, addFarPieces(count))
  end
  local clearBoxes = removeFarPieces

  step("god mode on, player to the basin near Vas", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    math.randomseed(12345)
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.positionCell({ reference = tes3.player, position = { x, y, level + 150 } })
  end)

  step("a large pond and 60 actors in it", 8, function()
    local object = tes3.getObject("wv_stress_pond") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_stress_pond", mesh = "wv\\wv_square_2048.nif" })
    pond = tes3.createReference({ object = object, position = { x, y, level }, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
    local ids = { "rat", "rat", "mudcrab", "fargoth" }
    for i = 1, 60 do
      local ok, reference = pcall(tes3.createReference, {
        object = ids[i % #ids + 1], cell = tes3.player.cell, orientation = { 0, 0, 0 },
        position = { x + math.random(-700, 700), y + math.random(-700, 700), level - 150 },
      })
      if ok and reference then actors[#actors + 1] = reference end
    end
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { x, y, level - 150 } })
    say("stress: %d actors placed", #actors)
  end)

  measure("60 actors in the water", 8)

  step("drain the pond; one volume stays registered far away", 1, function()
    pond:disable()
    addFarBoxes(1)
  end)
  measure("60 actors on land, 1 volume registered elsewhere", 8, function()
    return string.format("engine query %.0f ns", restQueryNs())
  end)

  step("no volume at all", 1, function() clearBoxes() end)
  measure("60 actors on land, no volume registered", 8, function()
    return string.format("engine query %.0f ns", restQueryNs())
  end)

  step("1000 volumes registered elsewhere", 1, function() addFarBoxes(1000) end)
  measure("60 actors on land, 1000 volumes registered elsewhere", 6, function()
    return string.format("engine query %.0f ns", restQueryNs())
  end)

  step("5000 volumes registered elsewhere", 1, function()
    addFarBoxes(4000)
    -- What the plugin's look at every reference costs, once per frame.
    local native = require("waterVolumes.interop").native
    local started = seconds()
    for _ = 1, 200 do native.update() end
    say("plugin update with %d volumes: %.1f microseconds per call", native.count(), (seconds() - started) / 200 * 1e6)
  end)
  measure("60 actors on land, 5000 volumes registered elsewhere", 6, function()
    return string.format("engine query %.0f ns", restQueryNs())
  end)

  step("remove the far volumes and the actors", 1, function()
    clearBoxes()
    for _, reference in ipairs(actors) do reference:delete() end
    actors = {}
    pond:enable()
    tes3.positionCell({ reference = tes3.player, position = { x - 1500, y - 1500, level + 400 } })
    camera = { position = tes3vector3.new(x - 1300, y - 1300, level + 1100), target = tes3vector3.new(x, y, level) }
  end)

  -- 24 more surfaces in view, in each of the three looks.
  local function surfacesStep(label, id, settings)
    step("24 more surfaces in view: " .. label, 2, function()
      if settings then require("waterVolumes.interop").registerObject(id, settings) end
      local object = tes3.getObject(id) or tes3.createObject({ objectType = tes3.objectType.static, id = id, mesh = "wv\\wv_disc_512.nif" })
      for gx = -2, 2 do
        for gy = -2, 2 do
          if not (gx == 0 and gy == 0) then
            surfaces[#surfaces + 1] = tes3.createReference({
              object = object, cell = tes3.player.cell, orientation = { 0, 0, 0 },
              position = { x + gx * 560, y + gy * 560, level + 40 },
            })
          end
        end
      end
    end)
    measure("25 surfaces in view, " .. label, 6)
    -- The capture is taken a frame after it is asked for, so the surfaces go in a later step.
    step("photograph them", 1, function()
      local path = string.format("%s/%sstress 25 surfaces %s.jpg", spec.waterShotDir or runDirectory(spec), spec.waterShotPrefix or "", label)
      os.remove(path)
      mge.saveScreenshot({ path = path })
    end)
    step("remove them", 1.5, function()
      for _, reference in ipairs(surfaces) do reference:delete() end
      surfaces = {}
    end)
  end
  measure("1 surface in view", 6)
  surfacesStep("reflecting the scene", "wv_stress_full", nil)
  surfacesStep("reflecting the sky only", "wv_stress_sky", { skyOnly = true })
  surfacesStep("plain", "wv_stress_plain", { plain = true })

  step("the pond moves every frame", 2, function()
    churn = { reference = pond, x = x, y = y, z = level, frames = 0 }
  end)
  measure("pond re-registered every frame", 6)
  step("stop moving it", 1, function()
    local frames = churn.frames
    churn = nil
    pond.position = tes3vector3.new(x, y, level)
    say("stress: the pond moved on %d frames", frames)
  end)
  step("the water is where the pond stopped", 2, function()
    local found = controller:getVolumeSurfaceAt({ x, y, level - 50 })
    note(found == level, "surface after moving every frame", string.format("surface %s, expected %d", tostring(found), level))
    camera = nil
    tes3.positionCell({ reference = tes3.player, position = { x, y, level - 200 } })
  end)

  -- In and out of the water, checking the state the player was left in each time.
  local wrong, checks = 0, 0
  for i = 1, 20 do
    local inWater = i % 2 == 1
    step(inWater and "check in the water, throw the player out" or "check on land, throw the player in", 0.8, function()
      checks = checks + 1
      if player.isSwimming ~= inWater then wrong = wrong + 1 end
      if inWater then
        tes3.positionCell({ reference = tes3.player, position = { dryX, dryY, 40 } })
      else
        tes3.positionCell({ reference = tes3.player, position = { x, y, level - 200 } })
      end
    end)
  end
  step("in and out result", 1, function()
    note(wrong == 0, "swimming state after 20 moves in and out", string.format("%d of %d checks wrong", wrong, checks))
  end)

  step("clean up", 1, function()
    camera = nil
    probe = nil
    churn = nil
    clearBoxes()
    pond:delete()
    tes3.worldController.menuController.godModeEnabled = true
  end)

  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Grid: ponds a plugin placed in four cells in a row, seen from two of them.
-- Needs demo/WaterVolumesGrid.esp of the Water Volumes mod, added by run_dump.py.
-------------------------------------------------------------------------------

local function runGrid(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end

  local controller = waterController()
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local ponds = {
    { id = "wv_demo_disc", x = SITE.x, y = SITE.y, z = SITE.level },
    { id = "wv_demo_disc1", x = SITE.x + 8192, y = SITE.y, z = 1500 },
    { id = "wv_demo_disc2", x = SITE.x + 16384, y = SITE.y, z = 1500 },
    { id = "wv_demo_disc3", x = SITE.x + 24576, y = SITE.y, z = 1500 },
  }

  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end

  -- Which ponds have a loaded reference and which are water, against what is expected with the
  -- player in this cell: the three by three cells around the player are loaded.
  local function check(where, expected)
    local cell = tes3.player.cell
    local active = {}
    for _, other in ipairs(tes3.getActiveCells()) do
      active[#active + 1] = string.format("%d,%d", other.gridX, other.gridY)
    end
    say("grid: player in cell %d, %d; active cells: %s", cell.gridX, cell.gridY, table.concat(active, " "))
    for i, pond in ipairs(ponds) do
      local reference = tes3.getReference(pond.id)
      local loaded = reference ~= nil and reference.sceneNode ~= nil
      local surface = controller:getVolumeSurfaceAt({ pond.x, pond.y, pond.z - 50 })
      local water = surface == pond.z
      note(water == expected[i], string.format("%s, pond %d (%s)", where, i - 1, pond.id),
        string.format("water %s, expected %s; the reference has a scene node: %s", tostring(water), tostring(expected[i]), tostring(loaded)))
    end
  end

  sequence({
    { name = "god mode on, player to the first pond", wait = 1, run = function()
      if not controller.volumesSupported then error("this MWSE build has no water volume support") end
      tes3.mobilePlayer.vanityDisabled = true
      tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
      tes3.worldController.menuController.godModeEnabled = true
      tes3.worldController.hour.value = 13
      tes3.changeWeather({ id = 0, immediate = true })
      tes3.force3rdPerson()
      tes3.positionCell({ reference = tes3.player, position = { SITE.x - 900, SITE.y - 900, SITE.level + 300 } })
    end },
    { name = "from the first pond's cell", wait = 10, run = function()
      check("player at pond 0", { true, true, false, false })
      camera = { position = tes3vector3.new(SITE.x - 2500, SITE.y - 900, 3200), target = tes3vector3.new(SITE.x + 16384, SITE.y, 1200) }
    end },
    { name = "photograph the row looking east", wait = 3, run = function()
      shot("grid looking east from pond 0")
    end },
    { name = "player two cells east", wait = 1, run = function()
      camera = nil
      tes3.positionCell({ reference = tes3.player, position = { SITE.x + 16384 - 900, SITE.y - 900, 1900 } })
    end },
    { name = "from the third pond's cell", wait = 12, run = function()
      check("player at pond 2", { false, true, true, true })
      camera = { position = tes3vector3.new(SITE.x + 16384 + 2500, SITE.y - 900, 3200), target = tes3vector3.new(SITE.x, SITE.y, 1200) }
    end },
    { name = "photograph the row looking west", wait = 3, run = function()
      shot("grid looking west from pond 2")
      camera = { position = tes3vector3.new(SITE.x + 16384 - 900, SITE.y - 700, 1750), target = tes3vector3.new(SITE.x + 16384, SITE.y, 1500) }
    end },
    { name = "photograph pond 2 from nearby", wait = 3, run = function()
      shot("grid pond 2 from nearby")
    end },
    { name = "player back to the first pond", wait = 1, run = function()
      camera = nil
      tes3.positionCell({ reference = tes3.player, position = { SITE.x - 900, SITE.y - 900, SITE.level + 300 } })
    end },
    { name = "back in the first pond's cell", wait = 12, run = function()
      check("player back at pond 0", { true, true, false, false })
    end },
    { name = "clean up", wait = 1, run = function()
      tes3.worldController.menuController.godModeEnabled = true
    end },
  }, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Interior: a kit disc placed over the player in an interior that has water of its own and
-- in one that has none
-------------------------------------------------------------------------------

local function runInterior(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end

  step("god mode on", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
  end)

  local function interior(cellId, label)
    local state = {}
    step("go to " .. cellId, 1, function()
      tes3.runLegacyScript({ command = 'coc "' .. cellId .. '"', source = tes3.compilerSource.console })
    end)
    step(label .. ": place a disc over the player", 8, function()
      local cell = tes3.player.cell
      state.cell = cell
      state.hadWater = cell.hasWater
      observed(label .. ": cell", string.format("%s, interior %s, has water %s, water level %s", cell.id, tostring(cell.isInterior), tostring(cell.hasWater), tostring(cell.waterLevel)))
      local p = tes3.player.position
      state.x, state.y, state.floor, state.level = p.x, p.y, p.z, p.z + 150
      local object = tes3.getObject("wv_interior_disc") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_interior_disc", mesh = "wv\\wv_disc_512.nif" })
      state.reference = tes3.createReference({ object = object, position = { p.x, p.y, state.level }, orientation = { 0, 0, 0 }, cell = cell })
      tes3.force1stPerson()
    end)
    step(label .. ": is it water", 5, function()
      local node = state.reference.sceneNode
      note(node ~= nil and node:getObjectByName("WaterVolume") ~= nil, label .. ": tag", "a shape named WaterVolume in the scene node")
      local surface = controller:getVolumeSurfaceAt({ state.x, state.y, state.floor + 20 })
      note(surface ~= nil and math.abs(surface - state.level) < 0.5, label .. ": volume registered", string.format("surface %s, expected %.0f", tostring(surface), state.level))
      state.swims = player.isSwimming == true
      observed(label .. ": player", string.format("z %.0f, swimming %s, underwater %s", tes3.player.position.z, tostring(player.isSwimming), tostring(player.underwater)))
      observed(label .. ": cell while the disc is there", string.format("has water %s, water level %s", tostring(state.cell.hasWater), tostring(state.cell.waterLevel)))
      note(state.swims and player.underwater == true, label .. ": player swims under the disc",
        state.hadWater and "the cell has water of its own" or "the mod flagged the cell")
    end)
    step(label .. ": photograph from below", 1, function() shot(label .. " first person under") end)
    step(label .. ": camera above", 1, function()
      tes3.force3rdPerson()
      camera = { position = tes3vector3.new(state.x - 170, state.y - 170, state.level + 75), target = tes3vector3.new(state.x + 40, state.y + 40, state.level) }
    end)
    step(label .. ": photograph from above", 3, function() shot(label .. " from above") end)
    step(label .. ": clean up", 1, function()
      camera = nil
      state.reference:delete()
    end)
    step(label .. ": the cell is as it was", 2, function()
      note(state.cell.hasWater == state.hadWater, label .. ": cell flag restored", string.format("has water %s, had %s", tostring(state.cell.hasWater), tostring(state.hadWater)))
    end)
  end

  interior(spec.waterInteriorWet or "Addamasartus", "interior with water")
  interior(spec.waterInteriorDry or "Seyda Neen, Arrille's Tradehouse", "interior without water")

  step("god mode off", 2, function()
    tes3.worldController.menuController.godModeEnabled = true
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- River: pieces that meet at a cell border, and a piece that lies across one
-------------------------------------------------------------------------------

local function runRiver(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end
  local function view(name, settle, setup)
    step("set up: " .. name, 1.5, setup)
    step("photograph: " .. name, settle, function() shot(name) end)
  end

  -- The border between cells 0,22 and 1,22 runs along x = 8192; the one between 0,22 and 0,23
  -- along y = 188416. Each square is 2048 wide.
  local level = 900
  local borderX, y = 8192, SITE.y
  local westX, eastX = borderX - 1024, borderX + 1024
  local borderY = 188416
  local pieces = {}

  local function place(id, px, py, settings)
    if settings then require("waterVolumes.interop").registerObject(id, settings) end
    local object = tes3.getObject(id) or tes3.createObject({ objectType = tes3.objectType.static, id = id, mesh = "wv\\wv_square_2048.nif" })
    local reference = tes3.createReference({
      object = object, position = { px, py, level }, orientation = { 0, 0, 0 },
      cell = tes3.getCell({ position = tes3vector3.new(px, py, level) }),
    })
    pieces[#pieces + 1] = reference
    return reference
  end
  local function clearPieces()
    for _, reference in ipairs(pieces) do reference:delete() end
    pieces = {}
  end
  local function nodeState(reference)
    local node = reference.sceneNode
    return string.format("scene node %s, hidden %s", tostring(node ~= nil), tostring(node ~= nil and node.appCulled))
  end
  local across
  local acrossCamera = function()
    camera = { position = tes3vector3.new(westX, 188416 - 1400, level + 3000), target = tes3vector3.new(westX, 188416, level) }
  end
  local function surface(px, py) return controller:getVolumeSurfaceAt({ px, py, level - 50 }) end
  local function seamViews(label)
    view(label .. " from above", 3, function()
      camera = { position = tes3vector3.new(borderX - 500, y - 900, level + 550), target = tes3vector3.new(borderX, y, level) }
    end)
    view(label .. " along the border", 2, function()
      camera = { position = tes3vector3.new(borderX - 30, y - 1000, level + 45), target = tes3vector3.new(borderX, y + 900, level) }
    end)
  end

  step("god mode on, player to the border", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { borderX - 300, y, (groundAt(borderX - 300, y) or level - 150) + 10 } })
  end)

  step("two squares that meet on the border, one in each cell", 8, function()
    local west, east = place("wv_river_piece", westX, y), place("wv_river_piece", eastX, y)
    observed("cells of the two pieces", string.format("west in %d,%d, east in %d,%d", west.cell.gridX, west.cell.gridY, east.cell.gridX, east.cell.gridY))
  end)
  step("the water is continuous across the border", 3, function()
    local missing, total = 0, 0
    for dy = -900, 900, 150 do
      for dx = -40, 40 do
        total = total + 1
        if surface(borderX + dx, y + dy) ~= level then missing = missing + 1 end
      end
    end
    note(missing == 0, "level across the border", string.format("%d of %d points within 40 units of the border have no water", missing, total))
  end)
  -- The player is put 150 below the surface where the ground leaves room for it. Where the
  -- ground is higher the engine stands the player on it, and that is reported, not judged.
  local wrong, checks, lines = 0, 0, {}
  for _, dx in ipairs({ -60, -20, -2, 0, 2, 20, 60 }) do
    local ground
    step(string.format("player to %d units from the border", dx), 0.3, function()
      ground = groundAt(borderX + dx, y) or -100000
      tes3.positionCell({ reference = tes3.player, position = { borderX + dx, y, math.max(level - 150, ground + 5) } })
    end)
    step(string.format("player %d units from the border", dx), 1.2, function()
      local at = tes3.player.position
      local z = at.z
      local deep = ground < level - 140
      lines[#lines + 1] = string.format("%d: ground %.0f, player at %.0f %.0f %.0f in cell %d,%d, swimming %s, surface there %s", dx, ground, at.x, at.y, z,
        tes3.player.cell.gridX, tes3.player.cell.gridY, tostring(player.isSwimming), tostring(controller:getVolumeSurfaceAt(at)))
      say("border %s", lines[#lines])
      if deep then
        checks = checks + 1
        if player.isSwimming ~= true then wrong = wrong + 1 end
      end
    end)
  end
  step("swimming across the border", 0.5, function()
    note(wrong == 0 and checks > 0, "player swims at every step across the border where the ground is 140 or more below the surface",
      string.format("%d of %d checks not swimming", wrong, checks))
    tes3.positionCell({ reference = tes3.player, position = { westX - 700, y, level - 100 } })
  end)
  seamViews("river border renderer water")

  -- "riverhold" stops here and leaves the game to the person at the keyboard. DONE is never
  -- said, so the runner waits until the game is quit or the time budget ends.
  if spec.water == "riverhold" then
    step("hand the game over", 1, function()
      camera = nil
      tes3.positionCell({ reference = tes3.player, position = { borderX - 300, y, level - 100 } })
      tes3.messageBox("Test harness: the game is yours. The cell border runs north to south just east of you. God mode is on. Quit the game when you are done.")
      say("HANDED OVER: two pieces meet on the border at x = %d, level %d; quit the game to end the run", borderX, level)
    end)
    sequence(steps, say, after, function() end)
    return
  end

  step("the same two squares with the plain option", 1, function()
    clearPieces()
    place("wv_river_plain", westX, y, { plain = true })
    place("wv_river_plain", eastX, y)
  end)
  seamViews("river border plain texture")

  step("one square lying across the border to the north", 1, function()
    clearPieces()
    camera = nil
    across = place("wv_river_piece", westX, borderY)
    observed("cell of the piece across the border", string.format("%d,%d; the player is in %d,%d", across.cell.gridX, across.cell.gridY, tes3.player.cell.gridX, tes3.player.cell.gridY))
  end)
  step("both halves are water while the piece's cell is active", 4, function()
    note(surface(westX, borderY - 500) == level and surface(westX, borderY + 500) == level, "piece across a border, its cell active",
      string.format("south half %s, north half %s; %s", tostring(surface(westX, borderY - 500)), tostring(surface(westX, borderY + 500)), nodeState(across)))
  end)
  view("river piece across a border its cell active", 3, acrossCamera)
  step("player one cell further south, so the piece's cell is no longer active", 1, function()
    camera = nil
    tes3.positionCell({ reference = tes3.player, position = { westX, 180224 - 1500, level + 600 } })
    pcall(function() player.isFlying = true end)
  end)
  step("the half in the still active cell", 12, function()
    local active = {}
    for _, cell in ipairs(tes3.getActiveCells()) do active[#active + 1] = string.format("%d,%d", cell.gridX, cell.gridY) end
    observed("active cells", table.concat(active, " "))
    observed("piece across a border, its cell not active", string.format("south half, in active cell 0,22: surface %s; north half: surface %s",
      tostring(surface(westX, borderY - 500)), tostring(surface(westX, borderY + 500))))
    observed("the piece's reference, its cell not active", nodeState(across))
  end)
  view("river piece across a border its cell not active", 3, acrossCamera)

  step("clean up", 1, function()
    camera = nil
    pcall(function() player.isFlying = false end)
    clearPieces()
    tes3.worldController.menuController.godModeEnabled = true
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Creatures: does the creature AI treat a water volume as it treats the sea?
-------------------------------------------------------------------------------

local function runCreatures(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end

  -- A pond: a disc 2048 across over the test site. Everything about the site is measured first.
  -- The water is raised over the open sea: a disc 2048 across, 250 above sea level. Water that
  -- high exists only because of the volume, so a creature in it shows what the AI makes of it.
  local level = 250
  local centre = { x = SITE.x, y = SITE.y }
  local radius = 1024
  local pond
  local site = {}
  local results = {}

  -- God mode is set, not toggled: a toggle turns it off when it was already on.
  local godModeBefore
  local function godMode(state)
    local menuController = tes3.worldController.menuController
    if godModeBefore == nil then godModeBefore = menuController.godModeEnabled end
    menuController.godModeEnabled = state
    return menuController.godModeEnabled
  end

  -- Combat is started with tes3mobileActor:startCombat, and with mwscript.startCombat when that
  -- did not take. The combat events say what the engine then did with it.
  local watched
  local fights = { started = 0, stopped = 0, attempts = 0, scripted = 0 }
  local function onCombatStarted(e)
    if watched and e.actor == watched.mobile then fights.started = fights.started + 1 end
  end
  local function onCombatStopped(e)
    if watched and e.actor == watched.mobile then fights.stopped = fights.stopped + 1 end
  end
  event.register("combatStarted", onCombatStarted)
  event.register("combatStopped", onCombatStopped)
  local function setOn(reference)
    local mobile = reference.mobile
    if not mobile or mobile.inCombat then return end
    fights.attempts = fights.attempts + 1
    mobile.fight = 100
    mobile:startCombat(player)
    if not mobile.inCombat then
      fights.scripted = fights.scripted + 1
      mwscript.startCombat({ reference = reference, target = tes3.player })
    end
  end

  -- Line of sight as the engine's AI asks for it, between two points near the middle of the
  -- raised water: both under the surface, and from under it to above it.
  local function sight(label)
    local under = tes3vector3.new(centre.x + 300, centre.y, level - 100)
    local alsoUnder = tes3vector3.new(centre.x, centre.y, level - 60)
    local over = tes3vector3.new(centre.x, centre.y, level + 30)
    local within = tes3.testLineOfSight({ position1 = under, height1 = 0, position2 = alsoUnder, height2 = 0 })
    local across = tes3.testLineOfSight({ position1 = under, height1 = 0, position2 = over, height2 = 0 })
    say("sight %s: between two points under the surface %s; from under the surface to 30 above it %s", label, tostring(within), tostring(across))
    return within, across
  end

  local function inPond(position)
    local dx, dy = position.x - centre.x, position.y - centre.y
    return dx * dx + dy * dy <= radius * radius
  end

  step("god mode on, player to the site", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    local was = tes3.worldController.menuController.godModeEnabled
    say("god mode was %s after the load, now %s", tostring(was), tostring(godMode(true)))
    tes3.worldController.hour.value = 13
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, level - 60 } })
  end)

  step("measure the site and place the pond", 8, function()
    -- Water pieces that an earlier run left in the save would be water of their own here.
    local stale = {}
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local id = reference.baseObject.id:lower()
        if id:find("^wv_river") or id == "wv_ai_pond" then stale[#stale + 1] = reference end
      end
    end
    for _, reference in ipairs(stale) do reference:delete() end
    observed("water pieces left in the save by earlier runs", string.format("%d removed", #stale))
    site.centreGround = groundAt(SITE.x, SITE.y) or -100000
    -- The deepest place inside the pond, and the highest ground just outside it.
    local deep, shore, sea, land
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for _, r in ipairs({ 0, 250, 500, 750 }) do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and (not deep or ground < deep.ground) then deep = { x = x, y = y, ground = ground } end
      end
      for _, r in ipairs({ 1120, 1250, 1400 }) do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground > level + 5 and (not shore or r < shore.r or (r == shore.r and ground < shore.ground)) then
          shore = { x = x, y = y, ground = ground, r = r }
        end
      end
      -- For the control: open sea, and land beside it.
      for r = 1600, 3600, 250 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -250 and (not sea or r < sea.r) then sea = { x = x, y = y, ground = ground, r = r, c = c, s = s } end
      end
    end
    if sea then
      for back = 100, 1500, 100 do
        local x, y = sea.x - sea.c * back, sea.y - sea.s * back
        local ground = groundAt(x, y)
        if ground and ground > 30 then land = { x = x, y = y, ground = ground, away = back } break end
      end
    end
    site.deep, site.shore, site.sea, site.land = deep, shore, sea, land
    observed("site", string.format("pond level %d; deepest ground inside %s; shore point %s; sea point %s; land by the sea %s", level,
      deep and string.format("%.0f (%.0f deep)", deep.ground, level - deep.ground) or "none",
      shore and string.format("%.0f from the centre, ground %.0f", shore.r, shore.ground) or "none",
      sea and string.format("%.0f from the centre, sea floor %.0f", sea.r, sea.ground) or "none",
      land and string.format("%.0f from the sea point, ground %.0f", land.away, land.ground) or "none"))

    local object = tes3.getObject("wv_ai_pond") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_ai_pond", mesh = "wv\\wv_disc_2048.nif" })
    if not sea then error("no open sea was found near the site") end
    centre.x, centre.y = sea.x, sea.y
    pond = tes3.createReference({ object = object, position = { sea.x, sea.y, level }, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = tes3vector3.new(sea.x, sea.y, level) }) })

    local flags = {}
    for _, id in ipairs({ "slaughterfish", "rat", "mudcrab", "kagouti", "alit", "guar", "scrib", "kwama forager", "nix-hound", "shalk", "dreugh" }) do
      local creature = tes3.getObject(id)
      if creature then
        flags[#flags + 1] = string.format("%s walks=%s swims=%s flies=%s", id, tostring(creature.walks), tostring(creature.swims), tostring(creature.flies))
        if creature.walks and creature.swims == false and not site.nonSwimmer then site.nonSwimmer = id end
      end
    end
    say("creature flags: %s", table.concat(flags, "; "))
  end)

  step("the pond is water", 4, function()
    local surface = controller:getVolumeSurfaceAt({ centre.x, centre.y, level - 20 })
    note(surface == level, "the raised water is a water volume", "surface " .. tostring(surface))
    local within, across = sight("with the raised water")
    note(within == true and across == true, "the surface of the raised water does not block line of sight", string.format("under to under %s, under to over %s", tostring(within), tostring(across)))
  end)

  -- One trial: a creature and the player are put somewhere, the creature is set on the player,
  -- and it is watched for a while.
  local function trial(name, creatureId, waterLevel, where, duration, picture)
    local reference
    local samples = {}
    step("trial: " .. name, 1.5, function()
      local places = where()
      if not places then
        observed(name, "skipped: the site has no place for it")
        return
      end
      tes3.positionCell({ reference = tes3.player, position = places.player })
      samples.godMode = godMode(true)
      reference = tes3.createReference({ object = creatureId, position = places.creature, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = tes3vector3.new(places.creature[1], places.creature[2], places.creature[3]) }) })
      samples.start = places
    end)
    step("set it on the player: " .. name, 1.5, function()
      if not reference or not reference.mobile then return end
      samples.atStart = reference.position.z
      watched = reference
      fights.started, fights.stopped, fights.attempts, fights.scripted = 0, 0, 0, 0
      samples.activeAI = reference.mobile.activeAI
      setOn(reference)
    end)
    for index = 1, duration * 2 do
      step(string.format("watch %s, %.1f s", name, index / 2), 0.5, function()
        if not reference or not reference.mobile then return end
        local mobile = reference.mobile
        local at = reference.position
        -- Once a second, a creature that is not fighting is set on the player again.
        if index % 2 == 0 then setOn(reference) end
        samples[#samples + 1] = {
          distance = at:distance(tes3.player.position), z = at.z, swimming = mobile.isSwimming == true, combat = mobile.inCombat == true,
          x = at.x, y = at.y, inPond = inPond(at), wet = at.z < waterLevel, inAir = at.z > 5 and not inPond(at),
        }
        if picture and index == duration then
          camera = { position = tes3vector3.new(at.x + 260, at.y - 260, math.max(at.z, waterLevel) + 200), target = tes3vector3.new(at.x, at.y, at.z) }
        elseif picture and index == duration + 3 then
          shot(picture)
          camera = nil
        end
      end)
    end
    step("result: " .. name, 0.3, function()
      camera = nil
      if not reference then return end
      local count = #samples
      local result = { name = name, count = count }
      if count > 0 then
        local swimming, combat, wet, pondCount, air = 0, 0, 0, 0, 0
        local nearest, highest = math.huge, -math.huge
        local moved = 0
        for i, sample in ipairs(samples) do
          if sample.swimming then swimming = swimming + 1 end
          if sample.combat then combat = combat + 1 end
          if sample.wet then wet = wet + 1 end
          if sample.inPond then pondCount = pondCount + 1 end
          if sample.inAir then air = air + 1 end
          nearest = math.min(nearest, sample.distance)
          highest = math.max(highest, sample.z - waterLevel)
          if i > 1 then
            local dx, dy, dz = sample.x - samples[i - 1].x, sample.y - samples[i - 1].y, sample.z - samples[i - 1].z
            moved = moved + math.sqrt(dx * dx + dy * dy + dz * dz)
          end
        end
        result.swimming, result.combat, result.wet, result.pond = swimming / count, combat / count, wet / count, pondCount / count
        result.air = air
        result.first, result.nearest, result.last, result.highest, result.moved = samples[1].distance, nearest, samples[count].distance, highest, moved
        local series = {}
        for i = 1, count, 2 do series[#series + 1] = string.format("%.0f/%.0f", samples[i].z, samples[i].distance) end
        say("series %s: height 1.5 s after it was placed %.0f (placed at %.0f); then height/distance every second: %s; health %.0f, fight %s", name,
          samples.atStart or 0/0, samples.start.creature[3], table.concat(series, " "), reference.mobile and reference.mobile.health.current or -1,
          tostring(reference.mobile and reference.mobile.fight))
        say("combat %s: startCombat called %d times (mwscript.startCombat %d of them), combatStarted fired %d times, combatStopped %d times, in combat at the end %s, "
          .. "AI active when first set on the player %s, player detected %s", name, fights.attempts, fights.scripted, fights.started, fights.stopped,
          tostring(reference.mobile and reference.mobile.inCombat), tostring(samples.activeAI), tostring(reference.mobile and reference.mobile.isPlayerDetected))
        result.detected = reference.mobile and reference.mobile.isPlayerDetected == true
        watched = nil
        result.playerZ = tes3.player.position.z
        observed(name, string.format("distance to the player %.0f at first, %.0f nearest, %.0f at the end; travelled %.0f; swimming %d%%, below the water level %d%%, "
          .. "highest %.0f relative to sea level; in combat %d%%; under the raised water %d%%; above sea level outside it %d samples; player swimming %s",
          result.first, nearest, result.last, moved, result.swimming * 100, result.wet * 100, highest, result.combat * 100, result.pond * 100, air, tostring(player.isSwimming))
          .. string.format("; god mode %s, player health %.0f", tostring(tes3.worldController.menuController.godModeEnabled), player.health.current)
          .. string.format("; player asked to %.0f %.0f %.0f, is at %.0f %.0f %.0f", samples.start.player[1], samples.start.player[2], samples.start.player[3],
            tes3.player.position.x, tes3.player.position.y, tes3.player.position.z))
      else
        observed(name, "the creature never had a mobile")
      end
      results[name] = result
      reference:delete()
    end)
  end

  -- Every height here is measured from sea level, so "highest" above 0 means the creature was
  -- in water that only the volume provides.
  step("player into the raised water, 180 above sea level", 1, function()
    tes3.positionCell({ reference = tes3.player, position = { centre.x, centre.y, level - 70 } })
  end)
  step("the player floats there", 4, function()
    local at = tes3.player.position
    note(at.z > 100 and player.isSwimming == true, "the player floats in the raised water above sea level", string.format("at %.0f %.0f %.0f, swimming %s", at.x, at.y, at.z, tostring(player.isSwimming)))
  end)

  -- The same trial several times over: whether a fish notices the player is partly chance.
  local REPEATS = 4
  for i = 1, REPEATS do
    trial(string.format("raised water, fish placed above sea level, %d", i), "slaughterfish", 0, function()
      local sea = site.sea
      return { player = { sea.x, sea.y, level - 70 }, creature = { sea.x + sea.c * 350, sea.y + sea.s * 350, level - 100 } }
    end, 8, i == 1 and "creatures fish in raised water" or nil)
  end
  for i = 1, REPEATS do
    trial(string.format("raised water, fish placed below sea level, %d", i), "slaughterfish", 0, function()
      local sea = site.sea
      return { player = { sea.x, sea.y, level - 70 }, creature = { sea.x + sea.c * 350, sea.y + sea.s * 350, -150 } }
    end, 8)
  end

  step("take the raised water away for the controls", 1, function()
    if pond then pond:delete() pond = nil end
  end)
  step("the raised water is gone", 3, function()
    observed("after removing the raised water", "surface " .. tostring(controller:getVolumeSurfaceAt({ centre.x, centre.y, level - 20 })))
    sight("without the raised water")
  end)
  for i = 1, REPEATS do
    trial(string.format("sea, fish 30 above the player, %d", i), "slaughterfish", 0, function()
      local sea = site.sea
      return { player = { sea.x, sea.y, -120 }, creature = { sea.x + sea.c * 350, sea.y + sea.s * 350, -90 } }
    end, 8)
  end
  for i = 1, REPEATS do
    trial(string.format("sea, fish 280 below the player, %d", i), "slaughterfish", 0, function()
      local sea = site.sea
      return { player = { sea.x, sea.y, -40 }, creature = { sea.x + sea.c * 350, sea.y + sea.s * 350, -320 } }
    end, 8)
  end

  step("what the fish made of the raised water", 0.5, function()
    local function tally(prefix)
      local moved, close, total, detected = 0, 0, 0, 0
      for i = 1, REPEATS do
        local r = results[string.format("%s, %d", prefix, i)]
        if r and r.count > 0 then
          total = total + 1
          if r.moved > 100 then moved = moved + 1 end
          if r.nearest < r.first - 50 then close = close + 1 end
          if r.detected then detected = detected + 1 end
        end
      end
      return string.format("%s: of %d fish, %d noticed the player, %d moved more than 100, %d came more than 50 closer", prefix, total, detected, moved, close), total, moved
    end
    for _, prefix in ipairs({ "raised water, fish placed above sea level", "raised water, fish placed below sea level", "sea, fish 30 above the player", "sea, fish 280 below the player" }) do
      observed("tally", (tally(prefix)))
    end
  end)

  step("clean up", 1, function()
    camera = nil
    if pond then pond:delete() end
    if godModeBefore ~= nil then godMode(godModeBefore) end
    event.unregister("combatStarted", onCombatStarted)
    event.unregister("combatStopped", onCombatStopped)
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Combat: melee and spell projectiles at the surface of a water volume and of the sea
-------------------------------------------------------------------------------

local function runCombat(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end

  -- Water raised 250 above the open sea, as in the creature scenario. Every trial runs once in
  -- it and once in the plain sea, with all heights taken from the surface in use.
  local raised = 250
  local centre, out, pond
  local results = {}

  local godModeBefore
  local function godMode(state)
    local menuController = tes3.worldController.menuController
    if godModeBefore == nil then godModeBefore = menuController.godModeEnabled end
    menuController.godModeEnabled = state
  end

  -- What happens to projectiles and who hits whom, as the engine reports it.
  local log = {}
  local watched
  local function record(kind, e)
    local at = e.collisionPoint or e.position or (e.mobile and e.mobile.position)
    local velocity = e.velocity or (e.mobile and e.mobile.velocity)
    log[#log + 1] = {
      kind = kind, z = at and at.z, target = e.target and e.target.baseObject and e.target.baseObject.id or nil,
      down = velocity and velocity:length() > 0 and (velocity.z / velocity:length()) or nil,
    }
  end
  local handlers = {}
  for _, name in ipairs({ "projectileExpire", "projectileHitActor", "projectileHitObject", "projectileHitTerrain",
    "spellProjectileHitActor", "spellProjectileHitObject", "spellProjectileHitTerrain", "spellProjectileHitWater" }) do
    handlers[name] = function(e) record(name, e) end
    event.register(name, handlers[name])
  end
  handlers.mobileActivated = function(e)
    local mobile = e.mobile
    if mobile and (mobile.objectType == tes3.objectType.mobileSpellProjectile or mobile.objectType == tes3.objectType.mobileProjectile) then
      local velocity = mobile.velocity
      log[#log + 1] = { kind = "launched", z = mobile.position.z, down = velocity and velocity:length() > 0 and (velocity.z / velocity:length()) or nil }
    end
  end
  event.register("mobileActivated", handlers.mobileActivated)
  local melee = { swings = 0, aimed = 0, damaged = 0, damage = 0 }
  handlers.attack = function(e)
    if watched and e.reference == watched then
      melee.swings = melee.swings + 1
      if e.targetReference == tes3.player then melee.aimed = melee.aimed + 1 end
    end
  end
  handlers.damaged = function(e)
    if watched and e.reference == tes3.player and e.attackerReference == watched then
      melee.damaged = melee.damaged + 1
      melee.damage = melee.damage + (e.damage or 0)
    end
  end
  event.register("attack", handlers.attack)
  event.register("damaged", handlers.damaged)

  local function describe()
    local parts = {}
    for _, entry in ipairs(log) do
      parts[#parts + 1] = string.format("%s%s%s%s", entry.kind, entry.z and string.format(" at height %.0f", entry.z) or "",
        entry.down and string.format(" heading %.2f up", entry.down) or "", entry.target and (" on " .. entry.target) or "")
    end
    return #parts > 0 and table.concat(parts, "; ") or "nothing was reported"
  end

  local spell
  step("god mode on, player to the sea", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    godMode(true)
    tes3.worldController.hour.value = 13
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level - 60 } })
  end)

  step("find open sea, place the raised water, pick a spell", 8, function()
    local stale = {}
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local id = reference.baseObject.id:lower()
        if id:find("^wv_river") or id == "wv_ai_pond" then stale[#stale + 1] = reference end
      end
    end
    for _, reference in ipairs(stale) do reference:delete() end

    local sea
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for r = 1600, 3600, 250 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -250 and (not sea or r < sea.r) then sea = { x = x, y = y, ground = ground, r = r, c = c, s = s } end
      end
    end
    if not sea then error("no open sea was found near the site") end
    centre = tes3vector3.new(sea.x, sea.y, 0)
    out = tes3vector3.new(sea.c, sea.s, 0)
    local object = tes3.getObject("wv_ai_pond") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_ai_pond", mesh = "wv\\wv_disc_2048.nif" })
    pond = tes3.createReference({ object = object, position = { sea.x, sea.y, raised }, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = tes3vector3.new(sea.x, sea.y, raised) }) })

    for _, id in ipairs({ "fireball", "firebloom", "frostball", "shockball", "fire storm", "flamebolt", "frostbolt" }) do
      local candidate = tes3.getObject(id)
      if candidate and candidate.objectType == tes3.objectType.spell and candidate.effects[1] and candidate.effects[1].rangeType == tes3.effectRange.target then
        spell = candidate
        break
      end
    end
    observed("set up", string.format("sea floor %.0f at the chosen place, %d stale water pieces removed, spell %s", sea.ground, #stale, spell and spell.id or "none found"))
  end)

  -- Facing along the "out" direction, looking up or down by an angle in degrees (down is positive).
  local function face(pitch)
    tes3.player.orientation = tes3vector3.new(math.rad(pitch), 0, math.atan2(out.x, out.y))
  end

  -- Puts the player at a height and looks again shortly after; a placement that did not hold
  -- is repeated. Calls back with the number of tries.
  local function place(height, hold, tolerance, callback, tries)
    tries = (tries or 0) + 1
    tes3.positionCell({ reference = tes3.player, position = { centre.x, centre.y, height } })
    after(hold, function()
      if math.abs(tes3.player.position.z - height) > tolerance and tries < 5 then
        place(height, hold, tolerance, callback, tries)
      else
        callback(tries)
      end
    end)
  end

  local function trials(label, surface)
    step(label .. ": the water in use", 3, function()
      observed(label, string.format("surface at the place: %s", tostring(controller:getVolumeSurfaceAt({ centre.x, centre.y, surface - 20 }))))
    end)

    -- Melee: a fish below bites a player whose head is at the surface. Damage needs god mode off.
    local fish
    local meleeTries
    step(label .. ": melee, player floating at the surface", 1, function()
      place(surface - 70, 1.5, 90, function(tries) meleeTries = tries end)
    end)
    step(label .. ": melee, fish and player", 9, function()
      tes3.setStatistic({ reference = tes3.player, name = "health", value = 20000 })
      godMode(false)
      fish = tes3.createReference({ object = "slaughterfish", position = { centre.x + out.x * 250, centre.y + out.y * 250, surface - 110 }, orientation = { 0, 0, 0 },
        cell = tes3.getCell({ position = tes3vector3.new(centre.x + out.x * 250, centre.y + out.y * 250, surface - 110) }) })
      watched = fish
      melee.swings, melee.aimed, melee.damaged, melee.damage = 0, 0, 0, 0
    end)
    step(label .. ": melee, set the fish on the player", 1.5, function()
      if fish.mobile and not fish.mobile.inCombat then fish.mobile:startCombat(player) end
    end)
    step(label .. ": melee result", 16, function()
      godMode(true)
      local at = tes3.player.position
      results[label .. " melee"] = { swings = melee.swings, damaged = melee.damaged, valid = at.z - surface > -200 }
      observed(label .. " melee", string.format("in 16 s the fish swung %d times, %d of them with the player as the target, and damaged the player %d times for %.0f; "
        .. "player at height %.0f relative to the surface after %s placements, fish at %.0f", melee.swings, melee.aimed, melee.damaged, melee.damage, at.z - surface, tostring(meleeTries), fish.position.z - surface))
      watched = nil
      fish:delete()
    end)

    -- Spells. The player is put in place, faces the way, and casts at once.
    local function cast(name, height, pitch, withTarget)
      local target
      step(string.format("%s: spell %s", label, name), 2, function()
        log = {}
        if withTarget then
          target = tes3.createReference({ object = "slaughterfish", position = { centre.x + out.x * 300, centre.y + out.y * 300, surface + height }, orientation = { 0, 0, 0 },
            cell = tes3.getCell({ position = tes3vector3.new(centre.x + out.x * 300, centre.y + out.y * 300, surface + height) }) })
        end
        -- In the air the player falls, so the look comes soon and allows for the fall.
        place(surface + height, height > 0 and 0.15 or 0.8, height > 0 and 60 or 90, function(tries)
          if not spell then return end
          face(pitch)
          log.tries = tries
          log.castHeight = tes3.player.position.z - surface
          log.cast = tes3.cast({ reference = tes3.player, spell = spell, instant = true, target = target })
        end)
      end)
      step(string.format("%s: spell %s, result", label, name), 9, function()
        local text = describe()
        local hitWater, hitObject, launched
        for _, entry in ipairs(log) do
          if entry.kind == "spellProjectileHitWater" then hitWater = entry.z - surface end
          if entry.kind == "spellProjectileHitObject" or entry.kind == "projectileHitObject" then hitObject = entry.target or "something" end
          if entry.kind == "launched" then launched = true end
        end
        results[label .. " " .. name] = { hitWater = hitWater, hitObject = hitObject, launched = launched, text = text,
          valid = log.castHeight ~= nil and math.abs(log.castHeight - height) < 100 }
        observed(string.format("%s spell %s", label, name), string.format("asked for %.0f relative to the surface, cast from %.0f after %s placements, cast returned %s: %s",
          height, log.castHeight or 0/0, tostring(log.tries), tostring(log.cast), text))
        if target then target:delete() end
      end)
    end
    cast("downwards from above the water", 220, 75, false)
    cast("upwards from under the water", -220, -75, false)
    cast("level under the water at a fish", -150, 0, true)
  end

  trials("raised water", raised)
  step("take the raised water away", 1, function()
    if pond then pond:delete() pond = nil end
  end)
  trials("sea", 0)

  step("the raised water against the sea", 0.5, function()
    for _, name in ipairs({ "downwards from above the water", "upwards from under the water", "level under the water at a fish" }) do
      local a, b = results["raised water " .. name], results["sea " .. name]
      if a and b and not (a.valid and b.valid) then
        observed("a spell cast " .. name, "not compared: the player was not where the trial needs them")
      elseif a and b then
        local same = (a.hitWater ~= nil) == (b.hitWater ~= nil) and (a.hitObject ~= nil) == (b.hitObject ~= nil) and a.launched == b.launched
        local near = a.hitWater == nil or b.hitWater == nil or math.abs(a.hitWater - b.hitWater) < 30
        note(same and near, "a spell cast " .. name .. " ends the same way in both", string.format("raised water: %s | sea: %s", a.text, b.text))
      end
    end
    local a, b = results["raised water melee"], results["sea melee"]
    if a and b and not (a.valid and b.valid) then
      observed("melee", "not compared: the player was not at the surface")
    elseif a and b then
      note((a.damaged > 0) == (b.damaged > 0), "a fish under the surface can bite the player in both", string.format("raised water: %d swings, %d hits | sea: %d swings, %d hits",
        a.swings, a.damaged, b.swings, b.damaged))
    end
  end)

  step("clean up", 1, function()
    if pond then pond:delete() end
    for name, handler in pairs(handlers) do event.unregister(name, handler) end
    if godModeBefore ~= nil then godMode(godModeBefore) end
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Ranged: the player's melee, an NPC on the shore, arrows and an NPC's spells
-------------------------------------------------------------------------------

local function runRanged(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local player = tes3.mobilePlayer
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end

  -- Water raised 80 above the sea, low enough that the land beside it stays dry. An NPC on that
  -- land looks, shoots and casts down at a player floating at the surface. Every trial runs once
  -- with the raised water and once with the plain sea.
  local raised = 80
  local centre, out, land, pond
  local results = {}

  local function godMode(state) tes3.worldController.menuController.godModeEnabled = state end

  local log = {}
  local actor
  local counts = {}
  local function count(name, amount) counts[name] = (counts[name] or 0) + (amount or 1) end
  local handlers = {}
  local function projectileEvent(name)
    handlers[name] = function(e)
      local at = e.collisionPoint or e.position or (e.mobile and e.mobile.position)
      log[#log + 1] = { kind = name, z = at and at.z, target = e.target and e.target.baseObject and e.target.baseObject.id or nil }
    end
    event.register(name, handlers[name])
  end
  for _, name in ipairs({ "projectileExpire", "projectileHitActor", "projectileHitObject", "projectileHitTerrain",
    "spellProjectileHitActor", "spellProjectileHitObject", "spellProjectileHitTerrain", "spellProjectileHitWater" }) do
    projectileEvent(name)
  end
  handlers.mobileActivated = function(e)
    local mobile = e.mobile
    if mobile and (mobile.objectType == tes3.objectType.mobileSpellProjectile or mobile.objectType == tes3.objectType.mobileProjectile) then
      log[#log + 1] = { kind = mobile.objectType == tes3.objectType.mobileProjectile and "arrow launched" or "spell launched", z = mobile.position.z }
    end
  end
  event.register("mobileActivated", handlers.mobileActivated)
  handlers.attack = function(e)
    if e.reference == tes3.player then
      count("player swings")
      if actor and e.targetReference == actor then count("player swings with the target") end
    elseif actor and e.reference == actor then
      count("its swings")
      if e.targetReference == tes3.player then count("its swings at the player") end
    end
  end
  handlers.damaged = function(e)
    if actor and e.reference == actor and e.attackerReference == tes3.player then
      count("player hits")
    elseif actor and e.reference == tes3.player and e.attackerReference == actor then
      count("its hits")
    end
  end
  event.register("attack", handlers.attack)
  event.register("damaged", handlers.damaged)

  local function describe(surface)
    local tally, order = {}, {}
    for _, entry in ipairs(log) do
      local key = entry.kind .. (entry.target and (" on " .. entry.target) or "")
      if not tally[key] then tally[key] = { n = 0, low = math.huge, high = -math.huge } order[#order + 1] = key end
      local item = tally[key]
      item.n = item.n + 1
      if entry.z then item.low, item.high = math.min(item.low, entry.z - surface), math.max(item.high, entry.z - surface) end
    end
    local parts = {}
    for _, key in ipairs(order) do
      local item = tally[key]
      parts[#parts + 1] = string.format("%d x %s (height %.0f to %.0f from the surface)", item.n, key, item.low, item.high)
    end
    return #parts > 0 and table.concat(parts, "; ") or "nothing was reported"
  end
  local function has(kind, target)
    for _, entry in ipairs(log) do
      if entry.kind == kind and (target == nil or entry.target == target) then return true end
    end
    return false
  end

  local spell
  step("player to the sea", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    godMode(true)
    tes3.worldController.hour.value = 13
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level - 60 } })
  end)

  step("find open sea and dry land beside it, place the raised water", 8, function()
    local stale = {}
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local id = reference.baseObject.id:lower()
        if id:find("^wv_river") or id == "wv_ai_pond" then stale[#stale + 1] = reference end
      end
    end
    for _, reference in ipairs(stale) do reference:delete() end

    local sea
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for r = 1600, 3600, 250 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -250 and (not sea or r < sea.r) then sea = { x = x, y = y, ground = ground, r = r, c = c, s = s } end
      end
    end
    if not sea then error("no open sea was found near the site") end
    for back = 100, 1000, 50 do
      local x, y = sea.x - sea.c * back, sea.y - sea.s * back
      local ground = groundAt(x, y)
      if ground and ground > raised + 15 then land = { x = x, y = y, ground = ground, away = back } break end
    end
    if not land then error("no dry land was found beside the sea") end
    centre = tes3vector3.new(sea.x, sea.y, 0)
    out = tes3vector3.new(sea.c, sea.s, 0)
    local object = tes3.getObject("wv_ai_pond") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_ai_pond", mesh = "wv\\wv_disc_2048.nif" })
    pond = tes3.createReference({ object = object, position = { sea.x, sea.y, raised }, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = tes3vector3.new(sea.x, sea.y, raised) }) })
    spell = tes3.getObject("fireball")
    observed("set up", string.format("sea floor %.0f; dry land %.0f from the player's place, ground %.0f; %d stale water pieces removed", sea.ground, land.away, land.ground, #stale))
  end)

  local function place(height, hold, tolerance, callback, tries)
    tries = (tries or 0) + 1
    tes3.positionCell({ reference = tes3.player, position = { centre.x, centre.y, height } })
    after(hold, function()
      if math.abs(tes3.player.position.z - height) > tolerance and tries < 5 then
        place(height, hold, tolerance, callback, tries)
      else
        callback(tries)
      end
    end)
  end
  local function spawn(id, x, y, z)
    return tes3.createReference({ object = id, position = { x, y, z }, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = tes3vector3.new(x, y, z) }) })
  end
  local function summary(names)
    local parts = {}
    for _, name in ipairs(names) do parts[#parts + 1] = string.format("%s %d", name, counts[name] or 0) end
    return table.concat(parts, ", ")
  end

  local function trials(label, surface)
    step(label .. ": the water in use", 3, function()
      observed(label, string.format("surface at the place: %s", tostring(controller:getVolumeSurfaceAt({ centre.x, centre.y, surface - 20 }))))
    end)
    step(label .. ": player floating at the surface", 1, function()
      place(surface - 70, 1.5, 90, function() end)
    end)

    -- The player's own melee, against a fish that comes to bite.
    step(label .. ": player melee, a fish", 9, function()
      counts, log = {}, {}
      tes3.setStatistic({ reference = tes3.player, name = "health", value = 20000 })
      godMode(false)
      actor = spawn("slaughterfish", centre.x + out.x * 200, centre.y + out.y * 200, surface - 100)
      player.weaponReady = true
    end)
    step(label .. ": player melee, set the fish on the player", 1.5, function()
      tes3.setStatistic({ reference = actor, name = "health", value = 20000 })
      if actor.mobile and not actor.mobile.inCombat then actor.mobile:startCombat(player) end
    end)
    for second = 1, 14 do
      step(string.format("%s: player melee, swing %d", label, second), 1, function()
        player.weaponReady = true
        if player:forceWeaponAttack() then count("forced swings") end
      end)
    end
    step(label .. ": player melee result", 1, function()
      results[label .. " player melee"] = { hits = counts["player hits"] or 0, swings = counts["player swings"] or 0 }
      observed(label .. " player melee", string.format("%s; player %.0f and fish %.0f from the surface, %.0f apart",
        summary({ "forced swings", "player swings", "player swings with the target", "player hits", "its swings at the player", "its hits" }),
        tes3.player.position.z - surface, actor.position.z - surface, actor.position:distance(tes3.player.position)))
      actor:delete()
      actor = nil
    end)

    -- An NPC on the dry land with a bow.
    step(label .. ": archer on the land", 1, function()
      counts, log = {}, {}
      actor = spawn("fargoth", land.x, land.y, land.ground + 5)
      tes3.addItem({ reference = actor, item = "long bow", count = 1, playSound = false })
      tes3.addItem({ reference = actor, item = "iron arrow", count = 80, playSound = false })
    end)
    step(label .. ": archer, set on the player", 1.5, function()
      if not actor.mobile then return end
      tes3.setStatistic({ reference = actor, name = "health", value = 20000 })
      tes3.setStatistic({ reference = actor, skill = tes3.skill.marksman, value = 100 })
      actor.mobile.fight = 100
      actor.mobile:startCombat(player)
    end)
    local seen, fighting, samples = 0, 0, 0
    for second = 1, 24 do
      step(string.format("%s: archer, %d s", label, second), 1, function()
        if not actor.mobile then return end
        samples = samples + 1
        if actor.mobile.isPlayerDetected then seen = seen + 1 end
        if actor.mobile.inCombat then fighting = fighting + 1 else actor.mobile:startCombat(player) end
      end)
    end
    step(label .. ": archer result", 1, function()
      local weapon = actor.mobile and actor.mobile.readiedWeapon
      results[label .. " archer"] = { launched = has("arrow launched"), hitPlayer = has("projectileHitActor", "player"), seen = seen, fighting = fighting }
      observed(label .. " archer", string.format("saw the player in %d of %d seconds, in combat in %d; weapon in hand %s; %s; %s; archer at %.0f from the surface, %.0f from the player",
        seen, samples, fighting, weapon and weapon.object.id or "none", summary({ "its swings", "its swings at the player", "its hits" }), describe(surface),
        actor.position.z - surface, actor.position:distance(tes3.player.position)))
      seen, fighting, samples = 0, 0, 0
    end)

    -- The same NPC casts a spell at the player, three times.
    step(label .. ": NPC spells", 1, function()
      counts, log = {}, {}
      if actor.mobile then actor.mobile:stopCombat(true) end
    end)
    for index = 1, 3 do
      step(string.format("%s: NPC spell %d", label, index), 2.5, function()
        tes3.cast({ reference = actor, target = tes3.player, spell = spell, instant = true })
      end)
    end
    step(label .. ": NPC spell result", 5, function()
      results[label .. " NPC spell"] = { launched = has("spell launched"), hitPlayer = has("spellProjectileHitActor", "player"), hitWater = has("spellProjectileHitWater"), hitObject = has("spellProjectileHitObject") }
      observed(label .. " NPC spell", string.format("%s; player %.0f from the surface", describe(surface), tes3.player.position.z - surface))
      godMode(true)
      actor:delete()
      actor = nil
    end)
  end

  trials("raised water", raised)
  step("take the raised water away", 1, function()
    if pond then pond:delete() pond = nil end
  end)
  trials("sea", 0)

  step("the raised water against the sea", 0.5, function()
    local a, b = results["raised water player melee"], results["sea player melee"]
    note((a.hits > 0) == (b.hits > 0), "the player's melee reaches a fish in both", string.format("raised water: %d swings, %d hits | sea: %d swings, %d hits", a.swings, a.hits, b.swings, b.hits))
    a, b = results["raised water archer"], results["sea archer"]
    note(a.launched == b.launched and a.hitPlayer == b.hitPlayer and (a.seen > 0) == (b.seen > 0), "an archer on the shore does the same in both",
      string.format("raised water: saw %d s, fought %d s, shot %s, hit the player %s | sea: saw %d s, fought %d s, shot %s, hit the player %s",
        a.seen, a.fighting, tostring(a.launched), tostring(a.hitPlayer), b.seen, b.fighting, tostring(b.launched), tostring(b.hitPlayer)))
    a, b = results["raised water NPC spell"], results["sea NPC spell"]
    note(a.launched == b.launched and a.hitPlayer == b.hitPlayer and a.hitWater == b.hitWater and a.hitObject == b.hitObject, "an NPC's spell at a floating player ends the same way in both",
      string.format("raised water: launched %s, hit the player %s, hit water %s, hit an object %s | sea: launched %s, hit the player %s, hit water %s, hit an object %s",
        tostring(a.launched), tostring(a.hitPlayer), tostring(a.hitWater), tostring(a.hitObject), tostring(b.launched), tostring(b.hitPlayer), tostring(b.hitWater), tostring(b.hitObject)))
  end)

  step("clean up", 1, function()
    if pond then pond:delete() end
    for name, handler in pairs(handlers) do event.unregister(name, handler) end
    godMode(true)
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Marker: the kit pieces as closed bodies of water, taken from the kit plugin
-------------------------------------------------------------------------------

local function runMarker(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end
  local function view(name, settle, setup)
    step("set up: " .. name, 1.5, setup)
    step("photograph: " .. name, settle, function() shot(name) end)
  end

  -- Needs "Water Volumes Kit.esp", added by run_dump.py with --water-plugin. Each kit piece
  -- is a surface shape and a shape named WaterBody for its sides and bottom. The pieces are
  -- put over the open sea, 250 above it, in a row going out from the shore.
  local KIT = {}
  for _, piece in ipairs(kitPieces()) do KIT[#KIT + 1] = piece.name end
  local level = 250
  local centre, out, deep, half, shallow, wading, river

  step("player to the site", 1, function()
    if not controller.volumesSupported then error("this MWSE build has no water volume support") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level - 60 } })
  end)

  step("the kit plugin and the pieces", 8, function()
    local missing = {}
    for _, id in ipairs(KIT) do
      if not tes3.getObject(id) then missing[#missing + 1] = id end
    end
    note(#missing == 0, "the kit plugin provides every piece as a static", #missing == 0 and string.format("%d of %d found", #KIT, #KIT) or ("missing: " .. table.concat(missing, ", ")))
    if #missing > 0 then error("the kit plugin is not loaded") end

    local stale = {}
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local id = reference.baseObject.id:lower()
        if id:find("^wv_") then stale[#stale + 1] = reference end
      end
    end
    for _, reference in ipairs(stale) do reference:delete() end
    local sea
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for r = 1600, 3600, 250 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -250 and (not sea or r < sea.r) then sea = { x = x, y = y, c = c, s = s, r = r } end
      end
    end
    if not sea then error("no open sea was found near the site") end
    centre = tes3vector3.new(sea.x, sea.y, level)
    out = tes3vector3.new(sea.c, sea.s, 0)
    -- A depth of 100 by registration: deeper water than that can only come from the body.
    require("waterVolumes.interop").registerObject("wv_disc_2048", { depth = 100 })
    local function put(id, along, across, scale)
      local position = tes3vector3.new(centre.x + out.x * along - out.y * across, centre.y + out.y * along + out.x * across, level)
      return tes3.createReference({ object = id, position = position, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = position }), scale = scale })
    end
    deep = put("wv_disc_2048", 0, 0, 1)
    half = put("wv_disc_2048", 2200, 0, 0.5)
    shallow = put("wv_disc_1024_d150", 0, 1900, 1)
    wading = put("wv_square_1024_d64", 2200, 1900, 1)
    river = put("wv_riv_1024x2048_f256", 0, -2300, 1)
    observed("set up", string.format("%d stale pieces removed; pieces around %.0f %.0f", #stale, centre.x, centre.y))
  end)

  step("what the bodies do", 7, function()
    local bodies, hidden, shaded, plainShapes = 0, 0, {}, {}
    for object in table.traverse({ deep.sceneNode }) do
      if object:isInstanceOfType(ni.type.NiTriShape) then
        local name = tostring(object.name)
        if name:lower():find("^waterbody") then
          bodies = bodies + 1
          if object.appCulled then hidden = hidden + 1 end
        end
        local shininess = object.materialProperty and object.materialProperty.shininess or 0
        local list = (shininess == 99998 or shininess == 99997) and shaded or plainShapes
        list[#list + 1] = name
      end
    end
    note(bodies == 1 and hidden == 1, "the piece has a body shape and the game does not draw it", string.format("%d body shapes, %d hidden", bodies, hidden))
    note(#shaded == 1 and shaded[1] == "WaterVolume", "only the surface is given the renderer's water shading",
      string.format("shaded as water: %s; left alone: %s", table.concat(shaded, ", "), table.concat(plainShapes, ", ")))

    local function under(reference, below, dx)
      local p = reference.position
      return controller:getVolumeSurfaceAt({ p.x + (dx or 200), p.y, level - below })
    end
    local a, b, c, d = under(deep, 90), under(deep, 300), under(deep, 500), under(deep, 530)
    note(a == level and b == level and c == level and d == nil, "the water is as deep as the body, 512, although the piece is registered with a depth of 100",
      string.format("90 under %s, 300 under %s, 500 under %s, 530 under %s", tostring(a), tostring(b), tostring(c), tostring(d)))
    local e, f, inside, outside = under(half, 200), under(half, 270), under(half, 50, 400), under(half, 50, 600)
    note(e == level and f == nil and inside == level and outside == nil, "a piece at half scale has water half as deep and half as wide",
      string.format("200 under %s, 270 under %s; 400 from its middle %s, 600 from its middle %s", tostring(e), tostring(f), tostring(inside), tostring(outside)))
    local g, h = under(shallow, 140), under(shallow, 160)
    local i, j = under(wading, 50), under(wading, 70)
    note(g == level and h == nil and i == level and j == nil, "the shallow pieces are 150 and 64 deep",
      string.format("150 piece: 140 under %s, 160 under %s; 64 piece: 50 under %s, 70 under %s", tostring(g), tostring(h), tostring(i), tostring(j)))

    -- The river piece starts at its origin and falls 256 towards the south, over 2048.
    local p = river.position
    local function drop(distance) return 256 * distance / 2048 end
    local north = controller:getVolumeSurfaceAt({ p.x, p.y - 124, level - drop(124) - 50 })
    local south = controller:getVolumeSurfaceAt({ p.x, p.y - 1924, level - drop(1924) - 50 })
    local middle = controller:getVolumeSurfaceAt({ p.x, p.y - 1024, level - drop(1024) - 50 })
    local northFloor = controller:getVolumeSurfaceAt({ p.x, p.y - 124, level - drop(124) - 300 })
    local shapes = {}
    if river.sceneNode then
      for object in table.traverse({ river.sceneNode }) do
        if object:isInstanceOfType(ni.type.NiTriShape) then shapes[#shapes + 1] = string.format("%s%s", tostring(object.name), object.appCulled and " (hidden)" or "") end
      end
    end
    say("river piece: at %.0f %.0f %.0f in cell %d,%d, scene node %s, shapes %s; surface over its middle %s", p.x, p.y, p.z, river.cell.gridX, river.cell.gridY,
      tostring(river.sceneNode ~= nil), table.concat(shapes, ", "), tostring(middle))
    note(north ~= nil and south ~= nil and math.abs(north - (level - drop(124))) < 2 and math.abs(south - (level - drop(1924))) < 2 and northFloor == nil,
      "the falling river piece has a sloped surface and a floor 256 under it",
      string.format("surface 124 from its start %s, 1924 from its start %s (expected %.1f and %.1f); 300 under the surface near the start %s", tostring(north), tostring(south),
        level - drop(124), level - drop(1924), tostring(northFloor)))
  end)

  view("kit bodies in game from the side", 3, function()
    camera = { position = tes3vector3.new(centre.x - out.y * 2600 - out.x * 600, centre.y + out.x * 2600 - out.y * 600, level - 150), target = tes3vector3.new(centre.x, centre.y, level - 200) }
  end)
  view("kit bodies in game from above", 3, function()
    camera = { position = tes3vector3.new(centre.x - out.x * 2500, centre.y - out.y * 2500, level + 2600), target = tes3vector3.new(centre.x + out.x * 400, centre.y + out.y * 400, level) }
  end)

  step("clean up", 1, function()
    camera = nil
    for _, reference in ipairs({ deep, half, shallow, wading, river }) do reference:delete() end
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Save and load: a pond outdoors and one in an interior without water, saved and loaded again
-------------------------------------------------------------------------------

local function runSaveLoad(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local interop = require("waterVolumes.interop")
  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function hooks()
    local intact, total = interop.native.hookStatus()
    return string.format("%d of %d hooks, %d volumes", intact, total, interop.native.count())
  end
  local function playerLine()
    local p = tes3.player.position
    return string.format("player at %.0f %.0f %.0f, swimming %s, underwater %s", p.x, p.y, p.z,
      tostring(tes3.mobilePlayer.isSwimming), tostring(tes3.mobilePlayer.underwater))
  end

  local OUTDOOR_SAVE, INDOOR_SAVE = "wv_saveload_out", "wv_saveload_in"
  local x, y, level = SITE.x, SITE.y, SITE.level
  local bottom

  step("god mode on, player to the basin near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { x, y, level + 20 } })
  end)
  step("a pond over the basin, the player on its bottom", 6, function()
    bottom = (groundAt(x, y) or (level - 160)) + 5
    local object = tes3.getObject("wv_save_disc") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_save_disc", mesh = "wv\\wv_disc_1024.nif" })
    tes3.createReference({ object = object, position = { x, y, level }, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
    tes3.positionCell({ reference = tes3.player, position = { x, y, bottom } })
  end)
  step("outdoors, before the save", 4, function()
    local surface = controller:getVolumeSurfaceAt({ x, y, bottom + 20 })
    note(surface ~= nil and math.abs(surface - level) < 0.5 and tes3.mobilePlayer.isSwimming == true, "outdoors: the pond is water before the save",
      string.format("surface %s, expected %.0f; %s; %s", tostring(surface), level, playerLine(), hooks()))
  end)
  step("outdoors: save", 1, function()
    local ok = tes3.saveGame({ file = OUTDOOR_SAVE, name = OUTDOOR_SAVE })
    note(ok == true, "outdoors: the game saves with a pond loaded", "saveGame returned " .. tostring(ok))
  end)
  step("outdoors, after the save: raise the pond, so that the load has something to undo", 3, function()
    local surface = controller:getVolumeSurfaceAt({ x, y, bottom + 20 })
    note(surface ~= nil and math.abs(surface - level) < 0.5 and tes3.mobilePlayer.isSwimming == true, "outdoors: the pond is still water after the save",
      string.format("surface %s; %s; %s", tostring(surface), playerLine(), hooks()))
    local reference = tes3.getReference("wv_save_disc")
    reference.position = tes3vector3.new(x, y, level + 100)
  end)
  step("outdoors: load the save", 3, function()
    local surface = controller:getVolumeSurfaceAt({ x, y, bottom + 20 })
    observed("outdoors: raised pond before the load", string.format("surface %s", tostring(surface)))
    tes3.loadGame(OUTDOOR_SAVE)
  end)
  step("outdoors, after the load", 10, function()
    tes3.worldController.menuController.godModeEnabled = true
    local reference = tes3.getReference("wv_save_disc")
    local surface = controller:getVolumeSurfaceAt({ x, y, bottom + 20 })
    note(reference ~= nil and math.abs(reference.position.z - level) < 0.5, "outdoors: the pond's reference is back where it was saved",
      reference and string.format("z %.0f, expected %.0f", reference.position.z, level) or "no reference")
    note(surface ~= nil and math.abs(surface - level) < 0.5, "outdoors: the pond is water after the load",
      string.format("surface %s, expected %.0f; %s", tostring(surface), level, hooks()))
    note(tes3.mobilePlayer.isSwimming == true and tes3.mobilePlayer.underwater == true, "outdoors: the player loads into the water swimming", playerLine())
    note(interop.native.count() == 1, "outdoors: one volume after the load, none left over", hooks())
  end)

  -- The interior has no water of its own, so the mod flags the cell while the pond is there.
  local indoor = {}
  local duringSave
  local function onSave()
    local cell = tes3.player.cell
    duringSave = { hasWater = cell.hasWater, level = cell.waterLevel }
  end
  step("indoors: to an interior without water", 2, function()
    tes3.runLegacyScript({ command = 'coc "' .. (spec.waterInteriorDry or "Seyda Neen, Arrille's Tradehouse") .. '"', source = tes3.compilerSource.console })
  end)
  step("indoors: a pond over the player", 8, function()
    local cell = tes3.player.cell
    indoor.cellId = cell.id
    indoor.hadWater = cell.hasWater
    local p = tes3.player.position
    indoor.x, indoor.y, indoor.floor, indoor.level = p.x, p.y, p.z, p.z + 150
    observed("indoors: the cell", string.format("%s, has water %s, water level %s", cell.id, tostring(cell.hasWater), tostring(cell.waterLevel)))
    local object = tes3.getObject("wv_save_idisc") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_save_idisc", mesh = "wv\\wv_disc_512.nif" })
    tes3.createReference({ object = object, position = { p.x, p.y, indoor.level }, orientation = { 0, 0, 0 }, cell = cell })
  end)
  step("indoors, before the save", 5, function()
    local cell = tes3.player.cell
    local surface = controller:getVolumeSurfaceAt({ indoor.x, indoor.y, indoor.floor + 20 })
    note(surface ~= nil and tes3.mobilePlayer.isSwimming == true and cell.hasWater == true, "indoors: the pond is water and the cell is flagged before the save",
      string.format("surface %s; cell has water %s, level %s; %s", tostring(surface), tostring(cell.hasWater), tostring(cell.waterLevel), playerLine()))
    -- Runs after the mod's own handler, to see what the save is written with.
    event.register("save", onSave, { priority = -2000 })
  end)
  step("indoors: save", 1, function()
    local ok = tes3.saveGame({ file = INDOOR_SAVE, name = INDOOR_SAVE })
    event.unregister("save", onSave)
    note(ok == true, "indoors: the game saves with a pond loaded", "saveGame returned " .. tostring(ok))
    note(duringSave ~= nil and duringSave.hasWater == indoor.hadWater, "indoors: the save is written with the cell as it was",
      duringSave and string.format("while saving: has water %s, level %s; before the pond: has water %s", tostring(duringSave.hasWater), tostring(duringSave.level), tostring(indoor.hadWater)) or "the save event did not fire")
  end)
  step("indoors, after the save", 3, function()
    local cell = tes3.player.cell
    note(cell.hasWater == true and tes3.mobilePlayer.isSwimming == true, "indoors: the cell is flagged again after the save and the player still swims",
      string.format("cell has water %s, level %s; %s", tostring(cell.hasWater), tostring(cell.waterLevel), playerLine()))
  end)
  step("indoors: load the save", 1, function()
    tes3.loadGame(INDOOR_SAVE)
  end)
  step("indoors, after the load", 10, function()
    tes3.worldController.menuController.godModeEnabled = true
    local cell = tes3.player.cell
    local reference = tes3.getReference("wv_save_idisc")
    local surface = controller:getVolumeSurfaceAt({ indoor.x, indoor.y, indoor.floor + 20 })
    note(cell.id == indoor.cellId and reference ~= nil and surface ~= nil and math.abs(surface - indoor.level) < 0.5, "indoors: the pond is water after the load",
      string.format("cell %s, surface %s, expected %.0f; %s", cell.id, tostring(surface), indoor.level, hooks()))
    note(tes3.mobilePlayer.isSwimming == true, "indoors: the player loads into the water swimming",
      string.format("%s; cell has water %s, level %s", playerLine(), tostring(cell.hasWater), tostring(cell.waterLevel)))
    if reference then reference:delete() end
  end)
  step("indoors, the pond removed after the load", 3, function()
    local cell = tes3.player.cell
    note(cell.hasWater == indoor.hadWater, "indoors: without the pond the loaded cell has no water flag, so the save did not keep it",
      string.format("has water %s, had %s; %s; %s", tostring(cell.hasWater), tostring(indoor.hadWater), playerLine(), hooks()))
  end)
  step("clean up", 1, function()
    for _, name in ipairs({ OUTDOOR_SAVE, INDOOR_SAVE }) do
      local removed = os.remove("Saves\\" .. name .. ".ess")
      say("save %s removed: %s", name, tostring(removed))
    end
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Tilt: a closed kit piece at any tilt holds exactly the water inside it, and a piece that
-- only looks like water holds none
-------------------------------------------------------------------------------

local function runTilt(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end

  local interop = require("waterVolumes.interop")
  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end

  -- The piece hangs in the air over the basin, clear of everything.
  local HALF, DEPTH = 512, 512
  local origin = tes3vector3.new(SITE.x, SITE.y, SITE.level + 3000)
  local piece, falls

  -- Compares the plugin with the box the piece is, in the piece's own frame.
  local function compare(label)
    local node = piece.sceneNode
    node:update()
    local transform = node.worldTransform
    local inverse = transform.rotation:transpose()
    math.randomseed(2024)
    local checked, wrong, inside, firstWrong = 0, 0, 0, nil
    for _ = 1, 4000 do
      local p = tes3vector3.new(origin.x + (math.random() * 2 - 1) * 900, origin.y + (math.random() * 2 - 1) * 900, origin.z + (math.random() * 2 - 1) * 900)
      local l = inverse * (p - transform.translation) / transform.scale
      local nearFace = math.abs(math.abs(l.x) - HALF) < 3 or math.abs(math.abs(l.y) - HALF) < 3 or math.abs(l.z) < 3 or math.abs(l.z + DEPTH) < 3
      if not nearFace then
        local expected = math.abs(l.x) < HALF and math.abs(l.y) < HALF and l.z < 0 and l.z > -DEPTH
        local surface = controller:getVolumeSurfaceAt(p)
        local actual = surface ~= nil and p.z <= surface
        checked = checked + 1
        if expected then inside = inside + 1 end
        if actual ~= expected then
          wrong = wrong + 1
          firstWrong = firstWrong or string.format("local %.0f %.0f %.0f expected %s, surface %s at height %.0f", l.x, l.y, l.z, tostring(expected), tostring(surface), p.z)
        end
      end
    end
    note(wrong == 0, label .. ": the water is the inside of the piece",
      string.format("%d of %d points wrong, %d of them inside%s", wrong, checked, inside, firstWrong and ("; first: " .. firstWrong) or ""))
  end

  step("god mode on, player to the basin near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  step("a closed kit square in the air", 6, function()
    local object = tes3.getObject("wv_tilt_square") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_tilt_square", mesh = "wv\\wv_square_1024.nif" })
    piece = tes3.createReference({ object = object, position = origin, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
  end)

  local tilts = {
    { 0, 0, "level" }, { 20, 0, "tilted 20 degrees" }, { 45, 0, "tilted 45 degrees" }, { 70, 0, "tilted 70 degrees" },
    { 30, 25, "tilted 30 and 25 degrees about two axes" }, { 180, 0, "upside down" },
  }
  for _, tilt in ipairs(tilts) do
    step("tilt: " .. tilt[3], 2, function()
      piece.orientation = tes3vector3.new(math.rad(tilt[1]), math.rad(tilt[2]), 0)
    end)
    step("check: " .. tilt[3], 2, function() compare(tilt[3]) end)
  end

  -- The piece comes down into the basin, tilted 45 degrees, so that the player can stand in it.
  step("tilt 45 degrees, down into the basin", 1, function()
    piece.orientation = tes3vector3.new(math.rad(45), 0, 0)
    piece.position = tes3vector3.new(SITE.x, SITE.y, SITE.level)
  end)
  step("the player onto the bottom of the basin, inside the tilted piece", 2, function()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, (groundAt(SITE.x, SITE.y) or (SITE.level - 160)) + 5 } })
  end)
  step("the player swims in the tilted water", 4, function()
    local p = tes3.player.position
    local surface = controller:getVolumeSurfaceAt(p)
    note(tes3.mobilePlayer.isSwimming == true and surface ~= nil and math.abs(surface - SITE.level) < 1, "tilted 45 degrees: the player swims inside the piece",
      string.format("player at %.0f %.0f %.0f, surface there %s, expected %.0f, swimming %s, underwater %s", p.x, p.y, p.z, tostring(surface), SITE.level,
        tostring(tes3.mobilePlayer.isSwimming), tostring(tes3.mobilePlayer.underwater)))
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)

  step("a piece that only looks like water", 2, function()
    interop.registerObject("wv_tilt_falls", { noSwim = true })
    local object = tes3.getObject("wv_tilt_falls") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_tilt_falls", mesh = "wv\\wv_square_1024.nif" })
    falls = tes3.createReference({ object = object, position = { origin.x, origin.y + 2500, origin.z }, orientation = { math.rad(80), 0, 0 }, cell = tes3.player.cell })
  end)
  step("check: the piece that only looks like water", 3, function()
    local marked, bodiesHidden, bodies = 0, 0, 0
    for object in table.traverse({ falls.sceneNode }) do
      if object:isInstanceOfType(ni.type.NiTriShape) then
        if object.name and object.name:lower():find("^waterbody") then
          bodies = bodies + 1
          if object.appCulled then bodiesHidden = bodiesHidden + 1 end
        elseif object.materialProperty and object.materialProperty.shininess == interop.surfaceMarker then
          marked = marked + 1
        end
      end
    end
    local wet = 0
    for i = 1, 500 do
      local p = { origin.x + (math.random() * 2 - 1) * 600, origin.y + 2500 + (math.random() * 2 - 1) * 600, origin.z + (math.random() * 2 - 1) * 600 }
      if controller:getVolumeSurfaceAt(p) then wet = wet + 1 end
    end
    note(marked > 0 and bodiesHidden == bodies and wet == 0, "noswim: the piece is drawn as water and holds none",
      string.format("%d surface shapes marked for the water shading, %d of %d body shapes hidden, %d of 500 points around it have water; %d volumes registered",
        marked, bodiesHidden, bodies, wet, interop.native.count()))
  end)
  step("clean up", 1, function()
    piece:delete()
    falls:delete()
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Joints: river pieces chained on the grid meet without a gap
-------------------------------------------------------------------------------

local function runJoints(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end

  local GRID, DROP = 256, 64
  local joints = {}
  for _, piece in ipairs(kitPieces()) do joints[piece.name] = piece.joint end

  -- The stream: every piece is put with its origin on the far end of the one before it.
  local CHAIN = {
    "wv_riv_512x1024", "wv_riv_512_bend_e", "wv_riv_512x1024_f64", "wv_riv_512_bend_w_f64", "wv_riv_512_sway_e", "wv_riv_512_sway_w",
    "wv_riv_taper_512_1024", "wv_riv_1024_bend_w_f128", "wv_riv_1024x2048_f256", "wv_riv_1024_sway_e", "wv_riv_1024_bend_e", "wv_riv_1024_end",
  }
  -- High over the land, so that nothing else is in the way of the questions.
  local start = tes3vector3.new(2048, 191488, 2048)
  local placed = {}
  local pin
  local function onFrame()
    if pin and tes3.player.position:distance(pin) > 40 then
      tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
    end
  end

  -- The turn about the vertical, in quarters, that makes a piece's own south point along heading.
  local function quartersFor(reference, heading)
    for quarters = 0, 3 do
      reference.orientation = tes3vector3.new(0, 0, quarters * math.pi / 2)
      reference.sceneNode:update()
      local south = reference.sceneNode.worldTransform.rotation * tes3vector3.new(0, -1, 0)
      if south:dot(heading) > 0.99 then return quarters end
    end
    return nil
  end

  step("god mode on, player to the basin near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)

  step("lay the stream", 6, function()
    local missing = {}
    for _, id in ipairs(CHAIN) do
      if not tes3.getObject(id) then missing[#missing + 1] = id end
    end
    if #missing > 0 then error("the kit plugin lacks: " .. table.concat(missing, ", ")) end

    local at, heading = start:copy(), tes3vector3.new(0, -1, 0)
    for index, id in ipairs(CHAIN) do
      local reference = tes3.createReference({ object = id, position = at, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = at }) })
      local quarters = quartersFor(reference, heading)
      if not quarters then error("no quarter turn points " .. id .. " along the stream") end
      local transform = reference.sceneNode.worldTransform
      local joint = joints[id]
      local entry = { id = id, reference = reference, at = at:copy(), quarters = quarters, heading = heading:copy() }
      placed[index] = entry
      if joint.x then
        entry.out = transform.rotation * tes3vector3.new(joint.x, joint.y, joint.z) + at
        entry.outHeading = transform.rotation * tes3vector3.new(joint.dx, joint.dy, 0)
        -- The next origin is this far end, put on the grid as the Construction Set would.
        at = tes3vector3.new(math.round(entry.out.x / DROP) * DROP, math.round(entry.out.y / DROP) * DROP, math.round(entry.out.z / DROP) * DROP)
        entry.offGrid = entry.out:distance(at)
        heading = entry.outHeading
      end
    end
  end)

  step("the pieces are on the grid", 4, function()
    local worst, worstId, offLevel = 0, "", 0
    for _, entry in ipairs(placed) do
      if entry.offGrid and entry.offGrid > worst then worst, worstId = entry.offGrid, entry.id end
      local p = entry.reference.position
      offLevel = math.max(offLevel, math.abs(p.x / GRID - math.round(p.x / GRID)) * GRID, math.abs(p.y / GRID - math.round(p.y / GRID)) * GRID)
    end
    note(worst < 0.01 and offLevel < 0.01, "the far end of every piece is a grid point: 256 level, 64 down",
      string.format("%d pieces; farthest far end from the grid %.4f (%s); farthest origin from the 256 grid %.4f", #placed, worst, worstId, offLevel))
    local list = {}
    for _, entry in ipairs(placed) do
      list[#list + 1] = string.format("%s at %.0f %.0f %.0f turned %d", entry.id, entry.at.x, entry.at.y, entry.at.z, entry.quarters * 90)
    end
    say("stream: %s", table.concat(list, "; "))
  end)

  step("the ends of neighbours share their corners", 1, function()
    -- The surface corners of each piece, in the world.
    local function corners(reference)
      local list = {}
      for object in table.traverse({ reference.sceneNode }) do
        if object:isInstanceOfType(ni.type.NiTriShape) and object.name == "WaterVolume" then
          local transform = object.worldTransform
          for _, vertex in ipairs(object.data.vertices) do
            list[#list + 1] = transform.rotation * vertex * transform.scale + transform.translation
          end
        end
      end
      return list
    end
    local worst, worstAt, pairsFound = 0, "", 0
    for index = 1, #placed - 1 do
      local a, b = placed[index], placed[index + 1]
      local half = joints[a.id].width / 2
      local across = tes3vector3.new(a.outHeading.y, -a.outHeading.x, 0)
      for _, side in ipairs({ -1, 1 }) do
        local corner = a.out + across * (half * side)
        local nearestA, nearestB = math.huge, math.huge
        for _, p in ipairs(corners(a.reference)) do nearestA = math.min(nearestA, p:distance(corner)) end
        for _, p in ipairs(corners(b.reference)) do nearestB = math.min(nearestB, p:distance(corner)) end
        pairsFound = pairsFound + 1
        local gap = math.max(nearestA, nearestB)
        if gap > worst then worst, worstAt = gap, a.id .. " to " .. b.id end
      end
    end
    note(worst < 0.01, "at every joint both pieces have a surface corner on the same two points",
      string.format("%d corners at %d joints; farthest corner from its point %.5f (%s)", pairsFound, #placed - 1, worst, worstAt))
  end)

  step("the water is unbroken across every joint", 1, function()
    local gaps, steps_, worstStep, checked, firstGap = 0, 0, 0, 0, nil
    for index = 1, #placed - 1 do
      local a = placed[index]
      local half = joints[a.id].width / 2
      local across = tes3vector3.new(a.outHeading.y, -a.outHeading.x, 0)
      -- Lines along the stream through the joint, across most of its width.
      for _, part in ipairs({ -0.95, -0.5, 0, 0.5, 0.95 }) do
        local last
        for _, along in ipairs({ -24, -8, -2, -0.5, -0.05, -0.001, 0, 0.001, 0.05, 0.5, 2, 8, 24 }) do
          local p = a.out + across * (half * part) + a.outHeading * along
          local surface = controller:getVolumeSurfaceAt({ p.x, p.y, p.z - 40 })
          checked = checked + 1
          if not surface then
            gaps = gaps + 1
            firstGap = firstGap or string.format("%s, %.3f past its far end, %.0f%% across", a.id, along, part * 100)
          elseif last then
            worstStep = math.max(worstStep, math.abs(surface - last))
          end
          last = surface or last
        end
      end
    end
    note(gaps == 0 and worstStep < 4, "40 under the surface there is water at every point on lines through every joint, and the level has no step",
      string.format("%d of %d points without water%s; largest change of level between neighbouring points %.3f", gaps, checked, firstGap and (" (first: " .. firstGap .. ")") or "", worstStep))
  end)

  step("set up: the stream from above", 1, function()
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, entry in ipairs(placed) do sx, sy, sz, n = sx + entry.at.x, sy + entry.at.y, sz + entry.at.z, n + 1 end
    local middle = tes3vector3.new(sx / n, sy / n, sz / n)
    camera = { position = middle + tes3vector3.new(600, -900, 3400), target = middle }
    pin = camera.position - tes3vector3.new(0, 0, 130)
    event.register("enterFrame", onFrame)
  end)
  step("photograph: the stream from above", 4, function() shot("kit stream from above") end)
  step("set up: a joint from close by", 1, function()
    local a = placed[2]
    camera = { position = a.out + tes3vector3.new(500, 500, 450), target = a.out }
    pin = camera.position - tes3vector3.new(0, 0, 130)
  end)
  step("photograph: a joint from close by", 4, function() shot("kit stream joint after the first bend") end)
  step("set up: along the stream", 1, function()
    local a, b = placed[7], placed[9]
    camera = { position = a.at + tes3vector3.new(0, 0, 500) - a.heading * 900, target = b.at }
    pin = camera.position - tes3vector3.new(0, 0, 130)
  end)
  step("photograph: along the stream", 4, function() shot("kit stream along the wide part") end)

  step("clean up", 1, function()
    camera = nil
    pin = nil
    event.unregister("enterFrame", onFrame)
    for _, entry in ipairs(placed) do entry.reference:delete() end
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Blender: a mesh as the Morrowind Blender Plugin writes it, with no tag and no NCO entry,
-- is water all the same
-------------------------------------------------------------------------------

local function runBlender(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local interop = require("waterVolumes.interop")
  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end

  local HALF, DEPTH = 512, 512
  local FILE = "Data Files\\Meshes\\wv\\wv_test_blender.nif"
  local air = tes3vector3.new(SITE.x, SITE.y, SITE.level + 3000)
  local piece

  -- The exporter writes an object with several materials as a node with one shape per
  -- material, named "Tri <object> <n>". It writes no text entries on the root.
  local function shape(name, vertices, triangles)
    local s = niTriShape.new(#vertices, true, true, 0, #triangles)
    s.name = name
    for i, v in ipairs(vertices) do
      local p = s.data.vertices[i]
      p.x, p.y, p.z = v[1], v[2], v[3]
      local n = s.data.normals[i]
      n.x, n.y, n.z = 0, 0, 1
      local c = s.data.colors[i]
      c.r, c.g, c.b, c.a = 120, 170, 160, 200
    end
    for i, t in ipairs(triangles) do
      local indices = s.data.triangles[i].vertices
      indices[1], indices[2], indices[3] = t[1], t[2], t[3]
    end
    s.data:markAsChanged()
    s.data:updateModelBound()
    return s
  end
  local function buildMesh()
    local h, d = HALF, DEPTH
    local root = niNode.new()
    root.name = "wv_test_blender"
    local surface = niNode.new()
    surface.name = "WaterVolume skyonly"
    surface:attachChild(shape("Tri WaterVolume skyonly 0", { { -h, -h, 0 }, { h, -h, 0 }, { h, h, 0 } }, { { 0, 1, 2 } }))
    surface:attachChild(shape("Tri WaterVolume skyonly 1", { { -h, -h, 0 }, { h, h, 0 }, { -h, h, 0 } }, { { 0, 1, 2 } }))
    local body = niNode.new()
    body.name = "WaterBody.001"
    body:attachChild(shape("Tri WaterBody.001 0", { { -h, -h, -d }, { h, -h, -d }, { h, h, -d }, { -h, h, -d } }, { { 0, 2, 1 }, { 0, 3, 2 } }))
    local corners = { { -h, -h }, { h, -h }, { h, h }, { -h, h } }
    local vertices, triangles = {}, {}
    for i = 1, 4 do
      local a, b = corners[i], corners[i % 4 + 1]
      local base = #vertices
      vertices[base + 1] = { a[1], a[2], 0 }
      vertices[base + 2] = { b[1], b[2], 0 }
      vertices[base + 3] = { b[1], b[2], -d }
      vertices[base + 4] = { a[1], a[2], -d }
      triangles[#triangles + 1] = { base, base + 1, base + 2 }
      triangles[#triangles + 1] = { base, base + 2, base + 3 }
    end
    body:attachChild(shape("Tri WaterBody.001 1", vertices, triangles))
    root:attachChild(surface)
    root:attachChild(body)
    root:update()
    root:updateProperties()
    os.remove(FILE)
    local saved = root:saveBinary(FILE)
    return saved and lfs.attributes(FILE, "size")
  end

  local function compare(label)
    local node = piece.sceneNode
    node:update()
    local transform = node.worldTransform
    local inverse = transform.rotation:transpose()
    math.randomseed(2025)
    local checked, wrong, inside, firstWrong = 0, 0, 0, nil
    for _ = 1, 4000 do
      local p = tes3vector3.new(air.x + (math.random() * 2 - 1) * 900, air.y + (math.random() * 2 - 1) * 900, air.z + (math.random() * 2 - 1) * 900)
      local l = inverse * (p - transform.translation) / transform.scale
      local nearFace = math.abs(math.abs(l.x) - HALF) < 3 or math.abs(math.abs(l.y) - HALF) < 3 or math.abs(l.z) < 3 or math.abs(l.z + DEPTH) < 3
      if not nearFace then
        local expected = math.abs(l.x) < HALF and math.abs(l.y) < HALF and l.z < 0 and l.z > -DEPTH
        local surface = controller:getVolumeSurfaceAt(p)
        local actual = surface ~= nil and p.z <= surface
        checked = checked + 1
        if expected then inside = inside + 1 end
        if actual ~= expected then
          wrong = wrong + 1
          firstWrong = firstWrong or string.format("local %.0f %.0f %.0f expected %s, surface %s", l.x, l.y, l.z, tostring(expected), tostring(surface))
        end
      end
    end
    note(wrong == 0 and inside > 100, label, string.format("%d of %d points wrong, %d of them inside%s", wrong, checked, inside, firstWrong and ("; first: " .. firstWrong) or ""))
  end

  local function playerAbove(height)
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level + height } })
  end
  local function playerLine()
    local p = tes3.player.position
    return string.format("player at height %.0f, surface of the piece at %.0f, swimming %s", p.z, SITE.level, tostring(tes3.mobilePlayer.isSwimming))
  end

  step("god mode on, player beside the basin near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  step("write the mesh and place it in the air, tilted", 6, function()
    local size = buildMesh()
    if not size then error("the mesh could not be written to " .. FILE) end
    observed("mesh", string.format("%s, %d bytes: no text entries on the root, surface and body each a node with two shapes", FILE, size))
    local object = tes3.getObject("wv_blender_piece") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_blender_piece", mesh = "wv\\wv_test_blender.nif" })
    piece = tes3.createReference({ object = object, position = air, orientation = { math.rad(30), math.rad(25), 0 }, cell = tes3.player.cell })
  end)
  step("the mesh is taken as water by its names", 3, function()
    local node = piece.sceneNode
    local tagged = node:hasStringDataStartingWith("WaterVolume") or node:hasStringDataStartingWith("NCO")
    local surfaces, marked, bodyHidden, bodyShapes = 0, 0, false, 0
    local function walk(object, inBody)
      local name = tostring(object.name):lower()
      if name:find("^waterbody") then
        inBody = true
        bodyHidden = object.appCulled == true
      end
      if object:isInstanceOfType(ni.type.NiTriShape) then
        if inBody then
          bodyShapes = bodyShapes + 1
        else
          surfaces = surfaces + 1
          if object.materialProperty and object.materialProperty.shininess == interop.surfaceMarkerSkyOnly then marked = marked + 1 end
        end
      end
      if object.children then
        for _, child in ipairs(object.children) do
          if child then walk(child, inBody) end
        end
      end
    end
    walk(node, false)
    note(not tagged and interop.native.count() == 1, "a mesh with no text entries is water because an object in it is named WaterVolume",
      string.format("text entries on the root: %s; %d volumes registered", tostring(tagged), interop.native.count()))
    note(surfaces == 2 and marked == 2, "the option in the name is used: both surface shapes are marked for sky-only water shading",
      string.format("%d surface shapes, %d marked sky-only", surfaces, marked))
    note(bodyShapes == 2 and bodyHidden, "the body, written as a group of two shapes, is hidden as a whole",
      string.format("%d body shapes under a node that is hidden: %s", bodyShapes, tostring(bodyHidden)))
    compare("the body made of two shapes closes the mesh: the water is the inside of the piece, tilted 30 and 25 degrees")
  end)

  step("down into the basin, level", 1, function()
    piece.orientation = tes3vector3.new(0, 0, 0)
    piece.position = tes3vector3.new(SITE.x, SITE.y, SITE.level)
  end)
  step("the player is let go 60 above the surface", 3, function()
    observed("collision flag", string.format("the reference has its collision switched off: %s", tostring(piece.hasNoCollision)))
    playerAbove(60)
  end)
  step("the player falls through the surface into the water", 4, function()
    local p = tes3.player.position
    note(piece.hasNoCollision == true and p.z < SITE.level - 5 and tes3.mobilePlayer.isSwimming == true,
      "without an NCO entry nobody stands on the surface: the mod switches the collision off", playerLine())
    -- The same mesh with its collision on again, to show what the mod prevents.
    piece:setNoCollisionFlag(false, true)
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  step("control: collision on again, the player let go 60 above the surface", 3, function() playerAbove(60) end)
  step("control: the player stands on the surface", 4, function()
    local p = tes3.player.position
    note(math.abs(p.z - SITE.level) < 12 and tes3.mobilePlayer.isSwimming ~= true, "control: with its collision on the same mesh carries the player", playerLine())
    piece:setNoCollisionFlag(true, true)
    local started = seconds()
    for _ = 1, 5 do tes3.dataHandler:updateCollisionGroupsForActiveCells() end
    observed("cost", string.format("working the collisions out again for the loaded cells takes %.2f ms", (seconds() - started) / 5 * 1000))
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  -- A save holds the reference as it would be without the mod.
  local duringSave
  local function onSave() duringSave = piece.hasNoCollision end
  step("save with the piece loaded", 2, function()
    event.register("save", onSave, { priority = -2000 })
    local ok = tes3.saveGame({ file = "wv_blender_save", name = "wv_blender_save" })
    event.unregister("save", onSave)
    note(ok == true and duringSave == false, "the save is written with the collision of the reference on",
      string.format("saveGame returned %s; collision switched off while saving: %s", tostring(ok), tostring(duringSave)))
    say("save removed: %s", tostring(os.remove("Saves\\wv_blender_save.ess")))
  end)
  step("after the save", 2, function()
    note(piece.hasNoCollision == true, "the collision is switched off again after the save", string.format("switched off: %s", tostring(piece.hasNoCollision)))
    -- A registration made now has to reach the reference that is already loaded.
    interop.registerObject("wv_blender_piece", { noSwim = true })
  end)
  step("the object registered as water nobody swims in", 2, function()
    local surface = controller:getVolumeSurfaceAt({ SITE.x, SITE.y, SITE.level - 50 })
    note(interop.native.count() == 0 and surface == nil and piece.hasNoCollision == true, "a registration made later reaches the loaded reference",
      string.format("%d volumes registered, surface under the piece %s, collision switched off %s", interop.native.count(), tostring(surface), tostring(piece.hasNoCollision)))
  end)
  step("clean up", 2, function()
    piece:delete()
    say("mesh file removed: %s", tostring(os.remove(FILE)))
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Swim depth: how deep the water must be before the player swims
-------------------------------------------------------------------------------

local function runSwimDepth(spec, say, after, done)
  local rows = {}
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local piece, ground
  local readings = {}

  step("god mode on, player onto the bottom of the basin near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.force1stPerson()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level } })
  end)
  step("a pond with its surface at the player's feet", 6, function()
    ground = tes3.player.position.z
    local object = tes3.getObject("wv_depth_square") or tes3.createObject({ objectType = tes3.objectType.static, id = "wv_depth_square", mesh = "wv\\wv_square_1024.nif" })
    piece = tes3.createReference({ object = object, position = { SITE.x, SITE.y, ground }, orientation = { 0, 0, 0 }, cell = tes3.player.cell })
    local mobile = tes3.mobilePlayer
    local race = tes3.player.object.race
    local female = tes3.player.object.female
    local raceHeight = race and (female and race.height.female or race.height.male)
    observed("the player", string.format("standing at height %.1f; mobile height %.1f; race %s, %s, race height %s; fSwimHeightScale %.3f",
      ground, mobile.height, race and race.id or "?", female and "female" or "male", tostring(raceHeight), tes3.findGMST(tes3.gmst.fSwimHeightScale).value))
  end)
  -- The surface rises by 2 at a time. The player stays put, on the ground, until swimming starts.
  for depth = 80, 170, 2 do
    step("water " .. depth .. " deep", 0.45, function()
      if #readings > 0 then
        local last = readings[#readings]
        last.swimming = tes3.mobilePlayer.isSwimming == true
        last.underwater = tes3.mobilePlayer.underwater == true
        last.z = tes3.player.position.z
      end
      piece.position = tes3vector3.new(SITE.x, SITE.y, ground + depth)
      readings[#readings + 1] = { depth = depth }
    end)
  end
  step("what was seen", 0.6, function()
    local last = readings[#readings]
    last.swimming, last.underwater, last.z = tes3.mobilePlayer.isSwimming == true, tes3.mobilePlayer.underwater == true, tes3.player.position.z
    local firstSwim, firstUnder
    for _, r in ipairs(readings) do
      if r.swimming and not firstSwim then firstSwim = r end
      if r.underwater and not firstUnder then firstUnder = r end
    end
    local height = tes3.mobilePlayer.height
    observed("swimming", firstSwim and string.format("starts with the water %d deep over the player's feet, which is %.3f of the mobile height %.1f; the player was at height %.1f then, the ground at %.1f",
      firstSwim.depth, firstSwim.depth / height, height, firstSwim.z, ground) or "never started up to 170")
    observed("head under water", firstUnder and string.format("first reported with the water %d deep", firstUnder.depth) or "never reported up to 170")
    local line = {}
    for _, r in ipairs(readings) do line[#line + 1] = string.format("%d%s", r.depth, r.swimming and "s" or "-") end
    say("readings (s = swimming): %s", table.concat(line, " "))
  end)
  step("clean up", 1, function() piece:delete() end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- River demo: the river a plugin laid along Foyada Mamaea, checked against the real ground
-------------------------------------------------------------------------------

local function runRiverDemo(spec, say, after, done)
  local rows = {}
  local function note(ok, name, detail)
    rows[#rows + 1] = { ok = ok, name = name, detail = detail }
    say("%s %s: %s", ok and "PASS" or "FAIL", name, detail)
  end
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local interop = require("waterVolumes.interop")
  local controller = waterController()
  local directory = spec.waterShotDir or runDirectory(spec)
  local prefix = spec.waterShotPrefix or ""
  local shots = 0
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local function shot(name)
    shots = shots + 1
    local path = string.format("%s/%s%02d %s.jpg", directory, prefix, shots, name)
    os.remove(path)
    mge.saveScreenshot({ path = path })
    say("screenshot %s", path)
  end
  local function clearSky() tes3.changeWeather({ id = 0, immediate = true }) end

  local CELL = 8192
  -- "riverdemohold" makes the checks, then leaves the game to the person at the keyboard.
  local hold = spec.water == "riverdemohold"
  local kit = {}
  for _, piece in ipairs(kitPieces()) do kit[piece.name] = piece end
  local chain = {}      -- the pieces in the order the water runs through them
  local samples = {}    -- points down the middle of the stream, with the water and the land there
  local pin
  local function onFrame()
    if pin and tes3.player.position:distance(pin) > 40 then
      tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
    end
  end
  local function lookFrom(position, target)
    clearSky()
    camera = { position = position, target = target }
    pin = position - tes3vector3.new(0, 0, 130)
    tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
  end
  local function toWorld(reference, x, y, z)
    local t = reference.sceneNode.worldTransform
    return t.rotation * tes3vector3.new(x, y, z) * t.scale + t.translation
  end
  local function key(p) return string.format("%d,%d", math.round(p.x / 64), math.round(p.y / 64)) end

  step("god mode on, clear noon, to the foyada south-west of Ghostgate", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.force1stPerson()
    event.register("enterFrame", onFrame)
    pin = tes3vector3.new(1.5 * CELL, 3.5 * CELL, 6000)
    tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
    clearSky()
  end)

  step("the pieces of the river", 5, function()
    local pieces, byOrigin, isOut = {}, {}, {}
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local id = reference.baseObject.id:lower()
        if id:find("^wv_riv_") and reference.sceneNode and not reference.disabled then
          reference.sceneNode:update()
          local entry = { id = id, reference = reference, piece = kit[id], cell = cell }
          local joint = entry.piece and entry.piece.joint
          if joint and joint.x then
            entry.out = toWorld(reference, joint.x, joint.y, joint.z)
            entry.outHeading = reference.sceneNode.worldTransform.rotation * tes3vector3.new(joint.dx, joint.dy, 0)
            isOut[key(entry.out)] = true
            byOrigin[key(reference.position)] = entry
          end
          pieces[#pieces + 1] = entry
        end
      end
    end
    local first, ends = nil, 0
    for _, entry in ipairs(pieces) do
      if not entry.out then
        ends = ends + 1
      elseif not isOut[key(entry.reference.position)] then
        first = entry
      end
    end
    local at = first
    while at do
      chain[#chain + 1] = at
      at = byOrigin[key(at.out)]
    end
    local cells = {}
    for _, entry in ipairs(pieces) do cells[string.format("%d,%d", entry.cell.gridX, entry.cell.gridY)] = true end
    local names = {}
    for name in pairs(cells) do names[#names + 1] = name end
    table.sort(names)
    note(#chain > 0 and #chain + ends == #pieces and ends == 2, "the plugin's pieces form one stream from end to end",
      string.format("%d pieces found in cells %s: %d in one chain, %d rounded ends; %d volumes registered", #pieces, table.concat(names, " "), #chain, ends, interop.native.count()))
  end)

  step("the joints", 1, function()
    local function corners(reference)
      local list = {}
      for object in table.traverse({ reference.sceneNode }) do
        if object:isInstanceOfType(ni.type.NiTriShape) and object.name == "WaterVolume" then
          local t = object.worldTransform
          for _, vertex in ipairs(object.data.vertices) do list[#list + 1] = t.rotation * vertex * t.scale + t.translation end
        end
      end
      return list
    end
    local worst, worstAt = 0, ""
    for index = 1, #chain - 1 do
      local a, b = chain[index], chain[index + 1]
      local half = a.piece.joint.width / 2
      local across = tes3vector3.new(a.outHeading.y, -a.outHeading.x, 0)
      for _, side in ipairs({ -1, 1 }) do
        local corner = a.out + across * (half * side)
        local nearestA, nearestB = math.huge, math.huge
        for _, p in ipairs(corners(a.reference)) do nearestA = math.min(nearestA, p:distance(corner)) end
        for _, p in ipairs(corners(b.reference)) do nearestB = math.min(nearestB, p:distance(corner)) end
        local gap = math.max(nearestA, nearestB)
        if gap > worst then worst, worstAt = gap, a.id .. " to " .. b.id end
      end
    end
    note(worst < 0.01, "at every joint both pieces have a surface corner on the same two points",
      string.format("%d joints; farthest corner from its point %.5f %s", #chain - 1, worst, worstAt))
  end)

  step("the water against the land", 1, function()
    local dry, buried, hanging, banks, edges = 0, 0, 0, 0, 0
    local least, most, sum = math.huge, -math.huge, 0
    local travelled = 0
    for _, entry in ipairs(chain) do
      local points = entry.piece.points
      local n = #points / 2
      local last
      for i = 1, n do
        local w, e = points[i], points[n + i]
        local middle = toWorld(entry.reference, (w[1] + e[1]) / 2, (w[2] + e[2]) / 2, (w[3] + e[3]) / 2)
        if last then travelled = travelled + middle:distance(last) end
        last = middle
        local surface = controller:getVolumeSurfaceAt({ middle.x, middle.y, middle.z - 30 })
        local ground = groundAt(middle.x, middle.y)
        if not surface then
          dry = dry + 1
        elseif ground then
          local depth = surface - ground
          samples[#samples + 1] = { position = middle, surface = surface, ground = ground, depth = depth, along = travelled, id = entry.id, heading = entry.outHeading }
          least, most, sum = math.min(least, depth), math.max(most, depth), sum + depth
          if depth < 0 then buried = buried + 1 end
          if depth > 256 then hanging = hanging + 1 end
        end
        -- The banks: is the land at the two sides of the stream above the water?
        for _, side in ipairs({ w, e }) do
          local p = toWorld(entry.reference, side[1], side[2], side[3])
          local land = groundAt(p.x, p.y)
          edges = edges + 1
          if land and land >= p.z then banks = banks + 1 end
        end
      end
    end
    observed("the stream", string.format("%.0f long, the water falls from %.0f to %.0f; %d points down its middle",
      travelled, samples[1] and samples[1].surface or 0, samples[#samples] and samples[#samples].surface or 0, #samples))
    note(dry == 0, "there is water at every point down the middle of the stream", string.format("%d points without water", dry))
    note(buried == 0 and hanging == 0, "the water is neither under the land nor deeper than the body of a piece (256)",
      string.format("water %.0f to %.0f deep over the land, %.0f on average; %d points under the land, %d points deeper than 256",
        least, most, sum / math.max(#samples, 1), buried, hanging))
    observed("the banks", string.format("at %d of %d points on the two sides of the stream the land stands above the water", banks, edges))
    local shallow = {}
    for _, s in ipairs(samples) do
      if s.depth < 60 then shallow[#shallow + 1] = string.format("%.0f at %.0f (%s)", s.depth, s.along, s.id) end
    end
    say("points shallower than 60: %s", #shallow > 0 and table.concat(shallow, "; ") or "none")
  end)

  -- The player stands on the land under the water at three places.
  local swims = {}
  for index, part in ipairs({ 0.15, 0.5, 0.9 }) do
    step("the player into the stream, place " .. index, 2, function()
      camera, pin = nil, nil
      local best
      for _, s in ipairs(samples) do
        if s.depth >= 135 and (not best or math.abs(s.along - samples[#samples].along * part) < math.abs(best.along - samples[#samples].along * part)) then best = s end
      end
      swims[index] = best
      if best then tes3.positionCell({ reference = tes3.player, position = { best.position.x, best.position.y, best.ground + 5 } }) end
    end)
    step("does the player swim, place " .. index, 3, function()
      local s = swims[index]
      if not s then
        note(false, "the player swims in the stream, place " .. index, "no point 135 deep or more")
        return
      end
      local p = tes3.player.position
      note(tes3.mobilePlayer.isSwimming == true, "the player swims in the stream, place " .. index,
        string.format("%.0f along the stream in %s, water %.0f deep there; player at height %.0f, water at %.0f, swimming %s",
          s.along, s.id, s.depth, p.z, s.surface, tostring(tes3.mobilePlayer.isSwimming)))
    end)
  end

  -- Pictures looking down the stream, from four places and from high above.
  for index, part in ipairs(hold and {} or { 0.05, 0.35, 0.65, 0.9 }) do
    step("set up: view down the stream " .. index, 1, function()
      local s, ahead
      for _, sample in ipairs(samples) do
        if not s and sample.along >= samples[#samples].along * part then s = sample end
        if s and not ahead and sample.along >= s.along + 1400 then ahead = sample end
      end
      ahead = ahead or samples[#samples]
      local back = (s.position - ahead.position):normalized()
      lookFrom(s.position + back * 500 + tes3vector3.new(0, 0, 420), ahead.position)
    end)
    step("photograph: view down the stream " .. index, 4, function() shot("river demo " .. index .. " down the stream") end)
  end
  if not hold then
    step("set up: from above", 1, function()
      local middle = samples[math.ceil(#samples / 2)].position
      lookFrom(middle + tes3vector3.new(900, -1200, 4200), middle)
    end)
    step("photograph: from above", 4, function() shot("river demo 5 from above") end)
  end

  step("clean up", 1, function()
    camera, pin = nil, nil
    event.unregister("enterFrame", onFrame)
  end)
  if hold then
    -- DONE is never said: the runner waits, and restores the testing instance when the game is quit.
    step("hand over: the player beside the top of the stream", 1, function()
      local first = chain[1].reference
      local down = first.sceneNode.worldTransform.rotation * tes3vector3.new(0, -1, 0)
      local spot = first.position - down * 520
      local land = groundAt(spot.x, spot.y) or first.position.z
      clearSky()
      tes3.positionCell({
        reference = tes3.player, position = { spot.x, spot.y, land + 10 },
        orientation = { 0, 0, math.atan2(down.x, down.y) },
      })
      say("HANDED OVER: the game is yours. The stream runs %d pieces down the foyada from here. Quit the game when you are done.", #chain)
    end)
    sequence(steps, say, after, function() end)
    return
  end
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Stream AI: what fish and rats do in the demo river, against what they do in the sea and
-- in a pond that the land encloses
-------------------------------------------------------------------------------

local function runStreamAI(spec, say, after, done)
  local rows = {}
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end

  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local CELL = 8192
  local kit = {}
  for _, piece in ipairs(kitPieces()) do kit[piece.name] = piece end
  local samples = {}
  local created = {}

  local function toWorld(reference, x, y, z)
    local t = reference.sceneNode.worldTransform
    return t.rotation * tes3vector3.new(x, y, z) * t.scale + t.translation
  end

  -- Is a point in water, and how far under the surface? Volumes first, then the sea.
  local function waterAt(p)
    local surface = controller:getVolumeSurfaceAt(p)
    if surface and p.z <= surface then return true, surface - p.z, "volume" end
    if p.z < 0 then return true, -p.z, "sea" end
    return false, 0, "none"
  end

  -- Watches actors for a while and says what they did. where(p) gives extra words for a place.
  local watch
  local function startWatch(label, actors, seconds_, where)
    watch = { label = label, actors = actors, left = math.floor(seconds_ / 0.5), where = where, log = {} }
    for i, reference in ipairs(actors) do watch.log[i] = {} end
    local function tick()
      if not watch then return end
      for i, reference in ipairs(watch.actors) do
        local mobile = reference.mobile
        local p = reference.position:copy()
        local wet, under, kind = waterAt(p)
        local ground = groundAt(p.x, p.y)
        table.insert(watch.log[i], {
          p = p, wet = wet, under = under, kind = kind, above = ground and (p.z - ground) or nil,
          swimming = mobile and mobile.isSwimming == true, combat = mobile and mobile.inCombat == true,
          extra = watch.where and watch.where(p) or nil,
        })
      end
      watch.left = watch.left - 1
      if watch.left > 0 then timer.start({ type = timer.real, duration = 0.5, callback = tick }) end
    end
    tick()
  end
  local function endWatch()
    local w = watch
    watch = nil
    for i, log in ipairs(w.log) do
      local wetCount, swimCount, firstDry, lastWet = 0, 0, nil, nil
      for k, r in ipairs(log) do
        if r.wet then wetCount = wetCount + 1 lastWet = k elseif not firstDry then firstDry = k end
        if r.swimming then swimCount = swimCount + 1 end
      end
      local first, last = log[1], log[#log]
      local exit = "never left the water"
      if firstDry then
        local r = log[firstDry]
        exit = string.format("first out of the water after %.1f s at %.0f %.0f %.0f, %s above the land%s", (firstDry - 1) * 0.5, r.p.x, r.p.y, r.p.z,
          r.above and string.format("%.0f", r.above) or "?", r.extra and (", " .. r.extra) or "")
      end
      observed(w.label .. ", " .. w.actors[i].baseObject.id .. " " .. i, string.format(
        "in water at %d of %d looks, swimming flag at %d; %s; moved %.0f in all; at the end %s, %s above the land, swimming %s, in combat %s%s",
        wetCount, #log, swimCount, exit, first.p:distance(last.p), last.wet and ("in water (" .. last.kind .. "), " .. string.format("%.0f", last.under) .. " under the surface") or "out of the water",
        last.above and string.format("%.0f", last.above) or "?", tostring(last.swimming), tostring(last.combat), last.extra and (", " .. last.extra) or ""))
    end
  end
  local function spawn(id, position)
    local reference = tes3.createReference({ object = id, position = position, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = position }) })
    created[#created + 1] = reference
    return reference
  end
  local function removeAll()
    for _, reference in ipairs(created) do
      if reference.mobile then pcall(function() reference.mobile:stopCombat(true) end) end
      reference:delete()
    end
    created = {}
  end

  -- How far a point is from the middle line of the stream.
  local function offStream(p)
    local best = math.huge
    for _, s in ipairs(samples) do
      local d = math.sqrt((s.position.x - p.x) ^ 2 + (s.position.y - p.y) ^ 2)
      if d < best then best = d end
    end
    return string.format("%.0f from the middle of the stream (its side is at 256)", best)
  end

  step("god mode on, clear noon, to the foyada", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { 12800, 29440, 1400 } })
    tes3.changeWeather({ id = 0, immediate = true })
  end)

  local deep
  step("the stream", 6, function()
    for _, cell in ipairs(tes3.getActiveCells()) do
      for reference in cell:iterateReferences(tes3.objectType.static) do
        local piece = kit[reference.baseObject.id:lower()]
        if piece and piece.joint and piece.joint.x and reference.sceneNode then
          reference.sceneNode:update()
          local n = #piece.points / 2
          local out = reference.sceneNode.worldTransform.rotation * tes3vector3.new(piece.joint.dx, piece.joint.dy, 0)
          for i = 1, n do
            local w, e = piece.points[i], piece.points[n + i]
            local middle = toWorld(reference, (w[1] + e[1]) / 2, (w[2] + e[2]) / 2, (w[3] + e[3]) / 2)
            local ground = groundAt(middle.x, middle.y)
            local west = toWorld(reference, w[1], w[2], w[3])
            local east = toWorld(reference, e[1], e[2], e[3])
            samples[#samples + 1] = { position = middle, ground = ground, depth = ground and (middle.z - ground) or 0, id = reference.baseObject.id,
              westLand = groundAt(west.x, west.y), eastLand = groundAt(east.x, east.y), west = west, east = east, flow = out }
          end
        end
      end
    end
    if #samples == 0 then error("the river demo plugin is not loaded") end
    -- The deepest stretch near the player.
    for _, s in ipairs(samples) do
      if s.depth >= 180 and s.depth <= 230 and s.position:distance(tes3.player.position) < 2500 and (not deep or s.depth > deep.depth) then deep = s end
    end
    deep = deep or samples[math.ceil(#samples / 2)]
    observed("the place in the stream", string.format("%s at %.0f %.0f: water at %.0f, land under the middle %.0f (%.0f deep), land under the west side %.0f and under the east side %.0f: the sides of the water stand %.0f and %.0f above the land",
      deep.id, deep.position.x, deep.position.y, deep.position.z, deep.ground, deep.depth, deep.westLand or 0, deep.eastLand or 0,
      deep.position.z - (deep.westLand or 0), deep.position.z - (deep.eastLand or 0)))
    local open, total = 0, 0
    for _, s in ipairs(samples) do
      for _, land in ipairs({ s.westLand, s.eastLand }) do
        total = total + 1
        if land and land < s.position.z - 20 then open = open + 1 end
      end
    end
    observed("the sides of the stream", string.format("at %d of %d points on its two sides the land is more than 20 under the water: there the water has an open side with nothing to hold a swimmer in", open, total))
  end)

  step("four slaughterfish in the middle of the stream", 1, function()
    tes3.positionCell({ reference = tes3.player, position = { deep.position.x - 900, deep.position.y + 600, deep.position.z + 500 } })
    local fish = {}
    for i = 1, 4 do
      local p = deep.position + deep.flow * ((i - 2.5) * 120)
      fish[i] = spawn("slaughterfish", tes3vector3.new(p.x, p.y, deep.position.z - deep.depth * 0.5))
    end
    startWatch("stream, fish", fish, 30, offStream)
  end)
  step("what the fish in the stream did", 31, function() endWatch() removeAll() end)

  step("two rats on the land beside the stream, the player in the water", 1, function()
    tes3.positionCell({ reference = tes3.player, position = { deep.position.x, deep.position.y, deep.ground + 5 } })
    local across = tes3vector3.new(deep.flow.y, -deep.flow.x, 0)
    local rats = {}
    for i, side in ipairs({ -1, 1 }) do
      local p = deep.position + across * (side * 520)
      rats[i] = spawn("rat", tes3vector3.new(p.x, p.y, (groundAt(p.x, p.y) or deep.ground) + 10))
    end
    after(1.5, function()
      for _, rat in ipairs(rats) do
        if rat.mobile then rat.mobile:startCombat(tes3.mobilePlayer) end
      end
      observed("stream, the player", string.format("at height %.0f, swimming %s", tes3.player.position.z, tostring(tes3.mobilePlayer.isSwimming)))
      startWatch("stream, rat set on the swimming player", rats, 20, offStream)
    end)
  end)
  step("what the rats at the stream did", 23, function() endWatch() removeAll() end)

  -- The sea near Vas: the same, in the game's own water.
  local sea, shore
  step("to the sea near Vas", 1, function()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level + 20 } })
  end)
  step("find deep sea and a shore", 6, function()
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      local lastLand
      for r = 600, 4000, 100 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground > 20 then lastLand = { x = x, y = y, z = ground, r = r } end
        if ground and ground < -170 and ground > -260 and lastLand and r - lastLand.r <= 700 and not shore then
          shore = { land = lastLand, water = { x = x, y = y, z = ground } }
        end
        if ground and ground < -300 and (not sea or r < sea.r) then sea = { x = x, y = y, z = ground, r = r } end
      end
    end
    if not sea then error("no deep sea near the site") end
    tes3.positionCell({ reference = tes3.player, position = { sea.x + 500, sea.y + 500, 300 } })
    observed("the sea", string.format("deep sea at %.0f %.0f, bed at %.0f; shore %s", sea.x, sea.y, sea.z,
      shore and string.format("land at %.0f %.0f %.0f, water %.0f away with its bed at %.0f", shore.land.x, shore.land.y, shore.land.z,
        math.sqrt((shore.land.x - shore.water.x) ^ 2 + (shore.land.y - shore.water.y) ^ 2), shore.water.z) or "not found"))
  end)
  step("four slaughterfish in the sea", 2, function()
    local fish = {}
    for i = 1, 4 do fish[i] = spawn("slaughterfish", tes3vector3.new(sea.x + (i - 2.5) * 120, sea.y, -120)) end
    startWatch("sea, fish", fish, 30)
  end)
  step("what the fish in the sea did", 31, function() endWatch() removeAll() end)
  step("two rats on the shore, the player in the sea", 1, function()
    if not shore then return end
    tes3.positionCell({ reference = tes3.player, position = { shore.water.x, shore.water.y, shore.water.z + 5 } })
    local rats = {}
    for i = 1, 2 do rats[i] = spawn("rat", tes3vector3.new(shore.land.x + (i - 1.5) * 100, shore.land.y, shore.land.z + 10)) end
    after(1.5, function()
      for _, rat in ipairs(rats) do
        if rat.mobile then rat.mobile:startCombat(tes3.mobilePlayer) end
      end
      observed("sea, the player", string.format("at height %.0f, swimming %s", tes3.player.position.z, tostring(tes3.mobilePlayer.isSwimming)))
      startWatch("sea, rat set on the swimming player", rats, 20)
    end)
  end)
  step("what the rats at the sea did", 23, function() if watch then endWatch() end removeAll() end)

  -- A pond that the land holds in: the basin near Vas, filled to its rim.
  local pond
  step("a pond in the basin near Vas", 1, function()
    tes3.positionCell({ reference = tes3.player, position = { SITE.x + 700, SITE.y, SITE.level + 300 } })
    pond = spawn("wv_disc_1024", tes3vector3.new(SITE.x, SITE.y, SITE.level))
  end)
  step("four slaughterfish in the pond", 4, function()
    local open, total = 0, 0
    for angle = 0, 350, 10 do
      local x, y = SITE.x + math.cos(math.rad(angle)) * 505, SITE.y + math.sin(math.rad(angle)) * 505
      local ground = groundAt(x, y)
      total = total + 1
      if ground and ground < SITE.level - 20 then open = open + 1 end
    end
    local bed = groundAt(SITE.x, SITE.y) or (SITE.level - 160)
    observed("the pond", string.format("water at %.0f, bed at %.0f; at %d of %d points of its rim the land is more than 20 under the water", SITE.level, bed, open, total))
    local fish = {}
    for i = 1, 4 do fish[i] = spawn("slaughterfish", tes3vector3.new(SITE.x + (i - 2.5) * 80, SITE.y, (bed + SITE.level) / 2)) end
    startWatch("pond, fish", fish, 30, function(p)
      return string.format("%.0f from the middle of the pond (its rim is at 512)", math.sqrt((p.x - SITE.x) ^ 2 + (p.y - SITE.y) ^ 2))
    end)
  end)
  step("what the fish in the pond did", 31, function() endWatch() removeAll() end)

  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Fish cost: what the rule that keeps swim-only creatures in a volume costs per frame
-------------------------------------------------------------------------------

local function runFishCost(spec, say, after, done)
  local rows = {}
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end
  local function measured(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("MEASURED %s: %s", name, detail)
  end

  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local COUNT = 60
  local sea
  local fish = {}
  local pond
  local results = {}

  local function measure(name, extra)
    step("measure: " .. name, 2, function()
      probe = { sim = 0, simMax = 0, simFrames = 0, frame = 0, frameMax = 0, frames = 0 }
    end)
    step("report: " .. name, 10, function()
      local p = probe
      probe = nil
      local mean = p.simFrames > 0 and p.sim / p.simFrames * 1000 or -1
      results[#results + 1] = { name = name, mean = mean }
      measured(name, string.format("simulation %.3f ms mean, %.3f ms max over %d frames; frame %.2f ms mean%s",
        mean, p.simMax * 1000, p.simFrames, p.frames > 0 and p.frame / p.frames * 1000 or -1, extra and ("; " .. extra()) or ""))
    end)
  end
  local function addFarBoxes(count)
    say("far pieces: %d placed, %d more volumes hold water", count, addFarPieces(count))
  end
  local clearBoxes = removeFarPieces
  local function spawnFish(z0, z1)
    for _, reference in ipairs(fish) do reference:delete() end
    fish = {}
    math.randomseed(777)
    for i = 1, COUNT do
      local p = tes3vector3.new(sea.x + (math.random() * 2 - 1) * 800, sea.y + (math.random() * 2 - 1) * 800, z0 + math.random() * (z1 - z0))
      fish[i] = tes3.createReference({ object = "slaughterfish", position = p, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = p }) })
    end
  end
  local function inVolume()
    local n = 0
    for _, reference in ipairs(fish) do
      local p = reference.position
      local surface = controller:getVolumeSurfaceAt(p)
      if surface and p.z <= surface then n = n + 1 end
    end
    return n
  end

  step("god mode on, to the sea near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level + 20 } })
  end)
  step("deep sea, and sixty slaughterfish in it", 6, function()
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for r = 1800, 4000, 100 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -500 and (not sea or r < sea.r) then sea = { x = x, y = y, z = ground, r = r } end
      end
    end
    if not sea then error("no deep sea near the site") end
    -- The player stands on land well away, so that the fish have nothing to hunt.
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
    spawnFish(-400, -80)
    observed("the fish", string.format("%d slaughterfish in the sea around %.0f %.0f, bed at %.0f; %d volumes registered", #fish, sea.x, sea.y, sea.z, require("waterVolumes.interop").native.count()))
  end)

  -- The same fish in the same sea, with and without volumes somewhere else. Twice each, in turn.
  for round = 1, 2 do
    measure("fish in the sea, no volume registered, round " .. round)
    step("one volume far away", 1, function() addFarBoxes(1) end)
    measure("fish in the sea, 1 volume registered elsewhere, round " .. round)
    step("a thousand volumes far away", 1, function() addFarBoxes(999) end)
    measure("fish in the sea, 1000 volumes registered elsewhere, round " .. round)
    step("no volumes", 1, clearBoxes)
  end

  -- The fish inside one volume: a pond 2048 wide and 512 deep, hung in the air over the sea,
  -- so that every side and the bottom are open.
  step("a pond in the air, and sixty slaughterfish in it", 1, function()
    local p = tes3vector3.new(sea.x, sea.y, 1500)
    pond = tes3.createReference({ object = "wv_square_2048", position = p, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = p }) })
  end)
  step("the fish into the pond", 3, function() spawnFish(1500 - 420, 1500 - 80) end)
  for round = 1, 2 do
    measure("fish in a volume with open sides, round " .. round, function() return string.format("%d of %d fish in the volume at the end", inVolume(), #fish) end)
  end

  step("sum up", 1, function()
    local sums = {}
    for _, r in ipairs(results) do
      local key = r.name:gsub(", round %d", "")
      sums[key] = sums[key] or { total = 0, n = 0 }
      sums[key].total, sums[key].n = sums[key].total + r.mean, sums[key].n + 1
    end
    local base = sums["fish in the sea, no volume registered"]
    local baseMean = base.total / base.n
    for key, s in pairs(sums) do
      local mean = s.total / s.n
      observed("mean of " .. s.n .. " rounds, " .. key, string.format("simulation %.3f ms; %+.3f ms against no volume, which is %+.2f microseconds per fish per frame",
        mean, mean - baseMean, (mean - baseMean) * 1000 / COUNT))
    end
    for _, reference in ipairs(fish) do reference:delete() end
    if pond then pond:delete() end
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- City cost: what the plugin costs per frame where many actors are about
-------------------------------------------------------------------------------

local function runCityCost(spec, say, after, done)
  local rows = {}
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end
  local function measured(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("MEASURED %s: %s", name, detail)
  end

  local interop = require("waterVolumes.interop")
  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local CELL = 8192
  local PLACES = {
    { name = "Narsis", gridX = 6, gridY = -51 },
    { name = "Old Ebonheart docks", gridX = 7, gridY = -18 },
  }
  local results = {}

  local function addFarBoxes(count)
    say("far pieces: %d placed, %d more volumes hold water", count, addFarPieces(count))
  end
  local clearBoxes = removeFarPieces
  local function measure(place, condition, extra)
    step("measure: " .. place.name .. ", " .. condition, 2, function()
      probe = { sim = 0, simMax = 0, simFrames = 0, frame = 0, frameMax = 0, frames = 0 }
    end)
    step("report: " .. place.name .. ", " .. condition, 10, function()
      local p = probe
      probe = nil
      local sim = p.simFrames > 0 and p.sim / p.simFrames * 1000 or -1
      local frame = p.frames > 0 and p.frame / p.frames * 1000 or -1
      results[#results + 1] = { place = place, condition = condition, sim = sim, frame = frame }
      measured(place.name .. ", " .. condition, string.format("simulation %.3f ms mean, %.3f ms max over %d frames; frame %.2f ms mean (%.0f per second)%s",
        sim, p.simMax * 1000, p.simFrames, frame, frame > 0 and 1000 / frame or 0, extra and ("; " .. extra()) or ""))
    end)
  end

  step("god mode on, clear noon", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.force1stPerson()
  end)

  for _, place in ipairs(PLACES) do
    step("travel to " .. place.name, 2, function()
      tes3.positionCell({ reference = tes3.player, position = { (place.gridX + 0.5) * CELL, (place.gridY + 0.5) * CELL, 9000 } })
    end)
    step("stand in " .. place.name .. " and count the actors", 1.5, function()
      local cx, cy = (place.gridX + 0.5) * CELL, (place.gridY + 0.5) * CELL
      local spot
      for r = 0, 3400, 200 do
        for angle = 0, 330, 30 do
          local x, y = cx + math.cos(math.rad(angle)) * r, cy + math.sin(math.rad(angle)) * r
          local hit = tes3.rayTest({ position = tes3vector3.new(x, y, 20000), direction = tes3vector3.new(0, 0, -1), ignore = { tes3.player } })
          if hit and hit.intersection.z > 20 and not hit.reference and not spot then spot = tes3vector3.new(x, y, hit.intersection.z) end
        end
      end
      spot = spot or tes3vector3.new(cx, cy, 300)
      place.spot = spot
      tes3.positionCell({ reference = tes3.player, position = { spot.x, spot.y, spot.z + 10 } })
      tes3.changeWeather({ id = 0, immediate = true })
    end)
    step("the actors of " .. place.name, 3, function()
      local actors, near, swimOnly = 0, 0, 0
      for _, cell in ipairs(tes3.getActiveCells()) do
        for reference in cell:iterateReferences({ tes3.objectType.npc, tes3.objectType.creature }) do
          if reference.mobile and not reference.disabled then
            actors = actors + 1
            if reference.position:distance(place.spot) < 2000 then near = near + 1 end
            local object = reference.baseObject
            if object.objectType == tes3.objectType.creature and object.swims and not object.walks and not object.flies then swimOnly = swimOnly + 1 end
          end
        end
      end
      place.actors = actors
      observed(place.name, string.format("player at %.0f %.0f %.0f; %d actors in the loaded cells, %d within 2000 of the player, %d that can only swim; %d volumes registered",
        place.spot.x, place.spot.y, place.spot.z, actors, near, swimOnly, interop.native.count()))
    end)
    for round = 1, 2 do
      measure(place, "no volume")
      step("one volume far away", 1, function() addFarBoxes(1, place.spot) end)
      measure(place, "1 volume elsewhere")
      step("a thousand volumes far away", 1, function() addFarBoxes(999, place.spot) end)
      measure(place, "1000 volumes elsewhere")
      step("no far volumes; a pond 2048 across over the place where the player stands, 40 deep", 1, function()
        clearBoxes()
        local p = tes3vector3.new(place.spot.x, place.spot.y, place.spot.z + 40)
        place.pond = tes3.createReference({ object = "wv_disc_2048", position = p, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = p }) })
      end)
      measure(place, "a pond around the player", function()
        local inside = 0
        for _, cell in ipairs(tes3.getActiveCells()) do
          for reference in cell:iterateReferences({ tes3.objectType.npc, tes3.objectType.creature }) do
            if reference.mobile and controller:getVolumeSurfaceAt(reference.position) then inside = inside + 1 end
          end
        end
        return string.format("%d actors in or over the pond", inside)
      end)
      step("pond away", 1, function()
        place.pond:delete()
        place.pond = nil
      end)
      step("settle", 2, function() end)
    end
  end

  step("sum up", 1, function()
    for _, place in ipairs(PLACES) do
      local sums, order = {}, {}
      for _, r in ipairs(results) do
        if r.place == place then
          if not sums[r.condition] then
            sums[r.condition] = { sim = 0, frame = 0, n = 0, low = math.huge, high = -math.huge }
            order[#order + 1] = r.condition
          end
          local s = sums[r.condition]
          s.sim, s.frame, s.n = s.sim + r.sim, s.frame + r.frame, s.n + 1
          s.low, s.high = math.min(s.low, r.sim), math.max(s.high, r.sim)
        end
      end
      local base = sums["no volume"]
      for _, condition in ipairs(order) do
        local s = sums[condition]
        local sim, frame = s.sim / s.n, s.frame / s.n
        observed(place.name .. ", mean of " .. s.n .. " rounds, " .. condition, string.format(
          "simulation %.3f ms (rounds %.3f and %.3f), frame %.2f ms; against no volume: simulation %+.3f ms, frame %+.2f ms; %+.2f microseconds per actor per frame for %d actors",
          sim, s.low, s.high, frame, sim - base.sim / base.n, frame - base.frame / base.n, (sim - base.sim / base.n) * 1000 / math.max(place.actors or 1, 1), place.actors or 0))
      end
    end
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Fish in the air: what slaughterfish do in a pond that hangs over the sea, sample by sample
-------------------------------------------------------------------------------

local function runFishAir(spec, say, after, done)
  local rows = {}
  local function observed(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("OBSERVED %s: %s", name, detail)
  end
  local controller = waterController()
  local steps = {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end
  local LEVEL, HALF, DEPTH = 1500, 1024, 512
  local sea, pond
  local fish = {}
  local pin
  local function onFrame()
    if pin and tes3.player.position:distance(pin) > 40 then
      tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
    end
  end

  local function trace(label, seconds_)
    local log = {}
    for i = 1, #fish do log[i] = {} end
    local left = math.floor(seconds_ / 0.25)
    local function tick()
      for i, reference in ipairs(fish) do
        local p = reference.position
        local mobile = reference.mobile
        local surface = controller:getVolumeSurfaceAt(p)
        table.insert(log[i], {
          x = p.x - sea.x, y = p.y - sea.y, z = p.z, inside = surface ~= nil and p.z <= surface,
          swimming = mobile and mobile.isSwimming == true, falling = mobile and mobile.isFalling == true,
        })
      end
      left = left - 1
      if left > 0 then
        timer.start({ type = timer.real, duration = 0.25, callback = tick })
      else
        local stayed = 0
        for i, entries in ipairs(log) do
          local last = entries[#entries]
          if last.inside then stayed = stayed + 1 end
          local firstOut
          for k, e in ipairs(entries) do
            if not e.inside and not firstOut then firstOut = k end
          end
          local line = {}
          for k = 1, #entries, 2 do
            local e = entries[k]
            line[#line + 1] = string.format("%.0f%s%s", e.z, e.inside and "i" or "o", e.falling and "f" or (e.swimming and "s" or "-"))
          end
          local where = "never out"
          if firstOut then
            local e = entries[firstOut]
            where = string.format("first out after %.2f s at %.0f %.0f from the middle, height %.0f (pond: half width %d, water %d down to %d)",
              (firstOut - 1) * 0.25, e.x, e.y, e.z, HALF, LEVEL, LEVEL - DEPTH)
          end
          if i <= 3 or firstOut then
            say("%s, fish %d: %s; heights every half second (i in, o out; s swimming, f falling): %s", label, i, where, table.concat(line, " "))
          end
        end
        observed(label, string.format("%d of %d fish in the pond after %d seconds", stayed, #fish, seconds_))
      end
    end
    tick()
  end
  local function spawnFish()
    for _, reference in ipairs(fish) do reference:delete() end
    fish = {}
    math.randomseed(99)
    for i = 1, 8 do
      local p = tes3vector3.new(sea.x + (math.random() * 2 - 1) * 700, sea.y + (math.random() * 2 - 1) * 700, LEVEL - 120 - math.random() * 250)
      fish[i] = tes3.createReference({ object = "slaughterfish", position = p, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = p }) })
    end
  end

  step("god mode on, to the sea near Vas", 1, function()
    if not controller.volumesSupported then error("water volumes are not available") end
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.positionCell({ reference = tes3.player, position = { SITE.x, SITE.y, SITE.level + 20 } })
  end)
  step("a pond in the air over deep sea", 6, function()
    for angle = 0, 345, 15 do
      local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      for r = 1800, 4000, 100 do
        local x, y = SITE.x + c * r, SITE.y + s * r
        local ground = groundAt(x, y)
        if ground and ground < -500 and (not sea or r < sea.r) then sea = { x = x, y = y, z = ground, r = r } end
      end
    end
    if not sea then error("no deep sea near the site") end
    local p = tes3vector3.new(sea.x, sea.y, LEVEL)
    pond = tes3.createReference({ object = "wv_square_2048", position = p, orientation = { 0, 0, 0 }, cell = tes3.getCell({ position = p }) })
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  step("eight fish into the pond, the player far away on land", 3, function()
    spawnFish()
    observed("far", string.format("player %.0f from the pond", tes3.player.position:distance(tes3vector3.new(sea.x, sea.y, LEVEL))))
    trace("player far", 12)
  end)
  step("eight fish into the pond, the player held beside it", 14, function()
    event.register("enterFrame", onFrame)
    pin = tes3vector3.new(sea.x + HALF + 300, sea.y, LEVEL + 100)
    tes3.positionCell({ reference = tes3.player, position = { pin.x, pin.y, pin.z } })
    spawnFish()
    trace("player near", 12)
  end)
  step("clean up", 14, function()
    pin = nil
    event.unregister("enterFrame", onFrame)
    for _, reference in ipairs(fish) do reference:delete() end
    pond:delete()
    tes3.positionCell({ reference = tes3.player, position = { 6612, 184767, 1200 } })
  end)
  sequence(steps, say, after, function() done(rows) end)
end

-------------------------------------------------------------------------------
-- Reference cost: what 5000 more references in the active cells cost the simulation, whether
-- the cost stays, and whose it is. One kind of reference per run:
--   refcost        none are placed: how the numbers drift by themselves
--   refcostplain   a copy of a kit mesh under other names: not water, the mod leaves it alone
--   refcostnoswim  kit pieces registered as water nobody swims in: prepared and followed, no water
--   refcostwater   kit pieces: water
-------------------------------------------------------------------------------

local function runRefCost(spec, say, after, done)
  local rows = {}
  local function measured(name, detail)
    rows[#rows + 1] = { ok = true, name = name, detail = detail }
    say("MEASURED %s: %s", name, detail)
  end
  local interop = require("waterVolumes.interop")
  local x, y, level = SITE.x, SITE.y, 900
  local COUNT = 5000
  -- A name that ends in 0 is the same run without the 60 actors.
  local actorCount = spec.water:find("0$") and 0 or 60
  local kind = ({ refcost = "none", refcostplain = "plain", refcostnoswim = "noswim", refcostwater = "water" })[spec.water:gsub("0$", "")]
  local FILE = "Data Files\\Meshes\\wv\\wv_test_plain.nif"
  local actors, steps = {}, {}
  local function step(name, wait, run) steps[#steps + 1] = { name = name, wait = wait, run = run } end

  local function window(name, duration)
    step("measure: " .. name, 0.2, function()
      probe = { sim = 0, simMax = 0, simFrames = 0, frame = 0, frameMax = 0, frames = 0, samples = {} }
    end)
    step("report: " .. name, duration, function()
      local p = probe
      probe = nil
      table.sort(p.samples)
      local n = #p.samples
      local function at(q) return n > 0 and p.samples[math.max(1, math.ceil(n * q))] * 1000 or -1 end
      measured(name, string.format("simulation mean %.3f ms, median %.3f, 90th of 100 %.3f, max %.3f over %d frames; frame mean %.2f ms",
        p.simFrames > 0 and p.sim / p.simFrames * 1000 or -1, at(0.5), at(0.9), p.simMax * 1000, p.simFrames,
        p.frames > 0 and p.frame / p.frames * 1000 or -1))
    end)
  end

  step("god mode on, player to the basin near Vas", 1, function()
    math.randomseed(12345)
    tes3.mobilePlayer.vanityDisabled = true
    tes3.setVanityMode({ enabled = false, checkVanityDisabled = false })
    tes3.worldController.menuController.godModeEnabled = true
    tes3.worldController.hour.value = 13
    tes3.changeWeather({ id = 0, immediate = true })
    tes3.positionCell({ reference = tes3.player, position = { x, y, level + 150 } })
  end)
  step("60 actors on the land", 10, function()
    local ids = { "rat", "rat", "mudcrab", "fargoth" }
    for i = 1, actorCount do
      local ok, reference = pcall(tes3.createReference, {
        object = ids[i % #ids + 1], cell = tes3.player.cell, orientation = { 0, 0, 0 },
        position = { x + math.random(-700, 700), y + math.random(-700, 700), level - 150 },
      })
      if ok and reference then actors[#actors + 1] = reference end
    end
    tes3.force3rdPerson()
    tes3.positionCell({ reference = tes3.player, position = { x, y, level - 150 } })
    say("reference cost: %d actors placed, kind of reference: %s; %d volumes hold water", #actors, kind, interop.native.count())
  end)

  window("before, 1", 6)
  window("before, 2", 6)

  step("place the references", 1, function()
    if kind == "none" then
      say("placed: nothing")
      return
    end
    local id = "wv_square_512"
    if kind == "plain" then
      -- The same triangles, materials and text entries, under names that mean nothing.
      local mesh = tes3.loadMesh("wv\\wv_square_512.nif"):clone()
      for _, child in ipairs(mesh.children) do
        if child then child.name = child.name == "WaterBody" and "Body" or "Surface" end
      end
      mesh:saveBinary(FILE)
      id = "wv_refcost_plain"
      if not tes3.getObject(id) then tes3.createObject({ objectType = tes3.objectType.static, id = id, mesh = "wv\\wv_test_plain.nif" }) end
    elseif kind == "noswim" then
      id = "wv_refcost_noswim"
      interop.registerObject(id, { noSwim = true })
      if not tes3.getObject(id) then tes3.createObject({ objectType = tes3.objectType.static, id = id, mesh = "wv\\wv_square_512.nif" }) end
    end
    local started = seconds()
    local more = addFarPieces(COUNT, id)
    local placing = seconds() - started
    started = seconds()
    for _ = 1, 200 do interop.native.update() end
    say("placed: %d references of %s in %.0f ms; %d more volumes hold water; plugin update %.1f microseconds per call",
      COUNT, id, placing * 1000, more, (seconds() - started) / 200 * 1e6)
  end)

  for i = 1, 5 do window("after, " .. i, 6) end

  step("the engine's own question", 1, function()
    local rest = { checkForEnemies = false, showMessage = false }
    local started = seconds()
    for _ = 1, 100000 do tes3.canRest(rest) end
    measured("engine query", string.format("%.0f ns", (seconds() - started) / 100000 * 1e9))
  end)

  step("delete the references", 1, function()
    removeFarPieces()
  end)
  window("after the references are deleted, 1", 6)
  window("after the references are deleted, 2", 6)

  step("clean up", 1, function()
    for _, reference in ipairs(actors) do reference:delete() end
    say("mesh file removed: %s", tostring(os.remove(FILE)))
  end)
  sequence(steps, say, after, function() done(rows) end)
end

function this.run(spec, say, after, done)
  if spec.water:find("^refcost") then
    runRefCost(spec, say, after, done)
    return
  end
  if spec.water == "fishair" then
    runFishAir(spec, say, after, done)
    return
  end
  if spec.water == "citycost" then
    runCityCost(spec, say, after, done)
    return
  end
  if spec.water == "fishcost" then
    runFishCost(spec, say, after, done)
    return
  end
  if spec.water == "streamai" then
    runStreamAI(spec, say, after, done)
    return
  end
  if spec.water == "riverdemo" or spec.water == "riverdemohold" then
    runRiverDemo(spec, say, after, done)
    return
  end
  if spec.water == "swimdepth" then
    runSwimDepth(spec, say, after, done)
    return
  end
  if spec.water == "blender" then
    runBlender(spec, say, after, done)
    return
  end
  if spec.water == "joints" then
    runJoints(spec, say, after, done)
    return
  end
  if spec.water == "tilt" then
    runTilt(spec, say, after, done)
    return
  end
  if spec.water == "saveload" then
    runSaveLoad(spec, say, after, done)
    return
  end
  if spec.water == "plugin" then
    runPlugin(spec, say, after, done)
  elseif spec.water == "look" then
    runLook(spec, say, after, done)
  elseif spec.water == "stress" then
    runStress(spec, say, after, done)
  elseif spec.water == "grid" then
    runGrid(spec, say, after, done)
  elseif spec.water == "interior" then
    runInterior(spec, say, after, done)
  elseif spec.water == "marker" then
    runMarker(spec, say, after, done)
  elseif spec.water == "ranged" then
    runRanged(spec, say, after, done)
  elseif spec.water == "combat" then
    runCombat(spec, say, after, done)
  elseif spec.water == "creatures" then
    runCreatures(spec, say, after, done)
  elseif spec.water == "river" or spec.water == "riverhold" then
    runRiver(spec, say, after, done)
  else
    runTest(spec, say, after, done)
  end
end

return this
