-- ENCOUNTER TRACKER focused regression test.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
Data.encounters = {
  FIX_ROUTE = {
    grass = {
      rate = 25,
      slots = {
        { level = 3, species = "FIXMON_A" },
        { level = 4, species = "FIXMON_C" },
      },
    },
    water = {
      rate = 20,
      slots = { { level = 5, species = "FIXMON_B" } },
    },
  },
}
Data.field = Data.field or {}
Data.field.fishing = {
  OLD_ROD = { always = { level = 5, species = "FIXMON_F" } },
  GOOD_ROD = { pool = { { level = 6, species = "FIXMON_G" } } },
  SUPER_ROD = { perMap = "superRod" },
}
Data.field.superRod = {
  FIX_ROUTE = { { level = 7, species = "FIXMON_H" } },
}
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"
local tracker = run.loader.exports[MOD_ID].encounterTracker
local tracking = run.loader.exports[MOD_ID].tracking
local minimap = run.loader.exports[MOD_ID].minimap

T.check(#run.errors == 0, "ENCOUNTER TRACKER package load is clean")
T.check(tracker.enabled() == false,
  "ENCOUNTER TRACKER is disabled by default")
run.loader.modOptions[MOD_ID] = {
  minimap = true, tracking = true, encounterTracker = true,
}
local game = { data = Data, save = {} }
local world = { overworld = function()
  return { daytime = "DAY" }
end }
tracking.toggle(game, "FIXMON_A")
local model = tracker.collect(game, world, { mapId = "FIX_ROUTE" })
T.eq(model.timeLabel, "ANY TIME",
  "Gen 1 encounter tracker reports all-time encounters")
T.eq(#model.groups, 5,
  "encounter tracker includes grass, surfing, and all fishing rods")
T.eq(model.groups[1].label, "GRASS",
  "grass encounters are listed first")
T.eq(model.groups[1].entries[1].name, "FIXMON A",
  "encounter tracker resolves species names")
T.eq(model.groups[1].entries[1].min, 3,
  "encounter tracker preserves minimum level")
T.check(model.groups[1].entries[1].tracked,
  "Tracking highlights the tracked species in the encounter model")
T.eq(model.groups[2].label, "SURF",
  "surfing encounters are labeled separately")
T.eq(model.groups[3].label, "OLD ROD",
  "old rod encounters are listed separately")
T.eq(model.groups[3].entries[1].name, "FIXMON F",
  "old rod encounters use the engine's always-catch entry")
T.eq(model.groups[5].label, "SUPER ROD",
  "super rod encounters are listed separately")
local lines = tracker.format(model, 28, 10)
local text = {}
for _, line in ipairs(lines) do text[#text + 1] = line.text end
local joined = table.concat(text, "\n")
T.check(joined:find("ENCOUNTERS ANY TIME", 1, true) == nil,
  "Gen 1 encounter tracker omits the time scope heading")
T.check(joined:find("TRACKED FIXMON A", 1, true) ~= nil,
  "encounter tracker includes the active Tracking species")
T.check(joined:find("SURF", 1, true) ~= nil,
  "encounter tracker formatter includes surfing")
local filteredLines = tracker.format(model, 28, 10, {
  tracked = false, land = true, surf = false, fishing = false,
  time = true,
})
local filtered = {}
for _, line in ipairs(filteredLines) do filtered[#filtered + 1] = line.text end
local filteredText = table.concat(filtered, "\n")
T.check(filteredText:find("GRASS", 1, true) ~= nil,
  "encounter tracker keeps the enabled land section")
T.check(filteredText:find("SURF", 1, true) == nil,
  "encounter tracker hides surfing when disabled")
T.check(filteredText:find("OLD ROD", 1, true) == nil,
  "encounter tracker hides fishing when disabled")
T.check(filteredText:find("TRACKED", 1, true) == nil,
  "encounter tracker hides the tracked callout when disabled")
local emptyLines = tracker.format(model, 28, 10, {
  tracked = false, land = false, surf = false, fishing = false,
  time = false,
})
T.eq(emptyLines[#emptyLines].text, "NO ENCOUNTERS SHOWN",
  "encounter tracker explains when all sections are hidden")
T.check(tracker.collect(game, {}, { mapId = "FIX_ROUTE" }) ~= nil,
  "encounter tracker tolerates an unavailable overworld facade")
local roamerKeyBefore = tracker.key({ save = { roamers = {
  { species = "FIXMON_A", map = "FIX_ROUTE" },
} } }, world, { mapId = "FIX_ROUTE" })
local roamerKeyAfter = tracker.key({ save = { roamers = {
  { species = "FIXMON_A", map = "FIX_TOWN" },
} } }, world, { mapId = "FIX_ROUTE" })
T.check(roamerKeyBefore ~= roamerKeyAfter,
  "encounter tracker invalidates its cache when a roamer moves")
T.check(tracker.collect({ data = Data, save = { roamers = "corrupt" } },
  world, { mapId = "FIX_ROUTE" }) ~= nil,
  "encounter tracker ignores malformed roaming data")

-- The HUD wrapper should exist only while one of its two overlays needs it.
-- Repeated option notifications must not accumulate duplicate wrappers.
local function hookCount(name)
  return #(run.loader.hooks.chains[name] or {})
end
run.loader.modOptions[MOD_ID].minimap = false
run.loader.modOptions[MOD_ID].encounterTracker = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = false,
})
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "encounterTracker", value = false,
})
local disabledHooks = hookCount("render.hud")
T.check(not minimap.hudSubscribed(),
  "MINIMAP removes its HUD hook while both overlays are disabled")

run.loader.modOptions[MOD_ID].minimapTransparency = 100
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimapTransparency", value = 100,
})
run.loader.modOptions[MOD_ID].encounterTracker = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "encounterTracker", value = true,
})
T.check(minimap.hudSubscribed(),
  "standalone ENCOUNTER TRACKER installs the shared HUD hook")
T.eq(minimap.overlayOpacity(false, 100), 1,
  "standalone ENCOUNTER TRACKER stays opaque at hidden-minimap transparency")
local trackerHooks = hookCount("render.hud")
T.eq(trackerHooks, disabledHooks + 1,
  "enabling ENCOUNTER TRACKER adds exactly one HUD wrapper")
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "encounterTracker", value = true,
})
T.eq(hookCount("render.hud"), trackerHooks,
  "repeating an enabled toggle does not duplicate the HUD wrapper")

run.loader.modOptions[MOD_ID].minimap = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = true,
})
run.loader.modOptions[MOD_ID].encounterTracker = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "encounterTracker", value = false,
})
T.check(minimap.hudSubscribed(),
  "MINIMAP keeps the HUD hook after ENCOUNTER TRACKER is disabled")
run.loader.modOptions[MOD_ID].minimap = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "minimap", value = false,
})
T.eq(hookCount("render.hud"), disabledHooks,
  "the final overlay toggle removes the HUD wrapper")
T.check(not minimap.hudSubscribed(),
  "MINIMAP reports no dormant HUD subscription after a toggle cycle")

run.release()
T.finish("encounter_tracker")
