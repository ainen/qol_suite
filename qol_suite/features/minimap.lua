-- QoL Suite: a small, persistent overworld minimap.  The engine's
-- read-only world API supplies a visual tile overview when the imported map
-- has tileset art, and a collision-grid fallback when it does not.  This is
-- deliberately screen-space: it stays against the selected window corner
-- regardless of zoom, tilt, or a map renderer that owns the world canvas.
return function(mod, tracking, encounterTracker, overlayLayout)
  local GameVersion = require("src.core.GameVersion")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true
  local okFont, Font = pcall(require, "src.render.Font")
  if not okFont then Font = nil end
  local okPalette, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not okPalette then PaletteFX = nil end
  local GoldMap, GoldWorld, GoldPalettes, GbcPalette
  if isGold then
    local okMap, mapModule = pcall(require, "src.world.gen2.Map")
    local okWorld, worldModule = pcall(require, "src.world.gen2.World")
    local okPalettes, paletteModule = pcall(require, "src.world.gen2.Palettes")
    local okGbcPalette, gbcPaletteModule = pcall(require, "src.render.GbcPalette")
    if okMap then GoldMap = mapModule end
    if okWorld then GoldWorld = worldModule end
    if okPalettes then GoldPalettes = paletteModule end
    if okGbcPalette then GbcPalette = gbcPaletteModule end
  end
  local OPTION = "minimap"
  local TRACKER_OPTION = "encounterTracker"
  local CORNER_OPTION = "minimapCorner"
  local TRACKER_CORNER_OPTION = "encounterTrackerCorner"
  local TRANSPARENCY_OPTION = "minimapTransparency"
  local SIZE_OPTION = "minimapSize"
  local ZOOM_OPTION = "minimapZoom"
  local BORDER_OPTION = "minimapBorder"
  local TRACKING_EVENT = "mod." .. mod.id .. ".tracking.changed"
  local DEFAULT_CORNER = "top-right"
  local MARGIN = 12
  local FRAME = 6
  local MAX_PANEL_WIDTH = 280
  local MAX_PANEL_HEIGHT = 220
  local MIN_PANEL_WIDTH = 144
  local MIN_PANEL_HEIGHT = 108
  -- Six screen units per visual map tile gives roughly 20 cells of width on
  -- the normal desktop HUD panel: a closer, player-centered view rather than
  -- a tiny thumbnail of the entire map.
  local ZOOM = 6

  local SHADE_COLORS = {
    ["0"] = { 0.72, 0.86, 0.62, 1 },
    ["1"] = { 0.50, 0.68, 0.43, 1 },
    ["2"] = { 0.30, 0.48, 0.31, 1 },
    ["3"] = { 0.14, 0.25, 0.19, 1 },
    ["."] = { 0.72, 0.86, 0.62, 1 },
    ["+"] = { 0.72, 0.86, 0.62, 1 },
    ["~"] = { 0.25, 0.55, 0.78, 1 },
    [" "] = { 0.08, 0.11, 0.10, 1 },
    panel = { 0.03, 0.06, 0.05, 1 },
    border = { 0.86, 0.94, 0.73, 1 },
  }
  local MARKER_COLORS = {
    warp = { 0.95, 0.95, 0.95, 1 },
    item = { 1.00, 0.82, 0.24, 1 },
    hidden = { 1.00, 0.46, 0.28, 1 },
  }
  local TRACKING_FILL = { 1.00, 0.62, 0.08, 1 }
  local HINT_PANEL = { 0.98, 0.98, 0.94 }
  local DARK_INK = { 0.02, 0.02, 0.02 }
  local NATIVE_TILE = 8
  local TRACKER_ROW_HEIGHT = NATIVE_TILE
  local TRACKER_DISPLAY_KEYS = {
    "tracked", "land", "surf", "fishing", "time", "swarms",
    "roaming", "rare", "headbutt", "rockSmash", "contest",
  }

  local cached = {
    mapId = nil, overview = nil, dirty = true,
    trackedSpecies = nil, encounterKey = nil, trackerEnabled = false,
  }
  local rowRunCache = setmetatable({}, { __mode = "k" })
  local paletteCache = setmetatable({}, { __mode = "k" })
  local trackerLineCache
  local terrainCommandCache
  local drawGeometryCache
  local runtimeEnabled = mod.options:get(OPTION) == true
  local runtimeTrackerEnabled = mod.options:get(TRACKER_OPTION) == true

  local VALID_CORNERS = {
    ["top-left"] = true,
    ["top-right"] = true,
    ["bottom-left"] = true,
    ["bottom-right"] = true,
  }

  local VALID_BORDERS = {
    rounded = true,
    square = true,
    off = true,
  }

  local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return fallback end
    return value
  end

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  local function trackerEnabled()
    return runtimeTrackerEnabled
  end

  local function corner(value)
    value = value or mod.options:get(CORNER_OPTION)
    if VALID_CORNERS[value] then return value end
    return DEFAULT_CORNER
  end

  local function borderStyle(value)
    value = value or mod.options:get(BORDER_OPTION)
    if VALID_BORDERS[value] then return value end
    return "rounded"
  end

  -- The setting is expressed as transparency: 0 is opaque and 100 is fully
  -- transparent.  Keep invalid or missing stored values safe for older saves.
  local function transparency(value)
    if value == nil then value = mod.options:get(TRANSPARENCY_OPTION) end
    return math.max(0, math.min(100, finite(value, 0)))
  end

  local function opacity(value)
    return 1 - transparency(value) / 100
  end

  -- The tracker is an independent native-style panel. A hidden minimap's
  -- transparency is relevant only while the map itself is on screen.
  local function overlayOpacity(mapEnabled, value)
    if not mapEnabled then return 1 end
    return opacity(value)
  end

  -- The setting is a percentage of the current panel dimensions.  Keep the
  -- old 100% layout as the default and clamp older or malformed saves.
  local function sizePercent(value)
    if value == nil then value = mod.options:get(SIZE_OPTION) end
    return math.max(50, math.min(200, finite(value, 100)))
  end

  -- Higher percentages zoom in (larger map tiles and fewer visible cells);
  -- lower percentages zoom out.  Keep 100% identical to the original view.
  local function zoomPercent(value)
    if value == nil then value = mod.options:get(ZOOM_OPTION) end
    return math.max(50, math.min(200, finite(value, 100)))
  end

  local runtimeSettings = {
    corner = mod.options:get(CORNER_OPTION),
    trackerCorner = mod.options:get(TRACKER_CORNER_OPTION),
    transparency = mod.options:get(TRANSPARENCY_OPTION),
    size = mod.options:get(SIZE_OPTION),
    zoom = mod.options:get(ZOOM_OPTION),
    border = mod.options:get(BORDER_OPTION),
  }

  local function invalidate()
    cached.dirty = true
  end

  local syncHudHook
  mod.events:on("mod.options_changed", function(event)
    if type(event) ~= "table" or event.mod ~= mod.id then return end
    if event.key == OPTION then
      runtimeEnabled = event.value == true
    elseif event.key == TRACKER_OPTION then
      runtimeTrackerEnabled = event.value == true
    elseif event.key == CORNER_OPTION then
      runtimeSettings.corner = event.value
    elseif event.key == TRACKER_CORNER_OPTION then
      runtimeSettings.trackerCorner = event.value
    elseif event.key == TRANSPARENCY_OPTION then
      runtimeSettings.transparency = event.value
    elseif event.key == SIZE_OPTION then
      runtimeSettings.size = event.value
    elseif event.key == ZOOM_OPTION then
      runtimeSettings.zoom = event.value
    elseif event.key == BORDER_OPTION then
      runtimeSettings.border = event.value
    end
    if syncHudHook and (event.key == OPTION
        or event.key == TRACKER_OPTION) then
      syncHudHook()
    end
  end)

  -- Map entry/reload and object interaction events cover every part of the
  -- overview that can change. Player position is read independently each
  -- frame, so rebuilding the complete map after every walking step only
  -- repeats collision/tile extraction without changing a pixel.
  mod.events:on("map.entered", invalidate)
  mod.events:on("map.reloaded", invalidate)
  mod.events:on("world.object_toggled", invalidate)
  mod.events:on("world.block_replaced", invalidate)
  mod.events:on("world.interacted", invalidate)
  mod.events:on("world.tod_changed", invalidate)
  mod.events:on(TRACKING_EVENT, invalidate)

  local function grid(overview)
    if not overview then return nil end
    local rows = overview.tileRows or overview.rows
    local width = finite(overview.tileWidth or overview.width)
    local height = finite(overview.tileHeight or overview.height)
    if type(rows) ~= "table" or not width or not height
        or width < 1 or height < 1 then
      return nil
    end
    local logicalWidth = finite(overview.width)
    local logicalHeight = finite(overview.height)
    local cellWidth = logicalWidth and logicalWidth > 0
      and width / logicalWidth or 1
    local cellHeight = logicalHeight and logicalHeight > 0
      and height / logicalHeight or 1
    return rows, math.floor(width), math.floor(height),
      math.max(1, cellWidth), math.max(1, cellHeight)
  end

  local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
  end

  -- Returns screen-space geometry and a player-centered source-grid window.
  -- The panel is positioned against the real window, not the letterboxed
  -- playfield, so it reads like a persistent MMO-style HUD widget.
  local function geometry(overview, viewport, current, cornerName, sizeValue,
      zoomValue)
    local rows, sourceWidth, sourceHeight, cellSourceWidth, cellSourceHeight =
      grid(overview)
    if not rows then return nil end
    viewport = viewport or {}
    local windowWidth = finite(viewport.width)
      or finite(viewport.gameWidth) or 160
    local windowHeight = finite(viewport.height)
      or finite(viewport.gameHeight) or 144
    if windowWidth <= 0 then windowWidth = 160 end
    if windowHeight <= 0 then windowHeight = 144 end
    local sizeScale = sizePercent(sizeValue) / 100
    local frame = FRAME
    local panelWidth = clamp(math.floor(windowWidth * 0.30 * sizeScale),
      math.floor(MIN_PANEL_WIDTH * sizeScale),
      math.floor(MAX_PANEL_WIDTH * sizeScale))
    local panelHeight = clamp(math.floor(windowHeight * 0.30 * sizeScale),
      math.floor(MIN_PANEL_HEIGHT * sizeScale),
      math.floor(MAX_PANEL_HEIGHT * sizeScale))
    local scale = ZOOM * zoomPercent(zoomValue) / 100
    local mapWidth = math.max(scale,
      math.floor((panelWidth - frame * 2) / scale) * scale)
    local mapHeight = math.max(scale,
      math.floor((panelHeight - frame * 2) / scale) * scale)
    local width = mapWidth + frame * 2
    local height = mapHeight + frame * 2
    local selectedCorner = corner(cornerName)
    local left = selectedCorner == "top-left"
      or selectedCorner == "bottom-left"
    local top = selectedCorner == "top-left"
      or selectedCorner == "top-right"
    local x = left and MARGIN or windowWidth - width - MARGIN
    local y = top and MARGIN or windowHeight - height - MARGIN

    if overlayLayout and type(overlayLayout.positions) == "function" then
      local panels = overlayLayout.positions(viewport, {
        { id = "minimap", corner = selectedCorner, width = width,
          height = height, order = 1 },
      })
      local panel = panels.minimap
      if panel then x, y = panel.x, panel.y end
    end

    -- Very small windows can be narrower than the minimum panel.  Keep the
    -- panel attached to the window and let its map viewport scale down only
    -- as a last resort.
    x = clamp(x, 0, math.max(0, windowWidth - width))
    y = clamp(y, 0, math.max(0, windowHeight - height))

    local currentOffsetX = overview.tileRows
      and finite(overview.currentTileOffsetX)
      or finite(overview.currentOffsetX, 0)
    local currentOffsetY = overview.tileRows
      and finite(overview.currentTileOffsetY)
      or finite(overview.currentOffsetY, 0)
    currentOffsetX = finite(currentOffsetX, 0)
    currentOffsetY = finite(currentOffsetY, 0)
    local centerX, centerY
    local currentX = current and finite(current.x)
    local currentY = current and finite(current.y)
    if currentX and currentY then
      centerX = currentOffsetX + currentX * cellSourceWidth
        + cellSourceWidth / 2
      centerY = currentOffsetY + currentY * cellSourceHeight
        + cellSourceHeight / 2
    else
      centerX = sourceWidth / 2
      centerY = sourceHeight / 2
    end
    local viewSourceWidth = math.max(1, math.floor(mapWidth / scale))
    local viewSourceHeight = math.max(1, math.floor(mapHeight / scale))
    -- Clamp the camera only when the player reaches an edge.  On normal
    -- terrain this keeps the player in the exact center as they walk.
    local sourceX = math.floor(centerX - viewSourceWidth / 2)
    local sourceY = math.floor(centerY - viewSourceHeight / 2)
    if sourceWidth > viewSourceWidth then
      sourceX = clamp(sourceX, 0, sourceWidth - viewSourceWidth)
    end
    if sourceHeight > viewSourceHeight then
      sourceY = clamp(sourceY, 0, sourceHeight - viewSourceHeight)
    end

    return {
      x = x, y = y, width = width, height = height,
      mapX = x + frame, mapY = y + frame,
      mapWidth = mapWidth, mapHeight = mapHeight,
      scale = scale,
      cellWidth = cellSourceWidth * scale,
      cellHeight = cellSourceHeight * scale,
      sourceWidth = sourceWidth, sourceHeight = sourceHeight,
      sourceX = sourceX, sourceY = sourceY,
      viewSourceWidth = viewSourceWidth,
      viewSourceHeight = viewSourceHeight,
      currentOffsetX = currentOffsetX,
      currentOffsetY = currentOffsetY,
    }
  end

  -- The active map overview supplies its four-color palette in the engine's
  -- native 0..255 format. Gen 1 applies PaletteFX's COLORS mode; Gold applies
  -- the same GbcPalette mode and active rBGP remap as the overworld renderer.
  -- Collision-only/headless overviews keep the historical green fallback.
  local function colorsFor(overview)
    local source = overview and overview.colors
    if type(source) ~= "table" or #source < 4 then return SHADE_COLORS end
    if not isGold
        and (not PaletteFX or type(PaletteFX.effectiveColors) ~= "function") then
      return SHADE_COLORS
    end

    local mode = isGold and GbcPalette
      and ("gold:" .. tostring(GbcPalette.mode) .. ":" .. tostring(GbcPalette.bgp))
      or (PaletteFX and PaletteFX.mode)
    local shade = not isGold and type(PaletteFX.shadeMap) == "function"
      and PaletteFX.shadeMap() or nil
    local record = paletteCache[source]
    local unchanged = record and record.mode == mode and record.shade == shade
    if unchanged then
      for index = 1, 4 do
        local color = source[index]
        if type(color) ~= "table" then
          unchanged = false
          break
        end
        for channel = 1, 3 do
          local offset = (index - 1) * 3 + channel
          if record.sourceValues[offset] ~= tonumber(color[channel]) then
            unchanged = false
            break
          end
        end
        if not unchanged then break end
      end
    end
    if unchanged and shade then
      for index = 0, 3 do
        if record.shadeValues[index + 1] ~= shade[index] then
          unchanged = false
          break
        end
      end
    end
    if unchanged then return record.colors end

    local success, effective
    if isGold then
      if GbcPalette and type(GbcPalette.resolve) == "function" then
        success, effective = pcall(function()
          local resolved = GbcPalette.resolve(source)
          if type(GbcPalette.remap) == "function" then
            resolved = GbcPalette.remap(resolved, GbcPalette.bgp)
          end
          return resolved
        end)
      else
        success, effective = true, source
      end
    else
      success, effective = pcall(PaletteFX.effectiveColors, source)
    end
    if not success or type(effective) ~= "table" then return SHADE_COLORS end
    local colors = {}
    local sourceValues = {}
    for i = 1, 4 do
      local color = effective[i]
      if type(color) ~= "table" then return SHADE_COLORS end
      colors[tostring(i - 1)] = {
        (tonumber(color[1]) or 0) / 255,
        (tonumber(color[2]) or 0) / 255,
        (tonumber(color[3]) or 0) / 255,
        1,
      }
      local original = source[i]
      for channel = 1, 3 do
        sourceValues[(i - 1) * 3 + channel] =
          type(original) == "table" and tonumber(original[channel]) or nil
      end
    end
    colors["."] = colors["0"]
    colors["+"] = colors["0"]
    colors["~"] = colors["1"]
    colors[" "] = colors["3"]
    colors.panel = colors["3"]
    colors.border = colors["0"]
    local shadeValues = {}
    if shade then
      for index = 0, 3 do shadeValues[index + 1] = shade[index] end
    end
    paletteCache[source] = {
      mode = mode, shade = shade, sourceValues = sourceValues,
      shadeValues = shadeValues, colors = colors,
    }
    return colors
  end

  local function colorFor(value, colors)
    return colors[value] or colors[" "]
  end

  -- Compile each immutable overview row into flat run-length triples once.
  -- Camera movement then clips those runs instead of allocating one-character
  -- substrings for every visible cell on every rendered frame.
  local function compiledRows(rows, width, height)
    local record = rowRunCache[rows]
    if record and record.width == width and record.height == height then
      return record
    end
    record = { width = width, height = height, runs = {} }
    rowRunCache[rows] = record
    return record
  end

  local function compiledRow(rows, record, y)
    local cachedRuns = record.runs[y]
    if cachedRuns then return cachedRuns end
    local text = tostring(rows[y] or "")
    local runs = {}
    local start = 0
    local current = text:sub(1, 1)
    if current == "" then current = " " end
    for x = 1, record.width do
      local value
      if x < record.width then
        value = text:sub(x + 1, x + 1)
        if value == "" then value = " " end
      end
      if value ~= current then
        runs[#runs + 1] = start
        runs[#runs + 1] = x
        runs[#runs + 1] = current
        start, current = x, value
      end
    end
    record.runs[y] = runs
    return runs
  end

  local function terrainCommands(rows, geo)
    local previous = terrainCommandCache
    if previous and previous.rows == rows
        and previous.sourceWidth == geo.sourceWidth
        and previous.sourceHeight == geo.sourceHeight
        and previous.sourceX == geo.sourceX
        and previous.sourceY == geo.sourceY
        and previous.viewSourceWidth == geo.viewSourceWidth
        and previous.viewSourceHeight == geo.viewSourceHeight
        and previous.mapX == geo.mapX and previous.mapY == geo.mapY
        and previous.scale == geo.scale then
      return previous.commands
    end
    local compiled = compiledRows(rows, geo.sourceWidth, geo.sourceHeight)
    local viewLeft = geo.sourceX
    local viewRight = viewLeft + geo.viewSourceWidth
    local commands = {}
    local function append(value, left, right, rowIndex)
      if right <= left then return end
      commands[#commands + 1] = value
      commands[#commands + 1] = geo.mapX + (left - viewLeft) * geo.scale
      commands[#commands + 1] = geo.mapY + rowIndex * geo.scale
      commands[#commands + 1] = (right - left) * geo.scale
      commands[#commands + 1] = geo.scale
    end
    for rowIndex = 0, geo.viewSourceHeight - 1 do
      local sourceY = geo.sourceY + rowIndex
      if sourceY < 0 or sourceY >= geo.sourceHeight then
        append(" ", viewLeft, viewRight, rowIndex)
      else
        if viewLeft < 0 then
          append(" ", viewLeft, math.min(viewRight, 0), rowIndex)
        end
        local runs = compiledRow(rows, compiled, sourceY + 1)
        for index = 1, #runs, 3 do
          local left, right = runs[index], runs[index + 1]
          if right > viewLeft and left < viewRight then
            append(runs[index + 2], math.max(left, viewLeft),
              math.min(right, viewRight), rowIndex)
          end
          if left >= viewRight then break end
        end
        if viewRight > geo.sourceWidth then
          append(" ", math.max(viewLeft, geo.sourceWidth), viewRight, rowIndex)
        end
      end
    end
    terrainCommandCache = {
      rows = rows, sourceWidth = geo.sourceWidth,
      sourceHeight = geo.sourceHeight, sourceX = geo.sourceX,
      sourceY = geo.sourceY, viewSourceWidth = geo.viewSourceWidth,
      viewSourceHeight = geo.viewSourceHeight, mapX = geo.mapX,
      mapY = geo.mapY, scale = geo.scale, commands = commands,
    }
    return commands
  end

  local function drawRows(g, rows, geo, alpha, colors)
    local commands = terrainCommands(rows, geo)
    for index = 1, #commands, 5 do
      local ink = colorFor(commands[index], colors)
      g.setColor(ink[1], ink[2], ink[3], ink[4] * alpha)
      g.rectangle("fill", commands[index + 1], commands[index + 2],
        commands[index + 3], commands[index + 4])
    end
  end

  local function drawMarkers(g, overview, current, geo, alpha)
    local markerSize = math.max(2, math.floor(math.min(
      geo.cellWidth, geo.cellHeight) * 0.65))
    for _, marker in ipairs(overview.markers or {}) do
      local color = MARKER_COLORS[marker.kind]
      if color and type(marker.x) == "number" and type(marker.y) == "number" then
        local sourceMarkerX = marker.x * (geo.cellWidth / geo.scale)
        local sourceMarkerY = marker.y * (geo.cellHeight / geo.scale)
        local mx = geo.mapX + (sourceMarkerX - geo.sourceX) * geo.scale
          + math.floor((geo.cellWidth - markerSize) / 2)
        local my = geo.mapY + (sourceMarkerY - geo.sourceY) * geo.scale
          + math.floor((geo.cellHeight - markerSize) / 2)
        if mx + markerSize > geo.mapX and mx < geo.mapX + geo.mapWidth
            and my + markerSize > geo.mapY and my < geo.mapY + geo.mapHeight then
          g.setColor(color[1], color[2], color[3], color[4] * alpha)
          g.rectangle("fill", mx, my, markerSize, markerSize)
        end
      end
    end

    if current and type(current.x) == "number" and type(current.y) == "number" then
      local cellSourceWidth = geo.cellWidth / geo.scale
      local cellSourceHeight = geo.cellHeight / geo.scale
      local px = geo.mapX + (geo.currentOffsetX + current.x * cellSourceWidth
        - geo.sourceX) * geo.scale
      local py = geo.mapY + (geo.currentOffsetY + current.y * cellSourceHeight
        - geo.sourceY) * geo.scale
      local pw = math.max(2, math.floor(geo.cellWidth))
      local ph = math.max(2, math.floor(geo.cellHeight))
      if px + pw > geo.mapX and px < geo.mapX + geo.mapWidth
          and py + ph > geo.mapY and py < geo.mapY + geo.mapHeight then
        g.setColor(1, 0.93, 0.22, alpha)
        g.rectangle("fill", px, py, pw, ph)
        if g.rectangle then
          g.setColor(0.10, 0.08, 0.02, alpha)
          g.rectangle("line", px + 1, py + 1, math.max(1, pw - 2),
            math.max(1, ph - 2))
        end
      end
    end
  end

  -- Encounter data identifies a habitat at map level rather than at an
  -- individual tile.  Tint only the connected map rectangles that contain
  -- the tracked species, preserving the terrain details underneath.
  local function drawTrackedRegions(g, overview, geo, alpha, colors)
    local locations = overview and overview.trackingMaps
    local regions = overview and overview.regions
    if type(locations) ~= "table" or type(regions) ~= "table" then return end
    -- Gold makes the tracked habitat unambiguous against both pale and dark
    -- palette schemes; it is intentionally separate from the terrain ink.
    for _, region in ipairs(regions) do
      if locations[region.mapId] then
        local usesTiles = overview.tileRows ~= nil
        local rx = usesTiles and region.tileX or region.x
        local ry = usesTiles and region.tileY or region.y
        local rw = usesTiles and region.tileWidth or region.width
        local rh = usesTiles and region.tileHeight or region.height
        if type(rx) == "number" and type(ry) == "number"
            and type(rw) == "number" and type(rh) == "number" then
          local left = math.max(geo.mapX,
            geo.mapX + (rx - geo.sourceX) * geo.scale)
          local top = math.max(geo.mapY,
            geo.mapY + (ry - geo.sourceY) * geo.scale)
          local right = math.min(geo.mapX + geo.mapWidth,
            geo.mapX + (rx + rw - geo.sourceX) * geo.scale)
          local bottom = math.min(geo.mapY + geo.mapHeight,
            geo.mapY + (ry + rh - geo.sourceY) * geo.scale)
          if right > left and bottom > top then
            g.setColor(TRACKING_FILL[1], TRACKING_FILL[2],
              TRACKING_FILL[3], 0.46 * alpha)
            g.rectangle("fill", left, top, right - left, bottom - top)
            g.setColor(0.12, 0.08, 0.02, 0.90 * alpha)
            g.rectangle("line", left + 0.5, top + 0.5,
              math.max(1, right - left - 1), math.max(1, bottom - top - 1))
          end
        end
      end
    end
  end

  local function drawTrackingHint(g, overview, geo, alpha, colors)
    local name = overview and overview.trackingName
    if not name or name == "" then return end
    if not Font or type(Font.draw) ~= "function" then return end
    local text = "Tracking " .. tostring(name)
    local textWidth = type(Font.width) == "function" and Font.width(text)
      or (#text * 8)
    -- The normal Game Boy font is small at window scale.  Enlarge the hint
    -- on desktop-sized minimaps, while shrinking only when the native-size
    -- fallback cannot fit the complete label.
    local textScale = math.min(1.5,
      math.max(1, (geo.mapWidth - 8) / math.max(1, textWidth)))
    local boxWidth = math.min(geo.mapWidth,
      math.ceil(textWidth * textScale + 8))
    local boxHeight = math.min(geo.mapHeight,
      math.ceil(8 * textScale + 6))
    local boxX = geo.mapX + math.floor((geo.mapWidth - boxWidth) / 2)
    local boxY = geo.mapY + 2
    -- Font tile sheets contain dark ink, so a bright opaque badge gives the
    -- label reliable contrast even when the active map palette is pale.
    g.setColor(HINT_PANEL[1], HINT_PANEL[2], HINT_PANEL[3], 0.98 * alpha)
    g.rectangle("fill", boxX, boxY, boxWidth, boxHeight)
    g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], alpha)
    -- At the native 160px layout the longest Gen 1 name can be wider than
    -- the compact panel.  The screen-space minimap is normally larger, but
    -- clipping keeps the hint inside the widget on that smallest fallback.
    if g.setScissor then g.setScissor(boxX, boxY, boxWidth, boxHeight) end
    local textY = boxY + math.max(1,
      math.floor((boxHeight - 8 * textScale) / 2))
    if textScale > 1 and g.push and g.translate and g.scale then
      g.push()
      g.translate(boxX + 4, textY)
      g.scale(textScale, textScale)
      Font.draw(text, 0, 0)
      g.pop()
    else
      Font.draw(text, boxX + 4, textY)
    end
    if g.setScissor then g.setScissor() end
  end

  -- Keep the tracker on the same 8-pixel grid as the native Game Boy UI.
  -- The minimap itself is screen-space, so snapping only this companion
  -- window prevents fractional borders and uneven row spacing without
  -- changing the minimap's size or position.
  local function drawPanel(g, geo, radius, colors, alpha, style)
    local x = math.floor(geo.x)
    local y = math.floor(geo.y)
    local width = math.max(1, math.floor(geo.width))
    local height = math.max(1, math.floor(geo.height))
    local maxRadius = math.min(radius, math.floor(width / 2),
      math.floor(height / 2))

    if style == "off" then
      g.setColor(colors.panel[1], colors.panel[2], colors.panel[3], 0.94 * alpha)
      g.rectangle("fill", x, y, width, height, maxRadius)
      return
    end

    local corner = style == "rounded" and maxRadius or 0
    g.setColor(colors.border[1], colors.border[2], colors.border[3], alpha)
    g.rectangle("fill", x, y, width, height, corner)

    local inset = 1
    g.setColor(colors.panel[1], colors.panel[2], colors.panel[3], 0.94 * alpha)
    g.rectangle("fill", x + inset, y + inset,
      math.max(1, width - inset * 2), math.max(1, height - inset * 2),
      math.max(0, corner - inset))
  end

  local function trackerGeometry(geo, viewport, lineCount, mapCorner,
      trackerCorner, mapEnabled)
    viewport = viewport or {}
    local windowWidth = tonumber(viewport.width)
      or tonumber(viewport.gameWidth) or 160
    local windowHeight = tonumber(viewport.height)
      or tonumber(viewport.gameHeight) or 144
    local contentLines = math.max(1, math.floor(tonumber(lineCount) or 1))
    local tileHeight = contentLines + 2
    -- Keep the tracker the exact width of the minimap.  Its text uses native
    -- tile columns, but snapping the outer window to those columns made the
    -- tracker drift left or shrink by a few pixels whenever the minimap was
    -- positioned by a scaled window or Android surface.
    local width = math.max(NATIVE_TILE * 3, math.floor(geo.width))
    local height = tileHeight * NATIVE_TILE
    local x
    local y
    if overlayLayout and type(overlayLayout.positions) == "function" then
      local panels = {}
      if mapEnabled then
        panels[#panels + 1] = {
          id = "minimap", corner = corner(mapCorner), width = geo.width,
          height = geo.height, order = 1,
        }
      end
      panels[#panels + 1] = {
        id = "tracker", corner = corner(trackerCorner), width = width,
        height = height, order = 2,
      }
      panels = overlayLayout.positions(viewport, panels)
      local panel = panels.tracker
      if panel then x, y = panel.x, panel.y end
    end
    if not x then
      local selectedCorner = corner(trackerCorner)
      local left = selectedCorner == "top-left"
        or selectedCorner == "bottom-left"
      local top = selectedCorner == "top-left"
        or selectedCorner == "top-right"
      x = left and MARGIN or windowWidth - width - MARGIN
      local rawY
      if selectedCorner == corner(mapCorner) then
        rawY = top and geo.y + geo.height + 4 or geo.y - height - 4
      else
        rawY = top and MARGIN or windowHeight - height - MARGIN
      end
      x = clamp(math.floor(x), 0, math.max(0, windowWidth - width))
      y = clamp(math.floor(rawY / NATIVE_TILE) * NATIVE_TILE,
        0, math.max(0, windowHeight - height))
    end
    return {
      x = x, y = y, width = width, height = height,
      rowHeight = TRACKER_ROW_HEIGHT,
      contentX = x + NATIVE_TILE,
      contentY = y + NATIVE_TILE,
      contentWidth = math.max(NATIVE_TILE, width - NATIVE_TILE * 2),
    }
  end

  local function trackerDisplayKey(display)
    local value, bit = 0, 1
    for _, key in ipairs(TRACKER_DISPLAY_KEYS) do
      if not display or display[key] ~= false then value = value + bit end
      bit = bit * 2
    end
    return value
  end

  local function encounterLines(model, maxChars, maxLines)
    local display, displayKey
    if type(encounterTracker.displayState) == "function" then
      display, displayKey = encounterTracker.displayState()
    else
      display = encounterTracker.displayOptions
        and encounterTracker.displayOptions() or nil
      displayKey = trackerDisplayKey(display)
    end
    if trackerLineCache and trackerLineCache.model == model
        and trackerLineCache.maxChars == maxChars
        and trackerLineCache.maxLines == maxLines
        and trackerLineCache.displayKey == displayKey then
      return trackerLineCache.lines
    end
    local lines = encounterTracker.format(model, maxChars, maxLines, display)
    trackerLineCache = {
      model = model, maxChars = maxChars, maxLines = maxLines,
      displayKey = displayKey, lines = lines,
    }
    return lines
  end

  local function drawNativeTrackerBox(g, geo, alpha)
    local border = Font and Font.BORDER
    if not (Font and type(Font.drawCode) == "function"
        and type(border) == "table") then
      drawPanel(g, geo, 0, { panel = HINT_PANEL, border = DARK_INK }, alpha,
        "square")
      return
    end

    local tx = geo.x
    local ty = geo.y
    local right = tx + geo.width - NATIVE_TILE
    local bottom = ty + geo.height - NATIVE_TILE
    local columns = math.max(0, math.floor(geo.width / NATIVE_TILE) - 2)
    local rows = math.max(0, math.floor(geo.height / NATIVE_TILE) - 2)
    g.setColor(HINT_PANEL[1], HINT_PANEL[2], HINT_PANEL[3], 0.98 * alpha)
    g.rectangle("fill", tx, ty, geo.width, geo.height)
    g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], alpha)
    Font.drawCode(border.tl, tx, ty)
    Font.drawCode(border.tr, right, ty)
    Font.drawCode(border.bl, tx, bottom)
    Font.drawCode(border.br, right, bottom)
    for index = 1, columns do
      local x = tx + index * NATIVE_TILE
      Font.drawCode(border.h, x, ty)
      Font.drawCode(border.h, x, bottom)
    end
    -- The tracker keeps the minimap's exact pixel width for scaled Android
    -- surfaces, so its right edge is not always an exact multiple of the
    -- native 8px tile.  Add one final horizontal glyph anchored to the right
    -- corner whenever the regular tile loop would leave a fractional gap.
    local finalX = right - NATIVE_TILE
    local loopEnd = tx + columns * NATIVE_TILE
    if finalX >= tx + NATIVE_TILE and finalX ~= loopEnd then
      Font.drawCode(border.h, finalX, ty)
      Font.drawCode(border.h, finalX, bottom)
    end
    for index = 1, rows do
      local y = ty + index * NATIVE_TILE
      Font.drawCode(border.v, tx, y)
      Font.drawCode(border.v, right, y)
    end
  end

  local function drawEncounterTracker(g, overview, geo, viewport, alpha,
      selectedCorner, selectedTrackerCorner, mapEnabled)
    if not (encounterTracker and overview and overview.encounterData) then
      return
    end
    local tileWidth = math.max(3, math.floor(geo.width / NATIVE_TILE))
    local maxChars = math.max(12, tileWidth - 2)
    local windowHeight = tonumber(viewport and viewport.height)
      or tonumber(viewport and viewport.gameHeight) or 144
    local available = windowHeight - MARGIN * 2 - 4
    if mapEnabled then available = available - geo.height end
    local maxLines = math.max(3, math.min(16,
      math.floor((available - NATIVE_TILE * 2) / TRACKER_ROW_HEIGHT)))
    local lines = encounterLines(overview.encounterData, maxChars, maxLines)
    local tgeo = trackerGeometry(geo, viewport, #lines, selectedCorner,
      selectedTrackerCorner, mapEnabled)
    if overlayLayout and type(overlayLayout.rememberTracker) == "function" then
      overlayLayout.rememberTracker(tgeo, viewport, selectedTrackerCorner)
    end
    drawNativeTrackerBox(g, tgeo, alpha)

    if not Font or type(Font.draw) ~= "function" then return end
    if g.setScissor then g.setScissor(tgeo.contentX, tgeo.contentY,
      tgeo.contentWidth, math.max(1, tgeo.height - NATIVE_TILE * 2)) end
    for index, line in ipairs(lines) do
      local y = tgeo.contentY + (index - 1) * tgeo.rowHeight
      if line.tracked then
        local width = type(Font.width) == "function" and Font.width(line.text)
          or (#line.text * NATIVE_TILE)
        g.setColor(TRACKING_FILL[1], TRACKING_FILL[2], TRACKING_FILL[3],
          0.85 * alpha)
        g.rectangle("fill", tgeo.contentX, y,
          math.min(tgeo.contentWidth, width), tgeo.rowHeight)
      end
      g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], alpha)
      Font.draw(line.text, tgeo.contentX, y)
    end
    if g.setScissor then g.setScissor() end
  end

  local function drawMap(overview, current, viewport)
    local g = love and love.graphics
    if not (g and g.rectangle and g.setColor) then return false end
    local rows = overview and (overview.tileRows or overview.rows)
    local mapEnabled = runtimeEnabled
    local trackerIsEnabled = trackerEnabled()
    local selectedCorner = corner(runtimeSettings.corner)
    local selectedTrackerCorner = corner(runtimeSettings.trackerCorner)
    local selectedBorder = borderStyle(runtimeSettings.border)
    local sizeValue = sizePercent(runtimeSettings.size)
    local zoomValue = zoomPercent(runtimeSettings.zoom)
    local viewportWidth = finite(viewport and (viewport.width
      or viewport.gameWidth), 160)
    local viewportHeight = finite(viewport and (viewport.height
      or viewport.gameHeight), 144)
    local currentX = current and finite(current.x)
    local currentY = current and finite(current.y)
    local previous = drawGeometryCache
    local geo
    if previous and previous.overview == overview
        and previous.viewportWidth == viewportWidth
        and previous.viewportHeight == viewportHeight
        and previous.currentX == currentX and previous.currentY == currentY
        and previous.corner == selectedCorner
        and previous.size == sizeValue and previous.zoom == zoomValue then
      geo = previous.geometry
    else
      geo = geometry(overview, viewport, current, selectedCorner, sizeValue,
        zoomValue)
      drawGeometryCache = {
        overview = overview, viewportWidth = viewportWidth,
        viewportHeight = viewportHeight, currentX = currentX,
        currentY = currentY, corner = selectedCorner,
        size = sizeValue, zoom = zoomValue, geometry = geo,
      }
    end
    if not (rows and geo) then return false end
    local alpha = overlayOpacity(mapEnabled, runtimeSettings.transparency)
    local colors = colorsFor(overview)

    local oldR, oldG, oldB, oldA = 1, 1, 1, 1
    if g.getColor then oldR, oldG, oldB, oldA = g.getColor() end
    if g.push then g.push("all") end

    local radius = math.min(14, math.floor(FRAME * 1.5))
    if mapEnabled then
      drawPanel(g, geo, radius, colors, alpha, selectedBorder)
      drawRows(g, rows, geo, alpha, colors)
      drawTrackedRegions(g, overview, geo, alpha, colors)
      drawMarkers(g, overview, current, geo, alpha)
      drawTrackingHint(g, overview, geo, alpha, colors)
    end
    if trackerIsEnabled then
      drawEncounterTracker(g, overview, geo, viewport, alpha, selectedCorner,
        selectedTrackerCorner, mapEnabled)
    end

    if g.pop then g.pop() end
    g.setColor(oldR, oldG, oldB, oldA)
    return true
  end

  -- Keep Tracking useful with an older engine build that has not yet exposed
  -- WorldAPI:speciesLocations.  The encounter table is read-only content
  -- data, so this fallback does not couple the minimap to world internals.
  local function encounterLocations(game, species)
    local locations = {}
    local data = game and game.data or {}
    local encounters = data.encounters or data.gen2Encounters or {}
    local function containsSpecies(value, depth)
      if depth > 5 or type(value) ~= "table" then return false end
      if value.species == species then return true end
      for _, child in pairs(value) do
        if type(child) == "table" and containsSpecies(child, depth + 1) then
          return true
        end
      end
      return false
    end

    local function mark(mapId, record)
      if mapId ~= nil and containsSpecies(record, 0) then
        locations[mapId] = true
      end
    end

    if isGold then
      -- Gold stores direct map tables for walking/surfing/swarms, but keeps
      -- fishing and tree methods behind group ids. Resolve those ids back to
      -- map ids so every habitat type can highlight a real minimap region.
      for _, key in ipairs({
        "grass", "water", "surf", "swarmGrass", "swarmWater",
      }) do
        for mapId, record in pairs(type(encounters[key]) == "table"
            and encounters[key] or {}) do
          mark(mapId, record)
        end
      end

      local treeSets = type(encounters.treeSets) == "table"
        and encounters.treeSets or {}
      for _, key in ipairs({ "trees", "rocks" }) do
        for mapId, setId in pairs(type(encounters[key]) == "table"
            and encounters[key] or {}) do
          local record = type(setId) == "table" and setId or treeSets[setId]
          mark(mapId, record)
        end
      end

      local fishGroups = type(encounters.fishGroups) == "table"
        and encounters.fishGroups or {}
      local maps = type(data.maps) == "table" and data.maps
        or type(data.gen2Maps) == "table" and data.gen2Maps or {}
      for mapId, def in pairs(maps) do
        if type(def) == "table" then
          local groupId = def.fishGroup or def.fishingGroup
          if groupId then
            mark(mapId, fishGroups[groupId])
            if type(groupId) == "string" then
              mark(mapId, fishGroups[groupId .. "_SWARM"])
            end
          end
        end
      end

      if containsSpecies(encounters.bugContest, 0) then
        locations.NATIONAL_PARK = true
      end
      local save = game and type(game.save) == "table" and game.save or {}
      for _, roamer in ipairs(type(save.roamers) == "table"
          and save.roamers or {}) do
        if roamer and roamer.species == species and roamer.map then
          locations[roamer.map] = true
        end
      end
    else
      -- Gen 1 keeps its land and water tables directly under each map id.
      for mapId, record in pairs(encounters) do mark(mapId, record) end

      local field = type(data.field) == "table" and data.field or {}
      local superRod = type(field.superRod) == "table" and field.superRod or {}
      for mapId, record in pairs(superRod) do mark(mapId, record) end

      -- OLD/GOOD ROD pools are global. Mark maps that carry a water table or
      -- a map-specific SUPER ROD pool; those are the cache's fishable maps.
      local fishing = type(field.fishing) == "table" and field.fishing or {}
      local globalFish = containsSpecies(fishing.OLD_ROD, 0)
        or containsSpecies(fishing.GOOD_ROD, 0)
      if globalFish then
        for mapId, record in pairs(encounters) do
          if type(record) == "table" and (record.water or superRod[mapId]) then
            locations[mapId] = true
          end
        end
      end
    end
    return locations
  end

  -- Gold does not expose Gen 1's WorldAPI:mapOverview.  Build the same
  -- read-only collision view from the native Gen 2 map objects instead, and
  -- compose the connected maps around the current zone so the camera can
  -- scroll naturally across map edges.
  local function goldOverview(worldApi, current)
    local ow = worldApi and worldApi:overworld()
    local root = ow and ow.map
    if not (root and root.id and ow.maps and ow.tilesets
        and GoldMap and GoldWorld) then return nil end
    local placed = {
      { id = root.id, map = root, x = 0, y = 0 },
    }
    for _, neighbor in ipairs(GoldWorld.computeNeighbors(ow.maps, root.id, 2)) do
      local def = ow.maps[neighbor.id]
      local tileset = def and ow.tilesets[def.tileset]
      if def and tileset then
        placed[#placed + 1] = {
          id = neighbor.id,
          map = GoldMap.new(def, tileset),
          x = math.floor((neighbor.ox or 0) / 16),
          y = math.floor((neighbor.oy or 0) / 16),
        }
      end
    end

    local minX, minY, maxX, maxY
    for _, region in ipairs(placed) do
      local width, height = region.map.widthCells, region.map.heightCells
      minX = minX and math.min(minX, region.x) or region.x
      minY = minY and math.min(minY, region.y) or region.y
      maxX = maxX and math.max(maxX, region.x + width) or region.x + width
      maxY = maxY and math.max(maxY, region.y + height) or region.y + height
    end
    local width, height = maxX - minX, maxY - minY
    local rows = {}
    for y = 1, height do rows[y] = string.rep(" ", width) end
    local markers, regions = {}, {}
    local function paint(region)
      local map = region.map
      local ox, oy = region.x - minX, region.y - minY
      regions[#regions + 1] = {
        mapId = region.id, x = ox, y = oy,
        width = map.widthCells, height = map.heightCells,
      }
      for y = 0, map.heightCells - 1 do
        local row = rows[oy + y + 1]
        local chars = {}
        for x = 0, map.widthCells - 1 do
          chars[x + 1] = map:isWarpTileCell(x, y) and "+"
            or map:isWaterCell(x, y) and "~"
            or map:isGrassCell(x, y) and "+"
            or map:isWalkableCell(x, y) and "." or " "
        end
        local before = row:sub(1, ox)
        local after = row:sub(ox + map.widthCells + 1)
        rows[oy + y + 1] = before .. table.concat(chars) .. after
      end
      for _, warp in ipairs(map.def.warps or {}) do
        markers[#markers + 1] = {
          kind = "warp", x = ox + warp.x, y = oy + warp.y,
        }
      end
    end
    for _, region in ipairs(placed) do paint(region) end

    local colors
    if GoldPalettes and type(GoldPalettes.bgSet) == "function" then
      local set = GoldPalettes.bgSet(ow.palettes, root.def,
        ow.daytime or "DAY")
      colors = set and set[1]
    end
    local rootRegion = regions[1]
    return {
      mapId = root.id, width = width, height = height, rows = rows,
      markers = markers, regions = regions, colors = colors,
      currentOffsetX = rootRegion.x, currentOffsetY = rootRegion.y,
    }
  end

  -- Gen 1's WorldAPI overview intentionally exposes terrain, not renderer
  -- internals. Resolve the same map palette the overworld renderer uses here
  -- so the HUD map follows COLORS (including OG/classic/inverted modes) rather
  -- than falling back to the old green debugging palette.
  local function gen1Colors(game, overworld)
    if isGold or not (PaletteFX and type(PaletteFX.pal) == "function") then
      return nil
    end
    local map = overworld and overworld.map
    local data = game and game.data
    if not (map and data) then return nil end
    local name
    if type(overworld.paletteNameFor) == "function" then
      local okName, value = pcall(overworld.paletteNameFor, overworld, map)
      if okName then name = value end
    end
    if not name and type(map.def) == "table" then
      name = map.def.palette
    end
    if not name then return nil end
    local okPalette, colors = pcall(PaletteFX.pal, data, name)
    return okPalette and colors or nil
  end

  local function trackingLocations(world, game, species)
    if world and type(world.speciesLocations) == "function" then
      local ok, locations = pcall(world.speciesLocations, world, species)
      if ok and type(locations) == "table" and next(locations) ~= nil then
        return locations
      end
    end
    return encounterLocations(game, species)
  end

  local function ensureTrackingRegions(overview, current)
    if type(overview.regions) == "table" and #overview.regions > 0 then return end
    local tiles = overview.tileRows ~= nil
    overview.regions = {
      {
        mapId = current.mapId,
        x = overview.currentOffsetX or 0,
        y = overview.currentOffsetY or 0,
        width = overview.width,
        height = overview.height,
        tileX = overview.currentTileOffsetX or 0,
        tileY = overview.currentTileOffsetY or 0,
        tileWidth = tiles and overview.tileWidth or nil,
        tileHeight = tiles and overview.tileHeight or nil,
      },
    }
  end

  local function freeRoam(game, overworld)
    local stack = game and game.stack
    if not (stack and type(stack.top) == "function") then return true end
    local ok, top = pcall(stack.top, stack)
    if not ok then return false end
    if isGold then return top == nil end
    return top == nil or top == overworld
  end

  local function activeWorld(game)
    local world = mod.world
    if not world then return nil, nil end
    local okOverworld, overworld = pcall(world.overworld, world)
    if not okOverworld then return nil, nil end
    if not overworld then return nil, nil end

    -- render.hud runs after every state has been composed.  Only draw on the
    -- free-roam overworld; drawing over a battle/menu would cover native UI.
    -- Gold keeps game.world alive while every menu and battle is pushed, so
    -- its empty stack -- not the mere presence of the world -- is the free-
    -- roam signal.  Gen 1 puts the overworld itself at the top of the stack.
    if not freeRoam(game, overworld) then return nil, nil end

    local okCurrent, current = pcall(world.current, world)
    if not okCurrent then return nil, nil end
    if not current then return nil, nil end
    local trackingCurrent = tracking
      and (tracking.activeCurrent or tracking.current)
    local trackedSpecies = runtimeEnabled and trackingCurrent
      and trackingCurrent(game) or nil
    local trackerIsEnabled = trackerEnabled()
    local encounterKey
    if trackerIsEnabled and type(encounterTracker.key) == "function" then
      local okKey, value = pcall(encounterTracker.key, game, world, current)
      if okKey then encounterKey = value end
    end
    if cached.dirty or cached.mapId ~= current.mapId
        or cached.trackedSpecies ~= trackedSpecies
        or cached.encounterKey ~= encounterKey
        or cached.trackerEnabled ~= trackerIsEnabled then
      local overview
      if type(world.mapOverview) == "function" then
        local okOverview
        okOverview, overview = pcall(world.mapOverview, world)
        if not okOverview then overview = nil end
      else
        local okOverview
        okOverview, overview = pcall(goldOverview, world, current)
        if not okOverview then overview = nil end
      end
      if not overview then return nil, nil end
      if not overview.colors then
        overview.colors = gen1Colors(game, overworld)
      end
      if trackedSpecies then
        overview.trackingSpecies = trackedSpecies
        local okName, name = pcall(tracking.name, game, trackedSpecies)
        overview.trackingName = okName and name or tostring(trackedSpecies)
        overview.trackingMaps = trackingLocations(world, game, trackedSpecies)
        ensureTrackingRegions(overview, current)
      end
      if trackerIsEnabled and encounterTracker.collect then
        local okCollect, value = pcall(encounterTracker.collect,
          game, world, current)
        if okCollect then overview.encounterData = value end
      end
      cached.mapId = current.mapId
      cached.overview = overview
      cached.trackedSpecies = trackedSpecies
      cached.encounterKey = encounterKey
      cached.trackerEnabled = trackerIsEnabled
      cached.dirty = false
    end
    return cached.overview, current
  end

  local hudUnsubscribe
  local hudHookInstalled = false
  local function drawHud(next, game, viewport)
    if overlayLayout and type(overlayLayout.clearTracker) == "function" then
      overlayLayout.clearTracker()
    end
    local result = next(game, viewport)
    if runtimeEnabled or trackerEnabled() then
      local overview, current = activeWorld(game)
      if overview then drawMap(overview, current, viewport) end
    end
    return result
  end

  syncHudHook = function()
    local requested = runtimeEnabled or trackerEnabled()
    if requested and not hudHookInstalled then
      hudHookInstalled = true
      local unsubscribe = mod.hooks:wrap("render.hud", drawHud, -1000)
      if type(unsubscribe) == "function" then
        hudUnsubscribe = unsubscribe
      end
    elseif not requested and hudHookInstalled and hudUnsubscribe then
      local unsubscribe = hudUnsubscribe
      hudUnsubscribe = nil
      hudHookInstalled = false
      unsubscribe()
      if overlayLayout and type(overlayLayout.clearTracker) == "function" then
        overlayLayout.clearTracker()
      end
    end
  end
  syncHudHook()

  mod.exports = {
    geometry = geometry,
    grid = grid,
    draw = drawMap,
    corner = function(value) return corner(value) end,
    trackerCorner = function(value)
      return corner(value or runtimeSettings.trackerCorner)
    end,
    transparency = transparency,
    overlayOpacity = overlayOpacity,
    size = sizePercent,
    zoom = zoomPercent,
    border = function(value) return borderStyle(value) end,
    colors = function(overview) return colorsFor(overview) end,
    locations = encounterLocations,
    freeRoam = freeRoam,
    hudSubscribed = function() return hudHookInstalled end,
    position = DEFAULT_CORNER,
  }
end
