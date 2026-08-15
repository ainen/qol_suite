-- Gold-only EGG TRACKER: carried egg progress and Day-Care parents.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
if not (GameVersion.VERSIONS and GameVersion.VERSIONS.gold) then
  print("SKIP egg_tracker: requires a Gold-enabled engine checkout")
  return
end
local Data = T.fixtures.fresh()
local originalVersion = GameVersion.get()
GameVersion.set("gold")
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local tracker = run.loader.exports.qol_suite.eggTracker

T.eq(#run.errors, 0, "egg tracker loads clean")
T.check(tracker.enabled() == false, "egg tracker is disabled by default")
local game = {
  data = Data,
  save = {
    party = { { species = "FIXMON_A", isEgg = true, eggSteps = 10 } },
    dayCare = {
      man = { mon = { species = "FIXMON_B" } },
      lady = { mon = { species = "FIXMON_C" } },
      compatible = true,
      stepsToEgg = 90,
    },
  },
}
local model = tracker.snapshot(game)
T.eq(#model.eggs, 1, "egg tracker finds a carried egg")
T.eq(model.eggs[1].steps, 2560,
  "egg tracker converts Gold hatch cycles into steps")
T.eq(model.parents[1], "FIXMON B", "egg tracker reports the first parent")
T.eq(model.parents[2], "FIXMON C", "egg tracker reports the second parent")
local lines = tracker.format(model, 5)
local joined = table.concat(lines, "\n")
T.check(joined:find("PARTY EGG 2560", 1, true) ~= nil,
  "egg tracker formats hatch progress")
T.check(joined:find("P1 FIXMON B", 1, true) ~= nil,
  "egg tracker formats parent information")
local invalidLimitLines = tracker.format(model, 0 / 0)
T.eq(#invalidLimitLines, 3,
  "egg tracker safely defaults a non-finite panel line limit")

T.check(type(tracker.layout) == "function",
  "Gold egg tracker exposes shared overlay geometry")
T.check(type(tracker.renderHookActive) == "function",
  "Gold egg tracker exposes dynamic render-hook state")
local function setOption(key, value)
  run.loader.modOptions.qol_suite = run.loader.modOptions.qol_suite or {}
  run.loader.modOptions.qol_suite[key] = value
  run.loader.events:emit("mod.options_changed", {
    mod = "qol_suite", key = key, value = value,
  })
end
local function renderHookCount()
  local chain = run.loader.hooks.chains["render.hud"]
  return chain and #chain or 0
end
local baseRenderHooks = renderHookCount()
T.check(not tracker.renderHookActive(),
  "disabled egg tracker owns no render.hud hook")
for _ = 1, 3 do
  setOption("eggTracker", true)
  T.check(tracker.renderHookActive(),
    "enabled egg tracker subscribes render.hud")
  T.eq(renderHookCount(), baseRenderHooks + 1,
    "egg tracker toggle cycles install one render hook")
  setOption("eggTracker", true)
  T.eq(renderHookCount(), baseRenderHooks + 1,
    "repeated egg tracker enable does not duplicate its hook")
  setOption("eggTracker", false)
  T.check(not tracker.renderHookActive(),
    "disabled egg tracker releases render.hud")
  T.eq(renderHookCount(), baseRenderHooks,
    "egg tracker toggle cycles restore the baseline hook count")
end
local viewport = { width = 640, height = 480 }
setOption("minimap", true)
setOption("minimapCorner", "top-right")
setOption("encounterTracker", true)
setOption("encounterTrackerCorner", "top-right")
setOption("partyOverview", true)
setOption("partyOverviewCorner", "top-right")
local exports = run.loader.exports.qol_suite
local mapWidth = select(1, exports.overlayLayout.minimapDimensions(
  viewport, 100, 100))
exports.overlayLayout.rememberTracker({
  x = viewport.width - mapWidth - exports.overlayLayout.margin,
  y = 160, width = mapWidth, height = 40,
}, viewport, "top-right")
local partyPanel = exports.partyOverview.layout(viewport)
local eggPanel = tracker.layout(viewport, #lines)
T.eq(eggPanel.corner, "top-right",
  "egg tracker follows PARTY CORNER")
T.eq(eggPanel.y, partyPanel.y + partyPanel.height
  + exports.overlayLayout.gap,
  "egg tracker stacks immediately after party overview")
T.check(eggPanel.y >= partyPanel.y + partyPanel.height,
  "egg tracker cannot overlap the party panel")
T.check(eggPanel.x >= 0 and eggPanel.y >= 0
    and eggPanel.x + eggPanel.width <= viewport.width
    and eggPanel.y + eggPanel.height <= viewport.height,
  "stacked egg tracker stays inside the viewport")

GameVersion.set(originalVersion)
T.finish("egg_tracker")
