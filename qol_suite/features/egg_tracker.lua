-- EGG TRACKER: Gold-only overworld information for carried eggs and the two
-- Day-Care parents.  Gen 2 stores the hatch counter in 256-step cycles; the
-- native breeding helper exposes the exact conversion used here.
return function(mod, overlayLayout)
  local GameVersion = require("src.core.GameVersion")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true
  local Font = require("src.render.Font")
  local OPTION = "eggTracker"
  local MARGIN = 4
  local PANEL_WIDTH = 112
  local NATIVE_TILE = 8
  local renderDirty = true
  local renderedLastFrame = false
  local renderGame, renderSave, renderParty, renderDayCare, renderLines
  local runtimeEnabled = isGold and mod.options:get(OPTION) == true
  local runtimeMinimapEnabled = mod.options:get("minimap") == true
  local runtimeMinimapCorner = mod.options:get("minimapCorner")
  local runtimeTrackerEnabled = mod.options:get("encounterTracker") == true
  local runtimeTrackerCorner = mod.options:get("encounterTrackerCorner")
  local runtimePartyEnabled = mod.options:get("partyOverview") == true
  local runtimePartyCorner = mod.options:get("partyOverviewCorner")
  local renderUnsubscribe, syncRenderHook

  local Breeding
  if isGold then
    local ok, module = pcall(require, "src.core.gen2.Breeding")
    if ok then Breeding = module end
  end

  local function gold()
    return isGold
  end

  local function enabled()
    return gold() and mod.options:get(OPTION) == true
  end

  local function nameOf(game, species)
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[species]
    local name = def and (def.name or def.speciesName)
    if name and name ~= "" then return tostring(name):upper() end
    return tostring(species or "UNKNOWN"):gsub("_", " "):upper()
  end

  local function breeding()
    return Breeding
  end

  local function invalidateRender()
    renderDirty = true
  end

  if isGold then
    mod.events:on("world.stepped", invalidateRender)
    mod.events:on("world.interacted", invalidateRender)
    mod.events:on("map.entered", invalidateRender)
    mod.events:on("map.reloaded", invalidateRender)
    mod.events:on("mod.options_changed", function(event)
      if type(event) == "table" and event.mod == mod.id then
        if event.key == OPTION then
          runtimeEnabled = event.value == true
          invalidateRender()
          if syncRenderHook then syncRenderHook() end
        elseif event.key == "minimap" then
          runtimeMinimapEnabled = event.value == true
        elseif event.key == "minimapCorner" then
          runtimeMinimapCorner = event.value
        elseif event.key == "encounterTracker" then
          runtimeTrackerEnabled = event.value == true
        elseif event.key == "encounterTrackerCorner" then
          runtimeTrackerCorner = event.value
        elseif event.key == "partyOverview" then
          runtimePartyEnabled = event.value == true
        elseif event.key == "partyOverviewCorner" then
          runtimePartyCorner = event.value
        end
      end
    end)
  end

  local function stepsFor(mon, Breeding)
    if not mon then return nil end
    local function steps(value, scale)
      value = tonumber(value)
      if not value or value ~= value or value == math.huge
          or value == -math.huge then return nil end
      return math.max(0, math.floor(value * (scale or 1)))
    end
    if Breeding and Breeding.isEgg and Breeding.isEgg(mon)
        and Breeding.stepsToHatch then
      local ok, value = pcall(Breeding.stepsToHatch, mon)
      if ok then
        local parsed = steps(value)
        if parsed ~= nil then return parsed end
      end
    end
    for _, key in ipairs({ "stepsRemaining", "hatchSteps" }) do
      local value = steps(mon[key])
      if value ~= nil then return value end
    end
    -- Older Gold-compatible builds may expose the raw eggSteps cycle without
    -- the Breeding helper. One cycle is 256 overworld steps in Gen 2.
    local raw = steps(mon.eggSteps, 256)
    if raw ~= nil then return raw end
    return nil
  end

  local function sideParent(game, side)
    local save = game and game.save
    local dc = save and (save.dayCare or save.daycare)
    if type(dc) ~= "table" then return nil end
    local record = dc and dc[side]
    if not record then return nil end
    return record.mon or record.pokemon
  end

  local function snapshot(game)
    local out = { eggs = {}, parents = {} }
    if not gold() then return out end
    local Breeding = breeding()
    local party = game and game.save and game.save.party
    if type(party) ~= "table" then party = {} end
    for index, mon in ipairs(party) do
      local isEgg = Breeding and Breeding.isEgg and Breeding.isEgg(mon)
        or mon.isEgg == true or mon.egg == true
      if isEgg then
        out.eggs[#out.eggs + 1] = {
          index = index,
          status = "PARTY EGG",
          steps = stepsFor(mon, Breeding),
          species = mon.species,
        }
      end
    end
    local save = game and game.save
    local dc = save and (save.dayCare or save.daycare)
    if type(dc) == "table" then
      local man = sideParent(game, "man")
      local lady = sideParent(game, "lady")
      out.parents[1] = man and nameOf(game, man.species) or "EMPTY"
      out.parents[2] = lady and nameOf(game, lady.species) or "EMPTY"
      if dc.hasEgg == true and dc.egg then
        out.eggs[#out.eggs + 1] = {
          status = "DAYCARE EGG",
          steps = stepsFor(dc.egg, Breeding),
          species = dc.egg.species,
        }
      elseif (man or lady) and (dc.compatible == true or dc.stepsToEgg ~= nil) then
        out.breeding = {
          status = dc.compatible == true and "BREEDING" or "DAYCARE",
          steps = tonumber(dc.stepsToEgg),
        }
      end
    end
    return out
  end

  local function format(snapshotValue, maxLines)
    local lines = {}
    maxLines = tonumber(maxLines)
    if not maxLines or maxLines ~= maxLines or maxLines == math.huge
        or maxLines == -math.huge then
      maxLines = 6
    end
    maxLines = math.max(3, math.floor(maxLines))
    for _, egg in ipairs(snapshotValue and snapshotValue.eggs or {}) do
      local steps = egg.steps == nil and "?" or tostring(egg.steps)
      lines[#lines + 1] = (egg.status or "EGG") .. " " .. steps
      if #lines >= maxLines - 2 then break end
    end
    if #lines == 0 and snapshotValue and snapshotValue.breeding then
      local breeding = snapshotValue.breeding
      lines[#lines + 1] = (breeding.status or "DAYCARE") .. " "
        .. tostring(breeding.steps or "?")
    end
    if #lines == 0 then lines[#lines + 1] = "NO EGGS" end
    local parents = snapshotValue and snapshotValue.parents or {}
    lines[#lines + 1] = "P1 " .. tostring(parents[1] or "EMPTY")
    lines[#lines + 1] = "P2 " .. tostring(parents[2] or "EMPTY")
    return lines
  end

  local function freeRoam(game)
    local world = mod.world
    if not (world and type(world.overworld) == "function") then return false end
    local ok, overworld = pcall(world.overworld, world)
    if not ok then return false end
    if not overworld then return false end
    local stack = game and game.stack
    if stack and type(stack.top) == "function" then
      local top = stack:top()
      if top and top ~= overworld then return false end
    end
    return not overworld.transitioning and not overworld.flyAnim
      and not overworld.teleportOut and not overworld.engaging
  end

  local function viewportSize(viewport)
    viewport = viewport or {}
    local width = tonumber(viewport.width)
      or tonumber(viewport.gameWidth) or 160
    local height = tonumber(viewport.height)
      or tonumber(viewport.gameHeight) or 144
    if width <= 0 then width = 160 end
    if height <= 0 then height = 144 end
    return width, height
  end

  -- EGG TRACKER follows PARTY CORNER and is the fourth shared overlay. It
  -- therefore stacks after minimap, encounter tracker and party overview
  -- instead of independently guessing an open screen edge.
  local function layout(viewport, lineCount)
    local windowWidth, windowHeight = viewportSize(viewport)
    local panelWidth = math.max(1, math.min(PANEL_WIDTH, windowWidth))
    local panelHeight = 10 + math.max(1,
      math.floor(tonumber(lineCount) or 1)) * NATIVE_TILE
    panelHeight = math.max(1, math.min(panelHeight, windowHeight))
    local selectedCorner = runtimePartyCorner or "bottom-left"

    if overlayLayout and type(overlayLayout.corner) == "function" then
      selectedCorner = overlayLayout.corner(selectedCorner)
    end
    if overlayLayout and type(overlayLayout.positions) == "function" then
      local panels = {}
      local mapWidth, mapHeight
      if type(overlayLayout.minimapDimensions) == "function" then
        mapWidth, mapHeight = overlayLayout.minimapDimensions(viewport,
          mod.options:get("minimapSize"), mod.options:get("minimapZoom"))
      end
      if runtimeMinimapEnabled and mapWidth and mapHeight then
        panels[#panels + 1] = {
          id = "minimap", corner = runtimeMinimapCorner,
          width = mapWidth, height = mapHeight, order = 1,
        }
      end
      if runtimeTrackerEnabled and type(overlayLayout.trackerRect) == "function" then
        local tracker = overlayLayout.trackerRect(viewport,
          runtimeTrackerCorner)
        if tracker then
          panels[#panels + 1] = {
            id = "tracker", corner = runtimeTrackerCorner,
            width = tracker.width, height = tracker.height, order = 2,
          }
        end
      end
      if runtimePartyEnabled then
        panels[#panels + 1] = {
          id = "party", corner = selectedCorner,
          width = math.max(1, math.min(mapWidth or 192, windowWidth)),
          height = overlayLayout.partyHeight or 72, order = 3,
        }
      end
      panels[#panels + 1] = {
        id = "egg", corner = selectedCorner,
        width = panelWidth, height = panelHeight, order = 4,
      }
      local rect = overlayLayout.positions(viewport, panels).egg
      if rect then return rect end
    end

    local left = selectedCorner == "top-left"
      or selectedCorner == "bottom-left"
    local top = selectedCorner == "top-left"
      or selectedCorner == "top-right"
    return {
      x = left and MARGIN or math.max(0, windowWidth - panelWidth - MARGIN),
      y = top and MARGIN or math.max(0, windowHeight - panelHeight - MARGIN),
      width = panelWidth,
      height = panelHeight,
      corner = selectedCorner,
    }
  end

  local function draw(game, viewport)
    if not (runtimeEnabled and freeRoam(game)) then
      renderedLastFrame = false
      return
    end
    local g = love and love.graphics
    if not (g and g.rectangle and g.setColor) then return end
    if not Font or type(Font.draw) ~= "function" then return end
    local pushed = type(g.push) == "function" and type(g.pop) == "function"
    local oldR, oldG, oldB, oldA
    if pushed then
      g.push("all")
    elseif type(g.getColor) == "function" then
      oldR, oldG, oldB, oldA = g.getColor()
    end
    local save = game and game.save
    local party = save and save.party
    local dayCare = save and (save.dayCare or save.daycare)
    if renderDirty or not renderedLastFrame or renderGame ~= game
        or renderSave ~= save or renderParty ~= party
        or renderDayCare ~= dayCare then
      renderLines = format(snapshot(game), 5)
      renderGame, renderSave = game, save
      renderParty, renderDayCare = party, dayCare
      renderDirty = false
    end
    renderedLastFrame = true
    local lines = renderLines or {}
    local panel = layout(viewport, #lines)
    local x, y = panel.x, panel.y
    local panelWidth, panelHeight = panel.width, panel.height
    g.setColor(0.96, 0.96, 0.88, 0.90)
    g.rectangle("fill", x, y, panelWidth, panelHeight, 3)
    g.setColor(0.08, 0.08, 0.08, 0.95)
    g.rectangle("line", x, y, panelWidth, panelHeight, 3)
    g.setColor(0.02, 0.02, 0.02, 1)
    Font.draw("EGG TRACKER", x + 4, y + 2)
    for index, line in ipairs(lines) do
      Font.draw(line:sub(1, 13), x + 4, y + 10 + (index - 1) * 8)
    end
    if pushed then
      g.pop()
    elseif oldR ~= nil then
      g.setColor(oldR, oldG, oldB, oldA)
    end
  end

  local function installRenderHook()
    if renderUnsubscribe ~= nil then return end
    local unsubscribe = mod.hooks:wrap("render.hud",
      function(next, game, viewport)
        local result = next(game, viewport)
        if runtimeEnabled then draw(game, viewport) end
        return result
      end, -800)
    renderUnsubscribe = type(unsubscribe) == "function" and unsubscribe or false
  end

  syncRenderHook = function()
    if not isGold then return end
    if runtimeEnabled then
      installRenderHook()
    elseif type(renderUnsubscribe) == "function" then
      renderUnsubscribe()
      renderUnsubscribe = nil
      renderedLastFrame = false
    end
    -- Engines predating hook unsubscription return nil from wrap. In that
    -- case `false` remains a sentinel for one gated wrapper, preventing a
    -- duplicate on later toggle cycles while preserving disabled correctness.
  end
  syncRenderHook()

  mod.exports = {
    enabled = enabled,
    snapshot = snapshot,
    format = format,
    stepsFor = stepsFor,
    layout = layout,
    renderHookActive = function() return renderUnsubscribe ~= nil end,
  }
end
