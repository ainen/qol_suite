-- Compatibility bridge for HighDrexler's Gen 3-inspired UI overhaul.
--
-- That mod intentionally owns presentation and does not expose its renderer as
-- a public API.  It does, however, preserve the engine's battle.overlay and
-- render.hud hook seams.  Run a small post-render bridge at a higher priority
-- so QoL overlays which would otherwise be covered by the overhaul remain
-- visible without taking ownership of the battle UI.
return function(mod)
  local EXTERNAL_ID = "gen3_battle_ui"
  local external = false
  local lookupSettled = false
  local exported
  local removeBattleBridge
  local removeHudBridge

  -- Do not assume the overhaul has already initialized. Mods with the same
  -- priority are ordered by id today, but an install may override priorities
  -- and future loaders are free to discover packages in another order.
  local function installed()
    if external then return true end
    if lookupSettled then return false end
    if type(mod.find) ~= "function" then return false end
    local ok, handle = pcall(mod.find, EXTERNAL_ID)
    external = ok and handle ~= nil
    if external and exported then exported.installed = true end
    return external
  end

  local function retireBridges()
    local battleBridge, hudBridge = removeBattleBridge, removeHudBridge
    removeBattleBridge, removeHudBridge = nil, nil
    if type(battleBridge) == "function" then pcall(battleBridge) end
    if type(hudBridge) == "function" then pcall(hudBridge) end
  end

  local function settleInstalled()
    local value = installed()
    -- The first runtime hook runs only after loader initialization, so an
    -- absent handle is final for this loader instance. Avoid polling the mod
    -- registry or entering hook chains on every HUD frame when the overhaul
    -- is not installed. Calls made during module initialization deliberately
    -- do not settle, leaving a later-loaded optional mod discoverable.
    lookupSettled = true
    if not value then retireBridges() end
    return value
  end
  local Font = require("src.render.Font")

  local defaults = {
    revampedBattleUI = true,
    mobileBattleUI = false,
    iosTopBattleHUD = false,
    uiBoxScale = "normal",
    uiTextSize = "normal",
    uiTextWeight = "normal",
  }

  local callbacks = {}
  local callbackOrder = {}
  local callbackFailures = {}
  local capturedBattle
  local fonts = {}

  local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then
      return fallback
    end
    return value
  end

  local function optionTable(game)
    local save = game and game.save
    local options = save and save.options
    local all = options and options.modOptions
    local values = all and all[EXTERNAL_ID]
    return type(values) == "table" and values or nil
  end

  local function option(game, key)
    local values = optionTable(game)
    if values and values[key] ~= nil then return values[key] end
    return defaults[key]
  end

  local function userBoxScale(game)
    local value = tostring(option(game, "uiBoxScale") or "normal")
    if value == "compact" then return 0.86 end
    if value == "large" then return 1.08 end
    if value == "x-large" then return 1.14 end
    return 1
  end

  local function userTextScale(game)
    local value = tostring(option(game, "uiTextSize") or "normal")
    if value == "small" then return 0.90 end
    if value == "large" then return 1.12 end
    if value == "x-large" then return 1.24 end
    return 1
  end

  local function windowSize(viewport)
    local g = love and love.graphics
    if g and type(g.getDimensions) == "function" then
      local ok, width, height = pcall(g.getDimensions)
      if ok and finite(width) and finite(height)
          and width > 0 and height > 0 then
        return width, height
      end
    end
    viewport = viewport or {}
    return math.max(1, finite(viewport.width
      or viewport.gameWidth, 160)),
      math.max(1, finite(viewport.height
        or viewport.gameHeight, 144))
  end

  local function battleSource(battle)
    if type(battle) ~= "table" then return battle end
    return battle.__gen3Source or battle
  end

  local function battleOwner(battle)
    if type(battle) ~= "table" then return nil end
    return battle.game
      or (battle.battle and battle.battle.game)
      or (battle.__gen3Source and battle.__gen3Source.game)
  end

  local function inStack(game, battle)
    if not (game and game.stack and type(game.stack.states) == "table") then
      return false
    end
    local source = battleSource(battle)
    for _, state in ipairs(game.stack.states) do
      if state == battle or state == source
          or (state and state.battle == battle)
          or (state and state.battle == source) then
        return true
      end
    end
    return false
  end

  local function battleUIActive(game, battle)
    if not installed() then return false end
    if not (option(game, "revampedBattleUI") ~= false) then return false end
    local owner = battleOwner(battle)
    if owner and game and owner ~= game then return false end
    return battle == nil or inStack(game, battle)
  end

  local function hudScale(viewport, game)
    local sw, sh = windowSize(viewport)
    local raw = math.min(sw / 430, sh / 245)
    local scale
    if raw <= 4.5 then
      scale = math.max(1.78, math.min(3.85, raw))
    else
      scale = math.max(3.85, math.min(7.0,
        3.85 + (raw - 4.5) * 0.72))
    end
    return scale * userBoxScale(game)
  end

  local function battleMenuScale(viewport, game)
    local sw, sh = windowSize(viewport)
    local raw = math.min(sw / 1280, sh / 720)
    local scale
    if raw <= 1.5 then
      scale = math.max(0.60, math.min(1.18, raw))
    else
      scale = math.max(1.18, math.min(2.30,
        1.18 + (raw - 1.5) * 0.75))
    end
    if option(game, "mobileBattleUI") == true then
      scale = scale * ((sh > sw) and 0.72 or 0.82)
    end
    return scale * userBoxScale(game)
  end

  local function commandGeometry(viewport, game)
    local sw, sh = windowSize(viewport)
    local u = battleMenuScale(viewport, game)
    local mobile = option(game, "mobileBattleUI") == true
    local portrait = sh > sw
    local width = math.max(mobile and 330 or 390,
      math.min(mobile and 920 or 1380,
        (mobile and (portrait and 500 or 540) or 600) * u))
    local height = math.max(mobile and 118 or 145,
      math.min(mobile and 330 or 485,
        (mobile and (portrait and 175 or 185) or 210) * u))
    local margin = math.max(mobile and 12 or 14,
      math.min(mobile and 34 or 56,
        (mobile and (portrait and 18 or 20) or 24) * u))
    return {
      x = math.max(8, sw - width - margin + 2),
      y = math.max(8, sh - height - margin),
      w = width, h = height, u = u,
    }
  end

  local function enemyGeometry(viewport, game)
    local s = hudScale(viewport, game)
    local margin = 7 * s
    return { x = margin, y = margin, w = 112 * s, h = 35 * s, scale = s }
  end

  local function moveGeometry(viewport, game)
    local sw, sh = windowSize(viewport)
    local u = battleMenuScale(viewport, game)
    local mobile = option(game, "mobileBattleUI") == true
    local portrait = sh > sw
    local width = math.max(mobile and 300 or 400,
      math.min(mobile and 1080 or 1660,
        (mobile and (portrait and 570 or 630) or 756) * u))
    local height = math.max(mobile and 160 or 215,
      math.min(mobile and 455 or 690,
        (mobile and (portrait and 235 or 255) or 300) * u))
    local margin = math.max(mobile and 12 or 14,
      math.min(mobile and 36 or 56,
        (mobile and (portrait and 18 or 20) or 24) * u))
    return {
      x = math.max(8, sw - width - margin + 2),
      y = math.max(8, sh - height - margin),
      w = width, h = height, u = u,
    }
  end

  local function compatFont(size)
    local rounded = math.max(7, math.floor((tonumber(size) or 12) + 0.5))
    if fonts[rounded] then return fonts[rounded] end
    local g = love and love.graphics
    if not (g and type(g.newFont) == "function") then return nil end
    local ok, value = pcall(g.newFont, Font.PLAINPIXEL, rounded,
      "normal")
    if not ok or not value then
      value = type(g.getFont) == "function" and g.getFont() or nil
    end
    if value and value.setFilter then
      pcall(value.setFilter, value, "linear", "linear")
    end
    fonts[rounded] = value
    return value
  end

  local function renderText(g, font, text, x, y, color, align, width)
    g.setFont(font)
    g.setColor((color and color[1]) or 0.1, (color and color[2]) or 0.1,
      (color and color[3]) or 0.1, (color and color[4]) or 1)
    text = tostring(text or "")
    if width and type(g.printf) == "function" then
      g.printf(text, x, y, width, align or "left")
    elseif type(g.print) == "function" then
      g.print(text, x, y)
    end
  end

  local function drawText(text, x, y, size, color, align, width, game)
    local g = love and love.graphics
    if not (g and type(g.setFont) == "function") then return false end
    local font = compatFont((tonumber(size) or 12) * userTextScale(game))
    if not font then return false end
    local oldFont = type(g.getFont) == "function" and g.getFont() or nil
    local oldR, oldG, oldB, oldA
    if type(g.getColor) == "function" then
      oldR, oldG, oldB, oldA = g.getColor()
    end
    local ok = pcall(renderText, g, font, text, x, y, color, align, width)
    if oldFont then pcall(g.setFont, oldFont) end
    if oldR ~= nil then pcall(g.setColor, oldR, oldG, oldB, oldA) end
    return ok
  end

  local function drawEffectiveness(status, viewport, game, color)
    if not status then return false end
    local g = love and love.graphics
    if not (g and type(g.rectangle) == "function") then return false end
    local rect = moveGeometry(viewport, game)
    local u = rect.u or 1
    local pad = 16 * u
    local infoHeight = 50 * u
    local infoY = rect.y + rect.h - pad - infoHeight
    return drawText(status, rect.x + pad, infoY + 10 * u,
      math.max(13, 17 * u), color, "center", rect.w - pad * 2, game)
  end

  local function registerBattleOverlay(name, callback)
    if type(name) ~= "string" or name == ""
        or type(callback) ~= "function" then return false end
    if not callbacks[name] then callbackOrder[#callbackOrder + 1] = name end
    callbacks[name] = callback
    return true
  end

  local function currentBattle(game)
    local battle = capturedBattle
    if not battle then return nil end
    local owner = battleOwner(battle)
    if owner and game and owner ~= game then return nil end
    if not inStack(game, battle) then return nil end
    return battle
  end

  local function reportCallbackFailure(name, err)
    if callbackFailures[name] then return end
    callbackFailures[name] = true
    if mod.log and type(mod.log.warn) == "function" then
      mod.log:warn("Gen 3 UI overlay %s failed: %s", name, tostring(err))
    end
  end

  local function runBattleOverlay(name, callback, battle, game, viewport)
    local g = love and love.graphics
    local pushed = false
    if g and type(g.push) == "function" and type(g.pop) == "function" then
      pushed = pcall(g.push, "all")
    end
    local ok, err = pcall(callback, battle, game, viewport)
    if pushed then
      local restored, restoreErr = pcall(g.pop)
      if not restored then
        reportCallbackFailure(name .. " state restore", restoreErr)
      end
    end
    if not ok then reportCallbackFailure(name, err) end
  end

  -- Register bridges before optional peers have necessarily initialized.
  -- Their first runtime call settles discovery; a native-only process then
  -- retires both wrappers instead of paying a dormant hook cost forever.
  removeBattleBridge = mod.hooks:wrap("battle.overlay", function(next, battle)
    local result = next(battle)
    if settleInstalled() then
      capturedBattle = battle
    end
    return result
  end, 12000)

  removeHudBridge = mod.hooks:wrap("render.hud", function(next, game, viewport)
    local result = next(game, viewport)
    if not lookupSettled then settleInstalled() end
    if battleUIActive(game) then
      local battle = currentBattle(game)
      if battle then
        for _, name in ipairs(callbackOrder) do
          local callback = callbacks[name]
          if callback then
            runBattleOverlay(name, callback, battle, game, viewport)
          end
        end
      end
    end
    return result
  end, 12000)

  exported = {
    installed = external,
    battleUIActive = battleUIActive,
    registerBattleOverlay = registerBattleOverlay,
    currentBattle = currentBattle,
    hudScale = hudScale,
    enemyGeometry = enemyGeometry,
    commandGeometry = commandGeometry,
    moveGeometry = moveGeometry,
    drawText = drawText,
    drawEffectiveness = drawEffectiveness,
    option = option,
  }
  mod.exports = exported
end
