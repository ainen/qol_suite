-- WALL BUMP SOUND: optionally silence the Gen 1 collision cue that plays when
-- the player walks into an impassable tile or entity.  The engine emits the
-- sound after the movement.collision decision, so the hook arms a same-frame
-- filter and sound.played stops only that matching cue.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Game = require("src.core.Game")
  local Sound = require("src.core.Sound")
  local OPTION = "wallCollisionSound"
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local pending = false

  local exports = {}
  function exports.enabled()
    return isGen1 and mod.options:get(OPTION) == true
  end
  function exports.pending()
    return pending
  end
  mod.exports = exports

  -- Gold currently has no movement-path Collision cue; do not install a
  -- visible-but-ineffective listener there.  The option row is Gen 1-only too.
  if not isGen1 then return end

  local function isPlayer(mover)
    local overworld = Game.overworld
    return type(overworld) == "table" and overworld.player == mover
  end

  -- Collision.canMove is also used by helper queries (for example a surf
  -- dismount check), so arm only for the live player and only for a refused
  -- step.  The same frame's OverworldController call then emits Collision.
  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    local result = next(allowed, ctx)
    if not result and type(ctx) == "table" and isPlayer(ctx.mover)
        and not exports.enabled() then
      pending = true
    end
    return result
  end)

  -- Sound.play emits this synchronously after starting the source.  Stopping
  -- the cached Collision source here makes the feature work without changing
  -- the engine's native collision result or affecting other SFX.
  mod.events:on("sound.played", function(event)
    if not pending then return end
    pending = false
    if not exports.enabled() and type(event) == "table"
        and event.kind == "sfx" and event.name == "Collision" then
      Sound.stop("Collision")
    end
  end)

  -- If a collision decision came from a helper path that did not emit a sound,
  -- never let it suppress a later unrelated Collision cue (e.g. an elevator).
  mod.hooks:wrap("core.update", function(next, game, dt)
    pending = false
    return next(game, dt)
  end, 1000)
end
