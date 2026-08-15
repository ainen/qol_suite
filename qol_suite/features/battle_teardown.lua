-- BATTLE TEARDOWN: prevent a high battle-speed frame from leaking its
-- remaining fixed-step catch-up into the overworld after the battle ends.
--
-- Game:update resolves the active speed once per rendered frame.  A battle
-- can finish inside FixedStep:update, so without this reset the rest of that
-- frame's steps run the overworld at the battle multiplier.  Besides making
-- NPC movement jump forward, that can leave the overworld's actor/render
-- state out of sync until the next map load.
return function(mod)
  local ok, FixedStep = pcall(require, "src.core.FixedStep")
  if not ok then FixedStep = nil end

  -- A battle can finish inside one fixed-step callback.  The return
  -- transition then runs before the next rendered frame, so the first frame
  -- back in the field is the safest place to repair the live draw list.  The
  -- engine keeps the authoritative NPC collection in `overworld.npcs` and
  -- the renderer/collision code consumes `overworld.entities`.  In normal
  -- play those two lists contain the same ordinary actors, but a battle-speed
  -- catch-up or a script that runs during the return can leave an actor out of
  -- `entities` without removing it from `npcs`.
  local pendingGames = setmetatable({}, { __mode = "k" })
  local isBattleState
  local discardCatchup
  local updateUnsubscribe
  local updateHookInstalled = false

  local function topState(game)
    local stack = game and game.stack
    if not (stack and type(stack.top) == "function") then return nil end
    local okTop, state = pcall(stack.top, stack)
    return okTop and state or nil
  end

  local function hasBattle(game)
    local stack = game and game.stack
    local states = stack and stack.states
    if type(states) ~= "table" then
      return isBattleState(topState(game))
    end
    for index = #states, 1, -1 do
      if isBattleState(states[index]) then return true end
    end
    return false
  end

  local function overworldReady(game)
    local overworld = game and game.overworld
    if overworld and overworld.isOverworld
        and topState(game) == overworld then
      return overworld
    end
    -- Gold owns the field as game.world and leaves its shared state stack
    -- empty during normal play. The battle callback clears battleActive
    -- before screen.popped fires, so this is the settled post-battle shape.
    local world = game and game.world
    if world and world.map and game.phase == "play"
        and topState(game) == nil and not world.battleActive then
      return world
    end
    return nil
  end

  local function containsId(list, id)
    for _, value in ipairs(list or {}) do
      if value and value.id == id then return true end
    end
    return false
  end

  local function fallbackObjectVisible(save, mapId, object)
    if type(object) ~= "table" then return false end
    local toggles = save and save.objectToggles
      and save.objectToggles[mapId] or {}
    local visible = not object.hidden
    if object.name and toggles and toggles[object.name] ~= nil then
      visible = toggles[object.name]
    end
    if object.item and save and save.itemsTaken
       and save.itemsTaken[mapId .. "_obj_" .. object.index] then
      visible = false
    end
    if object.pokemon and save and save.defeatedTrainers
       and save.defeatedTrainers[mapId .. "_obj_" .. object.index] then
      visible = false
    end
    return visible
  end

  -- A return transition should not normally have to recreate an NPC: the
  -- map loader already populated both collections.  If the battle-speed
  -- catch-up reaches the field while a script has only partially rebuilt the
  -- map, however, the actor can still exist in the map definition but be
  -- absent from `npcs`.  Reconcile visible current-map objects here using
  -- the same visibility and pooling helpers as OverworldController:setMap.
  -- This is deliberately limited to the one-shot post-battle path; it is not
  -- a per-frame scan and therefore has no ordinary overworld cost.
  local function restoreMissingMapNpcs(game, overworld)
    local map = overworld.map
    local objects = map and map.def and map.def.objects
    local pool = overworld.npcPool
    if type(objects) ~= "table" or type(pool) ~= "table"
       or type(overworld.npcs) ~= "table" then
      return false
    end

    local visible = overworld.objectVisible
    local pooled = overworld.pooledNPC
    if type(pooled) ~= "function" then return false end
    local repaired = false
    for _, object in ipairs(objects) do
      local isVisible
      if type(visible) == "function" then
        local okVisible, value = pcall(visible, game.save, map.id, object)
        if okVisible then isVisible = value end
      end
      if isVisible == nil then
        isVisible = fallbackObjectVisible(game.save, map.id, object)
      end
      local id = map.id .. "_obj_" .. object.index
      if isVisible and not containsId(overworld.npcs, id) then
        local okNpc, npc = pcall(pooled, pool, game.data, map.id, object)
        if okNpc and npc then
          npc.frozen = false
          table.insert(overworld.npcs, npc)
          repaired = true
        end
      end
    end
    return repaired
  end

  local function restoreWorldEntities(game)
    local overworld = overworldReady(game)
    -- Gold's World owns a different actor model; recognizing it here is only
    -- a readiness signal so the one-shot pending marker can be retired.
    if overworld and game and game.world == overworld
        and game.overworld ~= overworld then
      return false
    end
    if not overworld or type(overworld.entities) ~= "table"
       or type(overworld.npcs) ~= "table" or not overworld.player then
      return false
    end

    local repaired = restoreMissingMapNpcs(game, overworld)
    -- OverworldController draws and collides from `entities`, while NPC
    -- updates use `npcs`.  Rebuild the draw/collision list from the complete
    -- live NPC list so ordinary actors and the Yellow follower are restored
    -- together.  Pikachu is intentionally removed from `entities` during a
    -- Pokemon Center healing animation, but a battle cannot finish inside
    -- that animation; after a settled battle return the current `npcs` list
    -- is the authoritative visible set.
    local expected = { overworld.player }
    for _, npc in ipairs(overworld.npcs) do
      expected[#expected + 1] = npc
    end
    local same = #overworld.entities == #expected
    if same then
      for index, entity in ipairs(expected) do
        if overworld.entities[index] ~= entity then
          same = false
          break
        end
      end
    end
    if not same then
      for index = #overworld.entities, 1, -1 do
        overworld.entities[index] = nil
      end
      for _, entity in ipairs(expected) do
        overworld.entities[#overworld.entities + 1] = entity
      end
      repaired = true
    end
    return repaired
  end

  isBattleState = function(state)
    if type(state) ~= "table" then return false end
    if state.isBattle == true then return true end
    -- Gold's battle screen is a regular state with the battle model attached.
    return state.battle ~= nil and type(state.submit) == "function"
  end

  discardCatchup = function(game)
    -- Gen 1 exposes the shared clock through Game.fixedStep.  Keep the module
    -- fallback for Gold and older engine builds that do not expose that field.
    local clock = game and game.fixedStep
    if not (clock and type(clock.discardCatchup) == "function") then
      clock = FixedStep
    end
    if not (clock and type(clock.discardCatchup) == "function") then
      return false
    end
    local okDiscard = pcall(clock.discardCatchup, clock)
    return okDiscard
  end

  local function hasPending()
    for game in pairs(pendingGames) do
      if game then return true end
    end
    return false
  end

  local function removeUpdateHook()
    if not (updateHookInstalled and updateUnsubscribe) then return false end
    local unsubscribe = updateUnsubscribe
    updateUnsubscribe = nil
    updateHookInstalled = false
    unsubscribe()
    return true
  end

  local function updatePending(next, game, dt)
    local result = next(game, dt)
    if pendingGames[game] and overworldReady(game) then
      restoreWorldEntities(game)
      pendingGames[game] = nil
    end
    if not hasPending() then removeUpdateHook() end
    return result
  end

  local function ensureUpdateHook()
    if updateHookInstalled then return end
    updateHookInstalled = true
    local unsubscribe = mod.hooks:wrap("core.update", updatePending, 1000)
    if type(unsubscribe) == "function" then
      updateUnsubscribe = unsubscribe
    end
  end

  local function markPending(game)
    if not game then return end
    pendingGames[game] = true
    discardCatchup(game)
    ensureUpdateHook()
  end

  -- screen.popped covers both games, including battle states that finish
  -- without AUTO BATTLE being enabled.
  mod.events:on("screen.popped", function(event)
    local state = event and event.state
    if isBattleState(state) then
      markPending(state.game)
    end
  end)

  -- RBY emits battle.ended immediately after popping the battle state.  The
  -- second, idempotent guard also covers scripted/link endings that do not
  -- expose the same stack transition on older engine builds.
  mod.events:on("battle.ended", function(event)
    local battle = event and event.battle
    if battle then markPending(battle.game) end
  end)

  mod.exports = {
    isBattleState = isBattleState,
    discardCatchup = discardCatchup,
    hasBattle = hasBattle,
    restoreWorldEntities = restoreWorldEntities,
    overworldReady = overworldReady,
    pending = function(game) return pendingGames[game] == true end,
    updateSubscribed = function() return updateHookInstalled end,
  }
end
