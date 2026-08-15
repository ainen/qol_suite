-- QoL Suite: track one seen Pokédex species and show its habitat on
-- the minimap.  The selected species lives in the mod's namespaced save data,
-- so it survives save slots without changing the vanilla Pokédex format.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Screens = require("src.ui.Screens")
  local OPTION = "tracking"
  local MINIMAP_OPTION = "minimap"
  local SAVE_KEY = "trackedSpecies"
  local EVENT = "mod." .. mod.id .. ".tracking.changed"
  local goldDexActions = {}
  local goldDexOrder = {}
  local runtimeEnabled = mod.options:get(OPTION) == true
    and mod.options:get(MINIMAP_OPTION) == true

  local function enabled()
    return mod.options:get(OPTION) == true
      and mod.options:get(MINIMAP_OPTION) == true
  end

  local function speciesName(game, species)
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[species]
    return (def and def.name) or tostring(species or "")
  end

  local function current(game)
    if not enabled() then return nil end
    return mod.save:get(SAVE_KEY, nil)
  end

  local function activeCurrent(game)
    if not runtimeEnabled then return nil end
    return mod.save:get(SAVE_KEY, nil)
  end

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and (event.key == OPTION or event.key == MINIMAP_OPTION) then
      local trackingOn = mod.options:get(OPTION) == true
      local minimapOn = mod.options:get(MINIMAP_OPTION) == true
      if event.key == OPTION then trackingOn = event.value == true end
      if event.key == MINIMAP_OPTION then minimapOn = event.value == true end
      runtimeEnabled = trackingOn and minimapOn
    end
  end)

  local function setTracked(game, species)
    if not enabled() or species == nil then return false end
    local old = mod.save:get(SAVE_KEY, nil)
    if old == species then
      mod.save:set(SAVE_KEY, nil)
      mod.events:emit(EVENT, { species = nil, previous = old })
      return true
    end
    mod.save:set(SAVE_KEY, species)
    mod.events:emit(EVENT, { species = species, previous = old })
    return true
  end

  -- Gold's native Pokedex has a fixed PAGE/AREA/CRY/PRNT row and does not
  -- raise the Gen 1 ui.pokedex.actions hook.  Reuse the PRNT slot as a short
  -- QoL action menu when at least one QoL Pokedex action is available.  The
  -- menu is a native Gold ScriptMenu, so it keeps the same font, border, and
  -- input behavior as the rest of the game.
  local function goldActionRows(game, species)
    local rows = {}
    for _, key in ipairs(goldDexOrder) do
      local builder = goldDexActions[key]
      local row = builder(game, species)
      if row then rows[#rows + 1] = row end
    end
    return rows
  end

  local function installGoldDexMenu()
    if not (GameVersion.isGold and GameVersion.isGold())
        or #goldDexOrder == 0 then return end
    local PokedexMenu = require("src.ui.gen2.PokedexMenu")
    if PokedexMenu._qolSuiteDexActions then return end
    PokedexMenu._qolSuiteDexActions = true
    local originalUpdate = PokedexMenu.update
    function PokedexMenu:update(dt)
      local input = self.game and self.game.input
      local row = self.current and self:current()
      if self.view == "entry" and not self.newEntry
          and self.entryAction == 4 and input and input:wasPressed("a")
          and row and row.species then
        local actions = goldActionRows(self.game, row.species)
        if #actions > 0 then
          local labels = {}
          for _, action in ipairs(actions) do
            labels[#labels + 1] = action.label
          end
          labels[#labels + 1] = "CANCEL"
          local stack = self.game and self.game.stack
          Screens.push(self.game, "Gen2ScriptMenu", {
            header = {
              top = 4, left = 8, right = 18,
              bottom = 5 + #labels * 2, cursor = 1,
              dataFlags = 0x80, items = labels,
            },
            kind = "qol_dex_actions",
            onChoose = function(index)
              if stack and type(stack.top) == "function" and stack:top()
                  and type(stack.pop) == "function" then
                stack:pop()
              end
              local action = actions[index]
              if action and type(action.onSelect) == "function" then
                action.onSelect()
              end
            end,
          })
          return
        end
      end
      return originalUpdate(self, dt)
    end
  end

  local function registerGoldAction(key, builder)
    if type(key) ~= "string" or type(builder) ~= "function" then return end
    if not goldDexActions[key] then
      goldDexOrder[#goldDexOrder + 1] = key
    end
    goldDexActions[key] = builder
    installGoldDexMenu()
  end

  -- Gold does not emit Gen 1's ui.pokedex.actions hook. Register Tracking in
  -- the shared Gold action menu explicitly; AUTO CATCH TARGET joins the same
  -- deterministic registry when its feature initializes later.
  registerGoldAction("tracking", function(game, species)
    if not enabled() then return nil end
    return {
      label = current(game) == species and "UNTRACK" or "TRACK",
      onSelect = function() setTracked(game, species) end,
    }
  end)

  -- Add TRACK/UNTRACK to the existing DATA / CRY / AREA / QUIT menu.  A new
  -- choice replaces the old target, which keeps the minimap hint singular and
  -- makes changing targets a one-press action.  Put it before Yellow's PRNT
  -- row so it remains on the first visible page of the capped side menu.
  mod.hooks:wrap("ui.pokedex.actions", function(next, game, entries, species)
    local hooked = next(game, entries, species)
    if not enabled() or type(hooked) ~= "table" then return hooked end

    local action = {
      label = current(game) == species and "UNTRACK" or "TRACK",
      onSelect = function() setTracked(game, species) end,
    }
    local insertAt = #hooked + 1
    for index, entry in ipairs(hooked) do
      if entry.label == "PRNT" or entry.label == "QUIT" then
        insertAt = index
        break
      end
    end
    table.insert(hooked, insertAt, action)
    return hooked
  end, 0)

  mod.exports = {
    current = current,
    activeCurrent = activeCurrent,
    name = speciesName,
    toggle = setTracked,
    enabled = enabled,
    registerGoldAction = registerGoldAction,
    goldActions = goldActionRows,
  }
end
