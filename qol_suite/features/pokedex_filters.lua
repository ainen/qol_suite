-- POKEDEX FILTERS: add a compact filter menu to the native Gen 1 and Gold
-- Pokedex lists without replacing their entry pages or sort/search data.
return function(mod, encounterTracker)
  local GameVersion = require("src.core.GameVersion")
  local Menu = require("src.ui.Menu")
  local Strings = require("src.core.Strings")
  local OPTION = "pokedexFilters"

  local STATUS = {
    { key = "all", label = "ALL" },
    { key = "seen", label = "SEEN ONLY" },
    { key = "caught", label = "CAUGHT" },
    { key = "unseen", label = "UNSEEN" },
  }

  local function enabled()
    return mod.options:get(OPTION) ~= false
  end

  local function caught(saveDex, species)
    return saveDex and ((saveDex.owned and saveDex.owned[species] == true)
      or (saveDex.caught and saveDex.caught[species] == true)) or false
  end

  local function generation(data, species)
    local def = data and data.pokemon and data.pokemon[species] or {}
    local value = tonumber(def.generation or def.gen)
    if value then return value end
    return (tonumber(def.dex) or 0) <= 151 and 1 or 2
  end

  local function typeList(data, species)
    local def = data and data.pokemon and data.pokemon[species] or {}
    local types = def.types
    if type(types) == "table" then return types end
    local out = {}
    if def.type1 then out[#out + 1] = def.type1 end
    if def.type2 then out[#out + 1] = def.type2 end
    return out
  end

  local function contains(list, value)
    for _, item in ipairs(list or {}) do
      if item == value then return true end
    end
    return false
  end

  local function areaSpecies(game)
    if not encounterTracker or type(encounterTracker.collect) ~= "function" then
      return {}
    end
    local world = mod.world
    if not (world and type(world.current) == "function") then return {} end
    local okCurrent, current = pcall(world.current, world)
    if not okCurrent then return {} end
    if not current or not current.mapId then return {} end
    local ok, model = pcall(encounterTracker.collect, game, world, current)
    if not ok or type(model) ~= "table" then return {} end
    local out = {}
    for _, group in ipairs(model.groups or {}) do
      for _, entry in ipairs(group.entries or {}) do
        if entry.species then out[entry.species] = true end
      end
    end
    return out
  end

  local function matches(row, filters, data, available)
    filters = filters or {}
    if filters.status == "seen" and not (row.seen and not row.caught) then
      return false
    elseif filters.status == "caught" and not row.caught then
      return false
    elseif filters.status == "unseen" and row.seen then
      return false
    end
    if filters.area and not available[row.species] then return false end
    if filters.generation and filters.generation ~= "all"
        and generation(data, row.species) ~= tonumber(filters.generation) then
      return false
    end
    if filters.type and filters.type ~= "all"
        and not contains(typeList(data, row.species), filters.type) then
      return false
    end
    return true
  end

  local function filterRows(rows, filters, data, available)
    local out = {}
    available = available or {}
    for _, row in ipairs(rows or {}) do
      if matches(row, filters, data, available) then out[#out + 1] = row end
    end
    return out
  end

  local function choices(rows, data)
    local generations, types = {}, {}
    local generationSeen, typeSeen = {}, {}
    for _, row in ipairs(rows or {}) do
      local gen = generation(data, row.species)
      if not generationSeen[gen] then
        generationSeen[gen] = true
        generations[#generations + 1] = gen
      end
      for _, typeName in ipairs(typeList(data, row.species)) do
        if typeName and not typeSeen[typeName] then
          typeSeen[typeName] = true
          types[#types + 1] = typeName
        end
      end
    end
    table.sort(generations)
    table.sort(types)
    return generations, types
  end

  local function newFilters()
    return { status = "all", area = false, generation = "all", type = "all" }
  end

  local function valueLabel(prefix, value)
    return prefix .. ": " .. value
  end

  local function statusLabel(filters)
    for _, row in ipairs(STATUS) do
      if row.key == filters.status then return row.label end
    end
    return "ALL"
  end

  -- The filter menu is only 18 tiles wide. The surrounding menu already
  -- identifies this as the status choice, so keep the choice text compact.
  local function statusMenuLabel(filters)
    return statusLabel(filters)
  end

  local function summary(filters)
    local parts = {}
    if filters.status ~= "all" then parts[#parts + 1] = statusLabel(filters) end
    if filters.area then parts[#parts + 1] = "AREA" end
    if filters.generation ~= "all" then
      parts[#parts + 1] = "GEN " .. tostring(filters.generation)
    end
    if filters.type ~= "all" then parts[#parts + 1] = filters.type end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
  end

  -- Gen 1's native list already reserves its single bottom line for the
  -- SEEN/OWN totals. Do not add a second footer line: ListMenu would move the
  -- totals up one row and draw the filter summary over the native status area.
  -- Use the title strip for a compact, clipped indicator instead.
  local function titleForFilter(original, filters)
    local filterText = summary(filters)
    if not filterText then return original end
    local title = "DEX " .. filterText
    return #title > 18 and title:sub(1, 18) or title
  end

  local function updateLabel(items, index, label)
    if items[index] then items[index].label = label end
  end

  local function nextChoice(current, list)
    if type(list) ~= "table" or #list == 0 then return current end
    local index = 1
    for i, value in ipairs(list) do
      if value == current then index = i break end
    end
    return list[index % #list + 1]
  end

  local function openMenu(menu, apply, data, rows)
    if not enabled() then return end
    local filters = menu.qolFilters
    local generations, types = choices(rows, data)
    local items = {}
    local statusIndex = #items + 1
    items[statusIndex] = {
      label = statusMenuLabel(filters), keepOpen = true,
      onSelect = function()
        local keys = {}
        for _, row in ipairs(STATUS) do keys[#keys + 1] = row.key end
        filters.status = nextChoice(filters.status, keys)
        updateLabel(items, statusIndex, statusMenuLabel(filters))
        apply()
      end,
    }
    local areaIndex = #items + 1
    items[areaIndex] = {
      label = valueLabel("AREA", filters.area and "CURRENT" or "ANY"),
      keepOpen = true,
      onSelect = function()
        filters.area = not filters.area
        updateLabel(items, areaIndex,
          valueLabel("AREA", filters.area and "CURRENT" or "ANY"))
        apply()
      end,
    }
    local generationIndex
    if #generations > 1 then
      generationIndex = #items + 1
      local generationChoices = { "all" }
      for _, gen in ipairs(generations) do
        generationChoices[#generationChoices + 1] = tostring(gen)
      end
      items[generationIndex] = {
        label = valueLabel("GEN", filters.generation == "all"
          and "ALL" or filters.generation), keepOpen = true,
        onSelect = function()
          filters.generation = nextChoice(filters.generation, generationChoices)
          updateLabel(items, generationIndex, valueLabel("GEN",
            filters.generation == "all" and "ALL" or filters.generation))
          apply()
        end,
      }
    end
    local typeIndex = #items + 1
    local typeChoices = { "all" }
    for _, typeName in ipairs(types) do typeChoices[#typeChoices + 1] = typeName end
    items[typeIndex] = {
      label = valueLabel("TYPE", filters.type == "all" and "ALL" or filters.type),
      keepOpen = true,
      onSelect = function()
        filters.type = nextChoice(filters.type, typeChoices)
        updateLabel(items, typeIndex, valueLabel("TYPE",
          filters.type == "all" and "ALL" or filters.type))
        apply()
      end,
    }
    local clearIndex = #items + 1
    items[clearIndex] = {
      label = "CLEAR FILTERS", keepOpen = true,
      onSelect = function()
        menu.qolFilters = newFilters()
        filters = menu.qolFilters
        updateLabel(items, statusIndex, statusMenuLabel({ status = "all" }))
        updateLabel(items, areaIndex, valueLabel("AREA", "ANY"))
        if generationIndex then
          updateLabel(items, generationIndex, valueLabel("GEN", "ALL"))
        end
        updateLabel(items, typeIndex, valueLabel("TYPE", "ALL"))
        apply()
      end,
    }
    items[#items + 1] = { label = "DONE" }
    local stack = menu and menu.game and menu.game.stack
    if not (stack and type(stack.push) == "function") then return end
    stack:push(Menu.new(menu.game, items, {
      tx = 0, ty = 1, tw = 18, maxVisible = #items,
    }))
  end

  local function installGen1()
    -- Gold runs a generation-specific dex list instead. Build this legacy
    -- module id only inside the Gen 1 installer so a Gold boot never patches
    -- a dormant Gen 1 class merely because both files exist in the checkout.
    local legacyPokedexId = "src.ui."
      .. table.concat({ "Pokedex", "Menu" })
    local PokedexMenu = require(legacyPokedexId)
    if PokedexMenu._qolSuitePokedexFilters then return end
    PokedexMenu._qolSuitePokedexFilters = true
    local originalNew = PokedexMenu.new
    PokedexMenu.new = function(game, opts)
      local list = originalNew(game, opts)
      if not enabled() then return list end
      local originalTitle = list.title
      local save = game and game.save
      local dex = type(save) == "table" and save.pokedex
        or { seen = {}, owned = {} }
      if type(dex) ~= "table" then dex = { seen = {}, owned = {} } end
      local data = game and game.data or {}
      local byDex = {}
      for species, def in pairs(data.pokemon or {}) do
        if def.dex then byDex[def.dex] = { species = species, def = def } end
      end
      local constants = data.constants or {}
      local numFmt = ("%%0%dd"):format(constants.dexDigits or 3)
      local rows, seen, owned = {}, 0, 0
      for n = 1, constants.dexSize or 151 do
        local entry = byDex[n]
        if entry then
          local species, def = entry.species, entry.def
          local isCaught = caught(dex, species)
          local isSeen = isCaught or dex.seen and dex.seen[species] == true
          local label = isSeen and (numFmt .. " %s"):format(n, def.name)
            or (numFmt .. " -----"):format(n)
          if isSeen then seen = seen + 1 end
          if isCaught then owned = owned + 1 end
          rows[#rows + 1] = {
            species = species, seen = isSeen, caught = isCaught,
            item = { label = label, ball = isCaught or nil,
              value = isSeen and species or nil },
          }
        end
      end
      list.qolFilters = newFilters()
      local function apply()
        local available = areaSpecies(game)
        local filtered = filterRows(rows, list.qolFilters, data, available)
        local items = {}
        local filteredSeen, filteredOwned = 0, 0
        for _, row in ipairs(filtered) do
          items[#items + 1] = row.item
          if row.seen then filteredSeen = filteredSeen + 1 end
          if row.caught then filteredOwned = filteredOwned + 1 end
        end
        list.items = items
        list.index, list.scroll = 1, 0
        local text = Strings("SEEN %3d  OWN %3d", filteredSeen, filteredOwned)
        list.title = titleForFilter(originalTitle, list.qolFilters)
        list.footer = text
      end
      list.onSelectKey = function() openMenu(list, apply, data, rows) end
      list.qolFilterRows = rows
      list.qolApplyFilters = apply
      apply()
      return list
    end
  end

  local function installGold()
    local PokedexMenu = require("src.ui.gen2.PokedexMenu")
    if PokedexMenu._qolSuitePokedexFilters then return end
    PokedexMenu._qolSuitePokedexFilters = true
    local originalNew = PokedexMenu.new
    PokedexMenu.new = function(game, opts)
      local screen = originalNew(game, opts)
      if not enabled() then return screen end
      screen.qolFilters = newFilters()
      local originalRebuild = screen.rebuild
      local function apply()
        local available = areaSpecies(game)
        screen.rows = filterRows(screen.qolFilterRows, screen.qolFilters,
          game.data or {}, available)
        screen.index = math.max(1, math.min(screen.index,
          math.max(1, #screen.rows)))
        screen:ensureVisible()
      end
      screen.rebuild = function(self)
        originalRebuild(self)
        self.qolFilterRows = self.rows
        self.qolFilterGenerations, self.qolFilterTypes = choices(
          self.qolFilterRows, game.data or {})
        apply()
      end
      screen.qolFilterRows = screen.rows
      screen.qolFilterGenerations, screen.qolFilterTypes = choices(
        screen.rows, game.data or {})
      local originalUpdate = screen.update
      screen.update = function(self, dt)
        local input = self.game and self.game.input
        if self.view == "list" and input and input:wasPressed("start") then
          openMenu(self, apply, game.data or {},
            self.qolFilterRows)
          return
        end
        return originalUpdate(self, dt)
      end
      screen.qolApplyFilters = apply
      apply()
      return screen
    end
  end

  if GameVersion.isGold and GameVersion.isGold() then
    installGold()
  else
    installGen1()
  end

  mod.exports = {
    enabled = enabled,
    caught = caught,
    generation = generation,
    types = typeList,
    matches = matches,
    filterRows = filterRows,
    summary = summary,
    statusMenuLabel = statusMenuLabel,
  }
end
