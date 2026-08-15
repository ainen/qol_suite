-- EXP SHARE: emulate the game's built-in EXP.ALL item without requiring the
-- item to be present in the save.  The engine's battle award routine already
-- implements the exact Gen 1 split; it only checks whether EXP_ALL is held.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local OPTION = "expShare"

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    if not enabled() then return next(ctx) end

    local battle = ctx and ctx.battle
    -- Gold determines its real EXP.SHARE holders before this hook runs, so
    -- changing held items here is too late (and risks leaking a temporary item
    -- onto a Pokemon that originally held nothing).  Run the two native award
    -- passes directly instead: participants divide one half, then every live
    -- non-Egg party member divides the other half.  giveExperiencePass owns
    -- Gold's exact rounding, stat EXP, Lucky Egg/traded boosts, messages,
    -- level-ups, and move learning, while no held item is changed.
    if GameVersion.isGold and GameVersion.isGold() then
      local party = battle and battle.party
      local recipients = ctx and ctx.recipients
      local loser = ctx and ctx.loser
      if type(party) ~= "table" or type(recipients) ~= "table"
          or not loser or type(battle.giveExperiencePass) ~= "function"
          or type(battle.speciesDef) ~= "function" then
        return next(ctx)
      end
      local shared = {}
      for index, mon in ipairs(party) do
        if mon and (mon.hp or 0) > 0 and not mon.isEgg then
          shared[#shared + 1] = index
        end
      end
      if #shared == 0 then return next(ctx) end
      local def = battle:speciesDef(loser)
      battle:giveExperiencePass(loser, def, recipients,
        math.max(1, #recipients), true)
      battle:giveExperiencePass(loser, def, shared, #shared, true)
      return
    end

    local game = battle and battle.game
    local save = game and game.save
    local inventory = save and save.inventory
    if type(inventory) ~= "table" then return next(ctx) end

    -- The vanilla award path treats any positive EXP_ALL quantity as active.
    -- Preserve a real item quantity and restore a missing/zero entry after the
    -- award so this toggle never changes the player's inventory.
    local previous = inventory.EXP_ALL
    if tonumber(previous) and tonumber(previous) > 0 then
      return next(ctx)
    end

    inventory.EXP_ALL = 1
    local ok, err = pcall(next, ctx)
    if previous == nil then
      inventory.EXP_ALL = nil
    else
      inventory.EXP_ALL = previous
    end
    if not ok then error(err, 0) end
  end)

  mod.exports = {
    enabled = enabled,
  }
end
