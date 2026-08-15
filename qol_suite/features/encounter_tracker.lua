-- ENCOUNTER TRACKER: summarize the wild encounters available on the current
-- map. The minimap owns the screen-space panel; this module owns the
-- generation-aware encounter data and compact text model behind it.
return function(mod, tracking)
  local GameVersion = require("src.core.GameVersion")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true
  local OPTION = "encounterTracker"
  local displayCache
  local displayRevision = 0
  local keyCache = setmetatable({}, { __mode = "k" })
  local runtimeEnabled = mod.options:get(OPTION) == true

  local function optionEnabled(key)
    return mod.options:get(key) ~= false
  end

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  local function gold()
    return isGold
  end

  local function buildDisplayOptions()
    return {
      tracked = optionEnabled("encounterTrackerTracked"),
      land = optionEnabled("encounterTrackerLand"),
      surf = optionEnabled("encounterTrackerSurf"),
      fishing = optionEnabled("encounterTrackerFishing"),
      time = not gold() or optionEnabled("encounterTrackerTime"),
      swarms = not gold() or optionEnabled("encounterTrackerSwarms"),
      roaming = not gold() or optionEnabled("encounterTrackerRoaming"),
      rare = not gold() or optionEnabled("encounterTrackerRare"),
      headbutt = not gold() or optionEnabled("encounterTrackerHeadbutt"),
      rockSmash = not gold() or optionEnabled("encounterTrackerRockSmash"),
      contest = not gold() or optionEnabled("encounterTrackerContest"),
    }
  end

  -- Public callers get a fresh snapshot, while the minimap uses displayState
  -- to reuse one immutable table until the settings manager emits a change.
  -- This removes an eleven-field allocation from every rendered frame.
  local function displayOptions()
    return buildDisplayOptions()
  end

  local function displayState()
    if not displayCache then displayCache = buildDisplayOptions() end
    return displayCache, displayRevision
  end

  local DISPLAY_KEYS = {
    encounterTrackerTracked = true,
    encounterTrackerLand = true,
    encounterTrackerSurf = true,
    encounterTrackerFishing = true,
    encounterTrackerTime = true,
    encounterTrackerSwarms = true,
    encounterTrackerRoaming = true,
    encounterTrackerRare = true,
    encounterTrackerHeadbutt = true,
    encounterTrackerRockSmash = true,
    encounterTrackerContest = true,
  }
  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id then
      if event.key == OPTION then
        runtimeEnabled = event.value == true
      elseif DISPLAY_KEYS[event.key] then
        displayCache = nil
        displayRevision = displayRevision + 1
      end
    end
  end)

  local function nameOf(data, species)
    local pokemon = type(data) == "table" and type(data.pokemon) == "table"
      and data.pokemon or nil
    local def = pokemon and pokemon[species]
    local name = def and (def.name or def.speciesName)
    if name and name ~= "" then return tostring(name) end
    return tostring(species or "UNKNOWN"):gsub("_", " ")
  end

  local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return nil end
    return value
  end

  local function overworld(world)
    if not (world and type(world.overworld) == "function") then return nil end
    local ok, value = pcall(world.overworld, world)
    return ok and value or nil
  end

  local function currentDaytime(world)
    local ow = overworld(world)
    local value = ow and (ow.daytime or ow.tod)
    if value == "MORN" or value == "MORNING" then return "MORN" end
    if value == "NITE" or value == "NIGHT" or value == "DARK" then
      return "NITE"
    end
    return "DAY"
  end

  local function daytimeLabel(value)
    if value == "MORN" then return "MORNING" end
    if value == "NITE" then return "NIGHT" end
    return "DAY"
  end

  local function mapDef(game, world, current)
    local ow = overworld(world)
    local map = ow and ow.map
    if map and map.def then return map.def end
    local data = game and type(game.data) == "table" and game.data or nil
    local maps = data and (type(data.maps) == "table" and data.maps
      or type(data.gen2Maps) == "table" and data.gen2Maps) or nil
    return maps and current and maps[current.mapId] or nil
  end

  local function addGroup(groups, data, label, slots, trackedSpecies)
    if type(slots) ~= "table" then return end
    local entries, bySpecies = {}, {}
    for _, slot in ipairs(slots) do
      local species = type(slot) == "table" and slot.species or nil
      if species ~= nil and species ~= "NO_ITEM" and species ~= 0 then
        local entry = bySpecies[species]
        if not entry then
          entry = {
            species = species,
            name = nameOf(data, species),
            min = nil,
            max = nil,
            tracked = species == trackedSpecies,
          }
          bySpecies[species] = entry
          entries[#entries + 1] = entry
        end
        local level = finite(slot.level or slot.min)
        local maxLevel = finite(slot.max or slot.level or slot.min)
        if level then entry.min = entry.min and math.min(entry.min, level) or level end
        if maxLevel then
          entry.max = entry.max and math.max(entry.max, maxLevel) or maxLevel
        end
      end
    end
    if #entries > 0 then
      groups[#groups + 1] = { label = label, entries = entries }
    end
  end

  local function activeSwarm(save, mapId)
    local flags = save and type(save.dailyFlags) == "table"
      and save.dailyFlags or nil
    return flags and flags.swarm == true and save.swarmMap == mapId
  end

  local FISH_SWARMS = {
    [1] = {
      FISHGROUP_QWILFISH = "FISHGROUP_QWILFISH_SWARM",
    },
    [2] = {
      FISHGROUP_REMORAID = "FISHGROUP_REMORAID_SWARM",
    },
  }

  -- Gen 1 keeps fishing outside the normal grass/water encounter tables.
  -- Data.field.fishing is seeded by the engine; these small defaults keep
  -- the panel useful with older extracted caches too, matching the engine's
  -- FieldDefaults values.
  local GEN1_FISHING_DEFAULTS = {
    OLD_ROD = { always = { species = "MAGIKARP", level = 5 } },
    GOOD_ROD = { pool = {
      { species = "GOLDEEN", level = 10 },
      { species = "POLIWAG", level = 10 },
    } },
    SUPER_ROD = { perMap = "superRod" },
  }

  local function gen1Fishing(data, mapId)
    local field = type(data) == "table" and type(data.field) == "table"
      and data.field or {}
    local defs = type(field.fishing) == "table"
      and field.fishing or GEN1_FISHING_DEFAULTS
    local groups = {}
    for _, rod in ipairs({
      { key = "OLD_ROD", label = "OLD ROD" },
      { key = "GOOD_ROD", label = "GOOD ROD" },
      { key = "SUPER_ROD", label = "SUPER ROD" },
    }) do
      local def = defs[rod.key]
      local slots = def and def.pool
      if def and def.always then slots = { def.always } end
      if def and def.perMap then
        local perMap = field[def.perMap]
        slots = perMap and perMap[mapId]
      end
      groups[#groups + 1] = { label = rod.label, slots = slots }
    end
    return groups
  end

  local function collect(game, world, current)
    if not (game and type(game.data) == "table"
        and current and current.mapId) then return nil end
    local data = game.data
    local encounters = data.encounters or data.gen2Encounters or {}
    if type(encounters) ~= "table" then encounters = {} end
    local trackedSpecies = tracking and tracking.current
      and tracking.current(game) or nil
    local groups = {}
    local mapId = current.mapId
    local time = gold() and currentDaytime(world) or "ANY"
    local save = type(game.save) == "table" and game.save or {}

    if not gold() then
      local entry = encounters[mapId]
      if type(entry) ~= "table" then entry = nil end
      addGroup(groups, data, "GRASS", entry and entry.grass
        and entry.grass.slots, trackedSpecies)
      addGroup(groups, data, "SURF", entry and entry.water
        and entry.water.slots, trackedSpecies)
      for _, rod in ipairs(gen1Fishing(data, mapId)) do
        addGroup(groups, data, rod.label, rod.slots, trackedSpecies)
      end
    else
      local grass = encounters.grass and encounters.grass[mapId]
      local water = encounters.water and encounters.water[mapId]
      local grassSlots = grass and grass.slots
        and (grass.slots[time] or grass.slots.DAY)
      addGroup(groups, data, "GRASS " .. daytimeLabel(time), grassSlots,
        trackedSpecies)
      addGroup(groups, data, "SURF", water and water.slots, trackedSpecies)

      local map = mapDef(game, world, current) or {}
      local fishGroup = map.fishGroup
      local flags = type(save.dailyFlags) == "table" and save.dailyFlags or {}
      local fishingSwarm = flags.swarm == true and flags.fishingSwarm or 0
      local swarmMap = activeSwarm(save, mapId)
      local swap = FISH_SWARMS[tonumber(fishingSwarm)]
      local ordinaryFishGroup = fishGroup
      local swarmedFishGroup = swap and swap[fishGroup]
      fishGroup = swarmedFishGroup or fishGroup
      local fish = fishGroup and encounters.fishGroups
        and encounters.fishGroups[fishGroup]
      local fishingSwarmActive = swarmedFishGroup ~= nil and fish ~= nil
      -- Old extracted caches can lack the optional swarm group. Gold's native
      -- encounter code falls back to the ordinary group in that case.
      if not fish and swarmedFishGroup then
        fishGroup = ordinaryFishGroup
        fish = fishGroup and encounters.fishGroups
          and encounters.fishGroups[fishGroup]
        fishingSwarmActive = false
      end
      for _, rod in ipairs({
        { label = "OLD ROD", key = "old" },
        { label = "GOOD ROD", key = "good" },
        { label = "SUPER ROD", key = "super" },
      }) do
        local label = (fishingSwarmActive and "SWARM " or "") .. rod.label
        addGroup(groups, data, label, fish and fish[rod.key], trackedSpecies)
      end

      local treeSetName = encounters.trees and encounters.trees[mapId]
      local treeSet = treeSetName and encounters.treeSets
        and encounters.treeSets[treeSetName]
      addGroup(groups, data, "HEADBUTT", treeSet and treeSet.common,
        trackedSpecies)
      addGroup(groups, data, "HEADBUTT RARE", treeSet and treeSet.rare,
        trackedSpecies)

      local rockSetName = encounters.rocks and encounters.rocks[mapId]
      local rockSet = rockSetName and encounters.treeSets
        and encounters.treeSets[rockSetName]
      addGroup(groups, data, "ROCK SMASH", rockSet and rockSet.common,
        trackedSpecies)
      addGroup(groups, data, "ROCK SMASH RARE", rockSet and rockSet.rare,
        trackedSpecies)

      if swarmMap then
        local swarmGrass = encounters.swarmGrass
          and encounters.swarmGrass[mapId]
        local swarmWater = encounters.swarmWater
          and encounters.swarmWater[mapId]
        local swarmGrassSlots = swarmGrass and swarmGrass.slots
          and (swarmGrass.slots[time] or swarmGrass.slots.DAY)
        addGroup(groups, data, "SWARM " .. daytimeLabel(time), swarmGrassSlots,
          trackedSpecies)
        addGroup(groups, data, "SWARM SURF",
          swarmWater and swarmWater.slots, trackedSpecies)
      end

      local roamers = type(save.roamers) == "table" and save.roamers or {}
      for _, roamer in ipairs(roamers) do
        if roamer and roamer.map == mapId and roamer.species then
          addGroup(groups, data, "ROAMING", {
            { species = roamer.species, level = roamer.level },
          }, trackedSpecies)
        end
      end

      -- The National Park has a separate table during the Bug-Catching
      -- Contest. Keeping it visible as a condition tells the player why the
      -- available species can differ from the park's normal grass table.
      if mapId == "NATIONAL_PARK" and type(save.bugContest) == "table"
          and save.bugContest.active == true
          and type(encounters.bugContest) == "table" then
        addGroup(groups, data, "BUG CONTEST", encounters.bugContest,
          trackedSpecies)
      end
    end

    local trackedName = trackedSpecies and nameOf(data, trackedSpecies) or nil
    return {
      mapId = mapId,
      time = time,
      timeLabel = gold() and daytimeLabel(time) or "ANY TIME",
      groups = groups,
      trackedSpecies = trackedSpecies,
      trackedName = trackedName,
    }
  end

  local function key(game, world, current)
    if not current then return "none" end
    local save = game and type(game.save) == "table" and game.save or {}
    local flags = type(save.dailyFlags) == "table" and save.dailyFlags or {}
    local active = flags.swarm and save.swarmMap or ""
    local contest = type(save.bugContest) == "table"
      and save.bugContest.active == true or false
    local roamers = type(save.roamers) == "table" and save.roamers or {}
    local time = currentDaytime(world)
    local previous = type(game) == "table" and keyCache[game] or nil
    local unchanged = previous and previous.mapId == current.mapId
      and previous.time == time
      and previous.active == active
      and previous.fishingSwarm == flags.fishingSwarm
      and previous.contest == contest
      and #previous.roamers == #roamers
    if unchanged then
      for index, roamer in ipairs(roamers) do
        local saved = previous.roamers[index]
        if (type(roamer) == "table" and (type(saved) ~= "table"
            or saved.species ~= roamer.species or saved.map ~= roamer.map))
            or (type(roamer) ~= "table" and saved ~= false) then
          unchanged = false
          break
        end
      end
    end
    if unchanged then return previous.value end

    local roamerParts, roamerSnapshot = {}, {}
    for index, roamer in ipairs(roamers) do
      if type(roamer) == "table" then
        roamerParts[#roamerParts + 1] = tostring(roamer.species or "")
          .. ":" .. tostring(roamer.map or "")
        roamerSnapshot[index] = {
          species = roamer.species, map = roamer.map,
        }
      else
        roamerSnapshot[index] = false
      end
    end
    table.sort(roamerParts)
    local value = table.concat({
      tostring(current.mapId), time, tostring(active),
      tostring(flags.fishingSwarm or 0), tostring(contest),
      table.concat(roamerParts, ","),
    }, "|")
    if type(game) == "table" then
      keyCache[game] = {
        mapId = current.mapId, time = time, active = active,
        fishingSwarm = flags.fishingSwarm, contest = contest,
        roamers = roamerSnapshot, value = value,
      }
    end
    return value
  end

  local function levelText(entry)
    if not entry.min then return "" end
    if entry.max and entry.max ~= entry.min then
      return (" L%d-%d"):format(entry.min, entry.max)
    end
    return (" L%d"):format(entry.min)
  end

  local function groupSection(group)
    local label = tostring(group and group.label or ""):upper()
    if label == "SURF" then return "surf" end
    if label == "ROAMING" then return "roaming" end
    if label == "BUG CONTEST" then return "contest" end
    if label:match("^HEADBUTT") then return "headbutt" end
    if label:match("^ROCK SMASH") then return "rockSmash" end
    if label:find("RARE", 1, true) then return "rare" end
    if label:match("ROD$") then
      return label:match("^SWARM ") and "swarms" or "fishing"
    end
    if label:match("^SWARM ") then return "swarms" end
    if label:match("^GRASS") then return "land" end
    return nil
  end

  local function displayGroupLabel(group, showTime)
    local label = tostring(group.label or "")
    if gold() and not showTime then
      label = label:gsub("^GRASS (MORNING|DAY|NIGHT)$", "GRASS")
      label = label:gsub("^SWARM (MORNING|DAY|NIGHT)$", "SWARM")
    end
    return label
  end

  local function format(model, maxChars, maxLines, display)
    if not model then return {} end
    maxChars = finite(maxChars) or 28
    maxLines = finite(maxLines) or 16
    maxChars = math.max(12, math.floor(maxChars))
    maxLines = math.max(3, math.floor(maxLines))
    display = display or displayOptions()

    local groups = {}
    local hasTimeScopedGroup = false
    local modelGroups = type(model.groups) == "table" and model.groups or {}
    for _, group in ipairs(modelGroups) do
      local section = groupSection(group)
      local labelText = tostring(group and group.label or ""):upper()
      local rareHidden = labelText:find("RARE", 1, true)
        and display.rare == false
      local swarmFishingHidden = labelText:match("^SWARM ")
        and labelText:match("ROD$")
        and (display.swarms == false or display.fishing == false)
      if (not section or display[section] ~= false) and not rareHidden
          and not swarmFishingHidden then
        local label = displayGroupLabel(group, display.time ~= false)
        groups[#groups + 1] = { source = group, section = section,
          label = label }
        if section == "land" or (section == "swarms"
            and label == "SWARM") then
          hasTimeScopedGroup = true
        end
      end
    end

    local lines = {}
    if gold() and hasTimeScopedGroup and display.time ~= false then
      lines[#lines + 1] = {
        text = "ENCOUNTERS " .. tostring(model.timeLabel),
      }
    end
    if model.trackedName and display.tracked ~= false then
      lines[#lines + 1] = { text = "TRACKED " .. model.trackedName, tracked = true }
    end
    for _, rendered in ipairs(groups) do
      local group = rendered.source
      local prefix = rendered.label .. ": "
      local line = prefix
      local entries = type(group.entries) == "table" and group.entries or {}
      for _, entry in ipairs(entries) do
        local piece = entry.name .. levelText(entry)
        local separator = line == prefix and "" or ", "
        if line ~= prefix and #line + #separator + #piece > maxChars then
          lines[#lines + 1] = { text = line, group = group,
            section = rendered.section }
          line = string.rep(" ", #prefix) .. piece
        else
          line = line .. separator .. piece
        end
      end
      if line ~= prefix then
        lines[#lines + 1] = { text = line, group = group,
          section = rendered.section }
      end
    end
    if #lines == 0 or (#lines == 1 and lines[1].tracked) then
      lines[#lines + 1] = { text = "NO ENCOUNTERS SHOWN" }
    end
    if #lines > maxLines then
      local hidden = #lines - maxLines + 1
      while #lines >= maxLines do table.remove(lines) end
      lines[#lines + 1] = { text = ("... %d MORE"):format(hidden) }
    end
    return lines
  end

  mod.exports = {
    enabled = enabled,
    active = function() return runtimeEnabled end,
    displayOptions = displayOptions,
    displayState = displayState,
    collect = collect,
    key = key,
    format = format,
  }
end
