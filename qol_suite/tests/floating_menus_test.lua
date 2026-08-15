-- FLOATING MENUS focused regression test. Run from the gen1recomp checkout.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Font = require("src.render.Font")
local originalDrawBox = Font.drawBox
local originalRectangle = love.graphics.rectangle
local originalGetColor = love.graphics.getColor
local rectangleCalls = {}
local getColorCalls = 0
love.graphics.rectangle = function(...)
  rectangleCalls[#rectangleCalls + 1] = { ... }
  return originalRectangle(...)
end
love.graphics.getColor = function(...)
  getColorCalls = getColorCalls + 1
  return originalGetColor(...)
end
local run = T.sdk.loadMod("qol_suite", { data = T.fixtures.fresh(), root = ".." })
local MOD_ID = "qol_suite"
local floating = run.loader.exports[MOD_ID].floatingMenus
local hooks = run.loader.hooks

T.check(#run.errors == 0, "FLOATING MENUS package load is clean")
T.check(type(floating.enabled) == "function",
  "FLOATING MENUS exposes its enabled helper")
T.check(type(floating.floating) == "function",
  "FLOATING MENUS exposes its state classifier")
T.check(type(floating.screenHookActive) == "function",
  "FLOATING MENUS exposes dynamic hook state")
T.check(type(floating.state) == "function",
  "FLOATING MENUS exposes transient-state diagnostics")
T.check(Font.drawBox == originalDrawBox,
  "FLOATING MENUS preserves white Font.drawBox interiors")
local floatingSchema
for _, row in ipairs(run.loader.optionSchemas[MOD_ID]) do
  if row.key == "floatingMenus" then
    floatingSchema = row
    break
  end
end
T.check(floatingSchema ~= nil,
  "FLOATING MENUS is present in the settings schema")

local function chainCount(bus, name)
  local chain = bus.chains[name]
  return chain and #chain or 0
end

local menu = { isOpaque = true, screenId = "BagMenu" }
local overworld = { isOpaque = true, isOverworld = true }
local battle = { isOpaque = true, isBattle = true }

T.check(not floating.screenHookActive(),
  "disabled FLOATING MENUS does not subscribe screen.render_visible")
T.eq(chainCount(hooks, "screen.render_visible"), 0,
  "disabled FLOATING MENUS leaves the screen hot path empty")

run.loader.modOptions[MOD_ID] = { floatingMenus = false }
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "floatingMenus", value = false })
hooks:call("screen.render_visible", function(state) return state end, menu)
T.eq(menu.isOpaque, true,
  "a disabled FLOATING MENUS option preserves menu opacity")

run.loader.modOptions[MOD_ID] = { floatingMenus = true }
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "floatingMenus", value = true })
hooks:call("screen.render_visible", function(state) return state end, menu)
T.eq(menu.isOpaque, false,
  "an enabled FLOATING MENUS option makes menu screens transparent")
T.check(floating.floating(menu),
  "ordinary menu screens are classified as floating")
T.check(floating.floating({ isOpaque = true, screenId = "Gen2PackMenu" }),
  "Gold gameplay menus are classified as floating")
T.check(floating.screenHookActive(),
  "enabled FLOATING MENUS subscribes screen.render_visible")
T.eq(chainCount(hooks, "screen.render_visible"), 1,
  "FLOATING MENUS installs exactly one screen hook")

local function gen1ScreenId(...)
  return table.concat({ ... })
end
for _, id in ipairs({
  gen1ScreenId("Title", "State"), "Gen2TitleState", "YellowIntro", "IntroMovie",
  gen1ScreenId("Oak", "Speech"), "Gen2GoldSilverIntro", "EvolutionState",
  "Gen2EvolutionAnim", gen1ScreenId("Trade", "Anim"), "Gen2TradeAnim",
  gen1ScreenId("Cred", "its"), "Gen2Credits",
  gen1ScreenId("Slot", "Machine"), "SurfingMinigame", "Gen2CardFlip",
  "Gen2ContestMenu", "Gen2EggHatchAnim",
}) do
  local state = { isOpaque = true, screenId = id }
  T.check(not floating.floating(state),
    id .. " keeps its native opaque presentation")
  hooks:call("screen.render_visible", function(value) return value end, state)
  T.eq(state.isOpaque, true,
    id .. " is not made transparent by the screen hook")
end
T.check(not floating.floating({ isOpaque = true, screenId = "UnknownState" }),
  "unknown states default to native opacity")

-- Re-arm the menu after excluded-state checks so primitive filtering observes
-- an active menu render rather than the last excluded state.
hooks:call("screen.render_visible", function(state) return state end, menu)

local ordinaryColorCalls = getColorCalls
love.graphics.rectangle("fill", 8, 8, 16, 16)
T.eq(getColorCalls, ordinaryColorCalls,
  "ordinary rectangles bypass the floating-background color check")

love.graphics.setColor(1, 1, 1, 1)
local whiteCalls = #rectangleCalls
love.graphics.rectangle("fill", 0, 0, 160, 144)
T.eq(#rectangleCalls, whiteCalls + 1,
  "FLOATING MENUS keeps a white full-screen menu fill")
love.graphics.setColor(0, 0, 0, 1)
local blackCalls = #rectangleCalls
love.graphics.rectangle("fill", 0, 0, 160, 144)
T.eq(#rectangleCalls, blackCalls,
  "FLOATING MENUS removes a black full-screen menu fill")

hooks:call("screen.render_visible", function(state) return state end, overworld)
T.eq(overworld.isOpaque, true,
  "FLOATING MENUS does not change overworld opacity")
hooks:call("screen.render_visible", function(state) return state end, battle)
T.eq(battle.isOpaque, true,
  "FLOATING MENUS does not change battle opacity")

run.loader.modOptions[MOD_ID] = { floatingMenus = false }
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "floatingMenus", value = false })
hooks:call("screen.render_visible", function(state) return state end, menu)
T.eq(menu.isOpaque, true,
  "turning FLOATING MENUS off restores the original opacity")
T.check(not floating.screenHookActive(),
  "turning FLOATING MENUS off unsubscribes the screen hook")
T.eq(chainCount(hooks, "screen.render_visible"), 0,
  "disabled FLOATING MENUS removes its screen hook")
local disabledState = floating.state()
T.check(not disabledState.floatingVisible
    and not disabledState.suppressBlackBackground,
  "disabling clears every transient transparency flag")
local disabledColorCalls = getColorCalls
love.graphics.rectangle("fill", 0, 0, 160, 144)
T.eq(getColorCalls, disabledColorCalls,
  "disabled FLOATING MENUS bypasses full-screen color inspection")

for _ = 1, 3 do
  run.loader.events:emit("mod.options_changed",
    { mod = MOD_ID, key = "floatingMenus", value = true })
  T.eq(chainCount(hooks, "screen.render_visible"), 1,
    "toggle cycles never duplicate the screen hook")
  run.loader.events:emit("mod.options_changed",
    { mod = MOD_ID, key = "floatingMenus", value = false })
  T.eq(chainCount(hooks, "screen.render_visible"), 0,
    "toggle cycles always unsubscribe the screen hook")
end

run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "floatingMenus", value = true })
hooks:call("screen.render_visible", function(state) return state end, menu)
T.eq(menu.isOpaque, false,
  "pre-reload menu state is transparent")
local reloadRun = T.sdk.loadMod("qol_suite", {
  data = T.fixtures.fresh(), root = "..",
})
local reloaded = reloadRun.loader.exports[MOD_ID].floatingMenus
T.eq(#reloadRun.errors, 0, "FLOATING MENUS reload is clean")
T.eq(menu.isOpaque, true,
  "reload restores opacity changed by the discarded controller")
T.eq(chainCount(hooks, "screen.render_visible"), 0,
  "reload unsubscribes the discarded controller's screen hook")
T.check(not reloaded.enabled() and not reloaded.screenHookActive(),
  "reload starts disabled without stale screen subscriptions")
local reloadState = reloaded.state()
T.check(not reloadState.floatingVisible
    and not reloadState.suppressBlackBackground,
  "reload starts with clean transparency globals")

love.graphics.rectangle = originalRectangle
love.graphics.getColor = originalGetColor
T.finish("floating_menus")
