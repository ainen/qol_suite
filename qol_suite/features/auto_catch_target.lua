-- AUTO CATCH TARGET: let the player choose one Pokédex species that AUTO
-- CATCH may capture. The target is stored in the mod's save namespace so it
-- survives save slots without changing the vanilla Pokédex data.
return function(mod, dexActions)
  local AUTO_CATCH = "autoCatch"
  local AUTO_BATTLE = "autoBattle"
  local OPTION = "autoCatchTarget"
  local SAVE_KEY = "autoCatchTargetSpecies"
  local EVENT = "mod." .. mod.id .. ".autoCatchTarget.changed"

  local function enabled()
    return mod.options:get(AUTO_BATTLE) == true
      and mod.options:get(AUTO_CATCH) == true
      and mod.options:get(OPTION) == true
  end

  local function clear(game)
    local old = mod.save:get(SAVE_KEY, nil)
    if old == nil then return false end
    mod.save:set(SAVE_KEY, nil)
    mod.events:emit(EVENT, {
      species = nil,
      previous = old,
      game = game,
    })
    return true
  end

  local function current()
    if not enabled() then return nil end
    return mod.save:get(SAVE_KEY, nil)
  end

  local function matches(_, species)
    if not enabled() then return true end
    local selected = current()
    return selected == nil or selected == species
  end

  local function toggle(game, species)
    if not enabled() or species == nil then return false end
    local old = mod.save:get(SAVE_KEY, nil)
    local nextSpecies
    if old ~= species then nextSpecies = species end
    mod.save:set(SAVE_KEY, nextSpecies)
    mod.events:emit(EVENT, {
      species = nextSpecies,
      previous = old,
      game = game,
    })
    return true
  end

  if dexActions and type(dexActions.registerGoldAction) == "function" then
    dexActions.registerGoldAction("autoCatchTarget", function(game, species)
      if not enabled() then return nil end
      return {
        label = current() == species and "CLEAR" or "TARGET",
        onSelect = function() toggle(game, species) end,
      }
    end)
  end

  -- The settings menu emits this event through the engine-owned options
  -- service. Clear the persisted species immediately when either parent
  -- toggle is disabled, instead of restoring an old target if re-enabled.
  mod.events:on("mod.options_changed", function(event)
    if type(event) ~= "table" or event.mod ~= mod.id then return end
    if (event.key == AUTO_CATCH or event.key == OPTION)
       and event.value ~= true then
      clear()
    end
  end)

  -- Keep the action short enough for the Pokédex side menu. TARGET selects
  -- this species; CLEAR removes the currently selected catch target.
  mod.hooks:wrap("ui.pokedex.actions", function(next, game, entries, species)
    local hooked = next(game, entries, species)
    if not enabled() or type(hooked) ~= "table" then return hooked end

    local action = {
      label = current() == species and "CLEAR" or "TARGET",
      onSelect = function() toggle(game, species) end,
    }
    local insertAt = #hooked + 1
    for index, entry in ipairs(hooked) do
      if entry.label == "TRACK" or entry.label == "UNTRACK"
         or entry.label == "PRNT" or entry.label == "QUIT" then
        insertAt = index
        break
      end
    end
    table.insert(hooked, insertAt, action)
    return hooked
  end, 0)

  mod.exports = {
    current = current,
    matches = matches,
    toggle = toggle,
    enabled = enabled,
  }
end
