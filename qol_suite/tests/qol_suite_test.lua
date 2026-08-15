-- Consolidated package regression test. Run from the gen1recomp checkout:
--   luajit mods/qol_suite/tests/qol_suite_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"

local function withGameFacade(callback)
  local moduleName = table.concat({ "src.core.", "Ga", "me" })
  local ok, facade = pcall(require, moduleName)
  T.check(ok and type(facade) == "table",
    "the engine Game facade is available to integration checks")
  if ok and type(facade) == "table" then return callback(facade) end
end

T.eq(#run.errors, 0, "consolidated package loads clean (" .. tostring(run.errors[1]) .. ")")

local byKey, visibilityHas
do
local schema = run.loader.optionSchemas[MOD_ID]
local leaves = schema
T.eq(#schema, 53, "0.1.x receives every RBY setting in one flat list")
local keys = {}
for _, row in ipairs(leaves) do keys[row.key] = true end
for _, key in ipairs({
  "effectiveness", "swapMoves", "retainPP", "skipWildCatchNickname",
  "renameNpcTrades", "autoRenameTrades", "renameAnywhere", "restoreName",
  "toFront",
  "lowHealthAlarm", "experienceBar", "caughtIndicator",
  "fieldAbilities", "fieldAbilitiesAuto", "hmWithoutTeaching", "skipCenterDialogue", "encounterRate", "bagCategories",
  "bagSearch", "bagAutoSort", "quickUseItems", "reusableTMs", "minimap",
  "minimapCorner", "minimapTransparency", "minimapSize", "minimapZoom",
  "minimapBorder", "tracking",
  "encounterTracker", "encounterTrackerCorner", "encounterTrackerTracked", "encounterTrackerLand",
  "encounterTrackerSurf", "encounterTrackerFishing", "pokedexFilters",
  "expShare", "autoBattle", "autoCatch", "autoCatchTarget",
  "autoCatchNewOnly", "autoCatchBall", "showBallCounts", "floatingMenus",
  "partyOverview", "partyOverviewCorner", "partyOrder", "autoPartyOrder",
  "autoStopLowHp", "autoStopNoBalls", "autoStopTarget",
  "autoPauseNewEntry", "autoPauseEvolution",
}) do
  T.check(keys[key] == true, "schema contains " .. key)
end
T.check(keys.encounterTrackerTime ~= true,
  "SHOW TIME OF DAY is not offered by Gen 1")
T.check(keys.eggTracker ~= true,
  "EGG TRACKER is not offered by Gen 1")
for _, row in ipairs(schema) do
  T.check(type(row.label) == "string" and #row.label <= 18,
    "option label fits the settings window: " .. tostring(row.key))
  T.check(row.type == "toggle" or row.type == "choice"
      or row.type == "number" or row.type == "text",
    "option uses a supported 0.1.x row type: " .. tostring(row.key))
  T.eq(row.options, nil,
    "option has no nested child rows: " .. tostring(row.key))
end
local expectedLabels = {
  effectiveness = "TYPE MATCHUP",
  swapMoves = "SWAP MOVES",
  retainPP = "KEEP MOVE PP",
  skipWildCatchNickname = "SKIP CATCH NAME",
  renameNpcTrades = "RENAME NPC MON",
  autoRenameTrades = "AUTO RENAME TRADES",
  renameAnywhere = "RENAME ANYWHERE",
  restoreName = "RESET NAME",
  toFront = "ENABLE TO FRONT",
  lowHealthAlarm = "LOW HEALTH ALARM",
  experienceBar = "XP BAR",
  caughtIndicator = "CAUGHT MARKER",
  fieldAbilities = "QUICK FIELD MOVES",
  fieldAbilitiesAuto = "AUTO FIELD MOVES",
  hmWithoutTeaching = "USE HMs DIRECTLY",
  skipCenterDialogue = "SKIP CENTER TALK",
  encounterRate = "ENCOUNTER RATE",
  bagCategories = "BAG CATEGORIES",
  bagSearch = "BAG SEARCH",
  bagAutoSort = "AUTO SORT BAG",
  quickUseItems = "QUICK USE ITEMS",
  reusableTMs = "REUSABLE TMs",
  minimap = "MINIMAP",
  minimapCorner = "MINIMAP CORNER",
  minimapTransparency = "MAP TRANSPARENCY",
  minimapSize = "MINIMAP SIZE",
  minimapZoom = "MINIMAP ZOOM",
  minimapBorder = "MAP BORDER",
  tracking = "TRACKING",
  encounterTracker = "ENCOUNTER TRACKER",
  encounterTrackerCorner = "TRACKER CORNER",
  encounterTrackerTracked = "SHOW TRACKED",
  encounterTrackerLand = "SHOW LAND",
  encounterTrackerSurf = "SHOW SURFING",
  encounterTrackerFishing = "SHOW FISHING",
  pokedexFilters = "POKEDEX FILTERS",
  expShare = "EXP SHARE",
  autoBattle = "AUTO BATTLE",
  autoCatch = "AUTO CATCH",
  autoCatchNewOnly = "CATCH NEW ONLY",
  autoCatchTarget = "AUTO CATCH TARGET",
  autoCatchBall = "AUTO CATCH BALL",
  showBallCounts = "SHOW BALL COUNTS",
  autoStopLowHp = "STOP LOW HP",
  autoStopNoBalls = "STOP NO BALLS",
  autoStopTarget = "STOP ON TARGET",
  autoPauseNewEntry = "PAUSE NEW ENTRY",
  autoPauseEvolution = "PAUSE EVOLUTION",
  floatingMenus = "FLOATING MENUS",
  partyOverview = "PARTY OVERVIEW",
  partyOverviewCorner = "PARTY CORNER",
  partyOrder = "PARTY ORDER",
  autoPartyOrder = "AUTO PARTY ORDER",
}
for _, row in ipairs(leaves) do
  T.eq(row.label, expectedLabels[row.key],
    "setting label is clear: " .. tostring(row.key))
end
byKey = {}
for _, row in ipairs(leaves) do
  byKey[row.key] = row
end
T.eq(run.loader.exports[MOD_ID].optionVisibility.target, "v0.1.x",
  "the flat production manager receives dependent-row visibility support")
local expectedOrder = {
  "effectiveness", "lowHealthAlarm", "experienceBar", "caughtIndicator",
  "expShare", "swapMoves", "retainPP", "autoBattle", "autoStopLowHp", "autoPauseNewEntry",
  "autoPauseEvolution", "autoCatch", "autoCatchNewOnly", "autoCatchTarget",
  "autoCatchBall", "showBallCounts", "autoStopNoBalls", "autoStopTarget",
  "fieldAbilities",
  "fieldAbilitiesAuto", "hmWithoutTeaching", "skipCenterDialogue", "encounterRate",
  "partyOverview", "partyOverviewCorner", "partyOrder", "autoPartyOrder", "toFront",
  "bagCategories", "bagSearch", "bagAutoSort", "quickUseItems", "reusableTMs",
  "minimap", "minimapCorner", "minimapTransparency", "minimapSize", "minimapZoom",
  "minimapBorder", "tracking", "pokedexFilters", "encounterTracker",
  "encounterTrackerCorner", "encounterTrackerTracked", "encounterTrackerLand",
  "encounterTrackerSurf", "encounterTrackerFishing", "floatingMenus",
  "skipWildCatchNickname", "renameNpcTrades",
  "autoRenameTrades", "renameAnywhere", "restoreName",
}
for index, key in ipairs(expectedOrder) do
  T.eq(leaves[index].key, key, "settings retain a logical order within categories")
end
T.check(byKey.autoRenameTrades.default == false,
  "AUTO RENAME TRADES is disabled by default")
T.check(byKey.restoreName.default == true,
  "RESET NAME is enabled by default")
T.check(byKey.toFront.default == true,
  "ENABLE TO FRONT is enabled by default")
T.check(byKey.lowHealthAlarm.default == true,
  "LOW HEALTH ALARM is enabled by default")
T.check(byKey.experienceBar.default == true,
  "XP BAR is enabled by default")
T.check(byKey.caughtIndicator.default == true,
  "CAUGHT MARKER is enabled by default")
T.check(byKey.fieldAbilities.default == true,
  "FIELD MOVES is enabled by default")
T.check(byKey.fieldAbilitiesAuto.default == false,
  "AUTO FIELD MOVES prompts before use by default")
T.check(byKey.hmWithoutTeaching.default == false,
  "USE HMs DIRECTLY is disabled by default")
T.check(byKey.skipCenterDialogue.default == false,
  "SKIP CENTER TALK is disabled by default")
T.eq(byKey.encounterRate.default, 1,
  "ENCOUNTER RATE defaults to normal")
T.check(byKey.bagCategories.default == false,
  "BAG CATEGORIES is disabled by default")
T.check(byKey.reusableTMs.default == false,
  "REUSABLE TMs is disabled by default")
T.check(byKey.minimap.default == false,
  "MINIMAP is disabled by default")
T.eq(byKey.minimapCorner.default, "top-right",
  "MINIMAP CORNER defaults to the top-right")
T.eq(byKey.minimapTransparency.default, 0,
  "MINIMAP TRANSPARENCY defaults to opaque")
T.eq(byKey.minimapSize.default, 100,
  "MINIMAP SIZE defaults to 100 percent")
T.eq(byKey.minimapZoom.default, 100,
  "MINIMAP ZOOM defaults to 100 percent")
T.eq(byKey.minimapBorder.default, "rounded",
  "MAP BORDER defaults to rounded")
T.eq(byKey.tracking.default, false,
  "TRACKING is disabled by default")
T.eq(byKey.encounterTracker.default, false,
  "ENCOUNTER TRACKER is disabled by default")
T.eq(byKey.encounterTrackerCorner.default, "top-right",
  "TRACKER CORNER defaults to the top-right")
T.eq(byKey.encounterTrackerTracked.default, true,
  "SHOW TRACKED is enabled by default")
T.eq(byKey.encounterTrackerLand.default, true,
  "SHOW LAND is enabled by default")
T.eq(byKey.encounterTrackerSurf.default, true,
  "SHOW SURFING is enabled by default")
T.eq(byKey.encounterTrackerFishing.default, true,
  "SHOW FISHING is enabled by default")
T.eq(byKey.pokedexFilters.default, true,
  "POKEDEX FILTERS is enabled by default")
T.eq(byKey.expShare.default, false,
  "EXP SHARE is disabled by default")
T.eq(byKey.autoBattle.default, false,
  "AUTO BATTLE is disabled by default")
T.eq(byKey.autoCatch.default, false,
  "AUTO CATCH is disabled by default")
T.eq(byKey.autoCatchNewOnly.default, false,
  "CATCH NEW ONLY is disabled by default")
T.eq(byKey.autoCatchTarget.default, false,
  "AUTO CATCH TARGET is disabled by default")
T.eq(byKey.autoCatchBall.default, "best",
  "AUTO CATCH BALL defaults to BEST")
T.eq(byKey.showBallCounts.default, true,
  "SHOW BALL COUNTS is enabled by default")
T.eq(byKey.autoStopLowHp.default, false,
  "STOP LOW HP is disabled by default")
T.eq(byKey.autoStopNoBalls.default, false,
  "STOP NO BALLS is disabled by default")
T.eq(byKey.autoStopTarget.default, false,
  "STOP ON TARGET is disabled by default")
T.eq(byKey.autoPauseNewEntry.default, false,
  "PAUSE NEW ENTRY is disabled by default")
T.eq(byKey.autoPauseEvolution.default, false,
  "PAUSE EVOLUTION is disabled by default")
T.eq(byKey.floatingMenus.default, false,
  "FLOATING MENUS is disabled by default")
T.eq(byKey.partyOverviewCorner.default, "bottom-left",
  "PARTY CORNER defaults to the bottom-left")
local expectedVisibility = {
  retainPP = "swapMoves",
  autoRenameTrades = "renameNpcTrades",
  restoreName = "renameAnywhere",
  fieldAbilitiesAuto = "fieldAbilities",
  minimapCorner = "minimap",
  minimapTransparency = "minimap",
  minimapSize = "minimap",
  minimapZoom = "minimap",
  minimapBorder = "minimap",
  tracking = "minimap",
  encounterTrackerCorner = "encounterTracker",
  encounterTrackerTracked = "encounterTracker",
  encounterTrackerLand = "encounterTracker",
  encounterTrackerSurf = "encounterTracker",
  encounterTrackerFishing = "encounterTracker",
  autoCatch = "autoBattle",
  autoCatchNewOnly = { "autoBattle", "autoCatch" },
  autoCatchTarget = { "autoBattle", "autoCatch" },
  autoCatchBall = { "autoBattle", "autoCatch" },
  showBallCounts = { "autoBattle", "autoCatch" },
  autoStopLowHp = "autoBattle",
  autoStopNoBalls = { "autoBattle", "autoCatch" },
  autoStopTarget = { "autoBattle", "autoCatch", "autoCatchTarget" },
  autoPauseNewEntry = "autoBattle",
  autoPauseEvolution = "autoBattle",
  partyOrder = "partyOverview",
  partyOverviewCorner = "partyOverview",
  autoPartyOrder = "partyOverview",
}
visibilityHas = function(condition, key)
  if not condition then return false end
  if condition.key == key and condition.equals == true then return true end
  for _, child in ipairs(condition.all or {}) do
    if visibilityHas(child, key) then return true end
  end
  return false
end
local function isVisible(row, values)
  local function valueFor(key, default)
    local value = values[key]
    if value == nil then
      local source = byKey[key]
      if source then value = source.default end
    end
    if value == nil then return default end
    return value
  end
  local releaseVisibility = run.loader.exports[MOD_ID].optionVisibility
  return releaseVisibility.visible(row and row.visibleIf, valueFor)
end
T.check(not isVisible(byKey.autoCatchTarget,
    { autoBattle = true, autoCatch = false }),
  "AUTO CATCH TARGET remains hidden while catching is disabled")
for optionKey, parents in pairs(expectedVisibility) do
  if type(parents) == "string" then parents = { parents } end
  local condition = byKey[optionKey].visibleIf
  for _, parentKey in ipairs(parents) do
    T.check(visibilityHas(condition, parentKey),
      "dependent option " .. optionKey .. " is conditional on " .. parentKey)
  end
end
end

local exports = run.loader.exports[MOD_ID]
local hooks = run.loader.hooks
T.check(type(exports) == "table", "package exports a feature manifest")
T.eq(#exports.features, 28, "all runtime modules are loaded")
T.check(type(exports.overlayLayout.positions) == "function",
  "shared overlay layout helper is exported")
T.check(type(exports.overlayLayout.trackerRect) == "function",
  "shared overlay tracker geometry helper is exported")
T.check(type(exports.overlayLayout.rememberTracker) == "function",
  "shared overlay tracker geometry can be published")
T.check(type(exports.partyOverview.panelWidth) == "function",
  "party overview exposes its shared panel width")
local layout = exports.overlayLayout.positions({ width = 640, height = 480 }, {
  { id = "map", corner = "top-right", width = 200, height = 140, order = 1 },
  { id = "tracker", corner = "top-right", width = 200, height = 80, order = 2 },
  { id = "party", corner = "top-right", width = 200, height = 62, order = 3 },
})
T.eq(layout.map.x, 428, "shared layout anchors the map to the right")
T.eq(layout.tracker.y, layout.map.y + layout.map.height + 4,
  "shared layout stacks the tracker below the map")
T.eq(layout.party.y, layout.tracker.y + layout.tracker.height + 4,
  "shared layout stacks the party panel after the tracker")
T.eq(layout.party.width, layout.tracker.width,
  "shared layout gives the party and tracker the same width")
local sharedWidth = select(1, exports.overlayLayout.minimapDimensions(
  { width = 640, height = 480 }, 100, 100))
T.eq(exports.partyOverview.panelWidth({ width = 640, height = 480 }), sharedWidth,
  "party overview uses the minimap width")
exports.overlayLayout.rememberTracker({
  x = 428, y = 156, width = sharedWidth, height = 40,
}, { width = 640, height = 480 }, "top-right")
local liveTracker = exports.overlayLayout.trackerRect(
  { width = 640, height = 480 }, "top-right")
T.eq(liveTracker.height, 40,
  "shared layout keeps the tracker height from the current frame")
T.check(type(exports.partyOverview.layout) == "function",
  "party overview exposes its stacked panel layout")
local viewportForPartyLayout = { width = 640, height = 480 }
local function setPartyLayoutOption(key, value)
  run.loader.modOptions[MOD_ID] = run.loader.modOptions[MOD_ID] or {}
  run.loader.modOptions[MOD_ID][key] = value
  run.loader.events:emit("mod.options_changed", {
    mod = MOD_ID, key = key, value = value,
  })
end
setPartyLayoutOption("minimap", true)
setPartyLayoutOption("encounterTracker", true)
setPartyLayoutOption("partyOverview", true)
setPartyLayoutOption("partyOverviewCorner", "top-right")
exports.overlayLayout.rememberTracker({
  x = 428, y = 156, width = sharedWidth, height = 40,
}, viewportForPartyLayout, "top-right")
local partyPanel = exports.partyOverview.layout(viewportForPartyLayout)
local _, mapHeight = exports.overlayLayout.minimapDimensions(
  viewportForPartyLayout, 100, 100)
T.eq(partyPanel.width, sharedWidth,
  "party overview keeps the shared width in its live layout")
T.eq(partyPanel.y, exports.overlayLayout.margin + mapHeight
  + exports.overlayLayout.gap + 40 + exports.overlayLayout.gap,
  "party overview follows the current tracker height in the top-right")
setPartyLayoutOption("partyOverviewCorner", "bottom-left")
setPartyLayoutOption("partyOverview", false)
setPartyLayoutOption("encounterTracker", false)
setPartyLayoutOption("minimap", false)
exports.overlayLayout.clearTracker()
local splitLayout = exports.overlayLayout.positions({ width = 640, height = 480 }, {
  { id = "map", corner = "bottom-left", width = 200, height = 140, order = 1 },
  { id = "tracker", corner = "top-right", width = 200, height = 80, order = 2 },
  { id = "party", corner = "bottom-left", width = 152, height = 62, order = 3 },
})
T.check(splitLayout.party.y + splitLayout.party.height + 4
  <= splitLayout.map.y,
  "shared layout stacks panels in a shared bottom corner")
T.check(type(exports.partyOverview.snapshot) == "function",
  "PARTY OVERVIEW helper remains exported")
T.check(type(exports.eggTracker.snapshot) == "function",
  "EGG TRACKER helper remains exported")
T.check(type(exports.expShare.enabled) == "function",
  "EXP SHARE helper remains exported")
T.check(type(exports.autoBattle.chooseMove) == "function",
  "AUTO BATTLE move chooser is exported")
T.check(type(exports.autoBattle.chooseCatchAction) == "function",
  "AUTO CATCH chooser is exported")
T.check(type(exports.autoBattle.catchBallMode) == "function",
  "AUTO CATCH BALL mode helper is exported")
T.check(type(exports.autoCatchTarget.matches) == "function",
  "AUTO CATCH TARGET helper remains exported")
local catchTargetSchema = byKey.autoCatchTarget
T.check(visibilityHas(catchTargetSchema.visibleIf, "autoBattle")
  and visibilityHas(catchTargetSchema.visibleIf, "autoCatch"),
  "AUTO CATCH TARGET is hidden until AUTO BATTLE and AUTO CATCH are enabled")
local catchNewSchema = byKey.autoCatchNewOnly
T.check(visibilityHas(catchNewSchema.visibleIf, "autoBattle")
  and visibilityHas(catchNewSchema.visibleIf, "autoCatch"),
  "CATCH NEW ONLY is hidden until AUTO BATTLE and AUTO CATCH are enabled")
local catchBallSchema = byKey.autoCatchBall
T.check(visibilityHas(catchBallSchema.visibleIf, "autoBattle")
  and visibilityHas(catchBallSchema.visibleIf, "autoCatch"),
  "AUTO CATCH BALL is hidden until AUTO BATTLE and AUTO CATCH are enabled")
T.eq(#catchBallSchema.choices, 3,
  "AUTO CATCH BALL exposes three ball-selection choices")
T.check(byKey.floatingMenus.visibleIf == nil,
  "FLOATING MENUS is always available")
T.check(byKey.pokedexFilters.visibleIf == nil,
  "POKEDEX FILTERS is always available")
T.check(type(exports.moveEffectiveness.moveEffectiveness) == "function",
  "native effectiveness helper remains exported")
T.check(type(exports.moveEffectiveness.effectivenessLabel) == "function",
  "native effectiveness label helper remains exported")
T.check(type(exports.moveEffectiveness.statusColor) == "function",
  "native effectiveness color helper remains exported")
local superR, superG, superB = exports.moveEffectiveness.statusColor("SUPER")
T.check(superG > superR and superG > superB,
  "SUPER effectiveness uses a green status color")
local weakR, weakG, weakB = exports.moveEffectiveness.statusColor("WEAK")
T.check(weakR > weakG and weakR > weakB,
  "WEAK effectiveness uses a red status color")
T.check(type(exports.experienceBar.progress) == "function",
  "experience bar progress helper is exported")
T.check(type(exports.experienceBar.geometry) == "function",
  "experience bar geometry helper is exported")
T.check(type(exports.caughtIndicator.caught) == "function",
  "caught marker detection helper is exported")
T.check(type(exports.caughtIndicator.markerAt) == "function",
  "caught marker placement helper is exported")
T.check(type(exports.voxelHud.mapRect) == "function",
  "dramatic shape mapping helper is exported")
T.check(type(exports.bagCategories.categories) == "table",
  "bag category helper remains exported")
T.check(type(exports.bagCategories.matchesSearch) == "function",
  "bag search helper is exported")
T.check(type(exports.bagCategories.sortOrder) == "function",
  "bag auto-sort helper is exported")
T.check(type(exports.bagCategories.quickCategory) == "function",
  "quick-use shortcut helper is exported")
T.check(type(exports.autoBattle.ballCounts) == "function",
  "AUTO CATCH ball-count helper is exported")
T.check(type(exports.autoBattle.formatBallCounts) == "function",
  "AUTO CATCH ball breakdown formatter is exported")
T.check(type(exports.tracking.current) == "function",
  "tracking current-species helper is exported")
T.check(type(exports.tracking.toggle) == "function",
  "tracking toggle helper is exported")
T.check(type(exports.encounterTracker.collect) == "function",
  "encounter tracker collection helper is exported")
T.check(type(exports.encounterTracker.format) == "function",
  "encounter tracker formatter is exported")
T.check(type(exports.encounterRate.scale) == "function",
  "encounter rate scaling helper is exported")
T.check(type(exports.skipCenterDialogue.shouldSkip) == "function",
  "SKIP CENTER TALK helper is exported")
run.loader.modOptions[MOD_ID] = { skipCenterDialogue = true }
T.check(hooks:call("world.nurse_heal.confirmation", function() return false end,
    {}, { kind = "nurse_heal", generation = 1 }) == true,
  "SKIP CENTER TALK accepts the Gen 1 nurse prompt")
T.check(hooks:call("world.nurse_heal.confirmation", function() return false end,
    {}, { kind = "unrelated_yes_no", generation = 1 }) == false,
  "SKIP CENTER TALK leaves unrelated questions alone")
run.loader.modOptions[MOD_ID] = nil
T.eq(exports.encounterRate.scale(25, 1), 25,
  "normal ENCOUNTER RATE preserves the native rate")
T.eq(exports.encounterRate.scale(25, 4), 100,
  "ENCOUNTER RATE multiplies the native rate")
T.eq(exports.encounterRate.scale(200, 2), 256,
  "ENCOUNTER RATE caps guaranteed encounters at the byte maximum")
T.check(type(exports.pokedexFilters.filterRows) == "function",
  "Pokedex filter helper is exported")
T.check(type(exports.minimap.geometry) == "function",
  "minimap geometry helper is exported")
T.check(type(exports.minimap.corner) == "function",
  "minimap corner helper is exported")
T.check(type(exports.minimap.transparency) == "function",
  "minimap transparency helper is exported")
T.check(type(exports.minimap.size) == "function",
  "minimap size helper is exported")
T.check(type(exports.minimap.zoom) == "function",
  "minimap zoom helper is exported")
T.check(type(exports.minimap.border) == "function",
  "minimap border-style helper is exported")
T.check(type(exports.minimap.colors) == "function",
  "minimap color helper is exported")
T.check(type(exports.minimap.freeRoam) == "function",
  "minimap free-roam gate is exported")
T.check(type(exports.floatingMenus.enabled) == "function",
  "FLOATING MENUS helper remains exported")
T.eq(exports.minimap.position, "top-right",
  "minimap keeps the top-right position as its default")

run.loader.modOptions[MOD_ID] = { bagCategories = true }
local bagScreen = run.loader.content.screens:get("BagMenu")
local battleBagGame = {
  data = Data,
  save = { money = 0, inventory = { FIX_BALL = 1 }, bagOrder = { "FIX_BALL" } },
}
local battleBag = bagScreen.new(battleBagGame, { battle = {} })
T.check(battleBag.items ~= nil and battleBag.title == "ITEMS",
  "BAG CATEGORIES keeps the native bag screen during battle")
run.loader.modOptions[MOD_ID] = nil
T.eq(exports.minimap.corner(), "top-right",
  "minimap reports its default selected corner")
T.eq(exports.minimap.transparency(), 0,
  "minimap reports its default transparency")
T.eq(exports.minimap.size(), 100,
  "minimap reports its default size")
T.eq(exports.minimap.zoom(), 100,
  "minimap reports its default zoom")
T.eq(exports.minimap.border(), "rounded",
  "minimap reports its default rounded border")
T.eq(exports.minimap.transparency(0 / 0), 0,
  "minimap rejects a NaN transparency value")
T.eq(exports.minimap.size(0 / 0), 100,
  "minimap rejects a NaN size value")
T.eq(exports.minimap.zoom(0 / 0), 100,
  "minimap rejects a NaN zoom value")
T.eq(exports.minimap.transparency(math.huge), 0,
  "minimap rejects an infinite transparency value")
T.eq(exports.minimap.size(math.huge), 100,
  "minimap rejects an infinite size value")
T.eq(exports.minimap.zoom(-math.huge), 100,
  "minimap rejects an infinite zoom value")

-- TRACKING: the Pokédex entry action is added only while the feature is on,
-- and selecting it persists one target at a time.
local trackingGame = { data = { pokemon = {
  FIXMON_A = { name = "FIXMON A" },
} } }
run.loader.modOptions[MOD_ID] = { minimap = true, tracking = false }
local trackingEntries = { { label = "DATA" }, { label = "QUIT" } }
local plainEntries = hooks:call("ui.pokedex.actions", function(_, entries)
  return entries
end, trackingGame, trackingEntries, "FIXMON_A")
T.eq(#plainEntries, 2, "disabled TRACKING leaves the Pokédex menu unchanged")
run.loader.modOptions[MOD_ID].tracking = true
local trackedEntries = hooks:call("ui.pokedex.actions", function(_, entries)
  return entries
end, trackingGame, { { label = "DATA" }, { label = "QUIT" } }, "FIXMON_A")
T.eq(trackedEntries[2].label, "TRACK",
  "enabled TRACKING adds a TRACK action before QUIT")
local yellowTrackedEntries = hooks:call("ui.pokedex.actions", function(_, entries)
  return entries
end, trackingGame,
  { { label = "DATA" }, { label = "PRNT" }, { label = "QUIT" } },
  "FIXMON_A")
T.eq(yellowTrackedEntries[2].label, "TRACK",
  "TRACK stays before Yellow's PRNT row")
run.loader.modOptions[MOD_ID].minimap = false
plainEntries = hooks:call("ui.pokedex.actions",
  function(_, entries) return entries end, trackingGame,
  { { label = "DATA" }, { label = "QUIT" } }, "FIXMON_A")
T.eq(#plainEntries, 2,
  "TRACKING stays inactive when its MINIMAP parent is disabled")
run.loader.modOptions[MOD_ID].minimap = true
trackedEntries[2].onSelect()
T.eq(exports.tracking.current(trackingGame), "FIXMON_A",
  "TRACK stores the selected species")
local untrackEntries = hooks:call("ui.pokedex.actions", function(_, entries)
  return entries
end, trackingGame, { { label = "DATA" }, { label = "QUIT" } }, "FIXMON_A")
T.eq(untrackEntries[2].label, "UNTRACK",
  "the same Pokédex entry changes the action to UNTRACK")
untrackEntries[2].onSelect()
T.eq(exports.tracking.current(trackingGame), nil,
  "UNTRACK clears the selected species")
-- Keep the large minimap fixture's locals scoped to this block. Lua 5.1 has
-- a 200-local limit per function, and this consolidated regression file also
-- covers the battle HUD and field-move fixtures below it.
local function checkMinimapRuntime(MinimapGame)
local Menu = require("src.ui.Menu")
local sideMenu = Menu.new({ data = {} }, {
  { label = "DATA" }, { label = "CRY" }, { label = "AREA" },
  { label = "TRACK" }, { label = "PRNT" }, { label = "QUIT" },
}, { tx = 12, ty = 8, tw = 8, maxVisible = 4 })
T.eq(sideMenu.th, 10,
  "Pokédex side menu stays within the screen with four visible rows")
T.eq(sideMenu.maxVisible, 4,
  "Pokédex side menu scrolls extra actions")
run.loader.modOptions[MOD_ID] = nil
local paletteColors = exports.minimap.colors({ colors = {
  { 255, 240, 220 }, { 220, 160, 120 },
  { 120, 70, 50 }, { 20, 10, 5 },
} })
T.eq(paletteColors["0"][1], 1,
  "minimap uses the active palette's lightest shade")
T.eq(paletteColors["3"][3], 5 / 255,
  "minimap uses the active palette's darkest shade")

local minimapOverview = {
  mapId = "FIX_TOWN", width = 4, height = 3,
  rows = { ".+..", "~ ..", "...." },
  markers = { { kind = "warp", x = 1, y = 0 } },
}
local minimapGeo = exports.minimap.geometry(minimapOverview, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.check(minimapGeo.x + minimapGeo.width <= 160,
  "minimap stays inside the right edge of the playfield")
T.eq(minimapGeo.y, 12, "minimap is inset from the top-right window corner")
T.check(minimapGeo.mapWidth >= 120 and minimapGeo.mapHeight >= 90,
  "minimap uses a larger zoomed-in viewport")
T.check(minimapGeo.mapWidth > 0 and minimapGeo.mapHeight > 0,
  "minimap geometry includes a visible map area")
T.check(exports.minimap.geometry({
  width = 0, height = 0, tileWidth = 4, tileHeight = 3,
  tileRows = { "....", "....", "...." },
}, { width = 800, height = 600 }).cellWidth < math.huge,
  "minimap geometry rejects a zero logical map size")
T.check(exports.minimap.geometry(minimapOverview, {
  width = 0 / 0, height = 0 / 0,
}).width <= 160,
  "minimap geometry falls back from a non-finite viewport")
local largeViewport = { width = 800, height = 600 }
local topLeftGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "top-left")
local bottomRightGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "bottom-right")
local smallGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "top-left", 50)
local largeGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "top-left", 150)
local zoomedOutGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "top-left", 100, 50)
local zoomedInGeo = exports.minimap.geometry(minimapOverview, largeViewport,
  nil, "top-left", 100, 200)
T.eq(topLeftGeo.x, 12, "top-left minimap uses the left inset")
T.eq(topLeftGeo.y, 12, "top-left minimap uses the top inset")
T.eq(bottomRightGeo.x + bottomRightGeo.width, 800 - 12,
  "bottom-right minimap is attached to the right edge")
T.eq(bottomRightGeo.y + bottomRightGeo.height, 600 - 12,
  "bottom-right minimap is attached to the bottom edge")
T.check(smallGeo.width < topLeftGeo.width and smallGeo.height < topLeftGeo.height,
  "a smaller MINIMAP SIZE reduces the panel dimensions")
T.check(largeGeo.width > topLeftGeo.width and largeGeo.height > topLeftGeo.height,
  "a larger MINIMAP SIZE increases the panel dimensions")
T.check(zoomedOutGeo.viewSourceWidth > topLeftGeo.viewSourceWidth,
  "lower MINIMAP ZOOM shows more map cells")
T.check(zoomedInGeo.viewSourceWidth < topLeftGeo.viewSourceWidth,
  "higher MINIMAP ZOOM shows fewer map cells")
run.loader.modOptions[MOD_ID] = {
  minimapCorner = "bottom-left",
  minimapTransparency = 65,
  minimapSize = 135,
  minimapZoom = 135,
  minimapBorder = "square",
}
T.eq(exports.minimap.corner(), "bottom-left",
  "minimap corner follows the saved option")
T.eq(exports.minimap.transparency(), 65,
  "minimap transparency follows the saved option")
T.eq(exports.minimap.size(), 135,
  "minimap size follows the saved option")
T.eq(exports.minimap.zoom(), 135,
  "minimap zoom follows the saved option")
T.eq(exports.minimap.border(), "square",
  "minimap border follows the saved option")
run.loader.modOptions[MOD_ID] = nil

-- MINIMAP: the render hook is quiet when disabled and draws the current
-- overworld snapshot when enabled.  Use the engine singleton the public
-- WorldAPI facade resolves, just as a live render frame does.
local MinimapWorldAPI = require("src.world.WorldAPI")
local oldMapOverview = MinimapWorldAPI.mapOverview
local mapOverviewCalls = 0
MinimapWorldAPI.mapOverview = function(...)
  mapOverviewCalls = mapOverviewCalls + 1
  return oldMapOverview(...)
end
local oldMinimapStack, oldMinimapWorld = MinimapGame.stack, MinimapGame.overworld
local oldMinimapSave, oldMinimapData = MinimapGame.save, MinimapGame.data
local minimapMap = {
  id = "FIX_TOWN", widthCells = 4, heightCells = 3,
  def = { palette = "FIX_TOWN_PALETTE",
    warps = { { x = 3, y = 1 } }, objects = {} },
}
function minimapMap:isWarpTileCell(x, y) return x == 3 and y == 1 end
function minimapMap:isWaterCell() return false end
function minimapMap:isWalkableCell() return true end
local minimapWorld = {
  isOverworld = true, map = minimapMap,
  player = { cellX = 2, cellY = 1, facing = "right" },
  objectVisible = function() return true end,
  paletteNameFor = function() return "FIX_TOWN_PALETTE" end,
}
MinimapGame.stack = {
  states = { minimapWorld },
  top = function(self) return self.states[#self.states] end,
}
MinimapGame.overworld = minimapWorld
MinimapGame.save = {}
MinimapGame.data = {
  field = {},
  pokemon = { FIXMON_A = { name = "FIXMON A" } },
  encounters = {
    FIX_TOWN = { grass = { slots = { { species = "FIXMON_A" } } } },
  },
}
local MinimapPaletteFX = require("src.render.PaletteFX")
local oldMinimapPal = MinimapPaletteFX.pal
local fixturePalette = {
  { 250, 220, 180 }, { 200, 150, 100 },
  { 100, 70, 45 }, { 20, 12, 8 },
}
MinimapPaletteFX.pal = function(data, name)
  if name == "FIX_TOWN_PALETTE" then return fixturePalette end
  return oldMinimapPal(data, name)
end
local oldMinimapRect = love.graphics.rectangle
local oldMinimapColor = love.graphics.setColor
local oldMinimapLine = love.graphics.line
local minimapRects = 0
local minimapAlphas = {}
local minimapLines = 0
local minimapRectangleCalls = {}
local currentMinimapColor = { 1, 1, 1, 1 }
love.graphics.rectangle = function(mode, x, y, width, height, ...)
  minimapRects = minimapRects + 1
  minimapRectangleCalls[#minimapRectangleCalls + 1] = {
    mode = mode, x = x, y = y, width = width, height = height,
    radius = select(1, ...), color = currentMinimapColor,
  }
  return oldMinimapRect(mode, x, y, width, height, ...)
end
love.graphics.setColor = function(r, g, b, a)
  currentMinimapColor = { r, g, b, a }
  minimapAlphas[#minimapAlphas + 1] = a
  return oldMinimapColor(r, g, b, a)
end
love.graphics.line = function(...)
  minimapLines = minimapLines + 1
  if oldMinimapLine then return oldMinimapLine(...) end
end
run.loader.modOptions[MOD_ID] = { minimap = false }
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
local minimapRectsWhenOff = minimapRects
run.loader.modOptions[MOD_ID].minimap = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = true,
})
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.eq(minimapRectsWhenOff, 0,
  "disabled MINIMAP does not draw through render.hud")
T.check(minimapRects > minimapRectsWhenOff,
  "enabled MINIMAP draws the overworld snapshot")
local hasFixturePalette = false
for _, rectangle in ipairs(minimapRectangleCalls) do
  local color = rectangle.color
  if color and math.abs(color[1] - fixturePalette[1][1] / 255) < 0.001
      and math.abs(color[2] - fixturePalette[1][2] / 255) < 0.001 then
    hasFixturePalette = true
    break
  end
end
T.check(hasFixturePalette,
  "MINIMAP uses the active overworld palette instead of the green fallback")
T.eq(minimapLines, 0, "MINIMAP has no compass arrow")
local overviewCallsAfterFirstDraw = mapOverviewCalls
run.loader.events:emit("world.stepped", { mapId = "FIX_TOWN", x = 3, y = 1 })
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.eq(mapOverviewCalls, overviewCallsAfterFirstDraw,
  "MINIMAP moves its camera without rebuilding unchanged map terrain")
run.loader.events:emit("world.interacted", {
  mapId = "FIX_TOWN", x = 3, y = 1, kind = "item",
})
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.eq(mapOverviewCalls, overviewCallsAfterFirstDraw + 1,
  "MINIMAP still refreshes terrain and markers after an interaction")
run.loader.events:emit("world.block_replaced", {
  mapId = "FIX_TOWN", bx = 1, by = 1, block = 2,
})
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.eq(mapOverviewCalls, overviewCallsAfterFirstDraw + 2,
  "MINIMAP refreshes terrain after a native block replacement")
local function hasPanelRectangle(first, expected)
  for index = first, #minimapRectangleCalls do
    local rectangle = minimapRectangleCalls[index]
    if rectangle.mode == "fill" and rectangle.x == expected.x
        and rectangle.y == expected.y and rectangle.width == expected.width
        and rectangle.height == expected.height
        and rectangle.radius == expected.radius then
      return true
    end
  end
  return false
end
local roundedOuter = {
  x = minimapGeo.x, y = minimapGeo.y,
  width = minimapGeo.width, height = minimapGeo.height, radius = 9,
}
local roundedInner = {
  x = minimapGeo.x + 1, y = minimapGeo.y + 1,
  width = minimapGeo.width - 2, height = minimapGeo.height - 2, radius = 8,
}
T.check(hasPanelRectangle(1, roundedOuter),
  "MINIMAP ROUNDED draws one complete outer frame shape")
T.check(hasPanelRectangle(1, roundedInner),
  "MINIMAP ROUNDED insets the panel to leave a continuous border ring")
local boundsRows = {}
for index = 1, 100 do boundsRows[index] = string.rep(".", 100) end
local boundsOverview = { width = 100, height = 100, rows = boundsRows }
local boundsViewport = { width = 800, height = 600 }
local boundsGeo = exports.minimap.geometry(boundsOverview, boundsViewport)
local boundsStart = #minimapRectangleCalls
exports.minimap.draw(boundsOverview, nil, boundsViewport)
local checkedMapRows = 0
for index = boundsStart + 1, #minimapRectangleCalls do
  local rectangle = minimapRectangleCalls[index]
  if rectangle.mode == "fill" and rectangle.x >= boundsGeo.mapX
      and rectangle.y >= boundsGeo.mapY
      and rectangle.y < boundsGeo.mapY + boundsGeo.mapHeight
      and rectangle.height == boundsGeo.scale then
    checkedMapRows = checkedMapRows + 1
    T.check(rectangle.x + rectangle.width
        <= boundsGeo.mapX + boundsGeo.mapWidth,
      "MINIMAP terrain row stays inside the framed map viewport")
  end
end
T.check(checkedMapRows > 0,
  "MINIMAP frame-bound regression checks rendered terrain rows")
do
  local rowReads = 0
  local proxyRows = setmetatable({}, {
    __index = function(_, index)
      rowReads = rowReads + 1
      if index <= 40 then return string.rep(".+", 20) end
    end,
  })
  local cachedRowsOverview = {
    width = 40, height = 40, rows = proxyRows,
  }
  exports.minimap.draw(cachedRowsOverview, nil, boundsViewport)
  local firstPassReads = rowReads
  exports.minimap.draw(cachedRowsOverview, nil, boundsViewport)
  T.eq(rowReads, firstPassReads,
    "MINIMAP reuses compiled terrain runs across unchanged frames")
end
run.loader.modOptions[MOD_ID].minimapBorder = "square"
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimapBorder", value = "square",
})
local squareFrameStart = #minimapRectangleCalls
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
local squareOuter = {
  x = minimapGeo.x, y = minimapGeo.y,
  width = minimapGeo.width, height = minimapGeo.height, radius = 0,
}
local squareInner = {
  x = minimapGeo.x + 1, y = minimapGeo.y + 1,
  width = minimapGeo.width - 2, height = minimapGeo.height - 2, radius = 0,
}
T.check(hasPanelRectangle(squareFrameStart + 1, squareOuter),
  "MINIMAP SQUARE draws one complete outer frame shape")
T.check(hasPanelRectangle(squareFrameStart + 1, squareInner),
  "MINIMAP SQUARE insets the panel to leave a continuous border ring")
run.loader.modOptions[MOD_ID].minimapBorder = "off"
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimapBorder", value = "off",
})
local borderOffStart = #minimapRectangleCalls
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144,
})
T.check(hasPanelRectangle(borderOffStart + 1, roundedOuter),
  "MINIMAP OFF retains the rounded panel background")
T.check(not hasPanelRectangle(borderOffStart + 1, roundedInner),
  "MINIMAP OFF omits the inset that creates the border ring")
run.loader.modOptions[MOD_ID].minimapBorder = "rounded"
run.loader.modOptions[MOD_ID].minimapCorner = "bottom-left"
run.loader.modOptions[MOD_ID].minimapTransparency = 50
run.loader.modOptions[MOD_ID].minimapZoom = 150
for key, value in pairs({
  minimapBorder = "rounded", minimapCorner = "bottom-left",
  minimapTransparency = 50, minimapZoom = 150,
}) do
  run.loader.events:emit("mod.options_changed", {
    mod = MOD_ID, key = key, value = value,
  })
end
minimapAlphas = {}
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 600,
})
local hasHalfOpacity = false
for _, alpha in ipairs(minimapAlphas) do
  if alpha and alpha > 0.49 and alpha < 0.51 then
    hasHalfOpacity = true
    break
  end
end
T.check(hasHalfOpacity,
  "MINIMAP TRANSPARENCY applies the requested 50 percent opacity")

local TrackingFont = require("src.render.Font")
local oldTrackingFontDraw = TrackingFont.draw
local trackingHint
TrackingFont.draw = function(text, x, y)
  trackingHint = text
  return oldTrackingFontDraw(text, x, y)
end
run.loader.modOptions[MOD_ID].tracking = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "tracking", value = true,
})
exports.tracking.toggle(MinimapGame, "FIXMON_A")
local trackingRectStart = #minimapRectangleCalls
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 600,
})
T.eq(trackingHint, "Tracking FIXMON A",
  "tracked species appears as a minimap hint")
local hasTrackingHighlight = false
for index = trackingRectStart + 1, #minimapRectangleCalls do
  local rectangle = minimapRectangleCalls[index]
  if rectangle.mode == "line" and rectangle.width > 20
      and rectangle.width < 100 then
    hasTrackingHighlight = true
    break
  end
end
T.check(hasTrackingHighlight,
  "tracked habitat is visibly outlined on the minimap")
TrackingFont.draw = oldTrackingFontDraw
exports.tracking.toggle(MinimapGame, "FIXMON_A")
run.loader.modOptions[MOD_ID].tracking = nil

local oldEncounterFontDraw = TrackingFont.draw
local encounterHeader, encounterTextColor, encounterLandText
TrackingFont.draw = function(text, x, y)
  if text == "ENCOUNTERS ANY TIME" then
    encounterHeader = text
    encounterTextColor = currentMinimapColor
  end
  if text:find("GRASS", 1, true) then
    encounterLandText = text
    encounterTextColor = currentMinimapColor
  end
  return oldEncounterFontDraw(text, x, y)
end
run.loader.modOptions[MOD_ID].encounterTracker = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "encounterTracker", value = true,
})
run.loader.modOptions[MOD_ID].minimapCorner = "top-right"
local originalEncounterFormat = exports.encounterTracker.format
local encounterFormatCalls = 0
exports.encounterTracker.format = function(...)
  encounterFormatCalls = encounterFormatCalls + 1
  return originalEncounterFormat(...)
end
local encounterRectStart = #minimapRectangleCalls
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 600,
})
T.eq(encounterHeader, nil,
  "Gen 1 ENCOUNTER TRACKER omits the time scope heading")
T.check(encounterLandText ~= nil,
  "Gen 1 ENCOUNTER TRACKER still draws its land section")
T.check(encounterTextColor and encounterTextColor[1] < 0.1
    and encounterTextColor[2] < 0.1 and encounterTextColor[3] < 0.1,
  "ENCOUNTER TRACKER uses visible black font ink")
local hasReadableTrackerPaper = false
for index = encounterRectStart + 1, #minimapRectangleCalls do
  local rectangle = minimapRectangleCalls[index]
  local color = rectangle.color or {}
  local luminance = (color[1] or 0) * 0.2126
    + (color[2] or 0) * 0.7152 + (color[3] or 0) * 0.0722
  if rectangle.mode == "fill" and rectangle.y > 180
      and rectangle.width > 200 and luminance > 0.6 then
    hasReadableTrackerPaper = true
    break
  end
end
T.check(hasReadableTrackerPaper,
  "ENCOUNTER TRACKER uses a light panel behind the extracted black font")
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 600,
})
T.eq(encounterFormatCalls, 1,
  "ENCOUNTER TRACKER reuses formatted lines while its model is unchanged")
run.loader.modOptions[MOD_ID].minimap = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = false,
})
local independentTrackerStart = #minimapRectangleCalls
encounterLandText = nil
hooks:call("render.hud", function() end, MinimapGame, {
  gameX = 0, gameY = 0, gameWidth = 800, gameHeight = 600,
})
T.check(encounterLandText ~= nil and #minimapRectangleCalls > independentTrackerStart,
  "ENCOUNTER TRACKER renders when MINIMAP is disabled")
run.loader.modOptions[MOD_ID].minimap = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = true,
})
exports.encounterTracker.format = originalEncounterFormat
TrackingFont.draw = oldEncounterFontDraw
run.loader.modOptions[MOD_ID].encounterTracker = nil
love.graphics.rectangle = oldMinimapRect
love.graphics.setColor = oldMinimapColor
love.graphics.line = oldMinimapLine
MinimapPaletteFX.pal = oldMinimapPal
MinimapGame.stack, MinimapGame.overworld = oldMinimapStack, oldMinimapWorld
MinimapGame.save, MinimapGame.data = oldMinimapSave, oldMinimapData
MinimapWorldAPI.mapOverview = oldMapOverview
run.loader.modOptions[MOD_ID] = nil
end
withGameFacade(checkMinimapRuntime)

require("src.battle.TypeChart").load(Data)

local Growth = require("src.pokemon.Growth")
local xpDef = Data.pokemon.FIXMON_A
local xpLevel = 5
local xpStart = Growth.expForLevel(xpDef.growthRate, xpLevel, Data.growth_rates)
local xpNext = Growth.expForLevel(xpDef.growthRate, xpLevel + 1, Data.growth_rates)
local xpBattle = {
  data = Data,
  player = {
    mon = {
      species = "FIXMON_A", level = xpLevel,
      exp = xpStart + math.floor((xpNext - xpStart) / 2),
    },
    def = xpDef,
  },
  isWideBattleLayout = function() return false end,
}
T.eq(exports.experienceBar.progress(xpBattle),
  math.floor((xpNext - xpStart) / 2) / (xpNext - xpStart),
  "XP bar reports progress within the current level")
xpBattle.player.mon.exp = 0 / 0
T.eq(exports.experienceBar.progress(xpBattle), 0,
  "XP bar treats a non-finite experience value as the level baseline")
xpBattle.player.mon.exp = xpStart + math.floor((xpNext - xpStart) / 2)
xpBattle.player.mon.level = math.huge
T.eq(exports.experienceBar.progress(xpBattle), nil,
  "XP bar ignores a non-finite level")
xpBattle.player.mon.level = xpLevel
Data.growth_rates.BROKEN_GROWTH_RATE = {
  expForLevel = function() error("broken growth curve") end,
}
xpBattle.player.def = { growthRate = "BROKEN_GROWTH_RATE" }
T.eq(exports.experienceBar.progress(xpBattle), nil,
  "XP bar contains a failing custom growth curve")
xpBattle.player.def = xpDef
Data.growth_rates.BROKEN_GROWTH_RATE = nil
T.eq(exports.experienceBar.geometry(xpBattle).y, 89,
  "XP bar fallback uses the lower classic HUD row")
T.eq(exports.experienceBar.geometry(xpBattle).width, 64,
  "classic XP bar fills the lower HUD slot")
xpBattle.isWideBattleLayout = function() return true end
T.eq(exports.experienceBar.geometry(xpBattle).width, 96,
  "wide XP bar fills the wider player HUD slot")
T.eq(exports.experienceBar.geometry(xpBattle).y, 97,
  "wide fallback XP bar clears the panel box")
local hudAnchor = { x = 184, y = 56, bottomY = 96,
  paletteSpace = "final" }
local anchored = exports.experienceBar.geometry(xpBattle, hudAnchor)
T.eq(anchored.x, 192, "wide XP bar is anchored to the player HUD")
T.eq(anchored.width, 96, "wide XP bar fills the lower HUD slot")
T.eq(anchored.y, 97, "wide XP bar sits below the panel's border edge")
local bareWideAnchor = { x = 184, y = 56, paletteSpace = "final" }
local bareWide = exports.experienceBar.geometry(xpBattle, bareWideAnchor)
T.eq(bareWide.y, 97, "wide XP bar clears the closed panel box without bottomY")
local movedAnchor = { x = 200, y = 64, bottomY = 96,
  paletteSpace = "final" }
local moved = exports.experienceBar.geometry(xpBattle, movedAnchor)
T.eq(moved.x, 208, "XP bar follows a moved player HUD horizontally")
T.eq(moved.y, 97, "XP bar follows the HUD lower edge vertically")

local drawnRects, drawnClears, drawnColors = {}, {}, {}
local hudTrace = {}
local removeHudMover = hooks:wrap("battle.player_hud", function(next, battle, anchor)
  hudTrace[#hudTrace + 1] = "mover-before"
  local result = next(battle, anchor)
  hudTrace[#hudTrace + 1] = "mover-after"
  return result
end, 0, "test_hud_mover")
local originalRectangle = love.graphics.rectangle
local originalClear = love.graphics.clear
local originalSetColor = love.graphics.setColor
love.graphics.rectangle = function(mode, x, y, width, height)
  drawnRects[#drawnRects + 1] = {
    mode = mode, x = x, y = y, width = width, height = height,
  }
  hudTrace[#hudTrace + 1] = "xp-bar"
  return originalRectangle(mode, x, y, width, height)
end
love.graphics.clear = function(r, g, b, a)
  drawnClears[#drawnClears + 1] = { r = r, g = g, b = b, a = a }
  return originalClear(r, g, b, a)
end
love.graphics.setColor = function(r, g, b, a)
  drawnColors[#drawnColors + 1] = { r = r, g = g, b = b, a = a }
  return originalSetColor(r, g, b, a)
end
hooks:call("battle.player_hud", function() end, xpBattle, hudAnchor)
love.graphics.rectangle = originalRectangle
love.graphics.clear = originalClear
love.graphics.setColor = originalSetColor
removeHudMover()
T.eq(#drawnRects, 3, "enabled XP BAR draws the native-style track and fill")
local xpFillRect = drawnRects[#drawnRects]
T.check(xpFillRect.x > 192,
  "wide XP bar fill starts inside the native bar slot")
T.eq(xpFillRect.x + xpFillRect.width, 288,
  "wide XP bar ends at the native HP fill edge")
T.eq(xpFillRect.y, 97, "wide XP bar clears the panel's border edge")
T.check(#drawnClears == 0 or drawnClears[1].a == 0,
  "XP BAR does not erase wide HUD pixels with an opaque clear")
local xpColor = drawnColors[#drawnColors - 1]
T.check(xpColor.b > xpColor.g and xpColor.b > xpColor.r,
  "XP BAR fill is blue")
T.eq(table.concat(hudTrace, ","),
  "mover-before,xp-bar,xp-bar,xp-bar,mover-after",
  "XP BAR draws inside a HUD mover's active wrapper")

-- A classic-layout HUD mover translates the panel around its wrapper.  The
-- bar must ride that transform: the overlay replay applies the transform
-- captured inside the HUD hook and clips its transparent clear to the
-- screen-space rect, while the fill keeps drawing in the panel's own space.
xpBattle.isWideBattleLayout = function() return false end
local classicalAnchor = { x = 80, y = 56, bottomY = 88, paletteSpace = "final" }
local trans = { x = 0, y = 0 }
local fakeTransform = {
  transformPoint = function(_, x, y) return x + trans.x, y + trans.y end,
  transformDirection = function(_, w, h) return w, h end,
}
local xpApplied, xpScissors, xpPushes, xpPops = {}, {}, 0, 0
local xpRects, xpClears, xpColors = {}, {}, {}
local originalGetTransform = love.graphics.getTransform
local originalApplyTransform = love.graphics.applyTransform
local originalTranslate = love.graphics.translate
local originalXpPush = love.graphics.push
local originalXpPop = love.graphics.pop
local originalSetScissor = love.graphics.setScissor
love.graphics.getTransform = function() return fakeTransform end
love.graphics.applyTransform = function(t)
  xpApplied[#xpApplied + 1] = t
end
love.graphics.translate = function(x, y) trans.x, trans.y = x, y end
love.graphics.push = function() xpPushes = xpPushes + 1 end
love.graphics.pop = function() xpPops = xpPops + 1 end
love.graphics.setScissor = function(x, y, w, h)
  if y ~= nil then xpScissors[#xpScissors + 1] = { x, y, w, h } end
end
local xpOriginalRectangle = love.graphics.rectangle
local xpOriginalClear = love.graphics.clear
local xpOriginalColor = love.graphics.setColor
love.graphics.rectangle = function(mode, x, y, width, height)
  xpRects[#xpRects + 1] = { mode, x, y, width, height }
  return xpOriginalRectangle(mode, x, y, width, height)
end
love.graphics.clear = function(r, g, b, a)
  xpClears[#xpClears + 1] = { r, g, b, a }
  return xpOriginalClear(r, g, b, a)
end
love.graphics.setColor = function(r, g, b, a)
  xpColors[#xpColors + 1] = { r, g, b, a }
  return xpOriginalColor(r, g, b, a)
end
local removeClassicMover = hooks:wrap("battle.player_hud", function(next, battle, anchor)
  love.graphics.push()
  love.graphics.translate(0, -20)
  local result = next(battle, anchor)
  love.graphics.pop()
  return result
end, 0, "test_classic_hud_mover")
hooks:call("battle.player_hud", function() end, xpBattle, classicalAnchor)
hooks:call("battle.overlay", function() end, xpBattle)
removeClassicMover()
T.eq(#xpApplied, 1, "classic XP bar replays the captured HUD transform")
T.check(xpApplied[1] == fakeTransform,
  "replayed transform is the one active inside the mover")
T.eq(xpScissors[1][1], 80, "classic XP clear spans the bar slot")
T.eq(xpScissors[1][2], 69, "classic XP clear follows the panel translation")
local classicXpFill = xpRects[#xpRects]
T.eq(classicXpFill[2], 112, "classic XP fill keeps panel-space x")
T.eq(classicXpFill[3], 89, "classic XP fill keeps panel-space y")
T.eq(xpPushes, 2, "mover and replay balance their pushes")
T.eq(xpPops, 2, "mover and replay balance their pops")
T.eq(xpClears[1][4], 0, "classic XP clear stays transparent")

-- Classic's colorized pipeline applies the shake as a canvas draw offset at
-- composite time, so the replay adds the live shake before transforming.
local shakeBattle = {
  data = Data,
  player = { mon = xpBattle.player.mon, def = xpDef },
  fx = { shakeX = 3, shakeY = 0 },
  isWideBattleLayout = function() return false end,
}
local dmgAnchor = { x = 80, y = 56, bottomY = 88, paletteSpace = "dmg" }
xpApplied, xpScissors, xpRects, xpClears = {}, {}, {}, {}
trans.x, trans.y = 0, 0
hooks:call("battle.player_hud", function() end, shakeBattle, dmgAnchor)
hooks:call("battle.overlay", function() end, shakeBattle)
T.eq(#xpApplied, 1, "canvas-shake HUD still replays the captured transform")
T.eq(xpScissors[1][1], 83, "classic canvas-shake XP clear follows the shake")
T.eq(xpScissors[1][2], 89, "classic canvas-shake XP clear stays on the HUD row")
T.eq(xpRects[#xpRects][2], 115,
  "canvas-shake XP fill offsets with the panel")

-- Engines without transform capture keep the classic overlay math.
local legacyBattle = {
  data = Data,
  player = { mon = xpBattle.player.mon, def = xpDef },
  isWideBattleLayout = function() return false end,
}
xpApplied, xpScissors, xpRects = {}, {}, {}
love.graphics.getTransform = nil
hooks:call("battle.player_hud", function() end, legacyBattle, classicalAnchor)
hooks:call("battle.overlay", function() end, legacyBattle)
T.eq(#xpApplied, 0, "legacy engines draw without a transform replay")
T.eq(xpScissors[1][1], 80, "legacy XP clear keeps the classic slot")
T.eq(xpScissors[1][2], 89, "legacy XP clear keeps the classic row")
T.eq(xpRects[#xpRects][2], 112,
  "legacy XP fill keeps classic right alignment")
love.graphics.getTransform = originalGetTransform
love.graphics.applyTransform = originalApplyTransform
love.graphics.translate = originalTranslate
love.graphics.push = originalXpPush
love.graphics.pop = originalXpPop
love.graphics.setScissor = originalSetScissor
love.graphics.rectangle = xpOriginalRectangle
love.graphics.clear = xpOriginalClear
love.graphics.setColor = xpOriginalColor

-- VOXEL HUD FAMILY: DRAMALESS_SHAPE, PotatoVoxel, and BATTLE_ART_VOXEL_FORK
-- swap the battle's world canvas and re-composite the HUD panels at window
-- coordinates.  The suite maps its decorations off this frame's shot
-- instead of the letterbox frame those mods vacate.
local DRAMALESS_ID = "DRAMALESS_SHAPE"
local FORK_ID = "BATTLE_ART_VOXEL_FORK"
local POTATO_ID = "potato_voxel"
local voxelShot = { pw = 1280, ph = 720, lx = 240, ly = 0, scale = 5 }
local voxelBattle = {
  data = Data,
  player = { mon = xpBattle.player.mon, def = xpDef },
  isWideBattleLayout = function() return false end,
  dramaticShapeShot = voxelShot,
  game = { mods = run.loader, save = { options = { modOptions = {} } } },
}
T.check(exports.voxelHud.shot(voxelBattle) == voxelShot,
  "voxel helper reads the frame's dramatic shape shot")
T.check(exports.voxelHud.branch(voxelBattle) == "dramaless",
  "an unregistered producer falls back to the original math")

-- The original DRAMALESS_SHAPE pins the HUD to the window-fit scale.
run.loader.exports[DRAMALESS_ID] = { lib = {} }
T.eq(exports.voxelHud.branch(voxelBattle), "dramaless",
  "DRAMALESS_SHAPE is detected from the loader registry")
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).x,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).y,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).width,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).height,
}, ","), "880,445,320,10",
  "DRAMALESS maps the player bar to the window edge")
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).x,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).y,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).width,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).height,
}, ","), "0,40,40,40",
  "DRAMALESS maps the caught mark to the foe level row")
voxelShot.scale = 0 / 0
T.eq(exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }), nil,
  "voxel HUD ignores a non-finite external scale")
voxelShot.scale = 5
T.eq(exports.voxelHud.mapRect(voxelBattle, "enemy", {
  8, 8, 0 / 0, 8,
}), nil, "voxel HUD ignores malformed external geometry")
run.loader.exports[DRAMALESS_ID] = nil

-- PotatoVoxel is a performance-focused fork with its own package ID, but it
-- keeps the original HUD_RECT and window-fit scale.  It must take the same
-- mapping path explicitly rather than relying on the unknown-producer fallback.
run.loader.exports[POTATO_ID] = { lib = {} }
T.eq(exports.voxelHud.branch(voxelBattle), "potato",
  "PotatoVoxel is detected from its loader registry")
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).x,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).y,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).width,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).height,
}, ","), "880,445,320,10",
  "PotatoVoxel maps the player bar to the window edge")
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).x,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).y,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).width,
  exports.voxelHud.mapRect(voxelBattle, "enemy", { 8, 8, 8, 8 }).height,
}, ","), "0,40,40,40",
  "PotatoVoxel maps the caught mark to the foe level row")
run.loader.exports[POTATO_ID] = nil

-- The BATTLE_ART_VOXEL_FORK defaults to a HUD one scale unit smaller, and
-- its "og" mode lines the HUD up with the window-fit scale, pixel-identical
-- to DRAMALESS for external XP-bar mods.
run.loader.exports[FORK_ID] = { lib = {} }
T.eq(exports.voxelHud.branch(voxelBattle), "fork",
  "BATTLE_ART_VOXEL_FORK is detected from the loader registry")
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).x,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).y,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).width,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).height,
}, ","), "960,412,256,8",
  "fork SCALED maps the player bar to its scaled panel")
voxelBattle.game.save.options.modOptions[FORK_ID] = { hudScale = "og" }
T.eq(table.concat({
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).x,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).y,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).width,
  exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).height,
}, ","), "880,445,320,10",
  "fork OG maps pixel-identically to DRAMALESS")
voxelBattle.game.save.options.modOptions[FORK_ID] = {}
T.eq(exports.voxelHud.mapRect(voxelBattle, "player", { 80, 89, 64, 2 }).x,
  960, "an unknown fork HUD SCALE falls back to SCALED")
run.loader.exports[FORK_ID] = nil

local vanillaBattle = { isWideBattleLayout = function() return false end }
T.eq(exports.voxelHud.mapRect(vanillaBattle, "player", { 80, 89, 64, 2 }),
  nil, "a vanilla frame maps to nothing")

-- End to end: the XP bar overlay follows the mapped player panel into the
-- world canvas and never clears the fork's painted panel.
run.loader.exports[DRAMALESS_ID] = { lib = {} }
voxelShot.canvas = "world"
local voxelRects, voxelClears, voxelCanvasLog = {}, {}, {}
local voxelOriginalRectangle = love.graphics.rectangle
local voxelOriginalClear = love.graphics.clear
local voxelOriginalSetCanvas = love.graphics.setCanvas
local voxelOriginalXpPush = love.graphics.push
local voxelOriginalXpPop = love.graphics.pop
love.graphics.rectangle = function(mode, x, y, width, height)
  voxelRects[#voxelRects + 1] = { mode, x, y, width, height }
  return voxelOriginalRectangle(mode, x, y, width, height)
end
love.graphics.clear = function(r, g, b, a)
  voxelClears[#voxelClears + 1] = { r, g, b, a }
  return voxelOriginalClear(r, g, b, a)
end
love.graphics.setCanvas = function(c)
  voxelCanvasLog[#voxelCanvasLog + 1] = c
  return voxelOriginalSetCanvas(c)
end
love.graphics.push = function() end
love.graphics.pop = function() end
hooks:call("battle.overlay", function() end, voxelBattle)
love.graphics.rectangle = voxelOriginalRectangle
love.graphics.clear = voxelOriginalClear
love.graphics.setCanvas = voxelOriginalSetCanvas
love.graphics.push = voxelOriginalXpPush
love.graphics.pop = voxelOriginalXpPop
local voxelFill = math.max(1,
  math.floor(320 * exports.experienceBar.progress(voxelBattle)))
T.eq(#voxelRects, 3, "voxel XP bar draws its track and fill into the world canvas")
local voxelXpFill = voxelRects[#voxelRects]
T.eq(voxelXpFill[1], "fill", "voxel XP fill keeps the native fill mode")
T.eq(voxelXpFill[2], 880 + 320 - voxelFill,
  "voxel XP fill right-aligns within the mapped player panel")
T.eq(voxelXpFill[3], 445, "voxel XP fill rides the player HUD row")
T.eq(voxelXpFill[5], 5, "voxel XP fill scales with the panel")
T.eq(#voxelClears, 0, "voxel XP bar never clears the world canvas")
T.check(voxelCanvasLog[1] == "world",
  "voxel XP bar draws inside the world canvas")
run.loader.exports[DRAMALESS_ID] = nil

-- CAUGHT MARKER: a pokeball in the foe's level row marks a species already
-- owned in the Pokedex.  The fixed slot mirrors Gold's native HUD marker.
local caughtMiss = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_B" } },
  game = { save = { pokedex = { owned = { FIXMON_A = true } } } },
  isWideBattleLayout = function() return false end,
}
T.check(exports.caughtIndicator.caught(caughtMiss) == false,
  "unseen species reports uncaught")
local caughtHit = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_A" } },
  game = { save = { pokedex = { owned = { FIXMON_A = true } } } },
  isWideBattleLayout = function() return false end,
}
T.check(exports.caughtIndicator.caught(caughtHit) == true,
  "owned species reports caught")
local caughtBare = { isWideBattleLayout = function() return false end }
T.check(exports.caughtIndicator.caught(caughtBare) == false,
  "missing enemy or save data reports uncaught")
local markX, markY = exports.caughtIndicator.markerAt(caughtHit)
T.eq(markX, 8, "classic caught mark uses the native level-row slot")
T.eq(markY, 8, "classic caught mark rides the level row")
caughtHit.isWideBattleLayout = function() return true end
markX, markY = exports.caughtIndicator.markerAt(caughtHit)
T.eq(markX, 112, "wide caught mark uses the open right side of the level row")
T.eq(markY, 8, "wide caught mark rides the level row inside the panel")
local longName = {
  enemy = { name = "TANGELAWIDE", mon = { species = "FIXMON_A" } },
  game = caughtHit.game,
  isWideBattleLayout = function() return false end,
}
local longX, longY = exports.caughtIndicator.markerAt(longName)
T.eq(longX, 8, "a long name does not displace the native caught mark")
T.eq(longY, 8, "a long name keeps the marker on the level row")

if exports.caughtIndicator.nativeMarkerSupported then
  local nativeVisible = hooks:call("battle.caught_marker_visible",
    function() return false end, caughtHit)
  T.eq(nativeVisible, true,
    "CAUGHT MARKER enables the engine's native caught-ball renderer")
  run.loader.modOptions[MOD_ID] = { caughtIndicator = false }
  run.loader.events:emit("mod.options_changed",
    { mod = MOD_ID, key = "caughtIndicator", value = false })
  nativeVisible = hooks:call("battle.caught_marker_visible",
    function() return false end, caughtHit)
  T.eq(nativeVisible, false,
    "disabling CAUGHT MARKER leaves the native renderer disabled")
  run.loader.modOptions[MOD_ID] = nil
  run.loader.events:emit("mod.options_changed",
    { mod = MOD_ID, key = "caughtIndicator", value = true })
else
local caughtDraws = {}
local originalNewImage = love.graphics.newImage
local originalDraw = love.graphics.draw
local fakeImage = { getDimensions = function() return 8, 8 end }
love.graphics.newImage = function(path)
  caughtDraws[#caughtDraws + 1] = { img = path }
  return fakeImage
end
love.graphics.draw = function(img, x, y)
  caughtDraws[#caughtDraws + 1] = { img, x, y }
end
local caughtVisible = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_A" } },
  game = { save = { pokedex = { owned = { FIXMON_A = true } } } },
  isWideBattleLayout = function() return false end,
}
hooks:call("battle.overlay", function() end, caughtVisible)
local mark = caughtDraws[#caughtDraws]
T.check(type(mark) == "table" and mark[1] == fakeImage,
  "caught mark draws the procedural ball tile")
T.eq(mark[2], 8, "caught mark draws at the classic level-row slot")
T.eq(mark[3], 8, "caught mark draws on the classic level row")
caughtVisible.enemy.mon.stats = { hp = 100 }
caughtVisible.enemy.shownHP = 100
hooks:call("battle.overlay", function() end, caughtVisible)
local fullHealthImage = caughtDraws[#caughtDraws][1]
caughtVisible.enemy.shownHP = 1
hooks:call("battle.overlay", function() end, caughtVisible)
T.check(caughtDraws[#caughtDraws][1] == fullHealthImage,
  "caught mark keeps one palette while enemy HP changes")
local markerGetColor = love.graphics.getColor
local markerSetColor = love.graphics.setColor
local markerColorCalls = {}
markerSetColor(0.2, 0.4, 0.6, 0.8)
love.graphics.setColor = function(r, g, b, a)
  markerColorCalls[#markerColorCalls + 1] = { r, g, b, a }
  return markerSetColor(r, g, b, a)
end
hooks:call("battle.overlay", function() end, caughtVisible)
local markerColor = markerColorCalls[#markerColorCalls - 1]
T.check(markerColor and markerColor[1] == 1 and markerColor[2] == 1
    and markerColor[3] == 1 and markerColor[4] == 1,
  "caught mark draws without inheriting the HP bar tint")
local restoredMarkerColor = { markerGetColor() }
T.check(math.abs(restoredMarkerColor[1] - 0.2) < 0.001
    and math.abs(restoredMarkerColor[2] - 0.4) < 0.001
    and math.abs(restoredMarkerColor[3] - 0.6) < 0.001
    and math.abs(restoredMarkerColor[4] - 0.8) < 0.001,
  "caught mark restores the previous graphics color")
love.graphics.setColor = markerSetColor
caughtVisible.enemy.mon.stats = { hp = "corrupt" }
hooks:call("battle.overlay", function() end, caughtVisible)
T.check(caughtDraws[#caughtDraws][1] == fakeImage,
  "caught mark ignores malformed HP palette data")
caughtVisible.enemy.mon.stats = nil

local emptyDraws = {}
local caughtDraw = love.graphics.draw
love.graphics.draw = function(...) emptyDraws[#emptyDraws + 1] = { ... } end
local caughtHiding = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_A" } },
  game = { save = { pokedex = { owned = { FIXMON_A = true } } } },
  introBalls = true,
  isWideBattleLayout = function() return false end,
}
hooks:call("battle.overlay", function() end, caughtHiding)
T.eq(#emptyDraws, 0, "caught mark skips while the foe panel is hidden")
local caughtForeign = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_B" } },
  game = { save = { pokedex = { owned = { FIXMON_A = true } } } },
  isWideBattleLayout = function() return false end,
}
hooks:call("battle.overlay", function() end, caughtForeign)
T.eq(#emptyDraws, 0, "uncaught species draws no caught mark")
run.loader.modOptions[MOD_ID] = { caughtIndicator = false }
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "caughtIndicator", value = false })
hooks:call("battle.overlay", function() end, caughtVisible)
T.eq(#emptyDraws, 0, "disabling CAUGHT MARKER leaves the overlay untouched")
run.loader.modOptions[MOD_ID] = nil
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "caughtIndicator", value = true })
love.graphics.newImage = originalNewImage
love.graphics.draw = caughtDraw

-- The caught mark rides the foe panel into the world canvas under the
-- Dramatic Shape family.
run.loader.exports[DRAMALESS_ID] = { lib = {} }
local voxelMarks = {}
local voxelOriginalDraw = love.graphics.draw
local voxelOriginalNewImage = love.graphics.newImage
local voxelBallImage = { getDimensions = function() return 8, 8 end }
love.graphics.newImage = function(path)
  return voxelBallImage
end
love.graphics.draw = function(img, ...)
  voxelMarks[#voxelMarks + 1] = { img, ... }
end
local voxelCaught = {
  enemy = { name = "PIKACHU", mon = { species = "FIXMON_A" } },
  game = {
    mods = run.loader,
    save = { pokedex = { owned = { FIXMON_A = true } } },
  },
  isWideBattleLayout = function() return false end,
}
hooks:call("battle.overlay", function() end, voxelCaught)
local vanillaMark = voxelMarks[#voxelMarks]
T.eq(vanillaMark[2], 8, "vanilla caught mark keeps the classic level-row slot")
T.eq(vanillaMark[3], 8, "vanilla caught mark keeps the classic level row")
voxelCaught.dramaticShapeShot = { pw = 1280, ph = 720, lx = 240, ly = 0,
  scale = 5, canvas = "world" }
hooks:call("battle.overlay", function() end, voxelCaught)
local worldMark = voxelMarks[#voxelMarks]
T.eq(worldMark[2], 0, "voxel caught mark maps onto the foe level row")
T.eq(worldMark[3], 40, "voxel caught mark rides the level row")
T.eq(worldMark[4], 0, "voxel caught mark keeps a zero rotation")
T.eq(worldMark[5], 5, "voxel caught mark scales with the panel")
T.eq(worldMark[6], 5, "voxel caught mark scales with the panel")
love.graphics.draw = voxelOriginalDraw
love.graphics.newImage = voxelOriginalNewImage
run.loader.exports[DRAMALESS_ID] = nil
end

-- Effectiveness labels clear only their old glyphs.  The row must become
-- transparent white rather than an opaque white rectangle so background mods
-- can show their active battle surface through it.
local Font = require("src.render.Font")
local originalFontDraw = Font.draw
local effectOriginalClear = love.graphics.clear
local originalEffectRectangle = love.graphics.rectangle
local effectClears, effectRects = {}, {}
Font.draw = function() end
love.graphics.clear = function(r, g, b, a)
  effectClears[#effectClears + 1] = { r, g, b, a }
end
love.graphics.rectangle = function(mode, x, y, width, height)
  effectRects[#effectRects + 1] = { mode, x, y, width, height }
end
local effectivenessBattle = {
  data = Data,
  phase = "moveSelect",
  moveIndex = 1,
  enemy = { curTypes = { "GRASS" } },
  player = { curMoves = { { id = "FIX_EMBERISH" } } },
  isWideBattleLayout = function() return false end,
}
hooks:call("battle.overlay", function() end, effectivenessBattle)
Font.draw = originalFontDraw
love.graphics.clear = effectOriginalClear
love.graphics.rectangle = originalEffectRectangle
T.eq(effectClears[1][1], 1, "effectiveness cleanup keeps white tile RGB")
T.eq(effectClears[1][2], 1, "effectiveness cleanup keeps white tile RGB")
T.eq(effectClears[1][3], 1, "effectiveness cleanup keeps white tile RGB")
T.eq(effectClears[1][4], 0,
  "effectiveness cleanup leaves the label row transparent")
T.eq(#effectRects, 0,
  "effectiveness cleanup does not paint an opaque background rectangle")

run.loader.modOptions[MOD_ID] = { experienceBar = false }
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "experienceBar", value = false })
local disabledOverlay = { on = true }
hooks:call("battle.overlay", function(battle) return disabledOverlay end, xpBattle)
T.check(disabledOverlay.on == true,
  "disabling XP BAR leaves the overlay pipeline unchanged")
run.loader.modOptions[MOD_ID] = nil
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "experienceBar", value = true })

local alarmDefault = { on = true }
hooks:call("battle.low_health_alarm", function(ctx) return ctx end, alarmDefault)
T.check(alarmDefault.on == true, "low-health alarm remains enabled by default")

run.loader.modOptions[MOD_ID] = { lowHealthAlarm = false }
local alarmDisabled = { on = true }
hooks:call("battle.low_health_alarm", function(ctx) return ctx end, alarmDisabled)
T.check(alarmDisabled.on == false, "disabling low-health alarm silences the hook")
run.loader.modOptions[MOD_ID] = nil

local game = {
  data = Data,
  save = { party = {}, options = { modOptions = {} } },
  mods = run.loader,
  partyMenuSavedIndex = 3,
}
local menu = { game = game, index = 3 }
game.stack = { top = function() return menu end }
local first = { species = "FIXMON_A" }
local second = { species = "FIXMON_B" }
local third = { species = "FIXMON_C", nickname = "NICKNAMED" }
game.save.party = { first, second, third }

local items = hooks:call("ui.party.submenu", function(_, vanilla)
  return vanilla
end, game, { { label = "STATS" }, { label = "SWITCH" } }, third,
  { battle = false })

local labels = {}
for _, item in ipairs(items) do labels[item.label] = true end
T.check(labels["TO FRONT"] == true, "party lead action is present")
T.check(labels["MOVES"] == true, "move freedom action is present")
T.check(labels["RENAME"] == true, "naming action is present")
T.check(labels["RESET"] == true,
  "species-name reset action is present for nicknamed Pokemon")

local toFront
for _, item in ipairs(items) do
  if item.label == "TO FRONT" then toFront = item end
end
T.check(type(toFront.onSelect) == "function", "TO FRONT remains selectable")

local speciesName
for _, item in ipairs(items) do
  if item.label == "RESET" then speciesName = item end
end
speciesName.onSelect()
T.eq(third.nickname, nil,
  "RESET NAME clears a nickname back to the canonical species display")

third.nickname = "NICKNAMED"
run.loader.modOptions[MOD_ID] = { restoreName = false }
items = hooks:call("ui.party.submenu", function(_, vanilla)
  return vanilla
end, game, { { label = "STATS" }, { label = "SWITCH" } }, third,
  { battle = false })
labels = {}
for _, item in ipairs(items) do
  labels[item.label] = true
end
T.check(labels["RENAME"] == true and labels["RESET"] ~= true,
  "disabling RESET NAME keeps RENAME but hides the reset action")

run.loader.modOptions[MOD_ID] = { renameAnywhere = false }
items = hooks:call("ui.party.submenu", function(_, vanilla)
  return vanilla
end, game, { { label = "STATS" }, { label = "SWITCH" } }, third,
  { battle = false })
labels = {}
for _, item in ipairs(items) do
  labels[item.label] = true
end
T.check(labels["RENAME"] ~= true and labels["RESET"] ~= true,
  "RESET NAME stays hidden when RENAME ANYWHERE is disabled")
run.loader.modOptions[MOD_ID] = nil
third.nickname = nil

-- EXP SHARE: the toggle temporarily exposes the engine's own EXP.ALL item
-- check, then leaves the player's inventory exactly as it was.
game.save.inventory = {}
run.loader.modOptions[MOD_ID] = { expShare = true }
game._expShareObserved = false
hooks:call("battle.exp_award", function(ctx)
  game._expShareObserved = (ctx.battle.game.save.inventory.EXP_ALL or 0) > 0
end, { battle = { game = game } })
T.check(game._expShareObserved == true,
  "EXP SHARE enables the engine's EXP.ALL award path")
T.eq(game.save.inventory.EXP_ALL, nil,
  "EXP SHARE does not leave an EXP.ALL item in the inventory")
game.save.inventory.EXP_ALL = 0
hooks:call("battle.exp_award", function() end, { battle = { game = game } })
T.eq(game.save.inventory.EXP_ALL, 0,
  "EXP SHARE preserves an existing zero inventory entry")
game.save.inventory.EXP_ALL = nil
local expOk = pcall(function()
  hooks:call("battle.exp_award", function() error("award failed") end,
    { battle = { game = game } })
end)
T.check(not expOk, "EXP SHARE preserves native award errors")
T.eq(game.save.inventory.EXP_ALL, nil,
  "EXP SHARE restores inventory even when the native award fails")
run.loader.modOptions[MOD_ID] = nil

-- AUTO BATTLE / AUTO CATCH: exercise the strategy repeatedly through the
-- public helpers and the core.update automation seam. The loop catches
-- regressions where a chooser returns an illegal move or catch action after
-- the battle state changes.
local autoBattle = exports.autoBattle
local autoMoves = {
  QUICK = { id = "QUICK", power = 40, accuracy = 100, type = "NORMAL",
    effect = "NO_ADDITIONAL_EFFECT", testDamage = 8, testMult = 10 },
  STRONG = { id = "STRONG", power = 90, accuracy = 100, type = "NORMAL",
    effect = "NO_ADDITIONAL_EFFECT", testDamage = 24, testMult = 10 },
  SLEEP = { id = "SLEEP", power = 0, accuracy = 100, type = "NORMAL",
    effect = "SLEEP_EFFECT", testDamage = 0, testMult = 10 },
}
local function autoBattleFixture(hp, wild)
  local playerMon = { species = "FIXMON_A", hp = 30, stats = { hp = 30 }, level = 10,
    moves = { { id = "QUICK", pp = 20 }, { id = "STRONG", pp = 20 },
      { id = "SLEEP", pp = 10 } } }
  local enemyMon = { species = "FIXMON_B", hp = hp, stats = { hp = 30 }, level = 8 }
  local battle = {
    isBattle = true, phase = "menu", kind = wild and "wild" or "trainer",
    data = { moves = autoMoves, pokemon = {
      FIXMON_A = { name = "FIXMON A", types = { "GRASS" } },
      FIXMON_B = { name = "FIXMON B", types = { "FIRE" } },
    } },
    game = { save = { party = { playerMon }, inventory = { POKE_BALL = 3 } } },
    player = { mon = playerMon, curTypes = { "GRASS" }, curMoves = playerMon.moves,
      curStats = playerMon.stats, stages = {}, isPlayer = true },
    enemy = { mon = enemyMon, curTypes = { "FIRE" }, curStats = enemyMon.stats,
      stages = {}, isPlayer = false },
    moveDef = function(self, move) return self.data.moves[move.id] end,
    effectRecord = function(self, effect)
      return effect == "SLEEP_EFFECT" and { kind = "primary" } or { kind = "full" }
    end,
    computeDamage = function(self, user, target, def)
      return def.testDamage or 0, { typeMult = def.testMult or 10 }
    end,
  }
  return battle
end

for iteration = 1, 200 do
  local battle = autoBattleFixture(30, false)
  local action = autoBattle.chooseMove(battle)
  T.eq(action.kind, "move", "AUTO BATTLE returns a move on iteration " .. iteration)
  T.eq(action.move.id, "STRONG",
    "AUTO BATTLE selects the strongest legal move on iteration " .. iteration)
end

for iteration = 1, 100 do
  local battle = autoBattleFixture(20, true)
  local action = autoBattle.chooseCatchAction(battle)
  T.eq(action.kind, "move", "AUTO CATCH starts with status on iteration " .. iteration)
  T.eq(action.move.id, "SLEEP",
    "AUTO CATCH prefers sleep before damage on iteration " .. iteration)
  battle.enemy.mon.status = "SLP"
  battle.enemy.mon.hp = 20
  action = autoBattle.chooseCatchAction(battle)
  T.eq(action.move.id, "QUICK",
    "AUTO CATCH chooses safe damage on iteration " .. iteration)
  battle.enemy.mon.hp = 1
  action = autoBattle.chooseCatchAction(battle)
  T.eq(action.kind, "ball",
    "AUTO CATCH throws a ball at minimum HP on iteration " .. iteration)
end

run.loader.modOptions[MOD_ID] = { autoBattle = true, autoCatch = true }
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "autoBattle", value = true,
})
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "autoCatch", value = true,
})
for iteration = 1, 50 do
  local battle = autoBattleFixture(10, false)
  local resolved
  battle.resolveTurn = function(self, move) resolved = move.id end
  local fakeGame = battle.game
  fakeGame.stack = { top = function() return battle end }
  hooks:call("core.update", function(game, dt) return game, dt end, fakeGame, 0)
  T.eq(resolved, "STRONG",
    "AUTO BATTLE drives core.update on iteration " .. iteration)
end
run.loader.modOptions[MOD_ID] = nil

run.loader.modOptions[MOD_ID] = { toFront = false }
local disabledItems = hooks:call("ui.party.submenu", function(_, vanilla)
  return vanilla
end, game, { { label = "STATS" }, { label = "SWITCH" } }, third,
  { battle = false })
T.eq(#disabledItems, 4, "disabling TO FRONT removes only the party action")
local disabledLabels = {}
for _, item in ipairs(disabledItems) do disabledLabels[item.label] = true end
T.check(disabledLabels["TO FRONT"] ~= true,
  "disabling TO FRONT leaves the other party actions intact")
toFront.onSelect(third, game)
T.eq(game.save.party[1], first, "disabling TO FRONT blocks a stale callback")
run.loader.modOptions[MOD_ID] = nil

toFront.onSelect(third, game)
T.eq(game.save.party[1], third, "TO FRONT keeps its standalone behavior")
T.eq(game.partyMenuSavedIndex, 1, "TO FRONT resets the saved cursor")
T.eq(menu.index, 1, "TO FRONT resets the live cursor")

-- QUICK FIELD MOVES: the engine surfaces the contextual field actions from the
-- party menu; the feature claims an A-press on an empty tile (facing water or
-- a cuttable tree), or on a faced boulder. Gold also routes native Headbutt,
-- Rock Smash, Whirlpool, and Waterfall confirmations through AUTO FIELD MOVES.
local fieldAbilities = exports.fieldAbilities
T.check(type(fieldAbilities.opportunity) == "function",
  "field ability opportunity helper is exported")
T.check(type(fieldAbilities.execute) == "function",
  "field ability executor helper is exported")

local function fieldOw(stubs)
  local ow = { player = { surfing = false }, map = { id = "ROUTE_24" } }
  for k, v in pairs(stubs or {}) do
    if k == "surfing" then ow.player.surfing = v
    elseif k == "useSurfFieldMove" then ow.useSurfFieldMove = v
    elseif k == "useCutFieldMove" then ow.useCutFieldMove = v
    elseif k == "trySurf" or k == "tryCut" then ow[k] = v
    elseif k == "facingCell" then ow.player.facingCell = v
    elseif k == "pushableAtCell" or k == "partyKnows" then ow[k] = v
    elseif k == "strengthActive" then ow.strengthActive = v
    end
  end
  return ow
end
local surfOkOw = fieldOw({
  useSurfFieldMove = function() return "ok" end,
  useCutFieldMove = function() return "nothing" end,
})
T.eq(fieldAbilities.opportunity(surfOkOw, "none"), "surf",
  "facing water with a SURF mon is a surf opportunity")
local cutOkOw = fieldOw({
  useSurfFieldMove = function() return "no_water" end,
  useCutFieldMove = function() return "ok" end,
})
T.eq(fieldAbilities.opportunity(cutOkOw, "none"), "cut",
  "facing a tree with a CUT mon is a cut opportunity")
local strengthFacingCalls = 0
local strengthOw = fieldOw({
  facingCell = function()
    strengthFacingCalls = strengthFacingCalls + 1
    return 12, 9
  end,
  pushableAtCell = function(self, fx, fy)
    T.eq(fx, 12, "strength checks the full facing x coordinate")
    T.eq(fy, 9, "strength checks the full facing y coordinate")
    return { id = "BOULDER" }
  end,
  partyKnows = function(self, move)
    return move == "STRENGTH" and { species = "MACHOKE" }
  end,
})
T.eq(fieldAbilities.opportunity(strengthOw, "npc"), "strength",
  "facing a boulder with a STRENGTH mon is a strength opportunity")
T.eq(strengthFacingCalls, 1,
  "strength reads both coordinates from the player's facing cell")
T.check(fieldAbilities.opportunity(strengthOw, "npc", 12, 9) == "strength",
  "a boulder event can use its emitted facing coordinates")
local activeStrengthOw = fieldOw({
  strengthActive = true,
  pushableAtCell = function() return { id = "BOULDER" } end,
  partyKnows = function() return {} end,
})
T.check(fieldAbilities.opportunity(activeStrengthOw, "npc", 12, 9) == nil,
  "an already-active Strength gate is not prompted again")
T.check(fieldAbilities.opportunity(fieldOw({}), "npc", 12, 9) == nil,
  "an ordinary NPC is not claimed as a Strength opportunity")
T.check(fieldAbilities.opportunity(fieldOw({}), "none") == nil,
  "an empty tile with no applicable move is not claimed")
T.check(fieldAbilities.opportunity(surfOkOw, "sign") == nil,
  "an NPC or sign press is not claimed")
local surfingOw = fieldOw({
  surfing = true,
  useSurfFieldMove = function() return "dismount" end,
})
T.check(fieldAbilities.opportunity(surfingOw, "none") == nil,
  "surfing keeps the dismount with the party menu")
T.check(fieldAbilities.opportunity(nil, "none") == nil,
  "no overworld state means no opportunity")

-- Auto mode (no prompt) executes the ability immediately.
local autoSurfCalls = 0
local autoSurfOw = fieldOw({
  useSurfFieldMove = function() return "ok" end,
  trySurf = function(self, fx, fy)
    autoSurfCalls = autoSurfCalls + 1
    T.eq(fx, 8, "auto surf runs on the facing cell")
    T.eq(fy, 6, "auto surf runs on the facing cell")
  end,
})
T.check(fieldAbilities.execute(autoSurfOw, 8, 6, "surf", nil, true),
  "auto surf claims the interaction")
T.eq(autoSurfCalls, 1, "auto surf used the ability right away")
local autoCutCalls = 0
local autoCutOw = fieldOw({
  tryCut = function(self, fx, fy) autoCutCalls = autoCutCalls + 1 end,
})
T.check(fieldAbilities.execute(autoCutOw, 9, 7, "cut", nil, true),
  "auto cut claims the interaction")
T.eq(autoCutCalls, 1, "auto cut used the ability right away")
local autoStrengthOw = fieldOw({
  partyKnows = function(self, move) return move == "STRENGTH" and {} end,
})
T.check(fieldAbilities.execute(autoStrengthOw, 12, 9, "strength", nil, true),
  "auto Strength claims the interaction")
T.eq(autoStrengthOw.strengthActive, true,
  "auto Strength activates the native boulder gate")
T.check(fieldAbilities.execute(surfOkOw, 8, 6, "fly", nil, true) == false,
  "an unknown ability is not claimed")
T.check(type(fieldAbilities.flashResult) == "function",
  "flash readiness helper is exported")
T.check(type(fieldAbilities.executeFlash) == "function",
  "flash executor helper is exported")

-- With the prompt on, a YES/NO box is pushed and only YES runs the ability.
local promptSurfCalls = 0
local promptPushed = {}
local promptStack = { push = function(self, box)
  promptPushed[#promptPushed + 1] = box
end }
local promptSurfOw = fieldOw({
  useSurfFieldMove = function() return "ok" end,
  trySurf = function(self, fx, fy) promptSurfCalls = promptSurfCalls + 1 end,
})
T.check(fieldAbilities.execute(promptSurfOw, 8, 6, "surf",
  { stack = promptStack }, false), "prompt surf claims the interaction")
T.eq(#promptPushed, 1, "prompt surf pushes a confirmation box")
local promptBox = promptPushed[1]
T.eq(promptBox.defaultNo, true, "prompt defaults the cursor to NO")
T.check(type(promptBox.choice) == "function",
  "prompt box carries the YES/NO callback")
T.eq(#promptBox.pages, 1, "prompt text fits on a single page")
T.eq(promptSurfCalls, 0, "nothing runs before the choice")
promptBox.choice(false)
T.eq(promptSurfCalls, 0, "NO does not use the ability")
promptBox.choice(true)
T.eq(promptSurfCalls, 1, "YES uses the ability")

-- End to end: the world.interacted A-press event drives the whole flow and
-- the options gate it.  The real Game singleton is on the require path the
-- listener uses, so stub only its overworld + stack.
local function checkFieldMoveIntegration(realGame)
local prevOverworld, prevStack = realGame.overworld, realGame.stack
local listenerPushes = 0
realGame.stack = { push = function() listenerPushes = listenerPushes + 1 end }
local listenerSurf = 0
realGame.overworld = fieldOw({
  useSurfFieldMove = function() return "ok" end,
  useCutFieldMove = function() return "nothing" end,
  trySurf = function(self, fx, fy) listenerSurf = listenerSurf + 1 end,
})
local setFieldOption = function(key, value)
  local bucket = run.loader.modOptions[MOD_ID]
  if not bucket then
    bucket = {}
    run.loader.modOptions[MOD_ID] = bucket
  end
  local previous = bucket[key]
  bucket[key] = value
  return function() bucket[key] = previous end
end
local restoreOption
restoreOption = setFieldOption("fieldAbilities", false)
run.loader.events:emit("world.interacted", { mapId = "ROUTE_24", x = 8,
  y = 6, kind = "none", target = nil })
T.eq(listenerPushes, 0, "disabling FIELD MOVES silences the listener")
T.eq(listenerSurf, 0, "disabling FIELD MOVES never executes a move")
restoreOption()
restoreOption = setFieldOption("fieldAbilitiesAuto", true)
run.loader.events:emit("world.interacted", { mapId = "ROUTE_24", x = 8,
  y = 6, kind = "none", target = nil })
T.eq(listenerPushes, 0, "auto mode prompts with nothing")
T.eq(listenerSurf, 1, "auto mode surfs straight onto the water")
restoreOption()
run.loader.events:emit("world.interacted", { mapId = "ROUTE_24", x = 8,
  y = 6, kind = "none", target = nil })
T.eq(listenerPushes, 1, "prompt mode pushes one confirmation box")
T.eq(listenerSurf, 1, "prompt mode waits for the choice before surfing")
run.loader.events:emit("world.interacted", { mapId = "ROUTE_24", x = 8,
  y = 6, kind = "sign", target = nil })
T.eq(listenerPushes, 1, "a sign press never prompts a field ability")
local listenerStrength = fieldOw({
  partyKnows = function(self, move) return move == "STRENGTH" and {} end,
  pushableAtCell = function(self, fx, fy)
    T.eq(fx, 12, "Strength listener uses the event x coordinate")
    T.eq(fy, 9, "Strength listener uses the event y coordinate")
    return { id = "BOULDER" }
  end,
})
realGame.overworld = listenerStrength
restoreOption = setFieldOption("fieldAbilitiesAuto", true)
run.loader.events:emit("world.interacted", { mapId = "ROUTE_24", x = 12,
  y = 9, kind = "npc", target = { id = "BOULDER" } })
T.eq(listenerStrength.strengthActive, true,
  "a boulder A-press activates Strength in auto mode")
restoreOption()

-- USE HMs DIRECTLY: the native badge gate and the HM-in-bag requirement are
-- both preserved while the field-move eligibility hook supplies a party
-- representative when no mon actually knows the move.
Data.items.HM_SURF = {
  id = "HM_SURF", name = "HM03", machine = { kind = "HM", move = "SURF" },
}
local hmPartyMon = { species = "FIXMON_A", moves = { { id = "FIX_TACKLE" } } }
local hmSave = {
  inventory = { HM_SURF = 1, SOULBADGE = true },
  party = { hmPartyMon },
}
run.loader.modOptions[MOD_ID] = { hmWithoutTeaching = true }
local hmUser = hooks:call("fieldmove.eligibility", function() return nil end,
  "SURF", { save = hmSave, data = Data, party = hmSave.party })
T.eq(hmUser, hmPartyMon,
  "USE HMs DIRECTLY supplies a party user for an owned, badge-gated HM")
hmSave.inventory.SOULBADGE = nil
hmUser = hooks:call("fieldmove.eligibility", function() return nil end,
  "SURF", { save = hmSave, data = Data, party = hmSave.party })
T.eq(hmUser, nil,
  "USE HMs DIRECTLY keeps the native badge requirement")
hmSave.inventory.SOULBADGE = true
hmSave.inventory.HM_SURF = nil
hmUser = hooks:call("fieldmove.eligibility", function() return nil end,
  "SURF", { save = hmSave, data = Data, party = hmSave.party })
T.eq(hmUser, nil,
  "USE HMs DIRECTLY requires the HM to remain in the bag")

-- REUSABLE TMs: ItemEffects keeps the engine's successful teach result but
-- changes only the consumption marker for TMs, leaving HMs and failures native.
local ItemEffects = require("src.inventory.ItemEffects")
local tmSave = { inventory = { FIX_TM = 1 } }
local tmMon = { species = "FIXMON_A", moves = { { id = "FIX_TACKLE" } } }
run.loader.modOptions[MOD_ID] = { reusableTMs = false }
local tmResult = ItemEffects.use(Data, tmSave, "FIX_TM", tmMon)
T.eq(tmResult, "learn", "a disabled REUSABLE TMs option consumes a TM normally")
run.loader.modOptions[MOD_ID] = { reusableTMs = true }
tmResult = ItemEffects.use(Data, tmSave, "FIX_TM", tmMon)
T.eq(tmResult, "learnkept",
  "REUSABLE TMs preserves a successful TM after teaching")
run.loader.modOptions[MOD_ID] = nil
realGame.overworld, realGame.stack = prevOverworld, prevStack
end
withGameFacade(checkFieldMoveIntegration)

run.release()
T.finish(MOD_ID)
