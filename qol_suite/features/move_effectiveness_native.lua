-- TYPE MATCHUP (Mods menu -> Pokemon Move Effectiveness Native -> TYPE MATCHUP):
-- keep the battle move list completely vanilla and show a
-- compact effectiveness label in the existing move-details panel for the
-- currently selected move.
--
-- The classic panel already has a label row above the type and PP rows.  The
-- widescreen panel has a blank middle row between PP and type.  Reusing those
-- rows means the move names, borders, cursor, and menu spacing stay exactly
-- on the engine's native path.
return function(mod, compat)
  local GameVersion = require("src.core.GameVersion")
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local KEY = "effectiveness"
  local runtimeEnabled = mod.options:get(KEY) == true

  local function enabled()
    return mod.options:get(KEY) == true
  end

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and event.key == KEY then
      runtimeEnabled = event.value == true
    end
  end)

  local TypeChart = require("src.battle.TypeChart")
  local GoldDamage = not isGen1 and require("src.battle.gen2.Damage") or nil
  local Font = require("src.render.Font")

  local GLYPH = 8
  local fontColorShader
  local statusCache = setmetatable({}, { __mode = "k" })
  local STATUS_TINT = {
    IMMUNE = { 0.6, 0.6, 0.6, 1 },
    SUPER = { 0.15, 0.65, 0.25, 1 },
    WEAK = { 0.75, 0.2, 0.2, 1 },
    NEUTRAL = { 0, 0, 0, 1 },
  }

  local function statusColor(status)
    if status == "IMMUNE" then
      return 0.6, 0.6, 0.6
    elseif status and status:sub(1, 5) == "SUPER" then
      return 0.15, 0.65, 0.25
    elseif status and status:sub(1, 4) == "WEAK" then
      return 0.75, 0.2, 0.2
    end
    return 0, 0, 0
  end

  local function coloredFontShader()
    if fontColorShader or not love.graphics.newShader
        or not love.graphics.setShader then
      return fontColorShader
    end

    local source = [[
      extern vec4 tint;

      vec4 effect(vec4 color, Image texture, vec2 texture_coords,
                  vec2 screen_coords) {
        vec4 pixel = Texel(texture, texture_coords);
        return vec4(tint.rgb, pixel.a * tint.a);
      }
    ]]
    local ok, shader = pcall(love.graphics.newShader, source)
    if ok then fontColorShader = shader end
    return fontColorShader
  end

  local function dataMoves(battle)
    local model = battle and battle.battle or battle
    return model and model.data and model.data.moves
  end

  -- Return the chart's scaled multiplier for any non-neutral result.  The
  -- native panel can call an immunity out explicitly, unlike the arrow
  -- variant where an immunity intentionally has no marker.
  local function moveEffectiveness(battle, moveDef)
    if not enabled() then return nil end
    local model = battle and battle.battle or battle
    local enemy = model and model.enemy
    if not isGen1 then
      local types = model and model.speciesDef and model:speciesDef(enemy)
        or {}
      local defenderTypes = (types and types.types) or (enemy and enemy.types)
      if not (moveDef and moveDef.type and defenderTypes and GoldDamage) then
        return nil
      end
      local chart = model.data and model.data.type_chart or {}
      local ok, mult = pcall(GoldDamage.typeMultiplier, moveDef.type,
        defenderTypes, chart.matchups)
      return ok and mult ~= 10 and mult or nil
    end
    if not (moveDef and moveDef.type and enemy and enemy.curTypes) then
      return nil
    end
    local ok, mult = pcall(TypeChart.effectiveness,
      moveDef.type, enemy.curTypes)
    if ok and (mult == 0 or mult ~= 10) then return mult end
    return nil
  end

  local function effectivenessLabel(mult)
    if mult == nil then return nil end
    if mult == 0 then return "IMMUNE" end
    if mult > 10 then
      return mult >= 40 and "SUPER x4" or "SUPER"
    end
    return mult <= 2 and "WEAK x4" or "WEAK"
  end

  local function selectedMove(battle)
    local model = battle and battle.battle or battle
    local player = model and model.player
    local moves = isGen1 and player and player.curMoves
      or player and player.moves
    if not moves or #moves == 0 then return nil, nil end
    local index = tonumber(battle.moveIndex) or 1
    if index ~= index or index == math.huge or index == -math.huge then
      index = 1
    end
    index = math.max(1, math.min(#moves, math.floor(index)))
    local move = moves[index]
    local defs = dataMoves(battle)
    return move, defs and move and defs[move.id]
  end

  local function defenderTypes(battle)
    local model = battle and battle.battle or battle
    local enemy = model and model.enemy
    local types
    if isGen1 then
      types = enemy and enemy.curTypes
    elseif model and model.speciesDef then
      local definition = model:speciesDef(enemy)
      types = definition and definition.types or enemy and enemy.types
    else
      types = enemy and enemy.types
    end
    return enemy, types and types[1], types and types[2]
  end

  local function selectedStatus(battle)
    local move, def = selectedMove(battle)
    local enemy, type1, type2 = defenderTypes(battle)
    local moveType = def and def.type
    local cached = statusCache[battle]
    if cached and cached.move == move and cached.def == def
        and cached.enemy == enemy and cached.type1 == type1
        and cached.type2 == type2 and cached.moveType == moveType then
      return cached.status
    end
    local status = effectivenessLabel(moveEffectiveness(battle, def))
    statusCache[battle] = {
      move = move, def = def, enemy = enemy, type1 = type1, type2 = type2,
      moveType = moveType, status = status,
    }
    return status
  end

  -- Remove the previous tilemap text without introducing an opaque matte.
  -- Background mods can intentionally leave battle paper transparent, so a
  -- white rectangle here would create a visible box around the label.
  local function clearStatusBackground(x, y, width)
    local g = love.graphics
    if not g.clear or not g.setScissor then return end

    local savedScissor
    if g.getScissor then
      local sx, sy, sw, sh = g.getScissor()
      if sx ~= nil then savedScissor = { sx, sy, sw, sh } end
    end

    if g.intersectScissor then
      g.intersectScissor(x, y, width, GLYPH)
    else
      g.setScissor(x, y, width, GLYPH)
    end
    -- Keep the RGB value white for the engine's tile convention, but clear
    -- alpha so the active battle/background surface shows through.
    g.clear(1, 1, 1, 0)

    if savedScissor then
      g.setScissor(savedScissor[1], savedScissor[2],
                   savedScissor[3], savedScissor[4])
    else
      g.setScissor()
    end
  end

  -- The extracted font sheets contain black glyph pixels on transparency, so
  -- a normal setColor only multiplies black by the requested color and still
  -- renders black.  Use the glyph alpha as a mask when shaders are available;
  -- the fallback preserves the old behavior on unsupported renderers.
  local function paintStatus(x, y, width, status)
    local g = love.graphics
    local r, green, b, a = g.getColor()
    clearStatusBackground(x, y, width)
    if status then
      local cr, cg, cb = statusColor(status)
      local shader = coloredFontShader()
      local previousShader = g.getShader and g.getShader() or nil
      if shader then
        local tint = status == "IMMUNE" and STATUS_TINT.IMMUNE
          or status:sub(1, 5) == "SUPER" and STATUS_TINT.SUPER
          or status:sub(1, 4) == "WEAK" and STATUS_TINT.WEAK
          or STATUS_TINT.NEUTRAL
        shader:send("tint", tint)
        g.setColor(1, 1, 1, 1)
        g.setShader(shader)
      else
        g.setColor(cr, cg, cb, 1)
      end
      Font.draw(status, x, y)
      if shader then g.setShader(previousShader) end
    end
    g.setColor(r, green, b, a)
  end

  local function paintClassicStatus(battle)
    local status = selectedStatus(battle)
    if status then
      -- Replace the existing TYPE/ caption; the type and PP remain below it.
      paintStatus(8, 72, 72, status)
    end
  end

  local function paintWideStatus(battle)
    local status = selectedStatus(battle)
    -- This row is blank in the native widescreen details panel.  Always clear
    -- it so a previous selection's longer label cannot linger behind a
    -- neutral move.
    paintStatus(232, 120, 64, status)
  end

  local function paintGoldStatus(state)
    local status = selectedStatus(state)
    -- Gold's four-row move list has no spare details row.  Use the quiet
    -- right-hand end of its top border as the compact status readout, keeping
    -- the native move names and PP columns untouched.
    -- The longest labels ("SUPER x4" and "NOT VERY") are eight glyphs.
    -- Start one tile farther left and reserve the full 64-pixel row so they
    -- cannot be clipped by the 160-pixel Gold viewport.
    paintStatus(96, 96, 64, status)
  end

  -- The Gen 3-inspired overhaul replaces the native move panel after the
  -- battle.overlay hook has run.  Draw the colored label in its open details
  -- row after that renderer instead of allowing the native tile to disappear
  -- underneath the custom panel.
  if compat and type(compat.registerBattleOverlay) == "function" then
    compat.registerBattleOverlay("moveEffectiveness", function(
        battle, game, viewport)
      if not runtimeEnabled then return end
      local phase = battle and battle.phase
      if isGen1 then
        if phase ~= "moveSelect" then return end
      elseif phase ~= "moves" then
        return
      end
      local status = selectedStatus(battle)
      if not status then return end
      local r, green, b = statusColor(status)
      compat.drawEffectiveness(status, viewport, game,
        { r, green, b, 1 })
    end)
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    local res = next(battle)
    if not runtimeEnabled then return res end
    if compat and compat.battleUIActive
        and compat.battleUIActive(battle and battle.game, battle) then
      return res
    end
    if not isGen1 then
      if battle and battle.phase == "moves" then paintGoldStatus(battle) end
      return res
    end
    if not (battle and battle.phase == "moveSelect") then return res end
    if not (battle.player and battle.player.curMoves) then return res end

    if battle.isWideBattleLayout and battle:isWideBattleLayout() then
      paintWideStatus(battle)
    else
      paintClassicStatus(battle)
    end
    return res
  end)

  mod.exports = {
    moveEffectiveness = moveEffectiveness,
    effectivenessLabel = effectivenessLabel,
    statusColor = statusColor,
  }
end
