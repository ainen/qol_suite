-- Flat-settings regression test for supported gen1recomp 0.1.x releases.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
-- Load the manager first because the test loader can import mods from its own
-- dependency chain. The production application has already loaded it before
-- opening the in-game Mods screen.
local ManagerState = require("src.mods.ManagerState")
if GameVersion.set then GameVersion.set("red") end
local run = T.sdk.loadMod("qol_suite", {
  data = T.fixtures.fresh(), root = "..",
})

T.eq(#run.errors, 0, "supported 0.1.95+/0.2.x settings package load is clean")
local manifest = run.loader.mods.qol_suite.manifest
local Semver = require("src.mods.Semver")
T.eq(manifest.game_version, ">=0.1.95 <0.3.0",
  "the manifest targets engine lines that ship native visible_if")
T.check(Semver.satisfies("0.1.95", manifest.game_version)
    and Semver.satisfies("0.1.99", manifest.game_version)
    and Semver.satisfies("0.2.0", manifest.game_version)
    and Semver.satisfies("0.2.3", manifest.game_version),
  "supported engine releases satisfy the range")
T.check(not Semver.satisfies("0.1.94", manifest.game_version)
    and not Semver.satisfies("0.3.0", manifest.game_version),
  "pre-native and future major-minor engine lines stay outside the range")
local schema = run.loader.optionSchemas.qol_suite
T.eq(#schema, 53, "RBY receives every setting as a flat row")
for _, row in ipairs(schema) do
  T.check(row.type == "toggle" or row.type == "choice"
      or row.type == "number" or row.type == "text",
    "supported row type: " .. tostring(row.key))
  T.eq(row.options, nil,
    "schema contains no nested child list: " .. tostring(row.key))
end
local nativeConditions = 0
for _, row in ipairs(schema) do
  if row.visible_if ~= nil then
    T.check(type(row.visible_if) == "table" and row.visible_if ~= nil
        and (row.visible_if.key ~= nil),
      "dependent row " .. tostring(row.key) .. " uses a single-parent visible_if")
    nativeConditions = nativeConditions + 1
  end
end
T.eq(nativeConditions, 28,
  "RBY declares native single-parent visibility on 28 dependent rows")
T.check(run.loader.exports.qol_suite ~= nil,
  "settings initialize every runtime feature")

local manager = setmetatable({
  game = {
    save = { options = {} },
    mods = run.loader,
  },
  currentMod = { id = "qol_suite" },
  screen = "options",
  cursor = 1,
  scroll = 0,
  persistOptions = function() end,
  notify = function(self, message) self.notice = message end,
}, { __index = ManagerState })

local function rowById(rows, id)
  for _, row in ipairs(rows or {}) do
    if row.id == id then return row end
  end
  return nil
end

manager.optionRows = manager:buildOptionRows(manager.currentMod, schema)
T.check(rowById(manager.optionRows, "minimap") ~= nil,
  "MINIMAP remains visible as a parent setting")
T.check(rowById(manager.optionRows, "minimapCorner") == nil,
  "MINIMAP children are hidden while it is disabled")
T.check(rowById(manager.optionRows, "autoCatch") == nil,
  "AUTO CATCH is hidden while AUTO BATTLE is disabled")

rowById(manager.optionRows, "minimap").step()
T.check(rowById(manager.optionRows, "minimapCorner") ~= nil
    and rowById(manager.optionRows, "tracking") ~= nil,
  "MINIMAP children appear immediately after enabling it")
rowById(manager.optionRows, "minimap").step()
T.check(rowById(manager.optionRows, "minimapCorner") == nil,
  "MINIMAP children disappear immediately after disabling it")

rowById(manager.optionRows, "autoBattle").step()
T.check(rowById(manager.optionRows, "autoCatch") ~= nil,
  "AUTO CATCH appears after enabling AUTO BATTLE")
rowById(manager.optionRows, "autoCatch").step()
T.check(rowById(manager.optionRows, "autoCatchBall") ~= nil,
  "catch controls appear after enabling AUTO CATCH")
manager:setOption("qol_suite", "autoCatchBall", "worst")
rowById(manager.optionRows, "autoCatch").step()
T.check(rowById(manager.optionRows, "autoCatchBall") == nil,
  "AUTO CATCH BALL hides when its direct parent AUTO CATCH is disabled")
rowById(manager.optionRows, "__reset").activate()
T.eq(run.loader.modOptions.qol_suite.autoCatchBall, "best",
  "RESET DEFAULTS restores hidden dependent settings too")

T.finish("release_options")
