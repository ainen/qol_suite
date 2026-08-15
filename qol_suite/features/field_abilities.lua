-- QoL Suite: use common field abilities directly from the
-- overworld when the player is in a position where they apply.  The engine
-- only surfaces field moves through the party menu.  This feature listens on
-- the A-press event the engine already emits ("world.interacted", which
-- carries the facing cell and resolves to kind "none" on empty tiles like
-- water and trees, or "npc" for a faced boulder), runs the same eligibility
-- gates the party menu uses, and then either prompts with a YES/NO box or,
-- with the auto sub-toggle, executes immediately.  Everything else (texts,
-- surfing state, sprites, music, the white-flash ride onto the water, the
-- tree animation, and directional boulder pushing) remains in the engine.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Game = require("src.core.Game")
  local TextBox = require("src.render.TextBox")
  local Transition = require("src.render.Transition")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true

  -- Single-page prompts (18 cols x 2 lines) so the YES/NO box appears as
  -- soon as the text types out, with the cursor parked on NO.
  local PROMPTS = {
    surf = "The water is calm\nhere.  Use SURF?",
    cut = "The tree blocks\nthe way.  Use CUT?",
    strength = "A rock blocks the\nway.  Use STRENGTH?",
    flash = "Use FLASH?",
  }

  -- Which field ability applies at the interaction spot, if any.
  -- SURF and CUT only claim empty-tile presses -- an NPC, sign, door,
  -- hidden object, or script got there first.  STRENGTH is the exception the
  -- engine needs: a boulder is an NPC, so it claims only a faced pushable NPC.
  -- The engine's own gates then decide move/badge eligibility for SURF/CUT,
  -- while partyKnows supplies the move gate for STRENGTH.
  local function opportunity(ow, kind, fx, fy)
    if not (ow and ow.map and ow.player) then return nil end
    if ow.player.surfing then return nil end

    if kind == "none" then
      local surf = ow.useSurfFieldMove and ow:useSurfFieldMove()
      if surf == "ok" then return "surf" end
      local cut = ow.useCutFieldMove and ow:useCutFieldMove()
      if cut == "ok" then return "cut" end
    elseif kind ~= "npc" then
      return nil
    end

    -- Check for STRENGTH: facing a pushable boulder, player knows STRENGTH,
    -- and strength is not already active.
    if not ow.strengthActive and ow.pushableAtCell then
      if fx == nil or fy == nil then
        if not ow.player.facingCell then return nil end
        fx, fy = ow.player:facingCell()
      end
      local pushingNpc = ow:pushableAtCell(fx, fy)
      if pushingNpc and ow.partyKnows and ow:partyKnows("STRENGTH") then
        return "strength"
      end
    end
    return nil
  end

  -- The engine exposes Strength as a state gate rather than a dedicated
  -- executor.  PartyMenu's native action sets this flag, and movement then
  -- performs the normal two-step boulder push.  Keep that native path intact
  -- and provide only the missing overworld activation here.
  local function activateStrength(ow)
    if not (ow and ow.partyKnows and ow:partyKnows("STRENGTH")) then
      return false
    end
    ow.strengthActive = true
    return true
  end

  -- FLASH has no facing tile.  Offer it once when a dark map is entered,
  -- using the same party and badge gates as the native party menu.  RBY owns
  -- the dark-map redraw on OverworldState; Gold queues its native field-move
  -- result so the existing palette/text path remains in charge.
  local function flashResult(ow)
    if not ow then return nil end
    if isGold then
      local FieldMoves = require("src.world.gen2.FieldMoves")
      local ctx = ow:fieldContext()
      local result = FieldMoves.flashFromMenu(ctx)
      if not result.ok then return nil end
      result.mon = ow:partyMoveUser("FLASH")
      if not result.mon then return nil end
      return result
    end
    if not ow.dark or Game.save.flashLit then return nil end
    if not (ow.partyKnows and ow:partyKnows("FLASH")) then return nil end
    local badges = Game.save.inventory or {}
    if not badges.BOULDERBADGE then return nil end
    return { ok = true, action = "flash", mon = ow:partyKnows("FLASH") }
  end

  local function executeFlash(ow, game, auto)
    local result = flashResult(ow)
    if not result then return false end
    local run = function()
      if isGold then
        ow:useFieldMove("FLASH", result.mon)
        return true
      end
      Game.save.flashLit = true
      game.stack:push(TextBox.new(game,
        game.data.text._FlashLightsAreaText
          or "A blinding FLASH\nlights the area!", function()
          ow:setDark(false)
          game.stack:push(Transition.whiteFlash(game))
        end))
      return true
    end
    if auto then return run() end
    if not (game and game.stack
        and type(game.stack.push) == "function") then
      return run()
    end
    game.stack:push(TextBox.new(game, PROMPTS.flash, nil, {
      choice = function(yes)
        if yes then run() end
      end,
      defaultNo = true,
    }))
    return true
  end

  -- Execute the ability.  With auto on, or no prompt wanted, the engine's
  -- executor runs immediately (its own got-on / hacked-away text still
  -- shows); with a prompt, a YES/NO box asks first and the executor runs
  -- only on YES.  STRENGTH activates the engine state gate; subsequent
  -- directional input uses the native boulder-push implementation.
  local function execute(ow, fx, fy, ability, game, auto)
    if not ow then return false end
    local method = ability == "surf" and ow.trySurf
      or ability == "cut" and ow.tryCut
    if ability ~= "strength" and not method then return false end
    local run = function()
      if ability == "strength" then
        return activateStrength(ow)
      end
      method(ow, fx, fy)
      return true
    end
    if auto or not (game and game.stack
        and type(game.stack.push) == "function") then
      return run()
    end
    game.stack:push(TextBox.new(game, PROMPTS[ability], nil, {
      choice = function(yes)
        if yes then run() end
      end,
      defaultNo = true,
    }))
    return true
  end

  -- Gold already offers these field moves from an overworld A press,
  -- but its native path lives on World:runOverworldFieldMove rather than the
  -- Gen 1 OverworldController helpers above.  Preserve that complete native
  -- implementation and remove only its YES/NO gate when AUTO FIELD MOVES is
  -- enabled.  Copy the result so shared engine data is never mutated.
  if isGold then
    local GoldWorld = require("src.world.gen2.World")
    if type(GoldWorld.runOverworldFieldMove) == "function"
        and not GoldWorld._qolSuiteFieldAbilitiesPatched then
      local originalRunOverworldFieldMove = GoldWorld.runOverworldFieldMove
      local autoActions = {
        cut = true, surf = true, strength = true,
        headbutt = true, rocksmash = true,
        whirlpool = true, waterfall = true,
      }
      function GoldWorld:runOverworldFieldMove(result)
        if mod.options:get("fieldAbilities") == true
            and mod.options:get("fieldAbilitiesAuto") == true
            and type(result) == "table" and result.ok == true
            and result.ask ~= nil and autoActions[result.action] then
          local withoutPrompt = {}
          for key, value in pairs(result) do withoutPrompt[key] = value end
          withoutPrompt.ask = nil
          return originalRunOverworldFieldMove(self, withoutPrompt)
        end
        return originalRunOverworldFieldMove(self, result)
      end
      GoldWorld._qolSuiteFieldAbilitiesPatched = true
    end
  end

  mod.events:on("map.entered", function()
    if mod.options:get("fieldAbilities") ~= true then return end
    local ow = Game.overworld
    executeFlash(ow, Game, mod.options:get("fieldAbilitiesAuto") == true)
  end)

  mod.events:on("world.interacted", function(evt)
    if mod.options:get("fieldAbilities") ~= true then return end
    local ow = Game.overworld
    local ability = opportunity(ow, evt and evt.kind,
      evt and evt.x, evt and evt.y)
    if not ability then return end
    execute(ow, evt.x, evt.y, ability, Game,
      mod.options:get("fieldAbilitiesAuto") == true)
  end)

  mod.exports = {
    opportunity = opportunity,
    execute = execute,
    executeFlash = executeFlash,
    flashResult = flashResult,
    activateStrength = activateStrength,
    goldAutoSupported = isGold,
  }
end
