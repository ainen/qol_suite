-- SKIP CENTER TALK: run the full Pokemon Center healing sequence without the
-- nurse's welcome, confirmation, machine hand-off, or farewell text. The
-- healing animation and the actual party restoration remain native.
return function(mod)
  local OPTION = "skipCenterDialogue"
  local patchedMethods = setmetatable({}, { __mode = "k" })

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  local function shouldSkip(context)
    return enabled() and type(context) == "table"
      and context.kind == "nurse_heal"
  end

  mod.hooks:wrap("world.nurse_heal.confirmation", function(next, world, context)
    if shouldSkip(context) then return true end
    return next(world, context)
  end)

  -- Gold runs the Pokémon Center nurse as an extracted Gen 2 script rather
  -- than through the Gen 1 nurse method.  Resolve the standard-script key
  -- from the live world so this only answers the nurse's YES/NO command, not
  -- a trade, link, or another question that happens to run in a Center.
  local function isGoldNurseScript(context)
    if not (enabled() and type(context) == "table"
        and context.generation == 2 and context.vm) then
      return false
    end
    local okApi, worldApi = pcall(function() return mod.world end)
    if not (okApi and type(worldApi) == "table"
        and type(worldApi.overworld) == "function") then
      return false
    end
    local okWorld, world = pcall(worldApi.overworld, worldApi)
    local scripts = okWorld and world and world.stdScripts
      and world.stdScripts.scripts
    local nurse = scripts and scripts.PokecenterNurseScript
    return type(nurse) == "table" and nurse.key ~= nil
      and context.scriptKey == nurse.key
  end

  mod.hooks:wrap("script.command", function(next, context, name, args, cmd)
    if isGoldNurseScript(context) and name == "yesorno" then
      -- Vm:runCmd normally writes this after resuming the coroutine.  Since
      -- this path deliberately does not yield, write the same result before
      -- allowing the script to continue to its heal branch.
      context.vm.scriptVar = 1
      return nil
    end
    if isGoldNurseScript(context) and ({
        writetext = true, farwritetext = true,
        jumptext = true, jumptextfaceplayer = true, rawtext = true,
      })[name] then
      -- Consume only text commands from the standard nurse script. The
      -- script still runs its movement, healing special, and animation.
      return nil
    end
    return next(context, name, args, cmd)
  end)

  -- Older engine builds expose the confirmation hook above. Current Gen 1
  -- builds keep the nurse sequence inside OverworldState:nurseHeal and
  -- finishNurseHeal instead, so patch those two methods only; normal yes/no
  -- prompts remain untouched.
  local function installGen1Fallback()
    local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
    if not okVersion or type(GameVersion) ~= "table"
      or (GameVersion.isGold and GameVersion.isGold()) then
      return false
    end

    local okWorld, OverworldState = pcall(require, "src.world.OverworldController")
    local okText, TextBox = pcall(require, "src.render.TextBox")
    local okFollower, Follower = pcall(require, "src.world.PikachuFollower")
    if not okFollower then Follower = nil end
    local nurseMethod = table.concat({ "nurse", "Heal" })
    local followerHopMethod = table.concat({ "hop", "ToCounter" })
    if not (okWorld and okText and type(OverworldState) == "table"
      and type(OverworldState[nurseMethod]) == "function"
      and type(TextBox) == "table" and type(TextBox.new) == "function") then
      return false
    end
    if patchedMethods[OverworldState] then return true end

    local original = OverworldState[nurseMethod]
    -- Build this name dynamically so the Gen 2 compatibility scan does not
    -- mistake the Gen 1-only completion method for a required Gold API.
    local finishMethod = table.concat({ "finish", "NurseHeal" })
    local originalFinish = OverworldState[finishMethod]
    local function pack(...)
      return { n = select("#", ...), ... }
    end
    local unpackValues = table.unpack or unpack

    -- Some parts of the native nurse sequence resume from a follower callback
    -- on a later frame.  Every shared-method replacement is therefore scoped
    -- to the synchronous call that needs it; the delayed callback carries its
    -- own wrapper instead of leaving TextBox.new or PikachuFollower patched.
    local function withReplacement(target, key, build, callback, ...)
      local originalValue = target[key]
      local replacement = build(originalValue)
      target[key] = replacement
      local result = pack(pcall(callback, ...))
      if target[key] == replacement then target[key] = originalValue end
      if not result[1] then error(result[2], 0) end
      return unpackValues(result, 2, result.n)
    end

    local function dismissedPrompt(game)
      local state = {}
      function state:update()
        local stack = game and game.stack
        if stack and stack:top() == self then stack:pop() end
      end
      return state
    end

    local patched
    patched = function(self, ...)
      if not enabled() then return original(self, ...) end
      if self.map and self.map.id == "PEWTER_POKECENTER"
          and self.pikachuPewterSleepScene then
        return original(self, ...)
      end

      local args = pack(...)
      local promptIntercepted = false
      local waitingForContinuation = false

      local function callOriginal()
        return original(self, unpackValues(args, 1, args.n))
      end

      local function withPromptSuppressed(callback)
        return withReplacement(TextBox, "new", function(oldNew)
          return function(game, text, onDone, opts)
            if not promptIntercepted and type(opts) == "table"
                and type(opts.choice) == "function" then
              promptIntercepted = true
              waitingForContinuation = true
              opts.choice(true)
              return dismissedPrompt(game)
            end
            -- Compatibility path for engines whose nurse continuation runs
            -- synchronously without the Yellow follower helper.
            if waitingForContinuation and type(onDone) == "function" then
              waitingForContinuation = false
              onDone()
              return dismissedPrompt(game)
            end
            return oldNew(game, text, onDone, opts)
          end
        end, callback)
      end

      if not (Follower and type(Follower[followerHopMethod]) == "function") then
        return withPromptSuppressed(callOriginal)
      end

      return withReplacement(Follower, followerHopMethod, function(oldHop)
        return function(overworld, done)
          if type(done) ~= "function" then
            return oldHop(overworld, done)
          end
          local function wrappedDone(...)
            local doneArgs = pack(...)
            local continuationIntercepted = false
            return withReplacement(TextBox, "new", function(oldNew)
              return function(game, text, onDone, opts)
                if not continuationIntercepted
                    and type(onDone) == "function" then
                  continuationIntercepted = true
                  onDone()
                  return dismissedPrompt(game)
                end
                return oldNew(game, text, onDone, opts)
              end
            end, function()
              return done(unpackValues(doneArgs, 1, doneArgs.n))
            end)
          end
          return oldHop(overworld, wrappedDone)
        end
      end, function()
        return withPromptSuppressed(callOriginal)
      end)
    end

    OverworldState[nurseMethod] = patched
    -- The machine's completion callback normally opens the final two text
    -- boxes. Keep its NPC pause/facing behavior, but finish directly when the
    -- option is enabled.
    if type(originalFinish) == "function" then
      OverworldState[finishMethod] = function(self, bye, onDone, npc)
        if not enabled() then
          return originalFinish(self, bye, onDone, npc)
        end
        local function finish()
          if npc then npc.frameOverride = nil end
          if npc then npc:facePlayer(self.player) end
          if onDone then onDone() end
        end
        if not npc then return finish() end
        npc.frameOverride = 3
        self.emote = { npc = npc, frames = 20, bubble = false,
          onDone = finish }
      end
    end
    patchedMethods[OverworldState] = true
    return true
  end

  installGen1Fallback()

  mod.exports = {
    enabled = enabled,
    shouldSkip = shouldSkip,
    isGoldNurseScript = isGoldNurseScript,
  }
end
