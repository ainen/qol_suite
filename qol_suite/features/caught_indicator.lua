-- CAUGHT MARKER (Mods menu -> QOL SUITE -> CAUGHT MARKER): a small caught-ball
-- marker in the foe's level row marks a species the player has already
-- registered as owned in the Pokedex. Current engines draw it natively from
-- the player's imported battle-ball sheet; the overlay path remains for
-- older 0.1.x builds and external battle layouts. voxel is the Dramatic Shape
-- family helper (features/voxel_hud.lua).
return function(mod, voxel, compat)
  local GameVersion = require("src.core.GameVersion")
  local PaletteFX = require("src.render.PaletteFX")
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local KEY = "caughtIndicator"
  local GLYPH = 8
  -- Keep the marker's colors stable.  Using the foe's live HP-bar palette
  -- made the caught icon flip green/yellow/red as the enemy took damage.
  -- GREENBAR matches the native full-health marker appearance while
  -- PaletteFX.effectiveColors still applies the player's active color mode.
  local MARKER_PALETTE = "GREENBAR"
  -- The transform creates this transparent 8x8 tile from the player's own
  -- imported battle-ball sheet. The mod ships only that recipe, never the
  -- ROM-derived pixels themselves.
  local BALL_PATH = "save/mod-derived/qol_suite/caught_marker.png"
  local runtimeEnabled = mod.options:get(KEY) == true
  local nativeMarkerSupported = false
  if isGen1 then
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    local method = table.concat({ "caught", "Marker", "Visible" })
    nativeMarkerSupported = ok and type(BattleState[method]) == "function"
  end

  local function enabled()
    return mod.options:get(KEY) == true
  end

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and event.key == KEY then
      runtimeEnabled = event.value == true
    end
  end)

  -- Gold already draws this marker in its native enemy HUD.  The option is
  -- omitted from the Gold schema, so leave that renderer untouched.

  -- Owned = registered in the player's Pokedex.  Trades mark the received
  -- species as owned too, so a traded mon reads as caught like the games do.
  local function caught(battle)
    local mon = battle and battle.enemy and battle.enemy.mon
    local species = mon and mon.species
    local save = battle and battle.game and battle.game.save
    local owned = save and save.pokedex and save.pokedex.owned
    return species ~= nil and owned ~= nil and owned[species] == true
  end

  -- Only while the native foe panel is actually up: the same gates as the
  -- engine's drawHUDs (slide == 0, no trainer avatar, no send-out or
  -- grow-in, no intro ball rows, no faint).
  local function hudVisible(battle)
    local enemy = battle and battle.enemy
    if not enemy then return false end
    if (battle.introSlide or 0) ~= 0 then return false end
    if battle.showEnemyTrainer or battle.enemySendingOut or battle.introBalls
        or enemy.fainted then return false end
    if battle.growInScale and battle:growInScale(enemy) then return false end
    return true
  end

  -- Gold places the caught tile inside the foe's status panel.  The classic
  -- Gen 1 panel has a matching left slot, but WIDE gives the foe panel a
  -- separate level-row slot at the far right.  Keep the WIDE tile clear of
  -- the HP bar below it and the name/level text beside it.
  local function markerAt(battle)
    if not (battle and battle.enemy) then return nil end
    local wide = false
    if type(battle.isWideBattleLayout) == "function" then
      local ok, value = pcall(battle.isWideBattleLayout, battle)
      wide = ok and value == true
    end
    if wide then return 112, 8 end
    return 8, 8
  end

  local function markerPalette(battle)
    local data = battle.game and battle.game.data
    local ok, colors = pcall(PaletteFX.pal, data, MARKER_PALETTE)
    if not ok or not colors then return nil end
    return PaletteFX.effectiveColors(colors) or colors
  end

  local markerImages = {}
  local function markerImage(battle)
    if not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then
      return nil
    end
    local key = MARKER_PALETTE .. ":" .. tostring(PaletteFX.mode)
    if markerImages[key] then return markerImages[key] end
    local colors = markerPalette(battle)
    if not colors then
      colors = PaletteFX.effectiveColors(PaletteFX.GRAYS)
          or PaletteFX.GRAYS
    end
    local okData, imageData = pcall(love.image.newImageData, BALL_PATH)
    if not okData or not imageData then return nil end
    imageData:mapPixel(function(_, _, r, _, _, alpha)
      if alpha == 0 then return r, r, r, alpha end
      local shade = math.floor((1 - r) * 3 + 0.5) + 1
      local color = colors[shade] or colors[1]
      return color[1] / 255, color[2] / 255, color[3] / 255, alpha
    end)
    local okImage, image = pcall(love.graphics.newImage, imageData)
    if not okImage or not image then return nil end
    markerImages[key] = image
    return image
  end

  local function drawMark(battle)
    local asset = markerImage(battle)
    if not asset then return end
    local x, y = markerAt(battle)
    if not x then return end
    local g = love.graphics
    local oldR, oldG, oldB, oldA
    if g.getColor then oldR, oldG, oldB, oldA = g.getColor() end
    local function restoreColor()
      if oldR ~= nil and g.setColor then
        g.setColor(oldR, oldG, oldB, oldA)
      end
    end
    local function draw()
      if voxel then
        local mapped = voxel.mapRect(battle, "enemy", { x, y, GLYPH, GLYPH })
        if mapped then
          local restoreCanvas = voxel.drawChannel(battle)
          if restoreCanvas then
            -- The Gen 2 tile is 8x8 source pixels; the panel it rides is
            -- window-scaled, so the mark scales with it.
            local scale = voxel.drawScale(battle)
            g.setColor(1, 1, 1, 1)
            g.draw(asset, mapped.x, mapped.y, 0, scale, scale)
            restoreCanvas()
            restoreColor()
          end
          return
        end
      end
      g.setColor(1, 1, 1, 1)
      g.draw(asset, x, y)
      restoreColor()
    end
    draw()
  end

  -- The Gen 3-inspired overhaul draws its foe plate directly in window
  -- coordinates after the native battle canvas.  Reuse its screen-space
  -- scale and put the marker in the same reserved left slot as the native
  -- enemy panel, rather than letting the lower-priority native overlay get
  -- covered by the custom plate.
  local function drawExternalMark(battle, game, viewport)
    if not (compat and type(compat.enemyGeometry) == "function") then
      return
    end
    local asset = markerImage(battle)
    if not asset then return end
    local geo = compat.enemyGeometry(viewport, game)
    if not geo then return end
    local g = love and love.graphics
    if not (g and type(g.draw) == "function") then return end
    local oldR, oldG, oldB, oldA
    if type(g.getColor) == "function" then
      oldR, oldG, oldB, oldA = g.getColor()
    end
    g.setColor(1, 1, 1, 1)
    g.draw(asset, geo.x + 8 * geo.scale, geo.y + 8 * geo.scale,
      0, geo.scale, geo.scale)
    if oldR ~= nil then g.setColor(oldR, oldG, oldB, oldA) end
  end

  if isGen1 then
    if nativeMarkerSupported then
      mod.hooks:wrap("battle.caught_marker_visible", function(next, battle)
        if runtimeEnabled then return true end
        return next(battle)
      end)
    else
      mod.hooks:wrap("battle.overlay", function(next, battle)
        local result = next(battle)
        local externalBattle = compat
          and compat.battleUIActive
          and compat.battleUIActive(battle and battle.game, battle)
        if runtimeEnabled and not externalBattle
            and hudVisible(battle) and caught(battle) then
          drawMark(battle)
        end
        return result
      end)
    end

    if compat and type(compat.registerBattleOverlay) == "function" then
      compat.registerBattleOverlay("caughtIndicator", function(
          battle, game, viewport)
        if runtimeEnabled and hudVisible(battle) and caught(battle) then
          drawExternalMark(battle, game, viewport)
        end
      end)
    end
  end

  mod.exports = {
    caught = caught,
    markerAt = markerAt,
    nativeMarkerSupported = nativeMarkerSupported,
  }
end
