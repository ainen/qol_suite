-- Focused regressions for bounded hot-path work and AUTO CATCH status rules.
-- Run from the gen1recomp checkout.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")

local function feature(name)
  return assert(loadfile("../qol_suite/features/" .. name .. ".lua"))()
end

-- Equivalent per-frame overlay descriptors reuse geometry, while changed or
-- externally corrupted values are invalidated before another caller sees it.
do
  local mod = {}
  feature("overlay_layout")(mod)
  local layout = mod.exports
  local viewport = { width = 640, height = 480 }
  local function panels(width)
    return {
      { id = "map", corner = "top-right", width = width or 200,
        height = 140, order = 1 },
      { id = "tracker", corner = "top-right", width = width or 200,
        height = 80, order = 2 },
    }
  end
  local first = layout.positions(viewport, panels())
  local second = layout.positions({ width = 640, height = 480 }, panels())
  T.check(first == second,
    "overlay layout reuses equivalent settled geometry")
  local resized = layout.positions({ width = 800, height = 480 }, panels())
  T.check(resized ~= first and resized.map.x ~= first.map.x,
    "overlay layout invalidates on viewport changes")
  first.map.x = -500
  local repaired = layout.positions(viewport, panels())
  T.check(repaired ~= first and repaired.map.x >= 0,
    "overlay layout rejects externally mutated cached geometry")
  local changed = layout.positions(viewport, panels(216))
  T.eq(changed.map.width, 216,
    "overlay layout invalidates on panel-size changes")

  layout.rememberTracker({ x = 420, y = 160, width = 200, height = 48 },
    viewport, "top-right")
  local tracker = layout.trackerRect(viewport, "top-right")
  local trackerAgain = layout.trackerRect(viewport, "top-right")
  T.check(tracker == trackerAgain,
    "tracker geometry is reused while its frame is unchanged")
  tracker.x = -100
  local repairedTracker = layout.trackerRect(viewport, "top-right")
  T.check(repairedTracker ~= tracker and repairedTracker.x == 420,
    "tracker geometry repairs an externally mutated result")
end

-- Official DRAMATIC_SHAPE uses the original mapping and private registries
-- probe mod.find only once after a frame proves the producer is active.
do
  local findCalls = 0
  local mod = {
    find = function(id)
      findCalls = findCalls + 1
      return id == "DRAMATIC_SHAPE" and { id = id } or nil
    end,
  }
  feature("voxel_hud")(mod)
  local battle = { dramaticShapeShot = { scale = 5, pw = 1280, ly = 0 } }
  T.eq(mod.exports.branch(battle), "dramaless",
    "voxel compatibility recognizes official DRAMATIC_SHAPE")
  T.eq(mod.exports.branch(battle), "dramaless",
    "voxel compatibility keeps the settled producer")
  T.eq(findCalls, 1, "voxel compatibility probes mod.find only once")

  local registryFindCalls = 0
  local registryMod = { find = function()
    registryFindCalls = registryFindCalls + 1
    return nil
  end }
  feature("voxel_hud")(registryMod)
  battle.game = { mods = { exports = { DRAMATIC_SHAPE = {} } } }
  T.eq(registryMod.exports.branch(battle), "dramaless",
    "voxel compatibility reads the official producer registry")
  T.eq(registryFindCalls, 0,
    "voxel compatibility avoids mod.find when a registry is available")
end

-- The optional Gen 3 bridge remains discoverable until runtime, retires its
-- native-only hooks, restores exact draw state, and isolates bad callbacks.
do
  local found = false
  local findCalls, warnings = 0, 0
  local hooks = Hooks.new()
  local mod = {
    hooks = hooks,
    find = function()
      findCalls = findCalls + 1
      return found and { id = "gen3_battle_ui" } or nil
    end,
    log = { warn = function() warnings = warnings + 1 end },
  }
  feature("gen3_ui_compat")(mod)
  local compat = mod.exports
  T.check(not compat.battleUIActive({ stack = { states = {} } }),
    "Gen 3 bridge does not settle during pre-runtime discovery")
  found = true

  local game = { save = {}, stack = { states = {} } }
  local battle = { game = game }
  game.stack.states[1] = battle
  local goodRan, goodColor = false
  compat.registerBattleOverlay("bad", function()
    love.graphics.setColor(0.9, 0.1, 0.2, 0.3)
    error("intentional callback failure")
  end)
  compat.registerBattleOverlay("good", function()
    goodRan = true
    goodColor = { love.graphics.getColor() }
  end)
  hooks:call("battle.overlay", function() end, battle)
  love.graphics.setColor(0.17, 0.28, 0.39, 0.46)
  hooks:call("render.hud", function() end, game, { width = 640, height = 480 })
  local r, g, b, a = love.graphics.getColor()
  T.check(compat.installed and goodRan,
    "Gen 3 bridge discovers a later-loaded mod before runtime settles")
  T.same(goodColor, { 0.17, 0.28, 0.39, 0.46 },
    "Gen 3 bridge isolates graphics state between callbacks")
  T.same({ r, g, b, a }, { 0.17, 0.28, 0.39, 0.46 },
    "Gen 3 bridge restores graphics state after callbacks")
  T.eq(warnings, 1, "Gen 3 bridge reports a callback error once")

  local oldFont = { marker = "incoming" }
  love.graphics.setFont(oldFont)
  love.graphics.setColor(0.11, 0.22, 0.33, 0.44)
  T.check(compat.drawText("TEST", 0, 0, 12, { 1, 0, 0, 1 }),
    "Gen 3 helper draws text through its protected path")
  r, g, b, a = love.graphics.getColor()
  T.same({ r, g, b, a }, { 0.11, 0.22, 0.33, 0.44 },
    "Gen 3 text restores the exact incoming color")
  T.check(love.graphics.getFont() == oldFont,
    "Gen 3 text restores the incoming font")
  T.check(findCalls >= 2,
    "Gen 3 bridge retries a pre-runtime miss when runtime begins")

  local absentHooks = Hooks.new()
  local absentFindCalls = 0
  local absentMod = {
    hooks = absentHooks,
    find = function() absentFindCalls = absentFindCalls + 1 return nil end,
    log = { warn = function() end },
  }
  feature("gen3_ui_compat")(absentMod)
  absentHooks:call("render.hud", function() end,
    { stack = { states = {} } }, { width = 640, height = 480 })
  T.eq(#(absentHooks.chains["render.hud"] or {}), 0,
    "absent Gen 3 bridge retires its HUD hook after runtime discovery")
  T.eq(#(absentHooks.chains["battle.overlay"] or {}), 0,
    "absent Gen 3 bridge retires its battle hook after runtime discovery")
  T.eq(absentFindCalls, 1,
    "absent Gen 3 bridge performs one settled runtime lookup")
end

-- Disabled and externally owned XP rows skip transform snapshots entirely.
do
  local enabled, external = false, false
  local hooks, events = Hooks.new(), Events.new()
  local mod = {
    id = "xp_perf", hooks = hooks, events = events,
    options = { get = function() return enabled end },
  }
  feature("experience_bar")(mod, nil, {
    battleUIActive = function() return external end,
  })
  local captures = 0
  local previousGetTransform = love.graphics.getTransform
  love.graphics.getTransform = function()
    captures = captures + 1
    return { marker = captures }
  end
  local battle = { frame = 1, isWideBattleLayout = function() return false end }
  hooks:call("battle.player_hud", function() end, battle, { x = 72, y = 56 })
  T.eq(captures, 0, "disabled XP bar skips transform capture")
  enabled = true
  events:emit("mod.options_changed",
    { mod = mod.id, key = "experienceBar", value = true })
  external = true
  hooks:call("battle.player_hud", function() end, battle, { x = 72, y = 56 })
  T.eq(captures, 0, "external battle UI skips XP transform capture")
  external = false
  hooks:call("battle.player_hud", function() end, battle, { x = 72, y = 56 })
  T.eq(captures, 1, "native enabled XP bar captures its transform")
  love.graphics.getTransform = previousGetTransform
end

-- AUTO BATTLE installs continuous hooks only while enabled, supplied Gen 3
-- battles bypass stack discovery, and impossible status moves are skipped.
do
  local values = {
    autoBattle = false, autoCatch = true, showBallCounts = true,
  }
  local hooks, events = Hooks.new(), Events.new()
  local overlays = {}
  local mod = {
    id = "auto_perf", hooks = hooks, events = events,
    options = { get = function(_, key) return values[key] end },
    log = { info = function() end },
  }
  feature("auto_battle")(mod, nil, {
    battleUIActive = function() return true end,
    registerBattleOverlay = function(name, callback)
      overlays[name] = callback
      return true
    end,
  })
  local auto = mod.exports
  local function chainSize(name)
    return #(hooks.chains[name] or {})
  end
  T.eq(chainSize("core.update"), 0,
    "disabled AUTO BATTLE leaves core.update unsubscribed")
  T.eq(chainSize("render.hud"), 0,
    "disabled AUTO BATTLE leaves render.hud unsubscribed")
  values.autoCatch = false
  values.autoBattle = true
  events:emit("mod.options_changed",
    { mod = mod.id, key = "autoBattle", value = true })
  T.eq(chainSize("core.update"), 1,
    "AUTO BATTLE alone installs its update hook")
  T.eq(chainSize("render.hud"), 0,
    "AUTO BATTLE without ball counts leaves HUD unsubscribed")
  values.autoBattle = false
  events:emit("mod.options_changed",
    { mod = mod.id, key = "autoBattle", value = false })
  values.autoCatch = true
  for iteration = 1, 25 do
    values.autoBattle = true
    events:emit("mod.options_changed",
      { mod = mod.id, key = "autoBattle", value = true })
    events:emit("mod.options_changed",
      { mod = mod.id, key = "autoBattle", value = true })
    T.eq(chainSize("core.update"), 1,
      "AUTO BATTLE installs one update hook " .. iteration)
    T.eq(chainSize("render.hud"), 1,
      "AUTO BATTLE installs one HUD hook " .. iteration)
    values.autoBattle = false
    events:emit("mod.options_changed",
      { mod = mod.id, key = "autoBattle", value = false })
    T.eq(chainSize("core.update"), 0,
      "AUTO BATTLE removes its update hook " .. iteration)
    T.eq(chainSize("render.hud"), 0,
      "AUTO BATTLE removes its HUD hook " .. iteration)
  end

  values.autoBattle = true
  events:emit("mod.options_changed",
    { mod = mod.id, key = "autoBattle", value = true })
  local topCalls = 0
  local counterGame = {
    save = { inventory = { POKE_BALL = 10, GREAT_BALL = 2 } },
    stack = { top = function() topCalls = topCalls + 1 return nil end },
  }
  local counterBattle = { game = counterGame }
  local Font = require("src.render.Font")
  local previousDraw = Font.draw
  local text = {}
  Font.draw = function(value) text[#text + 1] = value end
  overlays.ballCounter(counterBattle, counterGame,
    { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 240 })
  overlays.ballCounter(counterBattle, counterGame,
    { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 240 })
  T.eq(topCalls, 0,
    "supplied Gen 3 battle bypasses AUTO CATCH stack discovery")
  T.eq(text[1], "BALLS 12", "AUTO CATCH counter reads the live bag")
  counterGame.save.inventory.POKE_BALL = 9
  text = {}
  overlays.ballCounter(counterBattle, counterGame,
    { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 240 })
  T.eq(text[1], "BALLS 11",
    "AUTO CATCH counter invalidates cached text when inventory changes")
  Font.draw = previousDraw

  local moves = {
    THUNDER_WAVE = { id = "THUNDER_WAVE", power = 0, accuracy = 100,
      type = "ELECTRIC", effect = "PARALYZE_EFFECT" },
    POISON_POWDER = { id = "POISON_POWDER", power = 0, accuracy = 100,
      type = "POISON", effect = "POISON_EFFECT" },
    SAFE = { id = "SAFE", power = 30, accuracy = 100,
      type = "NORMAL", effect = "NO_ADDITIONAL_EFFECT", testDamage = 3 },
  }
  local function catchBattle(statusMove, targetTypes)
    local playerMon = { species = "A", hp = 20, stats = { hp = 20 },
      moves = { { id = statusMove, pp = 20 }, { id = "SAFE", pp = 20 } } }
    local enemyMon = { species = "B", hp = 10, stats = { hp = 20 } }
    local battle = {
      kind = "wild", game = { save = { inventory = { POKE_BALL = 2 } } },
      data = { moves = moves },
      player = { mon = playerMon, curMoves = playerMon.moves,
        curTypes = { "NORMAL" } },
      enemy = { mon = enemyMon, curTypes = targetTypes },
      moveDef = function(self, move) return self.data.moves[move.id] end,
      effectRecord = function(_, effect)
        if effect == "PARALYZE_EFFECT" or effect == "POISON_EFFECT" then
          return { kind = "primary" }
        end
        return { kind = "full" }
      end,
      computeDamage = function(_, _, _, def)
        return def.testDamage or 0, { typeMult = 10 }
      end,
    }
    return battle
  end
  for iteration = 1, 100 do
    local ground = catchBattle("THUNDER_WAVE", { "GROUND" })
    T.eq(auto.chooseCatchAction(ground).move.id, "SAFE",
      "AUTO CATCH skips Electric paralysis against Ground " .. iteration)
    local poison = catchBattle("POISON_POWDER", { "POISON" })
    T.eq(auto.chooseCatchAction(poison).move.id, "SAFE",
      "AUTO CATCH skips poison against Poison " .. iteration)
  end
end

T.finish("performance_hotpaths")
