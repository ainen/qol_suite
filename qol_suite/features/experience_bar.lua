-- QoL Suite: show the active Pokemon's progress toward its next level.
-- voxel is the Dramatic Shape family helper (features/voxel_hud.lua) when the
-- package loaded it first; decorations then follow the panels into the world
-- canvas instead of the letterbox frame.
return function(mod, voxel, compat)
  local GameVersion = require("src.core.GameVersion")
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local OPTION = "experienceBar"
  local MAX_LEVEL = 100
  local BLUE = { 40 / 255, 138 / 255, 239 / 255 }
  local progressCache = setmetatable({}, { __mode = "k" })
  local runtimeEnabled = mod.options:get(OPTION) == true

  local Growth = require("src.pokemon.Growth")

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and event.key == OPTION then
      runtimeEnabled = event.value == true
    end
  end)

  -- Gold owns the experience strip in its native battle HUD.  The option is
  -- omitted from the Gold schema, so leave that renderer entirely untouched.

  local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
  end

  local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return nil end
    return value
  end

  local function progress(battle)
    local player = battle and battle.player
    local mon = player and player.mon
    local data = battle and battle.data
    local def = player and player.def
    if not def and data and data.pokemon and mon then
      def = data.pokemon[mon.species]
    end
    if not (mon and def and def.growthRate) then return nil end

    local levelValue = finite(mon.level)
    if not levelValue then return nil end
    local level = math.floor(levelValue)
    local cap = finite(data and data.constants and data.constants.levelCap)
      or MAX_LEVEL
    cap = math.max(1, math.floor(cap))
    if level < 1 or level >= cap then return nil end

    local rates = data and data.growth_rates
    local expValue = finite(mon.exp)
    local exp = math.floor(expValue or 0)
    local cached = progressCache[mon]
    if cached and cached.rate == def.growthRate and cached.level == level
        and cached.cap == cap and cached.rates == rates then
      if cached.exp == exp then return cached.fraction end
      local span = cached.nextLevel - cached.current
      local fraction = clamp((exp - cached.current) / span, 0, 1)
      cached.exp, cached.fraction = exp, fraction
      return fraction
    end

    local okCurrent, current = pcall(Growth.expForLevel,
      def.growthRate, level, rates)
    local okNext, nextLevel = pcall(Growth.expForLevel,
      def.growthRate, level + 1, rates)
    current = okCurrent and finite(current) or nil
    nextLevel = okNext and finite(nextLevel) or nil
    if not current or not nextLevel then return nil end
    local span = nextLevel - current
    if span <= 0 then return nil end

    if expValue == nil then exp = current end
    local fraction = clamp((exp - current) / span, 0, 1)
    progressCache[mon] = {
      rate = def.growthRate, level = level, cap = cap, rates = rates,
      current = current, nextLevel = nextLevel, exp = exp,
      fraction = fraction,
    }
    return fraction
  end

  local function geometry(battle, anchor)
    local wide = battle and battle.isWideBattleLayout
      and battle:isWideBattleLayout()
    if anchor then
      local xOffset = anchor.xpBarOffset
      if xOffset == nil then xOffset = wide and 8 or 0 end
      -- The wide panel is a closed 5-row box (40px tall) whose lower border
      -- edge is at y+40; the classic panel's open chrome strip starts at
      -- y+32.  Movers that relocate the panel update bottomY to its new edge.
      local bottomY = anchor.bottomY
        or (wide and anchor.y + 40 or anchor.y + 32)
      return {
        x = anchor.x + xOffset,
        y = bottomY + 1,
        width = anchor.xpBarWidth or (wide and 96 or 64),
        height = 1,
      }
    end
    if wide then
      return { x = 192, y = 97, width = 96, height = 1 }
    end
    return { x = 80, y = 89, width = 64, height = 1 }
  end

  local function clearBar(rect)
    local g = love.graphics
    if not g.clear or not g.setScissor then return end

    local savedScissor
    if g.getScissor then
      local sx, sy, sw, sh = g.getScissor()
      if sx ~= nil then savedScissor = { sx, sy, sw, sh } end
    end

    if g.intersectScissor then
      g.intersectScissor(rect.x, rect.y, rect.width, rect.height)
    else
      g.setScissor(rect.x, rect.y, rect.width, rect.height)
    end
    -- XP's empty pixels are transparent white, matching the battle tile
    -- convention and allowing custom battle backgrounds to show through.
    g.clear(1, 1, 1, 0)

    if savedScissor then
      g.setScissor(savedScissor[1], savedScissor[2],
                   savedScissor[3], savedScissor[4])
    else
      g.setScissor()
    end
  end

  local function drawBar(battle, rect, fraction, anchor, clearPrevious)
    local g = love.graphics
    local r, g0, b, a = g.getColor()
    if clearPrevious ~= false then clearBar(rect) end

    -- Gold's native bar is a one-pixel colored track with a black outline and
    -- a white empty channel.  Keep the same right-to-left growth and 64-pixel
    -- classic span on Gen 1, while allowing the wide HUD to scale the span.
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", rect.x - 1, rect.y - 1,
      rect.width + 2, rect.height + 2)
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", rect.x, rect.y, rect.width, rect.height)
    if fraction > 0 then
      local width = math.max(1, math.floor(rect.width * fraction))
      g.setColor(BLUE[1], BLUE[2], BLUE[3], 1)
      g.rectangle("fill", rect.x + rect.width - width, rect.y,
        width, rect.height)
    end
    g.setColor(r, g0, b, a)
  end

  local function shakeOffset(battle)
    local fx = battle and battle.fx
    local sx = (fx and fx.shakeX) or 0
    local sy = (fx and fx.shakeY) or 0
    if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
      sx = battle.frame % 4 < 2 and 2 or -2
    end
    return sx, sy
  end

  -- Replay the transform captured inside this frame's player HUD draw so the
  -- bar travels with the panel exactly as drawn.  Scissors are screen-space,
  -- so the transparent clear is clipped to the *transformed* rect, while the
  -- fill is redrawn under the captured transform in the panel's own space.
  -- Falls back to the classic overlay math (live shake offset, no transform)
  -- when the capture is missing or stale -- the panel was hidden this frame,
  -- or the engine predates LOVE transform capture.
  -- The Dramatic Shape family re-composites the HUD panels into a
  -- window-sized world canvas, so the bar rides the player panel there.
  -- The engine forces the classic layout under those mods, so the classic
  -- GB rect is the target; the transparent clear is skipped because the
  -- panel the bar covers is the mods' frosted glass -- erasing it would
  -- punch a hole straight to the arena.  The fill alone repaints the strip
  -- slot like the native bar does.
  local function drawAtOverlay(battle, anchor)
    if voxel then
      local mapped = voxel.mapRect(battle, "player", geometry(battle, nil))
      if mapped then
        local restore = voxel.drawChannel(battle)
        if restore then
          drawBar(battle, mapped, progress(battle), anchor, false)
          restore()
        end
        return
      end
    end
    local rect = geometry(battle, anchor)
    local g = love.graphics
    local t = battle and battle._experienceBarTransform
    if t and battle._experienceBarFrame == battle.frame
        and g.applyTransform and t.transformPoint and t.transformDirection then
      if battle._experienceBarCanvasShake then
        local sx, sy = shakeOffset(battle)
        rect.x, rect.y = rect.x + sx, rect.y + sy
      end
      local rx, ry = t:transformPoint(rect.x, rect.y)
      local rw, rh = t:transformDirection(rect.width, rect.height)
      clearBar({ x = rx, y = ry, width = rw, height = rh })
      g.push()
      g.applyTransform(t)
      drawBar(battle, rect, progress(battle), anchor, false)
      g.pop()
      return
    end
    local sx, sy = shakeOffset(battle)
    rect.x, rect.y = rect.x + sx, rect.y + sy
    drawBar(battle, rect, progress(battle), anchor)
  end

  -- The player HUD hook runs inside the native panel draw, after the panel
  -- has been drawn.  The same mutable anchor lets HUD-moving mods carry this
  -- bar with the panel and keeps it in the lower row below the HP readout.
  -- Keep this link inside HUD-moving wrappers.  A layout mod may translate the
  -- native panel around its `next()` call instead of only changing anchor.x/y;
  -- drawing after that wrapper returns would miss the transform entirely.
  -- The native panel is still drawn first by `next()`, and any anchor mutation
  -- made by an outer wrapper is visible here.
  if isGen1 then
  mod.hooks:wrap("battle.player_hud", function(next, battle, anchor)
    local result = next(battle, anchor)
    -- Transform snapshots can be relatively expensive on mobile renderers.
    -- Do not capture one for a disabled bar or for an external battle UI that
    -- owns its own EXP row and will cover the native panel.
    if not runtimeEnabled then return result end
    if compat and compat.battleUIActive
        and compat.battleUIActive(battle and battle.game, battle) then
      return result
    end
    if battle then
      battle._experienceBarAnchor = anchor
      battle._experienceBarDrawn = false
      local g = love.graphics
      if g and g.getTransform then
        local wide = battle.isWideBattleLayout
          and battle:isWideBattleLayout()
        battle._experienceBarTransform = g.getTransform()
        -- A classic anchor marked "dmg" is the colorized canvas pipeline,
        -- where the engine bakes the HUD onto a canvas and applies the shake
        -- as a canvas draw offset instead of a LOVE transform; "final" (flat),
        -- like wide's "dmg", draws the shake as a live transform instead.
        battle._experienceBarCanvasShake =
          (not wide) and anchor ~= nil and anchor.paletteSpace == "dmg"
        battle._experienceBarFrame = battle.frame
      else
        battle._experienceBarTransform = nil
        battle._experienceBarCanvasShake = false
      end
    end
    local fraction = progress(battle)
    if fraction == nil then return result end
    -- WideBattle draws directly to its final surface, so drawing here keeps
    -- any panel translation/shake applied by another HUD wrapper.  Classic's
    -- colorized HUD is still on its grayscale canvas; draw that one at the
    -- final overlay stage so the blue survives palette remapping.
    local wide = battle and battle.isWideBattleLayout
      and battle:isWideBattleLayout()
    if wide and anchor and anchor.paletteSpace == "final" then
      -- WideBattle repaints its complete surface before drawing the HUD.  Do
      -- not install a screen-space scissor here: an outer HUD mover may have
      -- an active LOVE transform, while scissor coordinates are untransformed.
      drawBar(battle, geometry(battle, anchor), fraction, anchor, false)
      battle._experienceBarDrawn = true
    end
    return result
  end, -1000)

  -- Compatibility path for an older engine that only exposes battle.overlay.
  -- Keep it inside other overlay wrappers for the same reason as the native
  -- HUD hook: a mover may keep its screen transform active around next().
  -- New engines mark the battle when the anchored hook runs, so this never
  -- draws a second bar.
  mod.hooks:wrap("battle.overlay", function(next, battle)
    local result = next(battle)
    if not isGen1 then return result end
    if compat and compat.battleUIActive
        and compat.battleUIActive(battle and battle.game, battle) then
      return result
    end
    if battle and battle._experienceBarDrawn then return result end
    if battle and battle.playerHudVisible == false then return result end
    if not runtimeEnabled then return result end
    local fraction = progress(battle)
    if fraction == nil then return result end
    drawAtOverlay(battle, battle and
      (battle._experienceBarAnchor or battle.playerHudAnchor))
    return result
  end, -1000)
  end

  mod.exports = {
    progress = progress,
    geometry = geometry,
  }
end
