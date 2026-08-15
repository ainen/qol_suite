-- ENCOUNTER RATE focused regression test. Run from the gen1recomp checkout:
--   luajit mods/qol_suite/tests/encounter_rate_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"
local rate = run.loader.exports[MOD_ID].encounterRate
local GameVersion = require("src.core.GameVersion")

T.eq(#run.errors, 0, "ENCOUNTER RATE package loads clean")
T.eq(rate.multiplier(), 1, "ENCOUNTER RATE defaults to normal")
T.eq(rate.scale(25, 1), 25, "normal scaling preserves the native rate")
T.eq(rate.scale(25, 4), 100, "scaling multiplies the native rate")
T.eq(rate.scale(200, 2), 256, "scaling caps at a guaranteed encounter")
T.eq(rate.scale(0, 200), 0, "a map with no encounters stays disabled")

run.loader.modOptions[MOD_ID] = { encounterRate = 4 }
T.eq(rate.multiplier(), 4, "the selected ENCOUNTER RATE is read from options")

for _, multiplier in ipairs({ 1, 2, 3, 4, 10, 20, 30, 50, 75, 100, 200 }) do
  run.loader.modOptions[MOD_ID] = { encounterRate = multiplier }
  local expected = math.min(256, 25 * multiplier)
  T.eq(rate.scale(25), expected,
    "the " .. tostring(multiplier) .. "X setting scales encounter rolls")
end

run.loader.modOptions[MOD_ID] = { encounterRate = 1 }
T.eq(rate.scale(25), 25, "normal ENCOUNTER RATE leaves water rates unchanged")

if GameVersion.isGold and GameVersion.isGold() then
  local Encounter = require("src.battle.gen2.Encounter")
  local roll = function() return 30 end
  T.eq(Encounter.triggers(25, roll), false,
    "Gold's native encounter gate still misses above its normal rate")
  run.loader.modOptions[MOD_ID] = { encounterRate = 4 }
  T.eq(Encounter.triggers(25, roll), true,
    "Gold's encounter trigger uses the selected multiplier")

  local BugContest = require("src.core.gen2.BugContest")
  T.eq(BugContest.encounterRate(false), 51,
    "Gold's Bug Contest keeps its native rate at 1X")
  run.loader.modOptions[MOD_ID] = { encounterRate = 4 }
  T.eq(BugContest.encounterRate(false), 204,
    "Gold's Bug Contest trigger uses the selected multiplier")
else
  local Encounter = require("src.world.Encounter")
  local def = {
    grass = { rate = 25, buckets = { 256 },
      slots = { { species = "RATTATA", level = 3 } } },
  }
  local function fixedRoll()
    return 30
  end
  run.loader.modOptions[MOD_ID] = { encounterRate = 1 }
  T.eq(Encounter.roll(def, fixedRoll), nil,
    "RBY's native encounter roll still misses above its normal rate")
  run.loader.modOptions[MOD_ID] = { encounterRate = 4 }
  T.eq(Encounter.roll(def, fixedRoll).species, "RATTATA",
    "RBY's encounter roll uses the selected multiplier")
  T.eq(def.grass.rate, 25,
    "RBY's encounter multiplier does not mutate the map encounter table")
end

T.finish("encounter_rate")
