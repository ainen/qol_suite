-- QoL Suite: allow field HMs to be used while they remain in the bag.
--
-- The engine still owns every real field-move check.  This feature only makes
-- an HM in the bag satisfy the party-move lookup and adds the usable HM rows
-- to the party submenu, so badges, map conditions, and the normal field-move
-- effects remain native.
return function(mod, fieldAbilities)
  local GameVersion = require("src.core.GameVersion")
  local FieldDefaults = require("src.world.FieldDefaults")
  local Map = require("src.world.Map")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true

  local OPTION = "hmWithoutTeaching"
  local HM_MOVES = {
    "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "WHIRLPOOL", "WATERFALL",
  }

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  local function teaches(def, itemId, moveId)
    if type(def) ~= "table" then return false end
    local machine = def.machine
    local learned = def.teaches or (machine and machine.move)
    if learned ~= moveId then return false end
    return (machine and machine.kind == "HM")
      or tostring(itemId):match("^HM_") ~= nil
  end

  local function hmItem(save, data, moveId)
    local inventory = save and save.inventory or {}
    for itemId, def in pairs((data and data.items) or {}) do
      if teaches(def, itemId, moveId) and (inventory[itemId] or 0) > 0 then
        return itemId
      end
    end
    local fallback = "HM_" .. moveId
    if (inventory[fallback] or 0) > 0 then return fallback end
    return nil
  end

  local function badgeOwned(save, data, moveId)
    if isGold then
      local FieldMoves = require("src.world.gen2.FieldMoves")
      return FieldMoves.hasBadge(save, FieldMoves.BADGE[moveId])
    end
    local rows = FieldDefaults.constant(data, "hmBadges") or {}
    local row = rows[moveId]
    return not row or not row.badge
      or (save and save.inventory and save.inventory[row.badge]) ~= nil
  end

  local function firstPartyMon(party)
    for _, mon in ipairs(party or {}) do
      if mon and not mon.isEgg and not mon.egg then return mon end
    end
    return nil
  end

  local function eligibilityMon(ctx, moveId)
    if not enabled() or not ctx or not hmItem(ctx.save, ctx.data, moveId)
        or not badgeOwned(ctx.save, ctx.data, moveId) then
      return nil
    end
    return firstPartyMon(ctx.party or (ctx.save and ctx.save.party))
  end

  -- CheckPartyMove is shared by RBY and Gold.  Let a real move user win first;
  -- otherwise an owned HM can stand in for the party lookup.  This hook does
  -- not bypass badges: the engine's original lookup and this fallback both
  -- require the native HM badge gate.
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local mon = next(moveId, ctx)
    if mon or not enabled() then return mon end
    return eligibilityMon(ctx, moveId)
  end)

  local function rbyDirectlyUsable(game, moveId)
    local ow = game and game.overworld
    if not (ow and ow.map and ow.player) then return false end
    if not badgeOwned(game.save, game.data, moveId)
        or not hmItem(game.save, game.data, moveId) then
      return false
    end
    if moveId == "CUT" then
      return ow:useCutFieldMove() == "ok"
    elseif moveId == "SURF" then
      -- The native party action handles dismounting separately.  Only expose
      -- the direct row when this is a mount, not while already surfing.
      return ow:useSurfFieldMove() == "ok"
    elseif moveId == "STRENGTH" then
      return true
    elseif moveId == "FLASH" then
      return ow.dark == true and not game.save.flashLit
    elseif moveId == "FLY" then
      return Map.isOutside(ow.map.def,
        -- With no path arguments, fieldValue returns the same field record as
        -- field while remaining available through the Gen 2 compatibility
        -- facade's supported accessor set.
        FieldDefaults.fieldValue(game.data, "outsideTilesets"))
    end
    return false
  end

  local function goldDirectlyUsable(game, moveId)
    local ow = game and game.world
    if not (ow and ow.map and ow.player) then return false end
    if not badgeOwned(game.save, game.data, moveId)
        or not hmItem(game.save, game.data, moveId) then
      return false
    end
    local FieldMoves = require("src.world.gen2.FieldMoves")
    local result = FieldMoves.fromMenu(moveId, ow:fieldContext(
      firstPartyMon(game.save and game.save.party)))
    return result and result.ok == true
  end

  local function directlyUsable(game, moveId)
    if not hmItem(game and game.save, game and game.data, moveId) then
      return false
    end
    return isGold and goldDirectlyUsable(game, moveId)
      or (not isGold and rbyDirectlyUsable(game, moveId))
  end

  local function hasEntry(items, moveId)
    for _, entry in ipairs(items or {}) do
      if entry.id == moveId or entry.action == moveId:lower()
          or entry.label == moveId then
        return true
      end
    end
    return false
  end

  local function closeParty(game)
    local stack = game and game.stack
    local top = stack and type(stack.top) == "function" and stack:top()
    if top and top.game == game and type(stack.pop) == "function" then
      stack:pop()
    end
  end

  local function useRbyHm(game, moveId)
    local ow = game and game.overworld
    if not (ow and directlyUsable(game, moveId)) then return false end
    closeParty(game)
    if moveId == "FLY" then
      local Screens = require("src.ui.Screens")
      Screens.push(game, "TownMap", {
        fly = true,
        onFly = function(mapId) ow:flyTo(mapId) end,
      })
      return true
    elseif moveId == "FLASH" then
      return fieldAbilities and fieldAbilities.executeFlash
        and fieldAbilities.executeFlash(ow, game, true) == true
    end
    local ability = moveId:lower()
    local fx, fy = ow.player:facingCell()
    return fieldAbilities and fieldAbilities.execute
      and fieldAbilities.execute(ow, fx, fy, ability, game, true)
        == true
  end

  -- Gold's native party submenu has a fieldMove arm; RBY's submenu accepts a
  -- callback row.  The same descriptor works for both.  Only field-usable
  -- HMs are shown, keeping the party menu compact and preventing a row that
  -- would immediately print a refusal.
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local result = next(game, items, mon, ctx)
    if not enabled() or type(result) ~= "table" or (ctx and ctx.battle)
        or not game or not game.save then
      return result
    end
    for _, moveId in ipairs(HM_MOVES) do
      if not hasEntry(result, moveId) and directlyUsable(game, moveId) then
        local entry = {
          id = moveId,
          label = moveId,
          fieldMove = true,
          onSelect = function(_, currentGame)
            if not enabled() then return end
            if isGold then
              -- Gold's PartyMenu consumes the fieldMove descriptor and calls
              -- World:useFieldMove, preserving its native confirmation/effect.
              return
            end
            useRbyHm(currentGame, moveId)
          end,
        }
        result = mod.ui.insertBefore(result, "STATS", entry)
      end
    end
    return result
  end)

  mod.exports = {
    enabled = enabled,
    hmItem = hmItem,
    directlyUsable = directlyUsable,
  }
end
