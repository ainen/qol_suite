-- Gold schema and generation-gating regression test.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local Data = T.fixtures.fresh()

if not (GameVersion.VERSIONS and GameVersion.VERSIONS.gold) then
  print("SKIP gold_compatibility: requires a Gold-enabled engine checkout")
  return
end

T.check(GameVersion.VERSIONS and GameVersion.VERSIONS.gold,
  "the test checkout exposes the Gold game version")
T.check(type(GameVersion.set) == "function", "GameVersion supports selecting Gold")
GameVersion.set("gold")

local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"
T.eq(#run.errors, 0, "Gold package load is clean (" .. tostring(run.errors[1]) .. ")")

local schema = run.loader.optionSchemas[MOD_ID]
T.eq(#schema, 61, "Gold exposes the complete flat 0.1.x schema")
local keys, byKey = {}, {}
for _, row in ipairs(schema) do
  keys[row.key] = true
  byKey[row.key] = row
  T.check(type(row.label) == "string" and #row.label <= 18,
    "Gold setting label fits the settings window: " .. tostring(row.key))
  T.check(row.type == "toggle" or row.type == "choice"
      or row.type == "number" or row.type == "text",
    "Gold uses only supported 0.1.x option row types")
  T.eq(row.options, nil, "Gold option rows are not nested")
end

for _, key in ipairs({
  "effectiveness", "lowHealthAlarm", "expShare", "autoBattle",
  "autoCatch", "autoCatchNewOnly", "autoCatchTarget", "autoCatchBall", "showBallCounts",
  "autoStopShiny", "autoStopLowHp", "autoStopNoBalls", "autoStopTarget",
  "catchShinyOnly",
  "autoPauseNewEntry", "autoPauseEvolution", "fieldAbilities",
  "fieldAbilitiesAuto", "hmWithoutTeaching", "skipCenterDialogue", "encounterRate", "minimap", "minimapCorner",
  "minimapTransparency", "minimapSize", "minimapZoom", "minimapBorder",
  "tracking", "encounterTracker", "encounterTrackerCorner", "encounterTrackerTracked",
  "encounterTrackerLand", "encounterTrackerSurf", "encounterTrackerFishing",
  "encounterTrackerTime", "encounterTrackerSwarms", "encounterTrackerRoaming",
  "encounterTrackerRare", "encounterTrackerHeadbutt",
  "encounterTrackerRockSmash", "encounterTrackerContest", "pokedexFilters",
  "floatingMenus", "partyOverview", "partyOverviewCorner", "partyOrder", "autoPartyOrder",
  "bagCategories", "bagSearch", "bagAutoSort", "quickUseItems", "reusableTMs", "toFront",
  "swapMoves", "retainPP", "skipWildCatchNickname", "renameNpcTrades",
  "autoRenameTrades", "renameAnywhere", "restoreName", "eggTracker",
}) do
  T.check(keys[key] == true, "Gold schema contains " .. key)
end
for _, key in ipairs({ "experienceBar", "caughtIndicator", "wallCollisionSound" }) do
  T.check(keys[key] ~= true, "Gen 1-only option is omitted from Gold: " .. key)
end

local function visibilityHas(condition, key)
  if type(condition) ~= "table" then return false end
  return condition.key == key and condition.equals == true
end

T.check(visibilityHas(byKey.autoCatch.visible_if, "autoBattle"),
  "Gold AUTO CATCH is gated by AUTO BATTLE")
T.check(not visibilityHas(byKey.encounterTrackerCorner.visible_if, "minimap")
  and visibilityHas(byKey.encounterTrackerCorner.visible_if, "encounterTracker"),
  "Gold TRACKER CORNER is gated by ENCOUNTER TRACKER without MINIMAP")
T.check(visibilityHas(byKey.partyOverviewCorner.visible_if, "partyOverview"),
  "Gold PARTY CORNER is gated by PARTY OVERVIEW")
T.check(visibilityHas(byKey.catchShinyOnly.visible_if, "autoCatch"),
  "Gold CATCH SHINY ONLY is gated by its direct parent AUTO CATCH")
for _, key in ipairs({ "autoCatchNewOnly", "autoCatchTarget", "autoCatchBall", "showBallCounts" }) do
  T.check(visibilityHas(byKey[key].visible_if, "autoCatch"),
    "Gold " .. key .. " is gated by its direct parent AUTO CATCH")
end
for _, key in ipairs({
  "encounterTrackerTime", "encounterTrackerSwarms", "encounterTrackerRoaming",
  "encounterTrackerRare", "encounterTrackerHeadbutt",
  "encounterTrackerRockSmash", "encounterTrackerContest",
}) do
  T.check(not visibilityHas(byKey[key].visible_if, "minimap")
    and visibilityHas(byKey[key].visible_if, "encounterTracker"),
    "Gold " .. key .. " is gated by ENCOUNTER TRACKER without MINIMAP")
end
T.check(byKey.eggTracker.visible_if == nil,
  "Gold EGG TRACKER is a direct PARTY category toggle")

local exports = run.loader.exports[MOD_ID]
T.check(type(exports) == "table" and #exports.features == 28,
  "Gold loads every QoL Suite runtime module")
for _, helper in ipairs({
  "autoBattle", "autoCatchTarget", "encounterTracker", "encounterRate",
  "eggTracker", "partyOverview", "pokedexFilters", "minimap", "moveFreedom",
  "hmWithoutTeaching", "reusableTMs",
}) do
  T.check(type(exports[helper]) == "table",
    "Gold exports the " .. helper .. " compatibility helper")
end
run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoCatchNewOnly = true,
}
local goldCaughtBattle = {
  enemy = { species = "FIXMON_A" },
  game = { save = { pokedex = { caught = { FIXMON_A = true } } } },
}
T.check(not exports.autoBattle.catchNewOnlyAllowed(
  goldCaughtBattle, goldCaughtBattle.game),
  "Gold CATCH NEW ONLY skips an already caught species")
goldCaughtBattle.game.save.pokedex.caught = {}
T.check(exports.autoBattle.catchNewOnlyAllowed(
  goldCaughtBattle, goldCaughtBattle.game),
  "Gold CATCH NEW ONLY allows a new species")

-- CATCH SHINY ONLY: the opposite policy of STOP ON SHINY. When on, auto-catch
-- fires only against a shiny enemy; a non-shiny enemy declines the catch so
-- the normal auto-battle loop continues.
local shinyBattle = { enemy = { species = "FIXMON_A", shiny = true } }
local nonShinyBattle = { enemy = { species = "FIXMON_A" } }
run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, catchShinyOnly = true,
}
T.check(exports.autoBattle.catchShinyOnlyAllowed(shinyBattle),
  "Gold CATCH SHINY ONLY allows a shiny enemy")
T.check(not exports.autoBattle.catchShinyOnlyAllowed(nonShinyBattle),
  "Gold CATCH SHINY ONLY declines a non-shiny enemy")
run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, catchShinyOnly = false,
}
T.check(exports.autoBattle.catchShinyOnlyAllowed(nonShinyBattle),
  "Gold CATCH SHINY ONLY is inert when off (allows any enemy)")
run.loader.modOptions[MOD_ID] = nil

T.check(type(exports.eggTracker.snapshot) == "function",
  "Gold exposes the egg tracker snapshot helper")
T.check(type(exports.encounterTracker.collect) == "function",
  "Gold exposes the encounter tracker collector")

do
  local GbcPalette = require("src.render.GbcPalette")
  local previousMode, previousBgp = GbcPalette.mode, GbcPalette.bgp
  local source = {
    { 248, 216, 160 }, { 168, 144, 96 },
    { 88, 80, 56 }, { 16, 24, 16 },
  }
  GbcPalette.setBgp(nil)
  GbcPalette.setMode("gbc")
  local gbc = exports.minimap.colors({ colors = source })
  T.eq(gbc["0"][1], 248 / 255,
    "Gold minimap uses the active GBC map palette")
  GbcPalette.setMode("dmg")
  local dmg = exports.minimap.colors({ colors = source })
  T.eq(dmg["0"][1], 1,
    "Gold minimap follows the DMG color option")
  T.eq(dmg["3"][1], 0,
    "Gold minimap maps the darkest shade in DMG mode")
  GbcPalette.setMode(previousMode)
  GbcPalette.setBgp(previousBgp)
end

do
  -- The native Gold nurse is an extracted standard script.  Keep this
  -- synthetic VM check focused on the script-command seam: the option must
  -- answer only PokecenterNurseScript's YES/NO command and leave the VM
  -- positioned on the script's normal heal branch.
  local vm = { scriptVar = 0 }
  run.loader.game = {
    world = { map = {}, stdScripts = { scripts = {
      PokecenterNurseScript = { key = "gold-nurse-key" },
    } } },
  }
  run.loader.modOptions[MOD_ID] = { skipCenterDialogue = true }
  T.check(exports.skipCenterDialogue.isGoldNurseScript({
    generation = 2, scriptKey = "gold-nurse-key", vm = vm,
  }), "Gold SKIP CENTER TALK recognizes the native nurse script")
  local continued = false
  local result = run.loader.hooks:call("script.command",
    function() continued = true return "vanilla" end,
    { generation = 2, scriptKey = "gold-nurse-key", vm = vm },
    "yesorno", {}, {})
  T.eq(result, nil, "Gold SKIP CENTER TALK consumes the nurse question")
  T.eq(vm.scriptVar, 1, "Gold SKIP CENTER TALK selects YES")
  T.check(not continued,
    "Gold SKIP CENTER TALK does not run the native yes/no prompt")
  for _, name in ipairs({ "writetext", "farwritetext", "jumptext",
      "jumptextfaceplayer", "rawtext" }) do
    continued = false
    local textResult = run.loader.hooks:call("script.command",
      function() continued = true return "vanilla" end,
      { generation = 2, scriptKey = "gold-nurse-key", vm = vm },
      name, {}, {})
    T.eq(textResult, nil,
      "Gold SKIP CENTER TALK consumes nurse " .. name)
    T.check(not continued,
      "Gold SKIP CENTER TALK does not display nurse " .. name)
  end
  local unrelated = run.loader.hooks:call("script.command",
    function() continued = true return "vanilla" end,
    { generation = 2, scriptKey = "other-key", vm = { scriptVar = 0 } },
    "yesorno", {}, {})
  T.eq(unrelated, "vanilla",
    "Gold SKIP CENTER TALK leaves unrelated script questions alone")
  run.loader.modOptions[MOD_ID] = nil
end

do
  local habitatData = {
    maps = {
      FISH_ROUTE = { fishGroup = "FISHGROUP_TEST" },
      TREE_ROUTE = {}, ROCK_ROUTE = {},
    },
    encounters = {
      fishGroups = { FISHGROUP_TEST = {
        old = { { species = "FISH_MON", level = 5 } },
      } },
      trees = { TREE_ROUTE = "TREE_SET" },
      rocks = { ROCK_ROUTE = "ROCK_SET" },
      treeSets = {
        TREE_SET = { common = { { species = "TREE_MON", level = 10 } } },
        ROCK_SET = { common = { { species = "ROCK_MON", level = 12 } } },
      },
      bugContest = { { species = "BUG_MON", min = 7, max = 9 } },
    },
  }
  T.check(exports.minimap.locations({ data = habitatData }, "FISH_MON").FISH_ROUTE,
    "Gold Tracking resolves fishing groups back to maps")
  T.check(exports.minimap.locations({ data = habitatData }, "TREE_MON").TREE_ROUTE,
    "Gold Tracking resolves Headbutt groups back to maps")
  T.check(exports.minimap.locations({ data = habitatData }, "ROCK_MON").ROCK_ROUTE,
    "Gold Tracking resolves Rock Smash groups back to maps")
  T.check(exports.minimap.locations({ data = habitatData }, "BUG_MON").NATIONAL_PARK,
    "Gold Tracking resolves Bug Contest habitat to National Park")
  T.check(exports.minimap.locations({ data = habitatData, save = {
    roamers = { { species = "ROAM_MON", map = "ROAM_ROUTE" } },
  } }, "ROAM_MON").ROAM_ROUTE,
    "Gold Tracking follows a roaming Pokemon's current map")
end

do
  local moveMon = { moves = {
    { id = "FIX_TACKLE", pp = 10, maxPp = 35 },
  } }
  run.loader.modOptions[MOD_ID] = { swapMoves = true, retainPP = true }
  local swapped = exports.moveFreedom.swapMove(
    { data = Data }, moveMon, 1, "FIX_EMBERISH")
  T.check(swapped, "Gold SWAP MOVES accepts an unlocked replacement")
  T.eq(moveMon.moves[1].maxPp, 25,
    "Gold SWAP MOVES writes the native maximum-PP field")
  T.eq(moveMon.moves[1].pp, 7,
    "Gold KEEP MOVE PP preserves the outgoing PP fraction")
end

-- Gold keeps its World object alive behind pushed menus and battles. HUD
-- overlays and quick-use chords must treat only an empty stack as free roam.
local goldStackTop
local goldFreeRoamGame = {
  input = {}, phase = "play", world = { battleActive = false },
  stack = { top = function() return goldStackTop end },
}
T.check(exports.minimap.freeRoam(goldFreeRoamGame, goldFreeRoamGame.world),
  "Gold minimap accepts the empty-stack overworld")
T.check(exports.bagCategories.overworldReady(goldFreeRoamGame),
  "Gold quick-use accepts the empty-stack overworld")
goldStackTop = { kind = "menu" }
T.check(not exports.minimap.freeRoam(goldFreeRoamGame, goldFreeRoamGame.world),
  "Gold minimap stays hidden behind menus and battles")
T.check(not exports.bagCategories.overworldReady(goldFreeRoamGame),
  "Gold quick-use cannot push another menu over a current screen")
goldStackTop = nil

-- Gold owns field-move prompts on World rather than the Gen 1 overworld
-- facade. AUTO FIELD MOVES must bypass only supported contextual prompts.
local GoldWorldForFieldMoves = require("src.world.gen2.World")
local fieldMoveWorld = setmetatable({
  runFieldMove = function(self, result)
    self.executedFieldMove = result
    return true
  end,
}, { __index = GoldWorldForFieldMoves })
run.loader.modOptions[MOD_ID] = {
  fieldAbilities = true, fieldAbilitiesAuto = true,
}
local nativePromptResult = {
  took = true, ok = true, ask = "ASK", action = "surf", marker = 7,
}
T.check(fieldMoveWorld:runOverworldFieldMove(nativePromptResult),
  "Gold AUTO FIELD MOVES executes a valid native field move")
T.eq(fieldMoveWorld.executedFieldMove.action, "surf",
  "Gold AUTO FIELD MOVES preserves the native action")
T.eq(fieldMoveWorld.executedFieldMove.marker, 7,
  "Gold AUTO FIELD MOVES preserves native result context")
T.eq(nativePromptResult.ask, "ASK",
  "Gold AUTO FIELD MOVES does not mutate the engine result")
for _, action in ipairs({
  "cut", "surf", "strength", "headbutt", "rocksmash", "whirlpool", "waterfall",
}) do
  local result = { took = true, ok = true, ask = "ASK", action = action }
  T.check(fieldMoveWorld:runOverworldFieldMove(result),
    "Gold AUTO FIELD MOVES accepts " .. action .. " prompts")
  T.eq(fieldMoveWorld.executedFieldMove.action, action,
    "Gold AUTO FIELD MOVES preserves " .. action .. "")
end

run.loader.modOptions[MOD_ID] = {
  minimap = true,
  encounterTracker = true,
  encounterTrackerTracked = true,
  encounterTrackerLand = true,
  encounterTrackerSurf = true,
  encounterTrackerFishing = true,
  encounterTrackerTime = true,
  encounterTrackerSwarms = true,
  encounterTrackerRoaming = true,
  encounterTrackerRare = true,
  encounterTrackerHeadbutt = true,
  encounterTrackerRockSmash = true,
  encounterTrackerContest = true,
}
local display = exports.encounterTracker.displayOptions()
for _, field in ipairs({
  "tracked", "land", "surf", "fishing", "time", "swarms", "roaming",
  "rare", "headbutt", "rockSmash", "contest",
}) do
  T.check(display[field] == true, "Gold encounter display includes " .. field)
end
for _, pair in ipairs({
  { key = "encounterTrackerTime", field = "time" },
  { key = "encounterTrackerSwarms", field = "swarms" },
  { key = "encounterTrackerRoaming", field = "roaming" },
  { key = "encounterTrackerRare", field = "rare" },
  { key = "encounterTrackerHeadbutt", field = "headbutt" },
  { key = "encounterTrackerRockSmash", field = "rockSmash" },
  { key = "encounterTrackerContest", field = "contest" },
}) do
  run.loader.modOptions[MOD_ID][pair.key] = false
  T.check(exports.encounterTracker.displayOptions()[pair.field] == false,
    "Gold hides encounter display when " .. pair.key .. " is off")
  run.loader.modOptions[MOD_ID][pair.key] = true
end
local goldLines = exports.encounterTracker.format({
  timeLabel = "MORNING",
  groups = {
    { label = "GRASS MORNING", entries = {
      { name = "FIXMON A", min = 2, max = 3 },
    } },
  },
}, 28, 8)
local goldText = {}
for _, line in ipairs(goldLines) do goldText[#goldText + 1] = line.text end
T.check(table.concat(goldText, "\n"):find("ENCOUNTERS MORNING", 1, true) ~= nil,
  "Gold encounter tracker formats the time-of-day heading")

do
  local swarmModel = { timeLabel = "DAY", groups = {
    { label = "SWARM OLD ROD", entries = {
      { name = "FIXMON A", min = 5, max = 5 },
    } },
  } }
  local noFishing = exports.encounterTracker.format(swarmModel, 28, 8, {
    fishing = false, swarms = true, time = true,
  })
  T.check(table.concat((function()
    local out = {}
    for _, line in ipairs(noFishing) do out[#out + 1] = line.text end
    return out
  end)(), "\n"):find("OLD ROD", 1, true) == nil,
    "Gold SHOW FISHING hides fishing-swarm rows too")

  local contestData = {
    pokemon = Data.pokemon,
    encounters = { bugContest = {
      { species = "FIXMON_A", min = 7, max = 9 },
    } },
  }
  local contestSave = { bugContest = { active = false } }
  local contestWorld = { overworld = function()
    return { daytime = "DAY", map = { def = {} } }
  end }
  local inactive = exports.encounterTracker.collect(
    { data = contestData, save = contestSave }, contestWorld,
    { mapId = "NATIONAL_PARK" })
  T.eq(#inactive.groups, 0,
    "Gold encounter tracker hides inactive Bug Contest encounters")
  local inactiveKey = exports.encounterTracker.key(
    { save = contestSave }, contestWorld, { mapId = "NATIONAL_PARK" })
  contestSave.bugContest.active = true
  local activeContest = exports.encounterTracker.collect(
    { data = contestData, save = contestSave }, contestWorld,
    { mapId = "NATIONAL_PARK" })
  T.eq(activeContest.groups[1].label, "BUG CONTEST",
    "Gold encounter tracker shows Bug Contest encounters only while active")
  T.check(exports.encounterTracker.key(
    { save = contestSave }, contestWorld, { mapId = "NATIONAL_PARK" })
      ~= inactiveKey,
    "Gold encounter cache invalidates when the Bug Contest starts")
end

-- Gold EXP SHARE must use the native two-pass calculation without mutating
-- any held item, including the nil/no-item state.
run.loader.modOptions[MOD_ID] = { expShare = true }
local expParty = {
  { hp = 20 },
  { hp = 20, item = "BERRY" },
  { hp = 0, item = "MINT_BERRY" },
  { hp = 20, isEgg = true },
}
local expPasses, vanillaExp = {}, false
local loser = { species = "FIXMON_A", level = 5 }
local expBattle = {
  party = expParty,
  speciesDef = function() return { id = "FIXMON_A" } end,
  giveExperiencePass = function(self, gotLoser, def, recipients, count, halved)
    local copy = {}
    for _, index in ipairs(recipients) do copy[#copy + 1] = index end
    expPasses[#expPasses + 1] = {
      loser = gotLoser, recipients = copy, count = count, halved = halved,
    }
  end,
}
run.loader.hooks:call("battle.exp_award", function()
  vanillaExp = true
end, { battle = expBattle, recipients = { 1 }, loser = loser })
T.check(not vanillaExp and #expPasses == 2,
  "Gold EXP SHARE replaces vanilla with the native two-pass distribution")
T.eq(expPasses[1].recipients[1], 1,
  "Gold EXP SHARE pays battle participants in the first half")
T.eq(#expPasses[2].recipients, 2,
  "Gold EXP SHARE pays every living non-Egg party member in the second half")
T.check(expPasses[1].halved and expPasses[2].halved,
  "Gold EXP SHARE halves both native award pools")
T.eq(expParty[1].item, nil,
  "Gold EXP SHARE preserves a Pokemon that held no item")
T.eq(expParty[2].item, "BERRY",
  "Gold EXP SHARE preserves an existing held item")

-- Gold's Pokedex action menu must contain both independently gated actions in
-- stable registration order.
run.loader.modOptions[MOD_ID] = {
  minimap = true, tracking = true, autoBattle = true,
  autoCatch = true, autoCatchTarget = true,
}
local goldActions = exports.tracking.goldActions({ data = Data }, "FIXMON_A")
T.eq(goldActions[1].label, "TRACK",
  "Gold Pokedex exposes the Tracking action")
T.eq(goldActions[2].label, "TARGET",
  "Gold Pokedex exposes AUTO CATCH TARGET after Tracking")

-- The Gold catch prompt is a UI battle state, not the Gen 1 battle model.
local GoldBattleState = require("src.ui.gen2.BattleState")
local nicknameState = {
  phase = "resolving",
  advanceQueue = function(self) self.advanced = true end,
  name = function() return "FIXMON A" end,
}
run.loader.modOptions[MOD_ID] = { skipWildCatchNickname = true }
GoldBattleState.askNickname(nicknameState, { species = "FIXMON_A" })
T.check(nicknameState.advanced and nicknameState.phase == "resolving",
  "SKIP CATCH NAME bypasses Gold's native nickname prompt")
local normalNicknameState = {
  name = function() return "FIXMON A" end,
}
run.loader.modOptions[MOD_ID] = { skipWildCatchNickname = false }
GoldBattleState.askNickname(normalNicknameState, { species = "FIXMON_A" })
T.eq(normalNicknameState.phase, "ask-nickname",
  "Gold keeps its native nickname prompt when SKIP CATCH NAME is off")

-- Gold NPC trades use NpcTrade.perform rather than Gen 1's Commands.trade.
-- The received mon must carry the eligibility marker and optional auto-reset.
local NpcTrade = require("src.core.gen2.NpcTrade")
local tradeRow = {
  give = "FIXMON_A", get = "FIXMON_B", nickname = "TRADE NAME",
  dvs = { 0x98, 0x88 }, otName = "NPC", otId = 1234, item = 0,
}
run.loader.modOptions[MOD_ID] = {
  renameNpcTrades = true, autoRenameTrades = false,
  renameAnywhere = false, swapMoves = false, toFront = false,
}
local tradeSave = { party = { { species = "FIXMON_A", level = 10 } } }
local _, tradedMon = NpcTrade.perform(Data, tradeSave, tradeRow, 1)
T.check(tradedMon ~= nil and tradedMon.nickname == "TRADE NAME",
  "Gold NPC trade keeps its preset name when AUTO RENAME TRADES is off")
local tradeActions = run.loader.hooks:call("ui.party.submenu",
  function(_, items) return items end, { save = tradeSave, data = Data },
  { { label = "STATS" }, { label = "SWITCH" } }, tradedMon,
  { battle = false })
local hasTradeRename = false
for _, action in ipairs(tradeActions) do
  if action.label == "RENAME" then hasTradeRename = true end
end
T.check(hasTradeRename,
  "RENAME NPC MON exposes Gold's party rename action for an NPC trade")
run.loader.modOptions[MOD_ID].autoRenameTrades = true
local secondSave = { party = { { species = "FIXMON_A", level = 10 } } }
local _, autoRenamed = NpcTrade.perform(Data, secondSave, tradeRow, 1)
T.eq(autoRenamed and autoRenamed.nickname, nil,
  "AUTO RENAME TRADES clears Gold's preset NPC-trade nickname")

-- Gold heals through World:healParty; remembered unequipped moves must refill
-- beside the equipped moves just as they do in RBY.
local GoldWorld = require("src.world.gen2.World")
local remembered = { pp = 0, ppUps = 1 }
GoldWorld.healParty({ game = {
  data = { moves = { OLD_MOVE = { pp = 10 } } },
  save = { party = { {
    hp = 1, maxHp = 20, status = "POISON",
    moves = { { id = "TACKLE", pp = 0, maxPp = 35 } },
    masterPP = { OLD_MOVE = remembered },
  } } },
} })
T.eq(remembered.pp, 12,
  "Gold healing refills remembered move PP including PP Ups")

-- A four-HM moveset has no legal forget slot. AUTO BATTLE must decline the
-- pending move instead of selecting an HM or indexing a partial prompt.
run.loader.modOptions[MOD_ID] = { autoBattle = true }
local hmState = {
  phase = "choose-forget",
  pendingLearn = { index = 1, move = { id = "NEW_MOVE" }, moveName = "NEW" },
  battle = { party = { { moves = {
    { id = "CUT" }, { id = "FLY" }, { id = "SURF" }, { id = "STRENGTH" },
  } } } },
  game = {},
  finishDecline = function(self) self.declined = true end,
}
hmState.game.stack = { top = function() return hmState end }
T.check(exports.autoBattle.goldAdvance(hmState) and hmState.declined,
  "Gold AUTO BATTLE declines move learning when all four slots are HMs")

-- USE HMs DIRECTLY: Gold's shared eligibility hook still requires both the
-- owned HM and the native Johto badge before supplying a representative mon.
Data.items.HM_SURF = { id = "HM_SURF", name = "HM03", teaches = "SURF" }
local goldHmMon = { species = "FIXMON_A", moves = { { id = "FIX_TACKLE" } } }
local goldHmSave = {
  inventory = { HM_SURF = 1 },
  player = { badges = { FOG = true } },
  party = { goldHmMon },
}
run.loader.modOptions[MOD_ID] = { hmWithoutTeaching = true }
local goldHmUser = run.loader.hooks:call(
  "fieldmove.eligibility", function() return nil end, "SURF", {
    save = goldHmSave, data = Data, party = goldHmSave.party,
  })
T.eq(goldHmUser, goldHmMon,
  "Gold USE HMs DIRECTLY supplies a user for an owned badge-gated HM")
goldHmSave.player.badges.FOG = nil
goldHmUser = run.loader.hooks:call(
  "fieldmove.eligibility", function() return nil end, "SURF", {
    save = goldHmSave, data = Data, party = goldHmSave.party,
  })
T.eq(goldHmUser, nil,
  "Gold USE HMs DIRECTLY preserves the native badge requirement")

-- REUSABLE TMs: Gold's final Game2 consumption seam keeps the item after a
-- successful teach, while the disabled path still decrements it normally.
Data.items.TM_TEST = { id = "TM_TEST", name = "TM01", teaches = "FIX_CUT" }
local GoldGame2 = require("src.core.Game2")
local tmGame = { data = Data, save = { inventory = { TM_TEST = 2 } } }
run.loader.modOptions[MOD_ID] = { reusableTMs = true }
GoldGame2.consumeItem(tmGame, "TM_TEST")
T.eq(tmGame.save.inventory.TM_TEST, 2,
  "Gold REUSABLE TMs keeps a TM in the bag")
run.loader.modOptions[MOD_ID] = { reusableTMs = false }
GoldGame2.consumeItem(tmGame, "TM_TEST")
T.eq(tmGame.save.inventory.TM_TEST, 1,
  "Gold consumes a TM normally when REUSABLE TMs is off")

T.finish("gold_compatibility")
