-- AUTO BATTLE: drive the native battle actions with a deterministic move
-- chooser. AUTO CATCH reuses the same turn path and only changes the target
-- selection for wild battles.
return function(mod, catchTarget, compat)
  local GameVersion = require("src.core.GameVersion")
  local TypeChart = require("src.battle.TypeChart")
  local Font = require("src.render.Font")
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local Gen1StatBox
  if isGen1 then
    -- Keep the Gen 1-only class behind the generation branch. Gold has its
    -- own inline stats phase and intentionally exposes no StatBox adapter.
    local legacyBattleStateId = table.concat({ "src", "battle", "BattleState" }, ".")
    local ok, legacyBattleState = pcall(require, legacyBattleStateId)
    if ok then Gen1StatBox = legacyBattleState.StatBox end
  end

  local AUTO_BATTLE = "autoBattle"
  local AUTO_CATCH = "autoCatch"
  local AUTO_CATCH_NEW_ONLY = "autoCatchNewOnly"
  local AUTO_CATCH_BALL = "autoCatchBall"
  local SHOW_BALL_COUNTS = "showBallCounts"
  local AUTO_STOP_SHINY = "autoStopShiny"
  local CATCH_SHINY_ONLY = "catchShinyOnly"
  local AUTO_STOP_LOW_HP = "autoStopLowHp"
  local AUTO_STOP_NO_BALLS = "autoStopNoBalls"
  local AUTO_STOP_TARGET = "autoStopTarget"
  local AUTO_PAUSE_NEW_ENTRY = "autoPauseNewEntry"
  local AUTO_PAUSE_EVOLUTION = "autoPauseEvolution"
  local STATUS_EFFECTS = {
    SLEEP_EFFECT = { rank = 3, status = "SLP" },
    PARALYZE_EFFECT = { rank = 2, status = "PAR" },
    POISON_EFFECT = { rank = 1, status = "PSN" },
  }
  local BALL_ORDER = {
    "MASTER_BALL", "ULTRA_BALL", "GREAT_BALL", "POKE_BALL",
  }
  local BALL_COUNTER_WIDTH = 144
  local BALL_COUNTER_HEIGHT = 40
  local BALL_COUNTER_MARGIN = 4
  local BALL_COUNTER_MAX_SCALE = 3
  local NATIVE_TILE = 8
  local HINT_PANEL = { 0.98, 0.98, 0.94 }
  local DARK_INK = { 0.02, 0.02, 0.02 }
  local ballDisplayCaches = setmetatable({}, { __mode = "k" })
  local fallbackBallDisplayCache = {}

  local function inventoryCount(inventory, id)
    if type(inventory) ~= "table" then return 0 end
    local value = tonumber(inventory[id]) or 0
    if value ~= value or value < 0 or value == math.huge
        or value == -math.huge then return 0 end
    -- Real bags use small byte-sized quantities. Keep a corrupt save from
    -- overflowing string.format while still making the bad value obvious.
    return math.min(999999, math.floor(value))
  end

  local function readBallCounts(game)
    local inventory = game and game.save and game.save.inventory
    return inventoryCount(inventory, "POKE_BALL"),
      inventoryCount(inventory, "GREAT_BALL"),
      inventoryCount(inventory, "ULTRA_BALL"),
      inventoryCount(inventory, "MASTER_BALL"),
      inventoryCount(inventory, "SAFARI_BALL")
  end

  local function ballCounts(game)
    local poke, great, ultra, master, safari = readBallCounts(game)
    local counts = {
      poke = poke, great = great, ultra = ultra,
      master = master, safari = safari,
    }
    counts.total = counts.poke + counts.great + counts.ultra
      + counts.master + counts.safari
    return counts
  end

  local function formatBallCounts(game, counts)
    counts = counts or ballCounts(game)
    return ("P%d G%d U%d M%d"):format(counts.poke, counts.great,
      counts.ultra, counts.master)
  end

  local function formatBallRows(counts)
    counts = counts or {}
    return ("POKE %d GREAT %d"):format(counts.poke or 0, counts.great or 0),
      ("ULTRA %d MASTER %d"):format(counts.ultra or 0, counts.master or 0)
  end

  local function ballDisplay(game)
    local cache
    if type(game) == "table" then
      cache = ballDisplayCaches[game]
      if not cache then
        cache = {}
        ballDisplayCaches[game] = cache
      end
    else
      cache = fallbackBallDisplayCache
    end
    local poke, great, ultra, master, safari = readBallCounts(game)
    if cache.counts and cache.poke == poke and cache.great == great
        and cache.ultra == ultra and cache.master == master
        and cache.safari == safari then
      return cache
    end
    local total = poke + great + ultra + master + safari
    local counts = { poke = poke, great = great, ultra = ultra,
      master = master, safari = safari, total = total }
    cache.poke, cache.great, cache.ultra = poke, great, ultra
    cache.master, cache.safari, cache.counts = master, safari, counts
    cache.title = ("BALLS %d"):format(total)
    cache.firstRow, cache.secondRow = formatBallRows(counts)
    return cache
  end

  local function enabled()
    return mod.options:get(AUTO_BATTLE) == true
  end

  local function catchEnabled()
    return enabled() and mod.options:get(AUTO_CATCH) == true
  end

  local runtimeEnabled = enabled()
  local runtimeCatchEnabled = runtimeEnabled
    and mod.options:get(AUTO_CATCH) == true
  local runtimeShowBallCounts = mod.options:get(SHOW_BALL_COUNTS) == true
  local syncRuntimeHooks

  -- A safety stop hands the current battle back to the player without
  -- changing the saved AUTO BATTLE setting.  Toggling AUTO BATTLE off and on
  -- clears the stop so a player can deliberately resume automation.
  local safetyPause

  local function battleModel(battle)
    return battle and battle.battle or battle
  end

  local function caughtBattle(battle)
    local model = battleModel(battle)
    return model and (model.result == "caught" or model.outcome == "caught")
  end

  local function automationActive(battle, assumedEnabled)
    if (not assumedEnabled and not enabled()) or not battle then return false end
    if not safetyPause then return true end
    -- Finish the native caught-mon flow after STOP ON TARGET fires, but do
    -- not automate another battle until AUTO BATTLE is toggled off/on.
    return safetyPause.reason == "target" and caughtBattle(battle)
  end

  local function pauseAutomation(reason, battle)
    if safetyPause then return end
    safetyPause = { reason = reason, battle = battle }
    if mod.log and type(mod.log.info) == "function" then
      mod.log:info("AUTO BATTLE paused: %s", reason)
    end
  end

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id then
      if event.key == AUTO_BATTLE then
        runtimeEnabled = event.value == true
        runtimeCatchEnabled = runtimeEnabled
          and mod.options:get(AUTO_CATCH) == true
        if runtimeEnabled then safetyPause = nil end
      elseif event.key == AUTO_CATCH then
        runtimeCatchEnabled = runtimeEnabled and event.value == true
      elseif event.key == SHOW_BALL_COUNTS then
        runtimeShowBallCounts = event.value == true
      end
      if syncRuntimeHooks then syncRuntimeHooks() end
    end
  end)

  local function wildBattle(battle)
    local model = battleModel(battle)
    return model and (isGen1 and model.kind == "wild" or model.wild == true)
  end

  local function enemyMon(battle)
    local model = battleModel(battle)
    if not model then return nil end
    return isGen1 and model.enemy and model.enemy.mon or model.enemy
  end

  local function activePlayerMon(battle)
    local model = battleModel(battle)
    if not model then return nil end
    return isGen1 and model.player and model.player.mon or model.player
  end

  local function monMaxHp(mon)
    return mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or 0
  end

  -- Stop only when every non-fainted party member is at or below 25% HP.
  -- Healthy reserves still allow AUTO BATTLE to make its normal switch.
  local function partyNeedsRest(battle, game)
    local model = battleModel(battle)
    local owner = (model and model.game) or game
    local save = owner and owner.save
    local party = save and save.party or (model and model.party)
    if type(party) ~= "table" then
      local mon = activePlayerMon(battle)
      local maxHp = monMaxHp(mon)
      return mon and mon.hp > 0 and maxHp > 0 and mon.hp * 4 <= maxHp
    end
    local living = 0
    for _, mon in ipairs(party) do
      local maxHp = monMaxHp(mon)
      if mon and (mon.hp or 0) > 0 and maxHp > 0 then
        living = living + 1
        if mon.hp * 4 > maxHp then return false end
      end
    end
    return living > 0
  end

  local function safetyOption(key)
    return mod.options:get(key) == true
  end

  local function catchTargetMatches(battle)
    if not catchTarget or type(catchTarget.matches) ~= "function" then
      return true
    end
    local enemy = battle and battle.enemy and battle.enemy.mon
    return enemy and catchTarget.matches(battle.game, enemy.species) or false
  end

  -- "New" means not already registered as caught. RBY stores this in the
  -- owned table; Gold uses the native caught table. A missing/corrupt Dex is
  -- treated as empty so AUTO CATCH does not silently stop catching.
  local function speciesCaught(game, species)
    local dex = game and game.save and game.save.pokedex
    local owned = dex and dex.owned
    local caught = dex and dex.caught
    return (type(owned) == "table" and owned[species] == true)
      or (type(caught) == "table" and caught[species] == true)
  end

  local function catchNewOnlyAllowed(battle, game)
    if mod.options:get(AUTO_CATCH_NEW_ONLY) ~= true then return true end
    local model = battleModel(battle)
    local owner = game or (model and model.game) or (battle and battle.game)
    local enemy = model and model.enemy
    if isGen1 then enemy = enemy and enemy.mon end
    return not (enemy and speciesCaught(owner, enemy.species))
  end

  -- CATCH SHINY ONLY is a Gold-only AUTO CATCH gate. When on, auto-catch only
  -- fires against a shiny wild Pokemon; any non-shiny enemy declines the
  -- catch so the normal auto-battle loop continues. It is the opposite policy
  -- of STOP ON SHINY (which pauses automation on a shiny). In RBY the option
  -- is never registered, so this helper is inert there.
  local function catchShinyOnlyAllowed(battle, state)
    if mod.options:get(CATCH_SHINY_ONLY) ~= true then return true end
    local enemy = battle and battle.enemy
    return not (not enemy or not enemy.shiny)
  end

  -- Gold and Gen 1 both emit this after the caught mon has been stored.  Keep
  -- the target selected for the player's reference, but stop before the next
  -- automated encounter when the target was successfully caught.
  mod.events:on("pokemon.caught", function(event)
    if not (enabled() and mod.options:get(AUTO_CATCH) == true
        and safetyOption(AUTO_STOP_TARGET)) then return end
    local selected = catchTarget and catchTarget.current
      and catchTarget.current(event and event.game)
    if selected and event and event.species == selected then
      pauseAutomation("target", event.battle)
    end
  end)

  local function catchBallMode()
    local mode = mod.options:get(AUTO_CATCH_BALL)
    if mode == "worst" or mode == "poke-ball-only" then return mode end
    return "best"
  end

  local function moveDef(battle, moveInst)
    if not moveInst then return nil end
    if battle and battle.moveDef then return battle:moveDef(moveInst) end
    return battle and battle.data and battle.data.moves
      and battle.data.moves[moveInst.id]
  end

  local function effectRecord(battle, effect)
    if battle and battle.effectRecord then return battle:effectRecord(effect) end
    return nil
  end

  local function statusRank(battle, moveInst)
    local def = moveDef(battle, moveInst)
    if not def then return nil end
    local info = STATUS_EFFECTS[def.effect]
    local record = effectRecord(battle, def.effect)
    if not info or not record or record.kind ~= "primary" then return nil end
    return info.rank, info.status, def
  end

  local function hasType(types, wanted)
    for _, value in ipairs(types or {}) do
      if value == wanted then return true end
    end
    return false
  end

  local function statusCanAffect(battle, target, def, status, types)
    types = types or (target and (target.curTypes or target.types)) or {}
    local moveType = def and def.type
    if status == "PAR" and moveType == "ELECTRIC"
        and hasType(types, "GROUND") then
      return false
    end
    if status == "PSN" and (hasType(types, "POISON")
        or (not isGen1 and hasType(types, "STEEL"))) then
      return false
    end
    if status == "FRZ" and hasType(types, "ICE") then return false end

    -- Gen 1 publishes the same status records used by the actual infliction
    -- path. Honor a patched/custom canInflict rule when this target is the
    -- native battler shape; Gold's raw party-mon target uses the explicit
    -- generation rules above instead.
    local records = battle and battle.data and battle.data.statuses
    local record = target and target.curTypes and records and records[status]
    if record and type(record.canInflict) == "function" then
      local ok, allowed = pcall(record.canInflict, target, {
        moveType = moveType, source = def and def.id,
      })
      if ok and allowed == false then return false end
    end
    return true
  end

  local function usableMoves(battler, battle)
    local moves, all = {}, battler and battler.curMoves or {}
    for index, moveInst in ipairs(all) do
      local def = moveDef(battle, moveInst)
      if def and battler.disabledSlot ~= index and (moveInst.pp or 0) > 0 then
        moves[#moves + 1] = { index = index, move = moveInst, def = def }
      end
    end
    return moves
  end

  local function deterministicDamage(battle, user, target, def)
    if not def or (def.power or 0) <= 0 then
      return 0, 10
    end
    if battle and battle.computeDamage then
      local ok, damage, info = pcall(function()
        return battle:computeDamage(user, target, def, {
          forceCrit = false,
          rng = function() return 255 end,
        })
      end)
      if ok and type(damage) == "number" then
        return damage, (info and info.typeMult) or 10
      end
    end
    local defenderTypes = target and target.curTypes or {}
    local chartOk, mult = pcall(TypeChart.effectiveness, def.type, defenderTypes)
    if not chartOk then mult = 10 end
    local base = math.max(1, tonumber(def.power) or 0)
    return math.floor(base * mult / 10), mult
  end

  local function damageScore(damage, typeMult, def)
    return damage * 10000 + typeMult * 100 + (def.power or 0)
      + (def.accuracy or 100) / 1000
  end

  local function bestDamageMove(battle, user, target, safeOnly)
    local best, bestScore, bestDamage, bestMult
    for _, candidate in ipairs(usableMoves(user, battle)) do
      local damage, typeMult = deterministicDamage(battle, user, target,
                                                     candidate.def)
      if damage > 0 and (not safeOnly or damage < target.mon.hp) then
        local score = damageScore(damage, typeMult, candidate.def)
        if not bestScore or score > bestScore then
          best, bestScore, bestDamage, bestMult = candidate, score, damage, typeMult
        end
      end
    end
    return best, bestDamage or 0, bestMult or 0, bestScore or 0
  end

  local function makeCandidate(battle, mon)
    local def = battle.data and battle.data.pokemon
      and battle.data.pokemon[mon.species]
    if not def or not mon.stats then return nil end
    return {
      mon = mon,
      name = mon.nickname or def.name,
      isPlayer = true,
      curStats = mon.stats,
      curTypes = def.types,
      curMoves = mon.moves or {},
      stages = {},
      statuses = battle.data.statuses,
    }
  end

  local function bestPartySwitch(battle, force)
    local party = battle.game and battle.game.save and battle.game.save.party
    if type(party) ~= "table" then return nil end
    local current = battle.player and battle.player.mon
    local currentMove, currentDamage, currentMult, currentScore
    if not force and battle.player and battle.enemy then
      currentMove, currentDamage, currentMult, currentScore =
        bestDamageMove(battle, battle.player, battle.enemy, false)
    end
    local selected, selectedScore
    for _, mon in ipairs(party) do
      if mon ~= current and (mon.hp or 0) > 0 then
        local candidate = makeCandidate(battle, mon)
        if candidate then
          local move, candidateDamage, candidateMult, score =
            bestDamageMove(battle, candidate, battle.enemy, false)
          if move and (not selectedScore or score > selectedScore) then
            selected, selectedScore = mon, score
          end
        end
      end
    end
    if not selected then return nil end
    if force then return selected end
    -- Switching costs a turn, so do it only for a clear improvement or when
    -- the current mon cannot damage the target at all.
    if not currentMove then return selected end
    if selectedScore > currentScore * 1.25
       or (currentMult == 0 and selectedScore > 0) then
      return selected
    end
    return nil
  end

  local function availableBall(battle)
    local inventory = battle.game and battle.game.save
      and battle.game.save.inventory
    if type(inventory) ~= "table" then return nil end
    local mode = catchBallMode()
    if mode == "poke-ball-only" then
      return (tonumber(inventory.POKE_BALL) or 0) > 0
        and "POKE_BALL" or nil
    end
    local first, last, step = 1, #BALL_ORDER, 1
    if mode == "worst" then first, last, step = #BALL_ORDER, 1, -1 end
    for index = first, last, step do
      local ball = BALL_ORDER[index]
      if (tonumber(inventory[ball]) or 0) > 0 then return ball end
    end
    return nil
  end

  local function bestStatusMove(battle, user, target)
    if target.mon.status then return nil end
    local selected, selectedRank
    for _, candidate in ipairs(usableMoves(user, battle)) do
      local rank, status, def = statusRank(battle, candidate.move)
      if rank and statusCanAffect(battle, target, def, status)
          and (not selectedRank or rank > selectedRank) then
        selected, selectedRank = candidate.move, rank
      end
    end
    return selected
  end

  local function catchAction(battle)
    local enemy = battle.enemy
    if not enemy or not enemy.mon or enemy.mon.hp <= 0 then return nil end
    if not catchNewOnlyAllowed(battle) then return nil end
    local statusMove = bestStatusMove(battle, battle.player, enemy)
    if statusMove then return { kind = "move", move = statusMove } end

    local candidate = bestDamageMove(battle, battle.player, enemy, true)
    if candidate then return { kind = "move", move = candidate.move } end

    local ball = availableBall(battle)
    if ball then return { kind = "ball", ball = ball } end

    local fallback = bestDamageMove(battle, battle.player, enemy, false)
    if fallback then return { kind = "move", move = fallback.move } end
    return { kind = "move", move = { id = "STRUGGLE", pp = 1, struggle = true } }
  end

  local function normalAction(battle)
    local candidate = bestDamageMove(battle, battle.player, battle.enemy, false)
    if candidate then return { kind = "move", move = candidate.move } end
    return { kind = "move", move = { id = "STRUGGLE", pp = 1, struggle = true } }
  end

  local function chooseAction(battle)
    if not automationActive(battle) then return nil end
    if not battle or not battle.player or not battle.enemy then return nil end
    local enemy = enemyMon(battle)
    local player = activePlayerMon(battle)
    if not player or not enemy then return nil end
    if safetyOption(AUTO_STOP_LOW_HP) and partyNeedsRest(battle) then
      pauseAutomation("low HP", battle)
      return nil
    end
    if safetyOption(AUTO_STOP_SHINY) and wildBattle(battle)
        and enemy and enemy.shiny then
      pauseAutomation("shiny", battle)
      return nil
    end
    if (player.hp or 0) <= 0 then
      local replacement = bestPartySwitch(battle, true)
      return replacement and { kind = "switch", mon = replacement } or nil
    end
    if catchEnabled() and catchTargetMatches(battle)
        and catchNewOnlyAllowed(battle)
        and wildBattle(battle) and not battle.safari
       and not battle.noCatch and not battle.ghost then
      if safetyOption(AUTO_STOP_NO_BALLS) and not availableBall(battle) then
        pauseAutomation("no balls", battle)
        return nil
      end
      local action = catchAction(battle)
      if action then return action end
    end
    return normalAction(battle)
  end

  local function stackFor(battle)
    return battle and battle.game and battle.game.stack
  end

  local function stackTop(stack)
    if not (stack and type(stack.top) == "function") then return nil end
    local ok, value = pcall(stack.top, stack)
    return ok and value or nil
  end

  local function stackPop(stack)
    if not (stack and type(stack.pop) == "function") then return false end
    return pcall(stack.pop, stack)
  end

  -- AUTO BATTLE owns every state it causes to be pushed above the battle.
  -- Find the battle under a ChoiceBox/PartyMenu instead of assuming it is
  -- always the stack top.
  local function activeBattle(game)
    local stack = game and game.stack
    if not stack or type(stack.top) ~= "function" then return nil end
    if not isGen1 then
      local top = stackTop(stack)
      if top and top.battle and type(top.submit) == "function" then
        return top
      end
      local states = type(stack.states) == "table" and stack.states or {}
      for index = #states, 1, -1 do
        local state = states[index]
        if state and state.battle and type(state.submit) == "function" then
          return state
        end
      end
      return nil
    end
    local top = stackTop(stack)
    if top and top.isBattle then return top end
    local states = type(stack.states) == "table" and stack.states or {}
    for index = #states, 1, -1 do
      local state = states[index]
      if state and state.isBattle then return state end
      if state and state.battle and state.battle.isBattle then
        return state.battle
      end
    end
    return nil
  end

  local function advanceBattleMessage(battle)
    if not battle or battle.phase ~= "messages" then return false end
    local stack = stackFor(battle)
    if stack and stackTop(stack) ~= battle then return false end

    -- These are the two native battle text waits that normally require A/B.
    -- Keep the engine's three-frame protected delay, then perform exactly the
    -- same state transition that its input branch would perform.
    if battle.msgWaiting and (battle.msgPreWait or 0) <= 0 then
      battle.msgWaiting = nil
      if battle.beginMsgLine then battle:beginMsgLine() end
      battle.waitFrames = 10
      return true
    end
    if battle.msgPrompt and (battle.msgPromptWait or 0) <= 0 then
      battle.msgPrompt = nil
      battle.current = nil
      return true
    end
    return false
  end

  local function advanceBattleChoice(battle)
    local stack = stackFor(battle)
    local top = stackTop(stack)
    if not battle or not top or top == battle then
      return false
    end
    -- SWAP MOVES offers an optional immediate replacement after a level-up.
    -- AUTO BATTLE keeps the new move in the pool and answers NO so the
    -- battle/evolution queue never waits on a human-only choice screen.
    if top._qolSuiteMovePoolPrompt and type(top.choice) == "function" then
      if not stackPop(stack) then return false end
      top.choice(false)
      return true
    end
    if not battle.waitingUI then return false end
    -- BattleState's direct ChoiceBox callbacks are the only choice UI that
    -- can be active while AUTO BATTLE is waiting.
    if type(stack.pop) == "function" and type(top.onChoose) == "function" then
      local states = type(stack.states) == "table" and stack.states or {}
      local below = states[#states - 1]
      -- The catch nickname question is a TextBox-owned choice. Selecting NO
      -- keeps AUTO CATCH from opening a NamingScreen.
      -- The SWAP MOVES prompt is also TextBox-owned, but its text box does not
      -- carry the generic isTextBox marker. Identify it by the explicit mod
      -- marker so AUTO BATTLE does not open the immediate-swap picker.
      local poolPrompt = below and below._qolSuiteMovePoolPrompt
      if poolPrompt then
        if not stackPop(stack) then return false end
        top.onChoose(false)
        return true
      end
      if battle.blankForAskName and below and below.isTextBox then
        if not stackPop(stack) then return false end
        top.onChoose(false)
        return true
      end
      -- Trainer SHIFT: "Will X change POKéMON?" — YES opens the party menu,
      -- NO keeps the current mon.  AUTO BATTLE already chose the current mon
      -- as best, so decline the switch to avoid a wasted turn and the
      -- spurious swap-to-first-then-back cycle.
      -- Wild "Use next POKéMON?" — YES stays in the battle, NO attempts to
      -- run.  Answer YES to keep automating.
      -- In a trainer battle the only remaining ChoiceBox is the SHIFT prompt;
      -- in a wild battle it is the "Use next" prompt.  The battle kind
      -- cleanly distinguishes them.
      local answer = (wildBattle(battle) == true)
      if not stackPop(stack) then return false end
      top.onChoose(answer)
      return true
    end
    return false
  end

  local function advanceBattleInfo(battle)
    local stack = stackFor(battle)
    local top = stackTop(stack)
    if not battle or not top or top == battle or not battle.waitingUI
       or type(stack.pop) ~= "function" then
      return false
    end
    -- Level-up stats are shown in a small battle-owned StatBox. Its native
    -- A/B path only pops the box and resumes the queue, so mirror that exact
    -- transition here for every level gained, including EXP.ALL gains.
    if Gen1StatBox and getmetatable(top) == Gen1StatBox then
      if not stackPop(stack) then return false end
      if top.onDone then top.onDone() end
      return true
    end
    -- A newly caught species opens a DexEntryMenu before the battle teardown.
    -- It is informational, so dismiss it automatically after its cry/page has
    -- been presented rather than leaving AUTO CATCH on the entry screen.
    if top.screenId == "DexEntryMenu" and top.game == battle.game then
      if safetyOption(AUTO_PAUSE_NEW_ENTRY) then return false end
      if not stackPop(stack) then return false end
      return true
    end
    return false
  end

  local function advanceForcedSwitch(battle)
    local stack = stackFor(battle)
    local top = stackTop(stack)
    if not battle or not top or top.battle ~= battle
       or not top.forceSwitch or type(top.onSwitch) ~= "function" then
      return false
    end
    local action = chooseAction(battle)
    local replacement = action and action.kind == "switch" and action.mon or nil
    if not replacement then
      local party = battle.game and battle.game.save and battle.game.save.party or {}
      local current = battle.player and battle.player.mon
      for _, mon in ipairs(party) do
        if mon ~= current and (mon.hp or 0) > 0 then
          replacement = mon
          break
        end
      end
    end
    if not replacement or not stackPop(stack) then return false end
    top.onSwitch(replacement, top)
    return true
  end

  local function advanceMimic(battle)
    if not battle or battle.phase ~= "mimicSelect"
       or type(battle.applyMimic) ~= "function" then return false end
    local rows, ctx = battle.mimicMoves, battle.mimicCtx
    local pick = rows and rows[1]
    if not pick or not ctx then return false end
    battle.mimicMoves, battle.mimicCtx = nil, nil
    battle.phase = "messages"
    battle.nextInsert = 0
    battle:applyMimic(ctx.user, ctx.target, ctx.moveInst, pick.slot)
    return true
  end

  local function advance(battle)
    if advanceBattleChoice(battle) then return true end
    if advanceForcedSwitch(battle) then return true end
    if advanceBattleInfo(battle) then return true end
    if advanceBattleMessage(battle) then return true end
    if advanceMimic(battle) then return true end
    return false
  end

  local function act(battle)
    if not automationActive(battle) or not battle or not battle.isBattle
       or battle.result or battle.phase == "messages" then
      return false
    end
    if battle.phase ~= "menu" and battle.phase ~= "moveSelect" then
      return false
    end
    local player = activePlayerMon(battle)
    if not player then return false end
    local replacement = bestPartySwitch(battle, false)
    if (player.hp or 0) <= 0 then
      replacement = bestPartySwitch(battle, true)
    end
    local action = replacement and { kind = "switch", mon = replacement }
      or chooseAction(battle)
    if not action then return false end
    if action.kind == "switch" then
      if type(battle.resolveSwitch) ~= "function" then return false end
      battle:resolveSwitch(action.mon)
      return true
    elseif action.kind == "ball" then
      local inventory = battle.game and battle.game.save
        and battle.game.save.inventory
      if type(inventory) ~= "table"
         or (tonumber(inventory[action.ball]) or 0) <= 0 then
        return false
      end
      -- BagMenu consumes balls before calling BattleState:throwBall. AUTO
      -- BATTLE calls the battle method directly, so mirror that native item
      -- flow here or an automated throw would never deplete the inventory.
      if type(battle.throwBall) ~= "function" then return false end
      require("src.inventory.Bag").remove(battle.game.save, action.ball, 1)
      battle.phase = "messages"
      battle.afterQueue = "menu"
      battle:throwBall(action.ball)
      return true
    elseif action.kind == "move" then
      if type(battle.resolveTurn) ~= "function" then return false end
      battle:resolveTurn(action.move)
      return true
    end
    return false
  end

  --------------------------------------------------------------------------
  -- Gold's battle screen is a separate state machine and presents the battle
  -- model as `state.battle`, so keep this adapter beside (rather than mixing
  -- it into) the proven Gen 1 path above.
  --------------------------------------------------------------------------
  local GoldDamage = not isGen1 and require("src.battle.gen2.Damage") or nil
  local GOLD_STATUS = {
    EFFECT_SLEEP = { rank = 3, status = "SLP" },
    EFFECT_FREEZE = { rank = 3, status = "FRZ" },
    EFFECT_PARALYZE = { rank = 2, status = "PAR" },
    EFFECT_TOXIC = { rank = 1, status = "PSN" },
    EFFECT_POISON = { rank = 1, status = "PSN" },
  }
  local GOLD_HM = {
    CUT = true, FLY = true, SURF = true, STRENGTH = true,
    FLASH = true, WHIRLPOOL = true, WATERFALL = true, ROCK_SMASH = true,
  }

  local function goldMoveDef(battle, move)
    return battle and battle.moveDef and move
      and battle:moveDef(move.id or move) or nil
  end

  local function goldUsableMoves(battle)
    if not (battle and battle.player and battle.usableMoves) then return {} end
    local ok, moves = pcall(battle.usableMoves, battle, battle.player)
    return ok and type(moves) == "table" and moves or {}
  end

  local function goldDamage(battle, user, target, def)
    if not def or (def.power or 0) <= 0 then return 0, 10 end
    local userDef = battle:speciesDef(user) or {}
    local targetDef = battle:speciesDef(target) or {}
    local chart = battle.data and battle.data.type_chart or {}
    local mult = 10
    if GoldDamage.typeMultiplier then
      local ok, value = pcall(GoldDamage.typeMultiplier, def.type,
        targetDef.types or target.types or {}, chart.matchups)
      if ok and type(value) == "number" then mult = value end
    end
    local damage
    if GoldDamage.calc then
      local ok, value = pcall(GoldDamage.calc, {
        level = user.level or 1,
        power = def.power,
        moveType = def.type,
        attacker = {
          attack = user.stats and user.stats.attack,
          specialAttack = user.stats and user.stats.specialAttack,
          types = userDef.types or user.types or {},
          stages = battle.stages and battle.stages.player or {},
        },
        defender = {
          defense = target.stats and target.stats.defense,
          specialDefense = target.stats and target.stats.specialDefense,
          types = targetDef.types or target.types or {},
          stages = battle.stages and battle.stages.enemy or {},
        },
        types = chart.types,
        matchups = chart.matchups,
        random = function(n) return math.max(0, (n or 1) - 1) end,
      })
      if ok and type(value) == "number" then damage = value end
    end
    if not damage then
      damage = math.floor(math.max(1, def.power or 1) * mult / 10)
    end
    return math.max(0, damage), mult
  end

  local function goldBestDamageMove(state, safeOnly)
    local battle = state and state.battle
    local user, target = battle and battle.player, battle and battle.enemy
    if not (battle and user and target) then return nil end
    local selected, selectedScore
    for _, move in ipairs(goldUsableMoves(battle)) do
      local def = goldMoveDef(battle, move)
      local damage, mult = goldDamage(battle, user, target, def)
      if damage > 0 and (not safeOnly or damage < (target.hp or 0)) then
        local score = damage * 10000 + mult * 100
          + (def.power or 0) + (def.accuracy or 100) / 1000
        if not selectedScore or score > selectedScore then
          selected, selectedScore = move, score
        end
      end
    end
    return selected
  end

  local function goldStatusMove(state)
    local battle = state and state.battle
    local target = battle and battle.enemy
    if not (battle and target and not target.status) then return nil end
    local volatile = battle.volatile and battle:volatile(target)
    if volatile and volatile.confuseCount then return nil end
    local selected, rank
    local targetDef = battle.speciesDef and battle:speciesDef(target) or {}
    local targetTypes = targetDef.types or target.types or {}
    for _, move in ipairs(goldUsableMoves(battle)) do
      local def = goldMoveDef(battle, move)
      local info = def and GOLD_STATUS[def.effect]
      -- Prefer dedicated status moves.  A damaging secondary effect is still
      -- valuable later, but the AUTO CATCH path must never choose it when it
      -- would risk knocking the wild Pokemon out.
      if info and (def.power or 0) <= 0
          and statusCanAffect(battle, target, def, info.status, targetTypes)
          and (not rank or info.rank > rank) then
        selected, rank = move, info.rank
      end
    end
    return selected
  end

  local function goldAvailableBall(state)
    local save = state and state.game and state.game.save
    local inventory = save and save.inventory
    if type(inventory) ~= "table" then return nil end
    local order = { "MASTER_BALL", "ULTRA_BALL", "GREAT_BALL", "POKE_BALL" }
    local mode = catchBallMode()
    if mode == "poke-ball-only" then
      return (tonumber(inventory.POKE_BALL) or 0) > 0 and "POKE_BALL" or nil
    end
    local first, last, step = 1, #order, 1
    if mode == "worst" then first, last, step = #order, 1, -1 end
    for index = first, last, step do
      local ball = order[index]
      if (tonumber(inventory[ball]) or 0) > 0 then return ball end
    end
    return nil
  end

  local function goldCatchTargetMatches(state)
    local battle = state and state.battle
    local enemy = battle and battle.enemy
    return not catchTarget or type(catchTarget.matches) ~= "function"
      or (enemy and catchTarget.matches(state.game, enemy.species)) == true
  end

  local function goldAction(state)
    local battle = state and state.battle
    local enemy = battle and battle.enemy
    if not (battle and battle.player and enemy) then return nil end
    if safetyOption(AUTO_STOP_LOW_HP) and partyNeedsRest(battle, state.game) then
      pauseAutomation("low HP", state)
      return nil
    end
    if safetyOption(AUTO_STOP_SHINY) and battle.wild and enemy.shiny then
      pauseAutomation("shiny", state)
      return nil
    end
    if catchEnabled() and battle.wild and not state.contest
        and not state.tutorial and goldCatchTargetMatches(state)
        and catchNewOnlyAllowed(battle, state.game)
        and catchShinyOnlyAllowed(battle, state) then
      if safetyOption(AUTO_STOP_NO_BALLS) and not goldAvailableBall(state) then
        pauseAutomation("no balls", state)
        return nil
      end
      local status = goldStatusMove(state)
      if status then return { kind = "move", move = status.id } end
      local safe = goldBestDamageMove(state, true)
      if safe then return { kind = "move", move = safe.id } end
      local ball = goldAvailableBall(state)
      if ball then return { kind = "item", item = ball } end
    end
    local move = goldBestDamageMove(state, false)
    return { kind = "move", move = move and move.id or "STRUGGLE" }
  end

  local function goldForceSwitch(state)
    local battle = state and state.battle
    local party = battle and battle.party or {}
    if not (battle and battle.switch) then return false end
    for index, mon in ipairs(party) do
      if mon and mon ~= battle.player and not mon.isEgg and (mon.hp or 0) > 0
          and battle:switch(index) then
        state:pushAll(battle:takeEvents())
        state.phase = "resolving"
        state:advanceQueue()
        return true
      end
    end
    return false
  end

  local function goldTopIs(state, id)
    local stack = state and state.game and state.game.stack
    local top = stackTop(stack)
    return top, top and top.screenId == id
  end

  local function goldSubmit(state, action)
    if not action then return false end
    -- Gold's native item path owns ball consumption, catch-rate resolution,
    -- animations, and post-catch prompts.  Passing a ball through
    -- Battle:takeTurn would treat it as a generic spent turn and let the
    -- wild Pokemon attack instead of throwing it.
    if action.kind == "item" and state.useItem then
      state:useItem(action.item)
    else
      state:submit(action)
    end
    return true
  end

  local function goldAdvance(state, assumedEnabled)
    if not (state and state.battle) then return false end
    if state.phase == "done" then
      -- Gold resolves catches through Battle:caught without emitting the
      -- Gen 1 pokemon.caught runtime event. Detect the completed native
      -- outcome here so STOP ON TARGET still pauses before another encounter.
      if safetyOption(AUTO_STOP_TARGET) and state.battle.outcome == "caught"
          and goldCatchTargetMatches(state) then
        pauseAutomation("target", state)
      end
      return false
    end
    if not automationActive(state, assumedEnabled) then return false end

    -- SWAP MOVES offers an optional immediate replacement after a full
    -- moveset learns a move.  AUTO BATTLE keeps that move in the pool and
    -- must dismiss both the prompt and any active picker explicitly; the
    -- battle state is not represented by a separate stack screen in Gold.
    if (state.qolPoolPrompt or state.qolPoolSelecting)
        and type(state.qolPoolKeep) == "function" then
      state:qolPoolKeep()
      return true
    end

    local stack = state.game and state.game.stack
    local top = stackTop(stack)
    if top and top ~= state then
      if top._qolSuiteMovePoolPrompt and type(top.choice) == "function" then
        if not stackPop(stack) then return false end
        top.choice(false)
        return true
      end
      if top.screenId == "Gen2EvolutionAnim" then
        if safetyOption(AUTO_PAUSE_EVOLUTION) then return false end
        -- Evolution messages and the move-learn prompt are PromptButton waits.
        -- Let the native animation update one frame at a time, but answer those
        -- prompts without requiring a physical A/B press.
        if top.phase == "stopped" or top.phase == "congrats"
            or top.phase == "learn" then
          top.timer = 0
          return true
        end
        return false
      end
      if top.screenId == "Gen2PokedexMenu" and top.newEntry then
        if safetyOption(AUTO_PAUSE_NEW_ENTRY) then return false end
        if top.page == 1 then
          top.page = 2
        elseif top.onClose then
          top.onClose()
        end
        return true
      end
      -- A fainted Gold party menu is the forced-switch prompt.  Choose the
      -- first legal replacement through Battle:switch, then resume the native
      -- queue instead of attempting to drive the menu's cursor.
      if top.screenId == "Gen2PartyMenu" and state.battle.player
          and (state.battle.player.hp or 0) <= 0 then
        if not stackPop(stack) then return false end
        state.phase = "forced-switch"
        return goldForceSwitch(state)
      end
      return false
    end

    if state.slideFrame and state.slideFrame < 72 then return false end
    -- BattleState:update keeps a completed animation object around when its
    -- sprites are still needed for the final frame.  Treat that same
    -- done/keepSprites state as finished; checking only for a non-nil anim
    -- strands caught battles on their final message forever.
    if state.anim then
      local done = type(state.anim.done) == "function"
        and state.anim:done()
      if not (done and state.anim.keepSprites) then return false end
    end
    if state.faintSlide or state.trainerSlide then return false end
    if state.messageTimer and state.messageTimer > 0 then
      state.messageTimer = 0
      -- Gold's BattleState waits on messageTimer inside update(); clear the
      -- wait after native update and drain the next queued event now so AUTO
      -- BATTLE cannot strand itself on the final informational message.
      if (state.phase == "resolving" or state.phase == "intro")
          and type(state.advanceQueue) == "function" then
        state:advanceQueue()
      end
      return true
    end
    if state.phase == "stats-box" then
      state.statsBoxMon = nil
      state.phase = "resolving"
      return true
    end
    if state.phase == "resolving" or state.phase == "intro" then
      state:advanceQueue()
      return true
    end
    if state.phase == "locked-in" then
      local move = state.battle:lockedInMove(state.battle.player)
      if move then state:submit({ kind = "move", move = move }) end
      return true
    end
    if state.phase == "menu" then
      return goldSubmit(state, goldAction(state))
    end
    if state.phase == "moves" then
      return goldSubmit(state, goldAction(state))
    end
    if state.phase == "ask-nickname" then
      return state:answerNickname(false) ~= false
    end
    if state.phase == "ask-shift" then
      state.phase = "resolving"
      state:advanceQueue()
      return true
    end
    if state.phase == "forced-switch" then return goldForceSwitch(state) end
    if state.phase == "refuse-shift" then
      state.message = nil
      state.phase = "resolving"
      state:advanceQueue()
      return true
    end
    if state.phase == "refuse-switch" then
      state.message = nil
      if state.refuseForced then
        state.phase = "forced-switch"
        return goldForceSwitch(state)
      end
      state.phase = "menu"
      return true
    end
    if state.phase == "refuse-move" then
      state.message = nil
      state.phase = "moves"
      return true
    end
    if state.phase == "learn-intro" then
      state:nextPage()
      if not state.messagePages then state.phase = "ask-forget" end
      return true
    end
    if state.phase == "ask-forget" then
      state:answerForgetPrompt(false)
      return true
    end
    if state.phase == "stop-learning" then
      state:answerForgetPrompt(true)
      return true
    end
    if state.phase == "choose-forget" then
      local learn = state.pendingLearn
      local party = state.battle and state.battle.party
      local mon = learn and type(party) == "table" and party[learn.index]
      local slot
      for index, move in ipairs((mon and mon.moves) or {}) do
        if move and not GOLD_HM[move.id] then slot = index break end
      end
      if not (learn and mon and slot
          and type(state.battle.resolveForget) == "function") then
        -- A four-HM moveset has no legal slot.  Follow the native decline arm
        -- instead of selecting an HM or indexing a partial learn prompt.
        if type(state.finishDecline) == "function" then
          state:finishDecline()
          return true
        end
        return false
      end
      state.battle:resolveForget(learn.index, slot, learn.move, learn.moveName)
      state.pendingLearn = nil
      state.phase = "resolving"
      state:pushAll(state.battle:takeEvents())
      state:advanceQueue()
      return true
    end
    return false
  end

  local removeCoreUpdateHook
  local removeRenderHudHook
  local coreUpdateSubscribed = false
  local renderHudSubscribed = false

  local function coreUpdateHook(next, game, dt)
    local result = next(game, dt)
    -- AUTO BATTLE is opt-in. Avoid walking the entire screen stack on every
    -- ordinary gameplay frame when automation is disabled.
    if not runtimeEnabled then return result end
    local battle = activeBattle(game)
    if automationActive(battle, true) then
      if isGen1 then
        advance(battle)
        local stack = game and game.stack
        if stackTop(stack) == battle then act(battle) end
      else
        -- Gold's battle screen is driven by Game:update through the same
        -- core.update hook as Gen 1.  Run its adapter after native update so
        -- queued messages, catches, level-ups, and prompts cannot wait for a
        -- draw callback to make progress.
        goldAdvance(battle, true)
      end
    end
    return result
  end

  local function viewportBounds(viewport)
    viewport = viewport or {}
    local x = tonumber(viewport.gameX) or 0
    local y = tonumber(viewport.gameY) or 0
    local width = tonumber(viewport.gameWidth) or tonumber(viewport.width) or 160
    local height = tonumber(viewport.gameHeight)
      or tonumber(viewport.height) or 144
    if width <= 0 then width = 160 end
    if height <= 0 then height = 144 end
    return x, y, width, height
  end

  local function ballCounterPosition(viewport)
    local gameX, gameY, gameWidth, gameHeight = viewportBounds(viewport)
    -- The battle canvas is normally enlarged by the renderer, while this
    -- hook runs after composition in window coordinates.  Keep the panel's
    -- font and border in the same visual scale as the battle without letting
    -- it become a full-screen card on a large desktop window.
    local scale = math.max(1, math.min(BALL_COUNTER_MAX_SCALE,
      gameWidth / 320))
    local maxScale = (gameWidth - BALL_COUNTER_MARGIN * 2)
      / BALL_COUNTER_WIDTH
    -- Keep the card usable on a very narrow phone viewport too.  Normal
    -- battle viewports stay at 1x or larger; only constrained windows use a
    -- fractional scale to remain fully attached to the playfield.
    scale = math.max(0.5, scale)
    if maxScale > 0 then scale = math.min(scale, maxScale) end

    local width = BALL_COUNTER_WIDTH * scale
    local height = BALL_COUNTER_HEIGHT * scale
    local margin = BALL_COUNTER_MARGIN * scale
    local wideBattle = gameWidth > gameHeight * 1.5
    local x
    local y
    if wideBattle then
      -- Wide battles leave a useful visual gap between the two battlers.
      -- Centering the card there keeps it away from both status panels and
      -- makes it read as part of the battle HUD instead of a screen corner
      -- debug label.
      x = gameX + (gameWidth - width) / 2
      y = gameY + gameHeight * 0.42 - height / 2
    else
      -- The classic layout has no center gap: keep the card in the lower-left
      -- margin, away from the enemy name/HP panel and the player's HUD.
      x = gameX + margin
      y = gameY + gameHeight - height - margin
    end

    x = math.max(gameX, math.min(x, gameX + gameWidth - width))
    y = math.max(gameY, math.min(y, gameY + gameHeight - height))
    return math.floor(x), math.floor(y), math.floor(width),
      math.floor(height), scale
  end

  -- Keep this readout in the same visual language as the game's text boxes:
  -- a warm-white interior, the native pixel border, a short title row, and a
  -- compact two-row inventory breakdown.  It is deliberately drawn after
  -- the native HUD and only while catching is active, so ordinary AUTO
  -- BATTLE remains visually unchanged.
  local function drawBallCounter(g, game, viewport)
    if not (Font and type(Font.draw) == "function") then return end
    local x, y, width, height, scale = ballCounterPosition(viewport)
    local pushed = type(g.push) == "function" and type(g.pop) == "function"
      and type(g.translate) == "function" and type(g.scale) == "function"
    local oldR, oldG, oldB, oldA
    if pushed then
      g.push("all")
    elseif type(g.getColor) == "function" then
      oldR, oldG, oldB, oldA = g.getColor()
    end

    -- Draw the card in logical battle pixels, then scale the complete card so
    -- the font, border glyphs, and background all stay in proportion.
    if pushed then
      g.translate(x, y)
      g.scale(scale, scale)
      x, y = 0, 0
      width, height = BALL_COUNTER_WIDTH, BALL_COUNTER_HEIGHT
    end

    g.setColor(HINT_PANEL[1], HINT_PANEL[2], HINT_PANEL[3], 0.98)
    g.rectangle("fill", x, y, width, height)
    local border = Font.BORDER
    if type(Font.drawCode) == "function" and type(border) == "table"
        and width >= NATIVE_TILE * 3 and height >= NATIVE_TILE * 3 then
      local right = x + width - NATIVE_TILE
      local bottom = y + height - NATIVE_TILE
      local columns = math.max(0, math.floor(width / NATIVE_TILE) - 2)
      local rows = math.max(0, math.floor(height / NATIVE_TILE) - 2)
      g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
      Font.drawCode(border.tl, x, y)
      Font.drawCode(border.tr, right, y)
      Font.drawCode(border.bl, x, bottom)
      Font.drawCode(border.br, right, bottom)
      for index = 1, columns do
        local edgeX = x + index * NATIVE_TILE
        Font.drawCode(border.h, edgeX, y)
        Font.drawCode(border.h, edgeX, bottom)
      end
      for index = 1, rows do
        local edgeY = y + index * NATIVE_TILE
        Font.drawCode(border.v, x, edgeY)
        Font.drawCode(border.v, right, edgeY)
      end
    else
      g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
      g.rectangle("line", x, y, width, height)
    end

    local display = ballDisplay(game)
    g.setColor(DARK_INK[1], DARK_INK[2], DARK_INK[3], 1)
    Font.draw(display.title, x + NATIVE_TILE, y + NATIVE_TILE)
    Font.draw(display.firstRow, x + NATIVE_TILE, y + NATIVE_TILE * 2)
    -- At the smallest fallback size, keep the second row inside the panel
    -- rather than allowing a long font/translation combination to spill.
    if height >= NATIVE_TILE * 4 then
      Font.draw(display.secondRow, x + NATIVE_TILE, y + NATIVE_TILE * 3)
    end

    if pushed then
      g.pop()
    elseif oldR ~= nil then
      g.setColor(oldR, oldG, oldB, oldA)
    end
  end

  local function drawBallCounterIfNeeded(game, viewport, battle)
    if not (runtimeCatchEnabled and runtimeShowBallCounts) then return end
    if not battle and not activeBattle(game) then return end
    local g = love and love.graphics
    if g then drawBallCounter(g, game, viewport) end
  end

  -- The Gen 3-inspired UI draws its battle panels in a higher-priority final
  -- HUD pass.  Register the counter there so it remains visible and keeps the
  -- same screen-space scale instead of being painted underneath that panel.
  if compat and type(compat.registerBattleOverlay) == "function" then
    compat.registerBattleOverlay("ballCounter", function(battle, game, viewport)
      drawBallCounterIfNeeded(game, viewport, battle)
    end)
  end

  local function renderHudHook(next, game, viewport)
    local result = next(game, viewport)
    if not (runtimeCatchEnabled and runtimeShowBallCounts) then return result end
    if compat and compat.battleUIActive
        and compat.battleUIActive(game) then
      return result
    end
    if activeBattle(game) then
      local g = love.graphics
      if g then
        drawBallCounter(g, game, viewport)
      end
    end
    return result
  end

  -- These are the suite's two continuous battle hooks. Modern hook buses
  -- return idempotent unsubscribe closures, so leave each chain entirely
  -- when its feature is inactive. Older buses that return no closure retain
  -- one guarded callback and never accumulate duplicates across changes.
  syncRuntimeHooks = function()
    local wantUpdate = runtimeEnabled
    local wantHud = runtimeEnabled and runtimeCatchEnabled
      and runtimeShowBallCounts

    if wantUpdate then
      if not coreUpdateSubscribed then
        removeCoreUpdateHook = mod.hooks:wrap("core.update", coreUpdateHook)
        coreUpdateSubscribed = true
      end
    elseif coreUpdateSubscribed and type(removeCoreUpdateHook) == "function" then
      local ok = pcall(removeCoreUpdateHook)
      if ok then
        coreUpdateSubscribed, removeCoreUpdateHook = false, nil
      end
    end

    if wantHud then
      if not renderHudSubscribed then
        removeRenderHudHook = mod.hooks:wrap("render.hud", renderHudHook, -900)
        renderHudSubscribed = true
      end
    elseif renderHudSubscribed and type(removeRenderHudHook) == "function" then
      local ok = pcall(removeRenderHudHook)
      if ok then
        renderHudSubscribed, removeRenderHudHook = false, nil
      end
    end
  end

  syncRuntimeHooks()

  mod.exports = {
    enabled = enabled,
    automationActive = automationActive,
    safetyStatus = function()
      return safetyPause and safetyPause.reason or nil
    end,
    catchEnabled = catchEnabled,
    catchNewOnlyAllowed = catchNewOnlyAllowed,
    catchShinyOnlyAllowed = catchShinyOnlyAllowed,
    catchBallMode = catchBallMode,
    ballCounts = ballCounts,
    formatBallCounts = formatBallCounts,
    formatBallRows = formatBallRows,
    ballCounterPosition = ballCounterPosition,
    activeBattle = activeBattle,
    advance = advance,
    chooseAction = chooseAction,
    chooseMove = normalAction,
    chooseCatchAction = catchAction,
    act = act,
    goldAdvance = goldAdvance,
    goldAction = goldAction,
  }
end
