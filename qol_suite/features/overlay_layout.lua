-- Shared screen-space layout for the QoL Suite HUD panels.
--
-- Keeping these calculations in one small module prevents the minimap,
-- encounter tracker, and party overview from making slightly different
-- assumptions about a window's corners or available space.
return function(mod)
  local DEFAULT_CORNER = "top-right"
  local MARGIN = 12
  local GAP = 4
  local FRAME = 6
  local MIN_PANEL_WIDTH = 144
  local MIN_PANEL_HEIGHT = 108
  local MAX_PANEL_WIDTH = 280
  local MAX_PANEL_HEIGHT = 220
  local BASE_ZOOM = 6
  local TRACKER_MAX_LINES = 16
  local NATIVE_TILE = 8
  local POSITION_CACHE_LIMIT = 6

  local VALID_CORNERS = {
    ["top-left"] = true,
    ["top-right"] = true,
    ["bottom-left"] = true,
    ["bottom-right"] = true,
  }

  local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then
      return fallback
    end
    return value
  end

  local function corner(value)
    return VALID_CORNERS[value] and value or DEFAULT_CORNER
  end

  local function percent(value, fallback)
    return math.max(50, math.min(200, finite(value, fallback)))
  end

  local function viewportSize(viewport)
    viewport = viewport or {}
    local width = finite(viewport.width) or finite(viewport.gameWidth) or 160
    local height = finite(viewport.height)
      or finite(viewport.gameHeight) or 144
    if width <= 0 then width = 160 end
    if height <= 0 then height = 144 end
    return width, height
  end

  -- This mirrors the minimap's visual sizing rules.  It is exposed so the
  -- party overview can reserve exactly the same map footprint before the
  -- minimap itself draws.
  local function minimapDimensions(viewport, sizeValue, zoomValue)
    local windowWidth, windowHeight = viewportSize(viewport)
    local sizeScale = percent(sizeValue, 100) / 100
    local panelWidth = math.max(1, math.min(
      math.floor(MAX_PANEL_WIDTH * sizeScale),
      math.max(math.floor(MIN_PANEL_WIDTH * sizeScale),
        math.floor(windowWidth * 0.30 * sizeScale))))
    local panelHeight = math.max(1, math.min(
      math.floor(MAX_PANEL_HEIGHT * sizeScale),
      math.max(math.floor(MIN_PANEL_HEIGHT * sizeScale),
        math.floor(windowHeight * 0.30 * sizeScale))))
    local scale = BASE_ZOOM * percent(zoomValue, 100) / 100
    local mapWidth = math.max(scale,
      math.floor((panelWidth - FRAME * 2) / scale) * scale)
    local mapHeight = math.max(scale,
      math.floor((panelHeight - FRAME * 2) / scale) * scale)
    return mapWidth + FRAME * 2, mapHeight + FRAME * 2
  end

  local function sortPanels(a, b)
    local ao = tonumber(a.order) or 100
    local bo = tonumber(b.order) or 100
    if ao ~= bo then return ao < bo end
    return tostring(a.id) < tostring(b.id)
  end

  local function buildPositions(windowWidth, windowHeight, panels)
    local groups = {}
    for _, panel in ipairs(panels or {}) do
      if type(panel) == "table" and panel.id then
        local selectedCorner = corner(panel.corner)
        groups[selectedCorner] = groups[selectedCorner] or {}
        groups[selectedCorner][#groups[selectedCorner] + 1] = {
          id = panel.id,
          corner = selectedCorner,
          width = math.max(1, finite(panel.width, 1)),
          height = math.max(1, finite(panel.height, 1)),
          order = panel.order,
        }
      end
    end

    local output = {}
    for selectedCorner, group in pairs(groups) do
      table.sort(group, sortPanels)
      local left = selectedCorner == "top-left"
        or selectedCorner == "bottom-left"
      local top = selectedCorner == "top-left"
        or selectedCorner == "top-right"
      local cursor = top and MARGIN or windowHeight - MARGIN
      for _, panel in ipairs(group) do
        local x = left and MARGIN or windowWidth - panel.width - MARGIN
        local y
        if top then
          y = cursor
          cursor = cursor + panel.height + GAP
        else
          y = cursor - panel.height
          cursor = y - GAP
        end
        output[panel.id] = {
          x = math.max(0, math.min(x, math.max(0, windowWidth - panel.width))),
          y = math.max(0, math.min(y, math.max(0, windowHeight - panel.height))),
          width = panel.width,
          height = panel.height,
          corner = selectedCorner,
        }
      end
    end
    return output
  end

  -- Callers construct short descriptor arrays each frame. Keep a bounded
  -- value-based cache so equivalent arrays reuse the same settled geometry,
  -- while viewport, option, order, or panel-size changes invalidate it. The
  -- integrity check also repairs a result if an outside consumer mutates the
  -- exported table instead of treating it as read-only.
  local positionCache = {}

  local function validPanel(panel)
    return type(panel) == "table" and panel.id ~= nil
  end

  local function cacheMatches(entry, width, height, panels)
    if entry.width ~= width or entry.height ~= height
        or entry.count ~= #(panels or {}) then return false end
    for index = 1, entry.count do
      local panel = panels[index]
      local saved = entry.panels[index]
      if saved.valid ~= validPanel(panel) then return false end
      if saved.valid and (saved.id ~= panel.id
          or saved.corner ~= corner(panel.corner)
          or saved.width ~= math.max(1, finite(panel.width, 1))
          or saved.height ~= math.max(1, finite(panel.height, 1))
          or saved.order ~= panel.order) then
        return false
      end
    end
    return true
  end

  local function outputIntact(entry)
    for _, saved in ipairs(entry.panels) do
      if saved.valid then
        local rect = entry.output[saved.id]
        if not rect or rect.x ~= saved.x or rect.y ~= saved.y
            or rect.width ~= saved.width or rect.height ~= saved.height
            or rect.corner ~= saved.corner then
          return false
        end
      end
    end
    return true
  end

  local function rememberPositions(width, height, panels, output)
    local snapshots, seen = {}, {}
    for index, panel in ipairs(panels or {}) do
      if validPanel(panel) then
        if seen[panel.id] then return end
        seen[panel.id] = true
        local rect = output[panel.id]
        snapshots[index] = {
          valid = true, id = panel.id, corner = corner(panel.corner),
          width = math.max(1, finite(panel.width, 1)),
          height = math.max(1, finite(panel.height, 1)),
          order = panel.order, x = rect.x, y = rect.y,
        }
      else
        snapshots[index] = { valid = false }
      end
    end
    positionCache[#positionCache + 1] = {
      width = width, height = height, count = #(panels or {}),
      panels = snapshots, output = output,
    }
    if #positionCache > POSITION_CACHE_LIMIT then table.remove(positionCache, 1) end
  end

  -- Return one rectangle per panel. Panels sharing a corner are stacked in
  -- order from the edge toward the center. Panels in other corners remain
  -- independently anchored to their own edge.
  local function positions(viewport, panels)
    panels = panels or {}
    local windowWidth, windowHeight = viewportSize(viewport)
    for index = #positionCache, 1, -1 do
      local entry = positionCache[index]
      if cacheMatches(entry, windowWidth, windowHeight, panels) then
        if outputIntact(entry) then return entry.output end
        table.remove(positionCache, index)
      end
    end
    local output = buildPositions(windowWidth, windowHeight, panels)
    rememberPositions(windowWidth, windowHeight, panels, output)
    return output
  end

  local function trackerHeight(lineCount)
    local lines = math.max(1, math.floor(finite(lineCount, 1)))
    return (lines + 2) * NATIVE_TILE
  end

  -- The encounter tracker determines its height from the lines that actually
  -- fit in the current window.  Keep that result here so another overlay can
  -- reserve the same rectangle instead of falling back to the 16-line
  -- maximum.  The viewport and corner are part of the cache key: a resized
  -- window or changed corner must never reuse an old frame's geometry.
  local lastTrackerRect
  local lastTrackerOutput

  local function rememberTracker(rect, viewport, selectedCorner)
    if type(rect) ~= "table" then return end
    local windowWidth, windowHeight = viewportSize(viewport)
    local width = finite(rect.width)
    local height = finite(rect.height)
    if not width or not height or width <= 0 or height <= 0 then return end
    local x, y = finite(rect.x, 0), finite(rect.y, 0)
    local selected = corner(selectedCorner)
    if lastTrackerRect and lastTrackerRect.x == x and lastTrackerRect.y == y
        and lastTrackerRect.width == width
        and lastTrackerRect.height == height
        and lastTrackerRect.viewportWidth == windowWidth
        and lastTrackerRect.viewportHeight == windowHeight
        and lastTrackerRect.corner == selected then
      lastTrackerOutput.x, lastTrackerOutput.y = x, y
      lastTrackerOutput.width, lastTrackerOutput.height = width, height
      lastTrackerOutput.corner = selected
      return
    end
    lastTrackerRect = { x = x, y = y, width = width, height = height,
      viewportWidth = windowWidth, viewportHeight = windowHeight,
      corner = selected }
    lastTrackerOutput = {
      x = x, y = y, width = width, height = height, corner = selected,
    }
  end

  local function trackerRect(viewport, selectedCorner)
    if not lastTrackerRect then return nil end
    local windowWidth, windowHeight = viewportSize(viewport)
    if lastTrackerRect.viewportWidth ~= windowWidth
        or lastTrackerRect.viewportHeight ~= windowHeight
        or lastTrackerRect.corner ~= corner(selectedCorner) then
      return nil
    end
    if not lastTrackerOutput or lastTrackerOutput.x ~= lastTrackerRect.x
        or lastTrackerOutput.y ~= lastTrackerRect.y
        or lastTrackerOutput.width ~= lastTrackerRect.width
        or lastTrackerOutput.height ~= lastTrackerRect.height
        or lastTrackerOutput.corner ~= lastTrackerRect.corner then
      lastTrackerOutput = {
        x = lastTrackerRect.x, y = lastTrackerRect.y,
        width = lastTrackerRect.width, height = lastTrackerRect.height,
        corner = lastTrackerRect.corner,
      }
    end
    return lastTrackerOutput
  end

  local function clearTracker()
    lastTrackerRect = nil
    lastTrackerOutput = nil
  end

  mod.exports = {
    corner = corner,
    margin = MARGIN,
    gap = GAP,
    minimapDimensions = minimapDimensions,
    positions = positions,
    trackerHeight = trackerHeight,
    trackerMaxHeight = trackerHeight(TRACKER_MAX_LINES),
    rememberTracker = rememberTracker,
    trackerRect = trackerRect,
    clearTracker = clearTracker,
    partyWidth = 192,
    partyHeight = 72,
  }
end
