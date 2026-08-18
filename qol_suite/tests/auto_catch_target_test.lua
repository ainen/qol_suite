-- AUTO CATCH TARGET focused regression test. Run from the gen1recomp checkout.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"
local packageExports = run.loader.exports.qol_suite
local target = packageExports.autoCatchTarget
local hooks = run.loader.hooks
local schemaByKey = {}
for _, row in ipairs(run.loader.optionSchemas[MOD_ID]) do
  schemaByKey[row.key] = row
end

T.check(#run.errors == 0, "AUTO CATCH TARGET package load is clean")
T.check(type(target.toggle) == "function",
  "AUTO CATCH TARGET exposes a toggle helper")
T.check(type(target.matches) == "function",
  "AUTO CATCH TARGET exposes a match helper")
local function visibilityHas(condition, key)
  if type(condition) ~= "table" then return false end
  return condition.key == key and condition.equals == true
end
T.check(visibilityHas(schemaByKey.autoCatchTarget.visible_if, "autoCatch"),
  "AUTO CATCH TARGET setting is gated by its direct parent AUTO CATCH")

local game = { data = { pokemon = {
  FIXMON_A = { name = "FIXMON A" },
  FIXMON_B = { name = "FIXMON B" },
} } }

local function actions(species)
  return hooks:call("ui.pokedex.actions", function(_, entries)
    return entries
  end, game, { { label = "DATA" }, { label = "QUIT" } }, species)
end

run.loader.modOptions[MOD_ID] = { autoCatch = false, autoCatchTarget = true }
for iteration = 1, 100 do
  T.eq(#actions("FIXMON_A"), 2,
    "AUTO CATCH TARGET is hidden when AUTO CATCH is off " .. iteration)
end

run.loader.modOptions[MOD_ID] = { autoCatch = true, autoCatchTarget = false }
T.eq(#actions("FIXMON_A"), 2,
  "AUTO CATCH TARGET menu action is hidden when its toggle is off")

run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoCatchTarget = true,
}
T.check(target.matches(game, "FIXMON_A"),
  "AUTO CATCH remains unrestricted until a target is selected")
for iteration = 1, 100 do
  run.loader.modOptions[MOD_ID].autoCatchTarget = true
  local entries = actions("FIXMON_A")
  T.eq(entries[2].label, "TARGET",
    "Pokedex offers TARGET for an unselected species " .. iteration)
  entries[2].onSelect()
  T.eq(target.current(game), "FIXMON_A",
    "TARGET selects the Pokedex species " .. iteration)
  T.check(target.matches(game, "FIXMON_A"),
    "AUTO CATCH matches the selected species " .. iteration)
  T.check(not target.matches(game, "FIXMON_B"),
    "AUTO CATCH rejects a different species " .. iteration)

  entries = actions("FIXMON_A")
  T.eq(entries[2].label, "CLEAR",
    "Pokedex offers CLEAR for the selected species " .. iteration)
  entries[2].onSelect()
  T.eq(target.current(game), nil,
    "CLEAR removes the selected catch target " .. iteration)
end

run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoCatchTarget = true,
}
target.toggle(game, "FIXMON_A")
run.loader.modOptions[MOD_ID].autoCatch = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "autoCatch", value = false,
})
run.loader.modOptions[MOD_ID].autoCatch = true
T.eq(target.current(game), nil,
  "disabling AUTO CATCH clears the persisted target")

target.toggle(game, "FIXMON_A")
run.loader.modOptions[MOD_ID].autoCatchTarget = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "autoCatchTarget", value = false,
})
run.loader.modOptions[MOD_ID].autoCatchTarget = true
T.eq(target.current(game), nil,
  "disabling AUTO CATCH TARGET clears the persisted target")

target.toggle(game, "FIXMON_A")
run.loader.modOptions[MOD_ID].autoBattle = false
T.check(not target.enabled() and target.current(game) == nil,
  "AUTO CATCH TARGET is inactive while AUTO BATTLE is off")
run.loader.modOptions[MOD_ID].autoBattle = true
T.eq(target.current(game), "FIXMON_A",
  "temporarily disabling AUTO BATTLE does not erase the explicit catch target")
target.toggle(game, "FIXMON_A")

local autoBattle = packageExports.autoBattle
local targetBattle = {
  isBattle = true,
  phase = "menu",
  kind = "wild",
  data = { moves = {}, pokemon = {
    FIXMON_A = { name = "FIXMON A", types = { "GRASS" } },
    FIXMON_B = { name = "FIXMON B", types = { "FIRE" } },
  } },
  game = { save = { party = {}, inventory = { POKE_BALL = 1 } } },
  player = { mon = { hp = 30 }, curMoves = {}, curTypes = { "GRASS" },
    curStats = { hp = 30 }, stages = {}, isPlayer = true },
  enemy = { mon = { species = "FIXMON_B", hp = 1, status = "SLP" },
    curTypes = { "FIRE" }, curStats = { hp = 30 }, stages = {}, isPlayer = false },
  throwBall = function(self, ball) self.lastBall = ball end,
}

for iteration = 1, 100 do
  target.toggle(game, "FIXMON_A")
  local action = autoBattle.chooseAction(targetBattle)
  T.check(action.kind ~= "ball",
    "AUTO CATCH does not catch a non-target species " .. iteration)
  target.toggle(game, "FIXMON_A")
  target.toggle(game, "FIXMON_B")
  action = autoBattle.chooseAction(targetBattle)
  T.eq(action.kind, "ball",
    "AUTO CATCH catches the selected target species " .. iteration)
  target.toggle(game, "FIXMON_B")
end

target.toggle(game, "FIXMON_B")
for iteration = 1, 100 do
  targetBattle.phase = "menu"
  targetBattle.lastBall = nil
  targetBattle.game.save.inventory = { POKE_BALL = 1 }
  T.check(autoBattle.act(targetBattle),
    "AUTO CATCH throws an available ball " .. iteration)
  T.eq(targetBattle.lastBall, "POKE_BALL",
    "AUTO CATCH uses the inventory ball " .. iteration)
  T.eq(targetBattle.game.save.inventory.POKE_BALL, nil,
    "AUTO CATCH depletes the thrown ball " .. iteration)
end
target.toggle(game, "FIXMON_B")

run.loader.modOptions[MOD_ID] = nil
T.finish("auto_catch_target")
