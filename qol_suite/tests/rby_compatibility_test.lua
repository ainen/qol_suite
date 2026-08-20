-- RBY generation-gating regression test. Run with QOL_SUITE_TEST_VERSION set
-- to red, blue, or yellow; the headless suite defaults to Red.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local version = string.lower(os.getenv("QOL_SUITE_TEST_VERSION") or "red")

local versionAvailable = GameVersion.VERSIONS and GameVersion.VERSIONS[version]
T.check(versionAvailable,
  "the test checkout exposes " .. version)
if not versionAvailable then
  T.finish("rby_compatibility_unsupported")
  return
end
GameVersion.set(version)

local run = T.sdk.loadMod("qol_suite", { data = T.fixtures.fresh(), root = ".." })
local MOD_ID = "qol_suite"
T.eq(#run.errors, 0, version .. " package load is clean ("
  .. tostring(run.errors[1]) .. ")")
local schema = run.loader.optionSchemas[MOD_ID]
T.eq(#schema, 54, version .. " exposes the complete flat 0.1.x schema")
local keys = {}
for _, row in ipairs(schema) do
  keys[row.key] = true
  T.check(type(row.label) == "string" and #row.label <= 18,
    version .. " setting label fits the settings window: " .. tostring(row.key))
  T.check(row.type == "toggle" or row.type == "choice"
      or row.type == "number" or row.type == "text",
    version .. " uses only supported 0.1.x option row types")
  T.eq(row.options, nil, version .. " option rows are not nested")
end
for _, key in ipairs({ "experienceBar", "caughtIndicator", "wallCollisionSound" }) do
  T.check(keys[key] == true, version .. " exposes Gen 1 option " .. key)
end
for _, key in ipairs({
  "autoStopShiny", "catchShinyOnly", "encounterTrackerTime", "encounterTrackerSwarms",
  "encounterTrackerRoaming", "encounterTrackerRare", "encounterTrackerHeadbutt",
  "encounterTrackerRockSmash", "encounterTrackerContest", "eggTracker",
}) do
  T.check(keys[key] ~= true, version .. " hides Gold-only option " .. key)
end

local exports = run.loader.exports[MOD_ID]
T.check(type(exports) == "table" and #exports.features == 28,
  version .. " loads every QoL Suite runtime module")
T.check(not (GameVersion.isGold and GameVersion.isGold()),
  version .. " follows the RBY generation path")

T.finish("rby_compatibility_" .. version)
