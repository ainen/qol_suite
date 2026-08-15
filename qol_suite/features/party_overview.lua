-- PARTY OVERVIEW: a compact overworld party readout and optional party-order
-- automation.  The data comes from the live save party so it follows healing,
-- status changes, move PP, catches, and level-ups without a second party model.
return function(mod, overlayLayout)
  local Font = require("src.render.Font")
  local OVERVIEW_OPTION = "partyOverview"
  local CORNER_OPTION = "partyOverviewCorner"
  local ORDER_OPTION = "partyOrder"
  local AUTO_ORDER_OPTION = "autoPartyOrder"
  local MARGIN = 4
  local PANEL_WIDTH = 192
  local PANEL_HEIGHT = 72
  local NATIVE_TILE = 8
  local HINT_PANEL = { 0.98, 0.98, 0.94 }
  local DARK_INK = { 0.02, 0.02, 0.02 }
  local ROW_HEIGHT = 8
  local LOW_HP_RATIO = 0.25
  local renderDirty = true
  local renderedLastFrame = false
  local renderGame, renderSave, renderParty, renderRows
  local runtimeOverviewEnabled = mod.options:get(OVERVIEW_OPTION) == true
  local runtimeAutoOrderEnabled = mod.options:get(AUTO_ORDER_OPTION) == true
  local runtimeOrder = mod.options:get(ORDER_OPTION)
  local runtimeMinimapEnabled = mod.options:get("minimap") == true
  local runtimeMinimapCorner = mod.options:get("minimapCorner")
  local runtimeTrackerEnabled = mod.options:get("encounterTracker") == true
  local runtimeTrackerCorner = mod.options:get("encounterTrackerCorner")
  local runtimePartyCorner = mod.options:get(CORNER_OPTION)
  local renderUnsubscribe, updateUnsubscribe
  local syncHooks

  local function invalidateRender()
    renderDirty = true
  end

  -- These are the native points at which an overworld-visible party summary
  -- can change. Menus and battles hide the panel and force a fresh snapshot
  -- when free roam resumes, so the six rows no longer need rebuilding at 60Hz.
  mod.events:on("world.stepped", invalidateRender)
  mod.events:on("world.interacted", invalidateRender)
  mod.events:on("map.entered", invalidateRender)
  mod.events:on("map.reloaded", invalidateRender)
  mod.events:on("mod.options_changed", function(event)
    if type(event) ~= "table" or event.mod ~= mod.id then return end
    if event.key == OVERVIEW_OPTION then
      runtimeOverviewEnabled = event.value == true
      invalidateRender()
      if syncHooks then syncHooks() end
    elseif event.key == AUTO_ORDER_OPTION then
      runtimeAutoOrderEnabled = event.value == true
      if syncHooks then syncHooks() end
    elseif event.key == ORDER_OPTION then
      runtimeOrder = event.value
    elseif event.key == "minimap" then
      runtimeMinimapEnabled = event.value == true
    elseif event.key == "minimapCorner" then
      runtimeMinimapCorner = event.value
    elseif event.key == "encounterTracker" then
      runtimeTrackerEnabled = event.value == true
    elseif event.key == "encounterTrackerCorner" then
      runtimeTrackerCorner = event.value
    elseif event.key == CORNER_OPTION then
      runtimePartyCorner = event.value
    end
  end)

  local ORDER_VALUES = {
    native = true,
    healthy = true,
    level = true,
    type = true,
  }

  local function enabled()
    return mod.options:get(OVERVIEW_OPTION) == true
  end

  local function autoEnabled()
    return enabled() and mod.options:get(AUTO_ORDER_OPTION) == true
  end

  local function orderValue(value)
    value = value or mod.options:get(ORDER_OPTION)
    if ORDER_VALUES[value] then return value end
    return "native"
  end

  local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then
      return fallback or 0
    end
    return value
  end

  local function maxHp(mon)
    return math.max(0, math.floor(finite(mon and (mon.maxHp
      or (mon.stats and mon.stats.hp)), 0)))
  end

  local function hp(mon)
    return math.max(0, math.floor(finite(mon and mon.hp, 0)))
  end

  local function statusCode(mon)
    if mon and (mon.isEgg == true or mon.egg == true) then return "EGG" end
    if hp(mon) <= 0 then return "FNT" end
    local status = mon and mon.status
    if type(status) == "table" then status = status.name or status.id end
    status = tostring(status or "")
    if status == "" or status == "0" or status == "NONE" then return "OK" end
    status = status:upper()
    if status:find("POISON", 1, true) then return "PSN" end
    if status:find("BURN", 1, true) then return "BRN" end
    if status:find("PARAL", 1, true) then return "PAR" end
    if status:find("SLEEP", 1, true) then return "SLP" end
    if status:find("FREEZ", 1, true) then return "FRZ" end
    return status:sub(1, 3)
  end

  local function pp(mon, data)
    local current, maximum = 0, 0
    for _, move in ipairs((mon and mon.moves) or {}) do
      if type(move) == "table" then
        local moveId = move.id or move.move or move.name
        local definition = data and data.moves and data.moves[moveId]
        local base = definition and finite(definition.pp, nil)
        local ups = math.max(0, math.min(3,
          math.floor(finite(move.ppUps or move.ppUpsCount, 0))))
        local calculated = base and (base + ups * math.floor(base / 5)) or nil
        current = current + math.max(0, math.floor(finite(move.pp
          or move.currentPp, 0)))
        maximum = maximum + math.max(0, math.floor(finite(move.maxPp
          or move.maxPP or move.ppMax or calculated, 0)))
      end
    end
    return current, maximum
  end

  local function nameOf(data, mon)
    local nickname = mon and mon.nickname
    if nickname and nickname ~= "" then return tostring(nickname):upper() end
    local def = data and data.pokemon and data.pokemon[mon and mon.species]
    local name = def and (def.name or def.speciesName)
    return tostring(name or mon and mon.species or "MON")
      :gsub("_", " "):upper()
  end

  local function row(mon, index, data)
    local current, maximum = pp(mon, data)
    return {
      index = index,
      hp = hp(mon),
      maxHp = maxHp(mon),
      status = statusCode(mon),
      pp = current,
      maxPp = maximum,
      name = nameOf(data, mon),
      species = mon and mon.species,
      level = finite(mon and mon.level, 0),
    }
  end

  local function snapshot(game)
    local out = {}
    local party = game and game.save and game.save.party
    if type(party) ~= "table" then return out end
    for index, mon in ipairs(party) do
      out[#out + 1] = row(mon, index, game.data)
    end
    return out
  end

  local function lowHealth(mon)
    local maximum = maxHp(mon)
    return hp(mon) <= 0 or (maximum > 0 and hp(mon) / maximum <= LOW_HP_RATIO)
  end

  local function typeName(game, mon)
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[mon and mon.species]
    local primary = def and (def.type1 or def.primaryType or def.type)
    if not primary and def and type(def.types) == "table" then
      primary = def.types[1]
    end
    if type(primary) == "table" then primary = primary[1] end
    return tostring(primary or ""):upper()
  end

  local function sortedParty(game, preset)
    local party = game and game.save and game.save.party
    if type(party) ~= "table" then return nil end
    local rows = {}
    for index, mon in ipairs(party) do
      rows[#rows + 1] = { mon = mon, index = index }
    end
    if preset == "native" then return rows end
    table.sort(rows, function(a, b)
      -- Every automatic preset keeps members that cannot safely lead behind
      -- healthy battlers. Eggs are pinned last, followed by fainted/low-health
      -- Pokemon; the selected preset only orders peers within those groups.
      local function backRank(mon)
        if mon and (mon.isEgg == true or mon.egg == true) then return 2 end
        return lowHealth(mon) and 1 or 0
      end
      local arank, brank = backRank(a.mon), backRank(b.mon)
      if arank ~= brank then return arank < brank end
      if preset == "healthy" then
        local ah, bh = hp(a.mon), hp(b.mon)
        local am, bm = maxHp(a.mon), maxHp(b.mon)
        local ar = am > 0 and ah / am or 0
        local br = bm > 0 and bh / bm or 0
        if ar ~= br then return ar > br end
      elseif preset == "level" then
        local al = finite(a.mon and a.mon.level, 0)
        local bl = finite(b.mon and b.mon.level, 0)
        if al ~= bl then return al > bl end
      elseif preset == "type" then
        local at, bt = typeName(game, a.mon), typeName(game, b.mon)
        if at ~= bt then return at < bt end
      end
      return a.index < b.index
    end)
    return rows
  end

  local function reorder(game, preset)
    preset = orderValue(preset)
    local party = game and game.save and game.save.party
    if type(party) ~= "table" or #party < 2 or preset == "native" then
      return false
    end
    local rows = sortedParty(game, preset)
    local changed = false
    for index, entry in ipairs(rows) do
      if party[index] ~= entry.mon then changed = true end
      party[index] = entry.mon
    end
    if changed then invalidateRender() end
    return changed
  end

  -- AUTO PARTY ORDER runs from a hot core.update hook. Keep one fixed six-slot
  -- primitive snapshot instead of allocating a table and concatenated key on
  -- every frame. Only values that can affect a preset are observed.
  local observedParty, observedPreset, observedCount
  local observedMon, observedSpecies = {}, {}
  local observedHp, observedMaxHp, observedLevel, observedEgg = {}, {}, {}, {}
  local autoOrderRuns = 0

  local function resetPartyState()
    observedParty, observedPreset, observedCount = nil, nil, nil
    for index = 1, 6 do
      observedMon[index], observedSpecies[index] = nil, nil
      observedHp[index], observedMaxHp[index] = nil, nil
      observedLevel[index], observedEgg[index] = nil, nil
    end
  end

  local function partyStateChanged(game, preset)
    local party = game and game.save and game.save.party
    if type(party) ~= "table" then party = nil end
    local count = party and #party or 0
    local changed = party ~= observedParty or preset ~= observedPreset
      or count ~= observedCount
    for index = 1, 6 do
      local mon = party and party[index] or nil
      local species = mon and mon.species or nil
      local currentHp = mon and mon.hp or nil
      local maximumHp = mon and (mon.maxHp
        or (mon.stats and mon.stats.hp)) or nil
      local level = mon and mon.level or nil
      local egg = mon and (mon.isEgg == true or mon.egg == true) or false
      if observedMon[index] ~= mon or observedSpecies[index] ~= species
          or observedHp[index] ~= currentHp
          or observedMaxHp[index] ~= maximumHp
          or observedLevel[index] ~= level or observedEgg[index] ~= egg then
        changed = true
      end
      if changed then
        observedMon[index], observedSpecies[index] = mon, species
        observedHp[index], observedMaxHp[index] = currentHp, maximumHp
        observedLevel[index], observedEgg[index] = level, egg
      end
    end
    if changed then
      observedParty, observedPreset, observedCount = party, preset, count
    end
    return changed
  end

  local function autoOrderTick(game, preset)
    preset = orderValue(preset)
    if not partyStateChanged(game, preset) then return false end
    autoOrderRuns = autoOrderRuns + 1
    if reorder(game, preset) then
      -- Reordering changes slot identity. Capture the resulting order now so
      -- the next unchanged frame remains allocation-free and does no work.
      partyStateChanged(game, preset)
    end
    return true
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

  local function panelWidthFor(viewport)
    viewport = viewport or {}
    local windowWidth = tonumber(viewport.width)
      or tonumber(viewport.gameWidth) or 160
    if windowWidth <= 0 then windowWidth = 160 end
    if overlayLayout and type(overlayLayout.minimapDimensions) == "function" then
      local width = select(1, overlayLayout.minimapDimensions(viewport,
        mod.options:get("minimapSize"), mod.options:get("minimapZoom")))
      if tonumber(width) and width > 0 then
        return math.max(1, math.min(width, windowWidth))
      end
    end
    return math.max(1, math.min(PANEL_WIDTH, windowWidth))
  end

  local function panelPosition(viewport, panelWidth)
    viewport = viewport or {}
    local width = tonumber(viewport.width) or 160
    local height = tonumber(viewport.height) or 144
    local x = MARGIN
    local y = math.max(MARGIN, height - PANEL_HEIGHT - MARGIN)
    if not (overlayLayout and type(overlayLayout.positions) == "function") then
      local minimapOnLeft = runtimeMinimapEnabled
        and (runtimeMinimapCorner == "top-left"
          or runtimeMinimapCorner == "bottom-left")
      x = minimapOnLeft and math.max(MARGIN,
        width - panelWidth - MARGIN) or MARGIN
      return x, y
    end

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
    if runtimeTrackerEnabled then
      local trackerWidth = mapWidth or PANEL_WIDTH
      local trackerHeight = overlayLayout.trackerMaxHeight
        or ((16 + 2) * NATIVE_TILE)
      local trackerVisible = true
      if type(overlayLayout.trackerRect) == "function" then
        local tracker = overlayLayout.trackerRect(viewport,
          runtimeTrackerCorner)
        if tracker then
          trackerWidth = tracker.width or trackerWidth
          trackerHeight = tracker.height or trackerHeight
        else
          -- The minimap publishes this only after it has a current encounter
          -- model.  If there is no tracker panel this frame, do not reserve a
          -- phantom 16-line panel that would push PARTY OVERVIEW downward.
          trackerVisible = false
        end
      end
      if trackerVisible then
        panels[#panels + 1] = {
          id = "tracker", corner = runtimeTrackerCorner,
          width = trackerWidth, height = trackerHeight, order = 2,
        }
      end
    end
    panels[#panels + 1] = {
      id = "party", corner = runtimePartyCorner,
      width = panelWidth, height = PANEL_HEIGHT, order = 3,
    }
    local rects = overlayLayout.positions(viewport, panels)
    local rect = rects.party
    if rect then
      return rect.x, rect.y, rect.width
    end
    return x, y
  end

  local function layout(viewport)
    local panelWidth = panelWidthFor(viewport)
    local x, y, laidOutWidth = panelPosition(viewport, panelWidth)
    return {
      x = x,
      y = y,
      width = laidOutWidth or panelWidth,
      height = PANEL_HEIGHT,
    }
  end

  local COMPACT_STATUS = {
    OK = "O", FNT = "X", EGG = "E", PSN = "P", BRN = "B",
    PAR = "P", SLP = "S", FRZ = "F",
  }

  local function compactNumber(value, digits)
    value = math.max(0, math.floor(finite(value, 0)))
    local text = tostring(value)
    if #text <= digits then return text end
    if digits <= 1 then return "+" end
    return string.rep("9", digits - 1) .. "+"
  end

  local function rowCandidate(entry, maxChars, hpText, statusText,
      minimumName, mode)
    local indexText = compactNumber(entry.index, 1)
    local ppText = "P" .. compactNumber(entry.pp, 3)
    local fixed = #indexText + #hpText + #statusText + #ppText + 4
    local nameChars = maxChars - fixed
    if nameChars < minimumName then return nil end
    local name = tostring(entry.name or "MON"):sub(1, math.min(6, nameChars))
    return indexText .. " " .. name .. " " .. hpText .. " "
      .. statusText .. " " .. ppText, mode
  end

  -- Build one measured native-font row. Wide panels retain current/max HP and
  -- full status; compact panels progressively shorten the name, HP and status
  -- without ever dropping HP, status or PP beyond the panel's inner edge.
  local function rowLayout(entry, panelWidth)
    entry = entry or {}
    panelWidth = math.max(NATIVE_TILE * 3, math.floor(finite(panelWidth, 160)))
    local contentWidth = math.max(1, panelWidth - NATIVE_TILE * 2)
    local maxChars = math.max(1, math.floor(contentWidth / NATIVE_TILE))
    local current = compactNumber(entry.hp, 3)
    local maximum = compactNumber(entry.maxHp, 3)
    local status = tostring(entry.status or "OK"):upper():sub(1, 3)
    local shortStatus = COMPACT_STATUS[status] or status:sub(1, 1)
    local text, mode = rowCandidate(entry, maxChars,
      current .. "/" .. maximum, status, 3, "full")
    if not text then
      text, mode = rowCandidate(entry, maxChars,
        current .. "/" .. maximum, shortStatus, 3, "exact-compact")
    end
    if not text then
      text, mode = rowCandidate(entry, maxChars,
        "H" .. current, status, 2, "hp-compact")
    end
    if not text then
      text, mode = rowCandidate(entry, maxChars,
        "H" .. current, shortStatus, 1, "compact")
    end
    if not text then
      local digits = maxChars >= 12 and 3 or maxChars >= 10 and 2 or 1
      current = compactNumber(entry.hp, digits)
      local ppText = compactNumber(entry.pp, digits)
      text = compactNumber(entry.index, 1) .. "H" .. current .. " "
        .. shortStatus .. " P" .. ppText
      if #text > maxChars then
        text = compactNumber(entry.index, 1) .. "H" .. current
          .. shortStatus .. "P" .. ppText
      end
      mode = "minimal"
    end
    return {
      text = text,
      mode = mode,
      maxChars = maxChars,
      contentWidth = contentWidth,
      pixelWidth = #text * NATIVE_TILE,
    }
  end

  local function headerText(panelWidth)
    local contentWidth = math.max(1, panelWidth - NATIVE_TILE * 2)
    return contentWidth >= #("PARTY HP/PP") * NATIVE_TILE
      and "PARTY HP/PP" or "PARTY"
  end

  local function drawPanel(g, x, y, width, height)
    local border = Font and Font.BORDER
    if not (Font and type(Font.drawCode) == "function"
        and type(border) == "table") then
      g.setColor(HINT_PANEL[1], HINT_PANEL[2], HINT_PANEL[3], 0.98)
      g.rectangle("fill", x, y, width, height)
      g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
      g.rectangle("line", x, y, width, height)
      return
    end

    local tx = math.floor(x)
    local ty = math.floor(y)
    local panelWidth = math.max(NATIVE_TILE * 3, math.floor(width))
    local panelHeight = math.max(NATIVE_TILE * 3, math.floor(height))
    local right = tx + panelWidth - NATIVE_TILE
    local bottom = ty + panelHeight - NATIVE_TILE
    local columns = math.max(0, math.floor(panelWidth / NATIVE_TILE) - 2)
    local rows = math.max(0, math.floor(panelHeight / NATIVE_TILE) - 2)
    g.setColor(HINT_PANEL[1], HINT_PANEL[2], HINT_PANEL[3], 0.98)
    g.rectangle("fill", tx, ty, panelWidth, panelHeight)
    g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
    Font.drawCode(border.tl, tx, ty)
    Font.drawCode(border.tr, right, ty)
    Font.drawCode(border.bl, tx, bottom)
    Font.drawCode(border.br, right, bottom)
    for index = 1, columns do
      local edgeX = tx + index * NATIVE_TILE
      Font.drawCode(border.h, edgeX, ty)
      Font.drawCode(border.h, edgeX, bottom)
    end
    local finalX = right - NATIVE_TILE
    local loopEnd = tx + columns * NATIVE_TILE
    if finalX >= tx + NATIVE_TILE and finalX ~= loopEnd then
      Font.drawCode(border.h, finalX, ty)
      Font.drawCode(border.h, finalX, bottom)
    end
    for index = 1, rows do
      local edgeY = ty + index * NATIVE_TILE
      Font.drawCode(border.v, tx, edgeY)
      Font.drawCode(border.v, right, edgeY)
    end
  end

  local function draw(game, viewport)
    if not (runtimeOverviewEnabled and freeRoam(game)) then
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
    viewport = viewport or {}
    local panel = layout(viewport)
    local x, y, panelWidth = panel.x, panel.y, panel.width
    drawPanel(g, x, y, panelWidth, PANEL_HEIGHT)
    g.setColor(0.02, 0.02, 0.02, 1)
    Font.draw(headerText(panelWidth), x + NATIVE_TILE, y + NATIVE_TILE)
    local save = game and game.save
    local party = save and save.party
    if renderDirty or not renderedLastFrame or renderGame ~= game
        or renderSave ~= save or renderParty ~= party then
      renderRows = snapshot(game)
      renderGame, renderSave, renderParty = game, save, party
      renderDirty = false
    end
    renderedLastFrame = true
    local rows = renderRows or {}
    if g.setScissor then g.setScissor(x + NATIVE_TILE, y + NATIVE_TILE,
      math.max(1, panelWidth - NATIVE_TILE * 2),
      PANEL_HEIGHT - NATIVE_TILE * 2) end
    for index, entry in ipairs(rows) do
      local lineY = y + NATIVE_TILE * 2 + (index - 1) * ROW_HEIGHT
      Font.draw(rowLayout(entry, panelWidth).text, x + NATIVE_TILE, lineY)
    end
    if g.setScissor then g.setScissor() end
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
        if runtimeOverviewEnabled then draw(game, viewport) end
        return result
      end, -900)
    renderUnsubscribe = type(unsubscribe) == "function" and unsubscribe or false
  end

  local function installUpdateHook()
    if updateUnsubscribe ~= nil then return end
    resetPartyState()
    local unsubscribe = mod.hooks:wrap("core.update", function(next, game, dt)
      if runtimeOverviewEnabled and runtimeAutoOrderEnabled and freeRoam(game) then
        autoOrderTick(game, runtimeOrder)
      elseif observedParty ~= nil then
        resetPartyState()
      end
      return next(game, dt)
    end, -1100)
    updateUnsubscribe = type(unsubscribe) == "function" and unsubscribe or false
  end

  local function removeHook(unsubscribe)
    if type(unsubscribe) == "function" then unsubscribe() return nil end
    -- Old engines that did not return an unsubscribe keep one gated wrapper;
    -- never install a duplicate on later option cycles.
    return unsubscribe
  end

  syncHooks = function()
    if runtimeOverviewEnabled then
      installRenderHook()
    else
      renderUnsubscribe = removeHook(renderUnsubscribe)
      renderedLastFrame = false
    end
    if runtimeOverviewEnabled and runtimeAutoOrderEnabled then
      installUpdateHook()
    else
      updateUnsubscribe = removeHook(updateUnsubscribe)
      resetPartyState()
    end
  end
  syncHooks()

  mod.exports = {
    enabled = enabled,
    autoEnabled = autoEnabled,
    order = orderValue,
    snapshot = snapshot,
    statusCode = statusCode,
    pp = pp,
    reorder = reorder,
    autoOrderTick = autoOrderTick,
    autoOrderRuns = function() return autoOrderRuns end,
    panelWidth = panelWidthFor,
    layout = layout,
    rowLayout = rowLayout,
    header = headerText,
    subscriptions = function()
      return renderUnsubscribe ~= nil, updateUnsubscribe ~= nil
    end,
    freeRoam = freeRoam,
  }
end
