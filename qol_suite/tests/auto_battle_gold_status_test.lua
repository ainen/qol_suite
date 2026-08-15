-- Gold AUTO CATCH must reject status moves that native Gen 2 rules cannot
-- apply, without treating unrelated type matchups as blanket immunities.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")

if not (GameVersion.VERSIONS and GameVersion.VERSIONS.gold) then
  print("SKIP auto_battle_gold_status: requires a Gold-enabled engine checkout")
  return
end

GameVersion.set("gold")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local values = { autoBattle = true, autoCatch = true }
local mod = {
  id = "auto_gold_status",
  events = Events.new(),
  hooks = Hooks.new(),
  options = { get = function(_, key) return values[key] end },
  log = { info = function() end },
}
local factory = assert(loadfile("../qol_suite/features/auto_battle.lua"))()
factory(mod)

local defs = {
  THUNDER_WAVE = { id = "THUNDER_WAVE", power = 0, accuracy = 100,
    type = "ELECTRIC", effect = "EFFECT_PARALYZE" },
  POISON_POWDER = { id = "POISON_POWDER", power = 0, accuracy = 100,
    type = "POISON", effect = "EFFECT_POISON" },
  SLEEP_POWDER = { id = "SLEEP_POWDER", power = 0, accuracy = 100,
    type = "GRASS", effect = "EFFECT_SLEEP" },
}

local function stateFor(moveId, targetTypes)
  local move = { id = moveId, pp = 20 }
  local player = { species = "PLAYER", hp = 20, types = { "NORMAL" } }
  local enemy = { species = "TARGET", hp = 10, types = targetTypes }
  local battle = {
    wild = true, player = player, enemy = enemy,
    data = { type_chart = {} },
    usableMoves = function() return { move } end,
    moveDef = function(_, id) return defs[id] end,
    speciesDef = function(_, mon) return { types = mon.types } end,
  }
  return {
    battle = battle,
    game = { save = { inventory = { POKE_BALL = 3 } } },
  }
end

for iteration = 1, 100 do
  local ground = mod.exports.goldAction(stateFor(
    "THUNDER_WAVE", { "GROUND" }))
  T.eq(ground.kind, "item",
    "Gold AUTO CATCH skips Electric paralysis against Ground " .. iteration)

  local poison = mod.exports.goldAction(stateFor(
    "POISON_POWDER", { "POISON" }))
  T.eq(poison.kind, "item",
    "Gold AUTO CATCH skips poison against Poison " .. iteration)

  local steel = mod.exports.goldAction(stateFor(
    "POISON_POWDER", { "STEEL" }))
  T.eq(steel.kind, "item",
    "Gold AUTO CATCH skips poison against Steel " .. iteration)
end

local sleep = mod.exports.goldAction(stateFor("SLEEP_POWDER", { "GROUND" }))
T.eq(sleep.kind, "move",
  "Gold AUTO CATCH keeps non-immune sleep eligible against Ground")
T.eq(sleep.move, "SLEEP_POWDER",
  "Gold AUTO CATCH selects the eligible sleep move")

GameVersion.set("red")
T.finish("auto_battle_gold_status")
