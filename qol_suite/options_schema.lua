-- QoL Suite option schema for the current gen1recomp production release.
-- Keep this file free of mod API calls: the launcher evaluates it before the
-- mod entry chunk runs. The engine renders dependent rows natively through
-- each row's single-parent visible_if condition (supported since v0.1.95).
local GameVersion = require("src.core.GameVersion")
local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
local GameSpeed = require("src.core.GameSpeed")

local encounterRateChoices = {}
for _, level in ipairs(GameSpeed.LEVELS) do
  encounterRateChoices[#encounterRateChoices + 1] = {
    GameSpeed.levelLabel(level), level,
  }
end

-- Native visible_if accepts one {key, equals} (or not_equals) parent. A row
-- that is logically "A AND B" is expressed by its innermost parent: the outer
-- parents are already gated by the inner one, so the chain stays coherent.
local function when(key, equals)
  return { key = key, equals = equals }
end

local optionSchema = {
  -- Battle
  { key = "effectiveness", label = "TYPE MATCHUP", type = "toggle", default = true },
  { key = "lowHealthAlarm", label = "LOW HEALTH ALARM", type = "toggle", default = true },
  { key = "expShare", label = "EXP SHARE", type = "toggle", default = false },
  { key = "swapMoves", label = "SWAP MOVES", type = "toggle", default = true },
  { key = "retainPP", label = "KEEP MOVE PP", type = "toggle", default = true,
    visible_if = when("swapMoves", true) },

  -- Automation
  { key = "autoBattle", label = "AUTO BATTLE", type = "toggle", default = false },
  { key = "autoStopLowHp", label = "STOP LOW HP", type = "toggle",
    default = false, visible_if = when("autoBattle", true) },
  { key = "autoPauseNewEntry", label = "PAUSE NEW ENTRY", type = "toggle",
    default = false, visible_if = when("autoBattle", true) },
  { key = "autoPauseEvolution", label = "PAUSE EVOLUTION", type = "toggle",
    default = false, visible_if = when("autoBattle", true) },
  { key = "autoCatch", label = "AUTO CATCH", type = "toggle", default = false,
    visible_if = when("autoBattle", true) },
  { key = "autoCatchNewOnly", label = "CATCH NEW ONLY", type = "toggle",
    default = false, visible_if = when("autoCatch", true) },
  { key = "autoCatchTarget", label = "AUTO CATCH TARGET", type = "toggle",
    default = false, visible_if = when("autoCatch", true) },
  { key = "autoCatchBall", label = "AUTO CATCH BALL", type = "choice",
    choices = {
      { "BEST", "best" },
      { "WORST", "worst" },
      { "POKE BALL ONLY", "poke-ball-only" },
    }, default = "best", visible_if = when("autoCatch", true) },
  { key = "showBallCounts", label = "SHOW BALL COUNTS", type = "toggle",
    default = true, visible_if = when("autoCatch", true) },
  { key = "autoStopNoBalls", label = "STOP NO BALLS", type = "toggle",
    default = false, visible_if = when("autoCatch", true) },
  { key = "autoStopTarget", label = "STOP ON TARGET", type = "toggle",
    default = false, visible_if = when("autoCatchTarget", true) },

  -- Field
  { key = "fieldAbilities", label = "QUICK FIELD MOVES", type = "toggle", default = true },
  { key = "fieldAbilitiesAuto", label = "AUTO FIELD MOVES", type = "toggle",
    default = false, visible_if = when("fieldAbilities", true) },
  { key = "hmWithoutTeaching", label = "USE HMs DIRECTLY", type = "toggle", default = false },
  { key = "skipCenterDialogue", label = "SKIP CENTER TALK", type = "toggle", default = false },
  { key = "encounterRate", label = "ENCOUNTER RATE", type = "choice",
    choices = encounterRateChoices, default = 1 },

  -- Party
  { key = "partyOverview", label = "PARTY OVERVIEW", type = "toggle", default = false },
  { key = "partyOverviewCorner", label = "PARTY CORNER", type = "choice",
    choices = {
      { "TOP LEFT", "top-left" },
      { "TOP RIGHT", "top-right" },
      { "BOTTOM LEFT", "bottom-left" },
      { "BOTTOM RIGHT", "bottom-right" },
    }, default = "bottom-left", visible_if = when("partyOverview", true) },
  { key = "partyOrder", label = "PARTY ORDER", type = "choice",
    choices = {
      { "NATIVE", "native" },
      { "HEALTHY FIRST", "healthy" },
      { "LEVEL HIGH", "level" },
      { "TYPE ORDER", "type" },
    }, default = "native", visible_if = when("partyOverview", true) },
  { key = "autoPartyOrder", label = "AUTO PARTY ORDER", type = "toggle",
    default = false, visible_if = when("partyOverview", true) },
  { key = "toFront", label = "ENABLE TO FRONT", type = "toggle", default = true },

  -- Bag
  { key = "bagCategories", label = "BAG CATEGORIES", type = "toggle", default = false },
  { key = "bagSearch", label = "BAG SEARCH", type = "toggle", default = false },
  { key = "bagAutoSort", label = "AUTO SORT BAG", type = "toggle", default = false },
  { key = "quickUseItems", label = "QUICK USE ITEMS", type = "toggle", default = false },
  { key = "reusableTMs", label = "REUSABLE TMs", type = "toggle", default = false },

  -- Minimap
  { key = "minimap", label = "MINIMAP", type = "toggle", default = false },
  { key = "minimapCorner", label = "MINIMAP CORNER", type = "choice",
    choices = {
      { "TOP LEFT", "top-left" },
      { "TOP RIGHT", "top-right" },
      { "BOTTOM LEFT", "bottom-left" },
      { "BOTTOM RIGHT", "bottom-right" },
    }, default = "top-right", visible_if = when("minimap", true) },
  { key = "minimapTransparency", label = "MAP TRANSPARENCY",
    type = "number", min = 0, max = 100, step = 5, default = 0,
    visible_if = when("minimap", true) },
  { key = "minimapSize", label = "MINIMAP SIZE", type = "number",
    min = 50, max = 200, step = 10, default = 100,
    visible_if = when("minimap", true) },
  { key = "minimapZoom", label = "MINIMAP ZOOM", type = "number",
    min = 50, max = 200, step = 10, default = 100,
    visible_if = when("minimap", true) },
  { key = "minimapBorder", label = "MAP BORDER", type = "choice",
    choices = {
      { "ROUNDED", "rounded" },
      { "SQUARE", "square" },
      { "OFF", "off" },
    }, default = "rounded", visible_if = when("minimap", true) },
  { key = "tracking", label = "TRACKING", type = "toggle", default = false,
    visible_if = when("minimap", true) },

  -- Interface
  { key = "pokedexFilters", label = "POKEDEX FILTERS", type = "toggle", default = true },
  { key = "encounterTracker", label = "ENCOUNTER TRACKER", type = "toggle", default = false },
  { key = "encounterTrackerCorner", label = "TRACKER CORNER", type = "choice",
    choices = {
      { "TOP LEFT", "top-left" },
      { "TOP RIGHT", "top-right" },
      { "BOTTOM LEFT", "bottom-left" },
      { "BOTTOM RIGHT", "bottom-right" },
    }, default = "top-right", visible_if = when("encounterTracker", true) },
  { key = "encounterTrackerTracked", label = "SHOW TRACKED", type = "toggle",
    default = true, visible_if = when("encounterTracker", true) },
  { key = "encounterTrackerLand", label = "SHOW LAND", type = "toggle",
    default = true, visible_if = when("encounterTracker", true) },
  { key = "encounterTrackerSurf", label = "SHOW SURFING", type = "toggle",
    default = true, visible_if = when("encounterTracker", true) },
  { key = "encounterTrackerFishing", label = "SHOW FISHING", type = "toggle",
    default = true, visible_if = when("encounterTracker", true) },
  { key = "floatingMenus", label = "FLOATING MENUS", type = "toggle", default = false },

  -- Naming
  { key = "skipWildCatchNickname", label = "SKIP CATCH NAME", type = "toggle", default = true },
  { key = "renameNpcTrades", label = "RENAME NPC MON", type = "toggle", default = false },
  { key = "autoRenameTrades", label = "AUTO RENAME TRADES", type = "toggle",
    default = false, visible_if = when("renameNpcTrades", true) },
  { key = "renameAnywhere", label = "RENAME ANYWHERE", type = "toggle", default = true },
  { key = "restoreName", label = "RESET NAME", type = "toggle", default = true,
    visible_if = when("renameAnywhere", true) },
}

local function insertAfter(key, row)
  for index, current in ipairs(optionSchema) do
    if current.key == key then
      table.insert(optionSchema, index + 1, row)
      return
    end
  end
  error("QOL_SUITE: missing option insertion point " .. tostring(key), 0)
end

if isGen1 then
  insertAfter("lowHealthAlarm", {
    key = "experienceBar", label = "XP BAR", type = "toggle", default = true,
  })
  insertAfter("experienceBar", {
    key = "caughtIndicator", label = "CAUGHT MARKER", type = "toggle", default = true,
  })
else
  insertAfter("autoBattle", {
    key = "autoStopShiny", label = "STOP ON SHINY", type = "toggle",
    default = false, visible_if = when("autoBattle", true),
  })
  -- CATCH SHINY ONLY is a Gold-only AUTO CATCH gate: when on, AUTO CATCH
  -- only fires against a shiny wild Pokemon. It mirrors STOP ON SHINY (the
  -- opposite policy) and sits under AUTO CATCH so it hides with it.
  insertAfter("autoCatch", {
    key = "catchShinyOnly", label = "CATCH SHINY ONLY", type = "toggle",
    default = false, visible_if = when("autoCatch", true),
  })
  insertAfter("partyOverview", {
    key = "eggTracker", label = "EGG TRACKER", type = "toggle", default = false,
  })

  local anchor = "encounterTrackerFishing"
  for _, row in ipairs({
    { key = "encounterTrackerTime", label = "SHOW TIME OF DAY", type = "toggle", default = true },
    { key = "encounterTrackerSwarms", label = "SHOW SWARMS", type = "toggle", default = true },
    { key = "encounterTrackerRoaming", label = "SHOW ROAMING", type = "toggle", default = true },
    { key = "encounterTrackerRare", label = "SHOW RARE", type = "toggle", default = true },
    { key = "encounterTrackerHeadbutt", label = "SHOW HEADBUTT", type = "toggle", default = true },
    { key = "encounterTrackerRockSmash", label = "SHOW ROCK SMASH", type = "toggle", default = true },
    { key = "encounterTrackerContest", label = "SHOW BUG CONTEST", type = "toggle", default = true },
  }) do
    row.visible_if = when("encounterTracker", true)
    insertAfter(anchor, row)
    anchor = row.key
  end
end

return optionSchema
