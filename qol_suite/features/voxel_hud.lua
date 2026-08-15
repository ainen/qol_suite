-- QoL Suite: keep the suite's battle decorations on the HUD when the
-- Dramatic Shape family of mods is installed. DRAMATIC_SHAPE,
-- DRAMALESS_SHAPE, PotatoVoxel, and BATTLE_ART_VOXEL_FORK replace the
-- battle's world canvas and re-composite
-- the HUD panels into it at window coordinates, so overlay decorations that
-- assume the vanilla 160x144 letterbox frame land in the middle of the box.
-- This module consumes only what those mods already publish -- the finished
-- shot stored on battle.dramaticShapeShot each frame -- and mirrors their
-- snapRects math for the known variants, so the XP bar and caught marker
-- follow the panels to the window edge.  No engine code and no changes to the
-- other mods are involved: a vanilla frame simply yields no mapping and the
-- decorations keep their classic letterbox coordinates.
return function(mod)
  local DRAMATIC = "DRAMATIC_SHAPE"
  local DRAMALESS = "DRAMALESS_SHAPE"
  local FORK = "BATTLE_ART_VOXEL_FORK"
  local POTATO = "potato_voxel"
  local findSettled = false
  local settledBranch

  -- The GB-frame HUD boxes both variants share (their HUD_RECT constants).
  local HUD_RECT = { enemy = { 8, 0, 80, 32 }, player = { 72, 56, 88, 40 } }

  local function shot(battle)
    return battle and battle.dramaticShapeShot
  end

  local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return nil end
    return value
  end

  -- A visible loader registry is an allocation-free live lookup (and keeps
  -- hot-reload/test registries observable). Packaged builds that keep it
  -- private use mod.find exactly once, after a shot proves a producer is
  -- active, then retain the settled variant for subsequent draw calls.
  local function registryBranch(game)
    local exports = game and game.mods and game.mods.exports
    if type(exports) ~= "table" then return nil, false end
    if exports[DRAMATIC] ~= nil or exports[DRAMALESS] ~= nil then
      return "dramaless", true
    end
    if exports[FORK] ~= nil then return "fork", true end
    if exports[POTATO] ~= nil then return "potato", true end
    return nil, true
  end

  local function findBranch()
    if findSettled then return settledBranch end
    findSettled = true
    if type(mod.find) ~= "function" then return nil end
    for _, candidate in ipairs({
      { DRAMATIC, "dramaless" }, { DRAMALESS, "dramaless" },
      { FORK, "fork" }, { POTATO, "potato" },
    }) do
      local ok, handle = pcall(mod.find, candidate[1])
      if ok and handle ~= nil then
        settledBranch = candidate[2]
        break
      end
    end
    return settledBranch
  end

  -- Which known variant produced this frame's shot, or nil for a vanilla
  -- frame.  A disabled or failed fork is naturally absent from both the
  -- loader table and mod.find().  An unrecognized producer (an unknown future
  -- fork keeping the same seam) is treated as the original DRAMALESS_SHAPE
  -- math.
  local function branch(battle)
    if not shot(battle) then return nil end
    local game = battle and battle.game
    local live, hasRegistry = registryBranch(game)
    if hasRegistry then return live or "dramaless" end
    return findBranch() or "dramaless"
  end

  -- HUD pixel scale.  The fork scales the HUD to s-1 by default ("SCALED")
  -- and to s when its HUD SCALE setting is "og" (its compatibility mode for
  -- external XP-bar mods); DRAMALESS_SHAPE always uses s.  The setting is
  -- read from the fork's persisted options, which both its hotkey cycle and
  -- its Mods page write.
  local function hudScale(battle, branchName)
    local s = finite(shot(battle) and shot(battle).scale)
    if not s or s <= 0 then return nil end
    if branchName ~= "fork" then return s end
    local game = battle and battle.game
    local bucket = game and game.save and game.save.options
      and game.save.options.modOptions
    local stored = bucket and bucket[FORK] and bucket[FORK].hudScale
    if stored == "og" then return s end
    return math.max(1, s - 1)
  end

  -- World-canvas origin of each HUD panel for the active variant.  The enemy
  -- panel hugs the window's left edge with a 2px margin in the fork; both
  -- variants pin the player panel to the window's right edge, with the
  -- vertical placement always in the window-fit scale s.
  local function panelOrigin(branchName, sh, hs)
    local pw, ly, scale = finite(sh and sh.pw), finite(sh and sh.ly),
      finite(sh and sh.scale)
    if not (pw and ly and scale) then return nil end
    local player = { pw - 88 * hs, ly + 56 * scale }
    if branchName == "fork" then
      return { enemy = { 2 * hs, ly }, player = player }
    end
    return { enemy = { 0, ly }, player = player }
  end

  -- Map a decoration rect from the vanilla frame into the world canvas the
  -- Dramatic Shape mods composite -- the space the HUD panels actually live
  -- in.  side is "player" or "enemy".  rect is a {x, y, width, height} box in
  -- GB pixels; both the keyed form the suite's geometry returns and the
  -- positional form are accepted.  Returns nil when this frame has no shot.
  local function mapRect(battle, side, rect)
    local branchName = branch(battle)
    if not branchName then return nil end
    local sh = shot(battle)
    local hs = hudScale(battle, branchName)
    if not hs then return nil end
    local rx, ry, rw, rh
    if type(rect) ~= "table" then return nil end
    if rect[1] ~= nil then
      rx, ry, rw, rh = rect[1], rect[2], rect[3], rect[4]
    else
      rx, ry, rw, rh = rect.x, rect.y, rect.width, rect.height
    end
    rx, ry, rw, rh = finite(rx), finite(ry), finite(rw), finite(rh)
    if not (rx and ry and rw and rh) then return nil end
    local box = HUD_RECT[side]
    local origins = panelOrigin(branchName, sh, hs)
    local origin = origins and origins[side]
    if not (box and origin) then return nil end
    return {
      x = origin[1] + (rx - box[1]) * hs,
      y = origin[2] + (ry - box[2]) * hs,
      width = rw * hs,
      height = rh * hs,
    }
  end

  -- The suite's overlay hooks run on the game's UI canvas, whose draw calls
  -- are clipped to the 160x144 letterbox -- exactly where the Dramatic Shape
  -- panels are not.  Decorations must switch into the window-sized world
  -- canvas the mods already painted, with the UI canvas transform reset so
  -- window coordinates stay window coordinates.  Returns a restorer function,
  -- or nil when there is no shot or the canvas API is unavailable.
  local function drawChannel(battle)
    local sh = shot(battle)
    local g = love and love.graphics
    if not (sh and sh.canvas and g and g.setCanvas) then return nil end
    local pushed = g.push and pcall(g.push)
    if not pushed then return nil end
    local ok, previous = pcall(g.getCanvas)
    if not ok then previous = nil end
    local switched = pcall(g.setCanvas, sh.canvas)
    if not switched then
      pcall(g.pop)
      return nil
    end
    if g.origin then pcall(g.origin) end
    return function()
      if previous ~= nil then pcall(g.setCanvas, previous)
      elseif g.setCanvas then pcall(g.setCanvas) end
      pcall(g.pop)
    end
  end

  local function drawScale(battle)
    local branchName = branch(battle)
    if not branchName then return nil end
    return hudScale(battle, branchName)
  end

  mod.exports = {
    shot = shot,
    branch = branch,
    hudScale = hudScale,
    mapRect = mapRect,
    drawChannel = drawChannel,
    drawScale = drawScale,
  }
end
