-- PARTY OVERVIEW: party summaries and stable order presets.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local party = run.loader.exports.qol_suite.partyOverview

T.eq(#run.errors, 0, "party overview loads clean")
local game = {
  data = Data,
  save = { party = {
    { species = "FIXMON_A", hp = 0, maxHp = 40, level = 20, moves = {} },
    { species = "FIXMON_B", hp = 28, maxHp = 30, level = 10, moves = {
      { pp = 10, maxPp = 15 },
    } },
    { species = "FIXMON_C", hp = 5, maxHp = 100, level = 30, moves = {
      { pp = 2, maxPp = 10 },
    } },
  } },
}

T.eq(party.statusCode(game.save.party[1]), "FNT",
  "party overview marks fainted Pokemon")
T.eq(party.statusCode(game.save.party[2]), "OK",
  "party overview reports healthy status")
local current, maximum = party.pp(game.save.party[2])
T.eq(current, 10, "party overview totals current move PP")
T.eq(maximum, 15, "party overview totals maximum move PP")

local rows = party.snapshot(game)
T.eq(rows[1].hp, 0, "party overview snapshot includes HP")
T.eq(rows[2].pp, 10, "party overview snapshot includes PP")
T.eq(rows[3].status, "OK",
  "party overview snapshot normalizes unspecified status")

local malformedRows = party.snapshot({
  data = { moves = { ODD_MOVE = { pp = 7 } }, pokemon = Data.pokemon },
  save = { party = { {
    species = "FIXMON_A", hp = 0 / 0, maxHp = math.huge,
    moves = { { id = "ODD_MOVE", pp = 0 / 0, ppUps = math.huge } },
  } } },
})
T.eq(malformedRows[1].hp, 0, "party overview sanitizes invalid HP")
T.eq(malformedRows[1].maxHp, 0,
  "party overview sanitizes invalid maximum HP")
T.eq(malformedRows[1].pp, 0, "party overview sanitizes invalid PP")
local _, oddMaximum = party.pp({
  moves = { { id = "ODD_MOVE", pp = 1, ppUps = 3 } },
}, { moves = { ODD_MOVE = { pp = 7 } } })
T.eq(oddMaximum, 10,
  "party overview matches the engine's PP Up scaling")

local typeGame = {
  data = { pokemon = {
    WATER_MON = { types = { "WATER" } },
    FIRE_MON = { types = { "FIRE" } },
  } },
  save = { party = {
    { species = "WATER_MON", hp = 10, maxHp = 10 },
    { species = "FIRE_MON", hp = 10, maxHp = 10 },
  } },
}
T.check(party.reorder(typeGame, "type"),
  "type preset reads Gold's types array")
T.eq(typeGame.save.party[1].species, "FIRE_MON",
  "type preset alphabetizes Gold primary types")

T.check(party.reorder(game, "healthy"),
  "healthy-first party preset changes the party order")
T.eq(game.save.party[1].species, "FIXMON_B",
  "healthy-first places the healthiest living Pokemon first")
T.eq(game.save.party[3].species, "FIXMON_A",
  "healthy-first places fainted Pokemon at the back")

T.check(not party.reorder(game, "level"),
  "level preset preserves an already safety-ordered party")
T.eq(game.save.party[1].species, "FIXMON_B",
  "level preset keeps a healthy Pokemon ahead of a higher-level low-HP one")
T.eq(game.save.party[2].species, "FIXMON_C",
  "level preset still orders the low-health group before fainted Pokemon")
T.eq(game.save.party[3].species, "FIXMON_A",
  "level preset keeps fainted Pokemon at the back")

game.save.party[#game.save.party + 1] = {
  species = "FIXMON_A", hp = 999, maxHp = 999, level = 100,
  isEgg = true, moves = {},
}
T.eq(party.statusCode(game.save.party[4]), "EGG",
  "party overview identifies Eggs without reporting them as healthy")
party.reorder(game, "type")
T.check(game.save.party[#game.save.party].isEgg == true,
  "every automatic preset pins Eggs behind usable party members")
T.eq(party.order("unknown"), "native",
  "party order safely falls back to native order")

local overlay = run.loader.exports.qol_suite.overlayLayout
local compactViewport = { width = 160, height = 144 }
local sharedWidth = select(1, overlay.minimapDimensions(
  compactViewport, 100, 100))
local compactPanel = party.layout(compactViewport)
T.eq(compactPanel.width, sharedWidth,
  "party overview matches encounter tracker width at 160x144")
T.check(compactPanel.x >= 0
    and compactPanel.x + compactPanel.width <= compactViewport.width,
  "party overview remains inside a 160x144 viewport")
local denseRow = party.rowLayout({
  index = 6, name = "FERALIGATR", hp = 999, maxHp = 999,
  status = "PSN", pp = 999,
}, compactPanel.width)
T.check(denseRow.pixelWidth <= denseRow.contentWidth,
  "compact party HP/status/PP row fits inside the native border")
T.check(denseRow.text:find("H999", 1, true) ~= nil,
  "compact party row retains HP")
T.check(denseRow.text:find(" P ", 1, true) ~= nil,
  "compact party row retains status")
T.check(denseRow.text:find("P999", 1, true) ~= nil,
  "compact party row retains PP")

local tinyViewport = { width = 96, height = 144 }
local tinyPanel = party.layout(tinyViewport)
local tinyRow = party.rowLayout({
  index = 6, name = "FERALIGATR", hp = 999, maxHp = 999,
  status = "PSN", pp = 999,
}, tinyPanel.width)
T.eq(tinyPanel.width, tinyViewport.width,
  "party overview shrinks to an unusually narrow viewport")
T.check(tinyRow.pixelWidth <= tinyRow.contentWidth,
  "minimal party HP/status/PP row never clips at narrow widths")
T.eq(party.header(tinyPanel.width), "PARTY",
  "narrow party panel uses a fitting native header")

local autoGame = {
  data = Data,
  save = { party = {
    { species = "FIXMON_A", hp = 1, maxHp = 40, level = 30 },
    { species = "FIXMON_B", hp = 30, maxHp = 30, level = 10 },
  } },
}
T.check(party.autoOrderTick(autoGame, "healthy"),
  "automatic party order reacts immediately to its first snapshot")
T.eq(autoGame.save.party[1].species, "FIXMON_B",
  "automatic party order applies the requested preset")
local unchangedRuns = party.autoOrderRuns()
T.check(not party.autoOrderTick(autoGame, "healthy"),
  "an unchanged frame does not run automatic reordering")
T.eq(party.autoOrderRuns(), unchangedRuns,
  "unchanged frames leave the automatic reorder counter unchanged")
autoGame.save.party[1].hp = 2
T.check(party.autoOrderTick(autoGame, "healthy"),
  "a relevant HP change immediately rechecks party order")
T.check(party.autoOrderTick(autoGame, "level"),
  "a preset change immediately rechecks party order")

local function chainCount(name)
  local chain = run.loader.hooks.chains[name]
  return chain and #chain or 0
end
local function setOption(key, value)
  run.loader.modOptions.qol_suite = run.loader.modOptions.qol_suite or {}
  run.loader.modOptions.qol_suite[key] = value
  run.loader.events:emit("mod.options_changed", {
    mod = "qol_suite", key = key, value = value,
  })
end
local baseRenderHooks = chainCount("render.hud")
local baseUpdateHooks = chainCount("core.update")
local renderActive, updateActive = party.subscriptions()
T.check(not renderActive and not updateActive,
  "disabled party overview owns no hot-path hooks")
setOption("partyOverview", true)
renderActive, updateActive = party.subscriptions()
T.check(renderActive and not updateActive,
  "party overview subscribes only its render hook when enabled")
T.eq(chainCount("render.hud"), baseRenderHooks + 1,
  "party render hook is installed once")
setOption("partyOverview", true)
T.eq(chainCount("render.hud"), baseRenderHooks + 1,
  "repeated enable does not duplicate the party render hook")
setOption("autoPartyOrder", true)
renderActive, updateActive = party.subscriptions()
T.check(renderActive and updateActive,
  "automatic ordering subscribes core.update only while active")
T.eq(chainCount("core.update"), baseUpdateHooks + 1,
  "party update hook is installed once")
setOption("autoPartyOrder", false)
T.eq(chainCount("core.update"), baseUpdateHooks,
  "disabling automatic ordering unsubscribes core.update")
setOption("partyOverview", false)
T.eq(chainCount("render.hud"), baseRenderHooks,
  "disabling party overview unsubscribes render.hud")

T.finish("party_overview")
