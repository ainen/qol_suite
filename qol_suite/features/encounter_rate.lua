-- ENCOUNTER RATE: multiply the native wild-encounter chance while preserving
-- the map's encounter tables, slot probabilities, repel checks, and native
-- music/items modifiers.
--
-- This feature used to register an `encounter.rate` hook.  That hook is not a
-- call site in the current engine, though: RBY performs the rate comparison
-- inside Encounter.roll, while Gold performs it in Encounter.triggers (and
-- uses a separate trigger for the Bug-Catching Contest).  Patch those shared
-- helpers instead so the option changes the real step gate in both games.
return function(mod)
  local GameSpeed = require("src.core.GameSpeed")
  local GameVersion = require("src.core.GameVersion")
  local OPTION = "encounterRate"

  local function multiplier()
    return GameSpeed.clamp(mod.options:get(OPTION))
  end

  local function scale(rate, value)
    rate = tonumber(rate)
    if rate == nil or rate ~= rate then return rate end
    value = tonumber(value) or multiplier()
    if value ~= value then value = 1 end
    if value <= 1 or rate <= 0 then return rate end
    -- Encounter rates are byte comparisons.  256 means guaranteed, while
    -- larger products must not wrap around and make a high setting rarer.
    return math.min(256, math.floor(rate * value + 0.5))
  end

  local function installRbyPatch()
    local Encounter = require("src.world.Encounter")
    if Encounter._qolSuiteEncounterRatePatched then
      Encounter._qolSuiteEncounterRateScale = scale
      return
    end

    local originalRoll = Encounter.roll
    Encounter.roll = function(encounterDef, rng)
      local grass = encounterDef and encounterDef.grass
      if not grass or grass.rate == nil then
        return originalRoll(encounterDef, rng)
      end

      local rate = Encounter._qolSuiteEncounterRateScale(grass.rate)
      if rate == grass.rate then
        return originalRoll(encounterDef, rng)
      end

      -- Encounter.roll only reads the rate and the slot data.  Copy the two
      -- small tables rather than mutating the map's cached encounter data.
      local patchedGrass = {}
      for key, value in pairs(grass) do patchedGrass[key] = value end
      patchedGrass.rate = rate
      local patchedDef = {}
      for key, value in pairs(encounterDef) do patchedDef[key] = value end
      patchedDef.grass = patchedGrass
      return originalRoll(patchedDef, rng)
    end
    Encounter._qolSuiteEncounterRatePatched = true
    Encounter._qolSuiteEncounterRateScale = scale
  end

  local function installGoldPatch()
    local Encounter = require("src.battle.gen2.Encounter")
    if not Encounter._qolSuiteEncounterRatePatched then
      local originalTriggers = Encounter.triggers
      Encounter.triggers = function(rate, random)
        return originalTriggers(
          Encounter._qolSuiteEncounterRateScale(rate), random)
      end
      Encounter._qolSuiteEncounterRatePatched = true
      Encounter._qolSuiteEncounterRateOriginalTriggers = originalTriggers
    end
    Encounter._qolSuiteEncounterRateScale = scale

    -- Gold's Bug-Catching Contest has its own 20%/40% step gate rather than
    -- calling Encounter.triggers.  Scaling encounterRate keeps that native
    -- branch consistent with ordinary wild encounters without changing its
    -- contest-specific species table or ball rules.
    local BugContest = require("src.core.gen2.BugContest")
    if not BugContest._qolSuiteEncounterRatePatched then
      local originalRate = BugContest.encounterRate
      BugContest.encounterRate = function(superTallGrass)
        return BugContest._qolSuiteEncounterRateScale(
          originalRate(superTallGrass))
      end
      BugContest._qolSuiteEncounterRatePatched = true
      BugContest._qolSuiteEncounterRateOriginalRate = originalRate
    end
    BugContest._qolSuiteEncounterRateScale = scale
  end

  if GameVersion.isGold and GameVersion.isGold() then
    installGoldPatch()
  else
    installRbyPatch()
  end

  mod.exports = {
    multiplier = multiplier,
    scale = scale,
  }
end
