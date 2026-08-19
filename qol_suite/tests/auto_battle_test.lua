-- AUTO BATTLE focused regression test. Run from the gen1recomp checkout:
--   luajit mods/qol_suite/tests/auto_battle_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local exports = run.loader.exports.qol_suite.autoBattle
local MOD_ID = "qol_suite"
local schema = run.loader.optionSchemas[MOD_ID]
local schemaByKey = {}
for _, row in ipairs(schema) do schemaByKey[row.key] = row end

T.check(#run.errors == 0, "AUTO BATTLE package load is clean")
T.check(type(exports.chooseAction) == "function",
  "AUTO BATTLE exposes its action chooser")
T.check(type(exports.act) == "function",
  "AUTO BATTLE exposes its automation step")
run.loader.modOptions[MOD_ID] = { autoBattle = true }
T.check(exports.automationActive(nil) == false,
  "AUTO BATTLE stays inactive when no battle exists")
T.eq(exports.activeBattle({ stack = {} }), nil,
  "AUTO BATTLE tolerates a partial stack without top()")
T.eq(exports.ballCounts({ save = { inventory = "corrupt" } }).total, 0,
  "AUTO CATCH treats malformed inventory data as empty")
T.eq(exports.ballCounts({ save = { inventory = {
  POKE_BALL = math.huge,
} } }).total, 0,
  "AUTO CATCH rejects a non-finite inventory quantity")
T.check(type(exports.formatBallRows) == "function",
  "SHOW BALL COUNTS exposes its native two-row formatter")
local firstBallRow, secondBallRow = exports.formatBallRows({
  poke = 2, great = 3, ultra = 4, master = 5,
})
T.eq(firstBallRow, "POKE 2 GREAT 3",
  "SHOW BALL COUNTS formats the common balls clearly")
T.eq(secondBallRow, "ULTRA 4 MASTER 5",
  "SHOW BALL COUNTS formats the rare balls clearly")
local counterX, counterY, counterWidth, counterHeight =
  exports.ballCounterPosition({ gameX = 10, gameY = 20,
    gameWidth = 160, gameHeight = 144 })
T.eq(counterX, 14, "SHOW BALL COUNTS anchors to the battle viewport")
T.eq(counterY, 120, "SHOW BALL COUNTS stays in the lower battle margin")
T.eq(counterWidth, 144, "SHOW BALL COUNTS reserves its framed width")
T.eq(counterHeight, 40, "SHOW BALL COUNTS reserves its title and two text rows")
local wideX, wideY, wideWidth, wideHeight, wideScale =
  exports.ballCounterPosition({ gameX = 0, gameY = 0,
    gameWidth = 304, gameHeight = 144 })
T.eq(wideX, 80, "SHOW BALL COUNTS centers in the wide battle field")
T.eq(wideY, 40, "SHOW BALL COUNTS stays above the wide battle message area")
T.eq(wideWidth, 144, "SHOW BALL COUNTS keeps its native width in a native viewport")
T.eq(wideHeight, 40, "SHOW BALL COUNTS keeps its native height in a native viewport")
T.eq(wideScale, 1, "SHOW BALL COUNTS uses native scale in a native viewport")
local largeX, largeY, largeWidth, largeHeight, largeScale =
  exports.ballCounterPosition({ gameX = 10, gameY = 20,
    gameWidth = 800, gameHeight = 720 })
T.check(largeScale > 1, "SHOW BALL COUNTS grows on a scaled battle viewport")
T.eq(largeWidth, 360, "SHOW BALL COUNTS scales its framed width")
T.eq(largeHeight, 100, "SHOW BALL COUNTS scales its framed height")
T.check(largeX >= 10 and largeY >= 20,
  "SHOW BALL COUNTS keeps its scaled card inside the viewport")
T.check(exports.act({ isBattle = true, phase = "menu" }) == false,
  "AUTO BATTLE safely ignores an incomplete battle model")
T.check(exports.advance({ phase = "messages", game = { stack = {} } }) == false,
  "AUTO BATTLE safely ignores a partial state stack")
T.check(exports.advance({ waitingUI = true, game = { stack = {
  states = { { onChoose = function() end } },
  top = function(self) return self.states[#self.states] end,
} } }) == false,
  "AUTO BATTLE never calls a missing stack pop method")
local function visibilityHas(condition, key)
  if type(condition) ~= "table" then return false end
  return condition.key == key and condition.equals == true
end
for _, row in ipairs({
  { "autoCatchNewOnly", "autoCatch" },
  { "autoCatchTarget", "autoCatch" },
  { "autoCatchBall", "autoCatch" },
}) do
  local option, parent = row[1], row[2]
  T.check(visibilityHas(schemaByKey[option].visible_if, parent),
    option .. " is gated by its direct parent " .. parent)
end
T.eq(#schemaByKey.autoCatchBall.choices, 3,
  "AUTO CATCH BALL exposes BEST, WORST, and POKE BALL ONLY")
for _, row in ipairs({
  { "autoStopLowHp", "autoBattle" },
  { "autoStopNoBalls", "autoCatch" },
  { "autoStopTarget", "autoCatchTarget" },
  { "autoPauseNewEntry", "autoBattle" },
  { "autoPauseEvolution", "autoBattle" },
}) do
  local option, parent = row[1], row[2]
  T.check(visibilityHas(schemaByKey[option].visible_if, parent),
    option .. " is gated by its direct parent " .. parent)
end

local moves = {
  WEAK = { id = "WEAK", power = 30, accuracy = 100, type = "NORMAL",
    effect = "NO_ADDITIONAL_EFFECT", testDamage = 3 },
  SAFE = { id = "SAFE", power = 45, accuracy = 100, type = "NORMAL",
    effect = "NO_ADDITIONAL_EFFECT", testDamage = 7 },
  KO = { id = "KO", power = 120, accuracy = 100, type = "NORMAL",
    effect = "NO_ADDITIONAL_EFFECT", testDamage = 50 },
  SLEEP = { id = "SLEEP", power = 0, accuracy = 100, type = "NORMAL",
    effect = "SLEEP_EFFECT", testDamage = 0 },
}

local function battleWith(hp, kind)
  local playerMon = { species = "FIXMON_A", hp = 30, stats = { hp = 30 }, level = 10 }
  local enemyMon = { species = "FIXMON_B", hp = hp, stats = { hp = 30 }, level = 8 }
  playerMon.moves = {
    { id = "WEAK", pp = 20 }, { id = "SAFE", pp = 20 },
    { id = "KO", pp = 20 }, { id = "SLEEP", pp = 20 },
  }
  return {
    isBattle = true, phase = "menu", kind = kind,
    data = { moves = moves, pokemon = {
      FIXMON_A = { name = "FIXMON A", types = { "GRASS" } },
      FIXMON_B = { name = "FIXMON B", types = { "FIRE" } },
      FIXMON_C = { name = "FIXMON C", types = { "WATER" } },
    } },
    game = { save = { party = { playerMon }, inventory = { POKE_BALL = 2 } } },
    player = { mon = playerMon, curMoves = playerMon.moves,
      curTypes = { "GRASS" }, curStats = playerMon.stats, stages = {}, isPlayer = true },
    enemy = { mon = enemyMon, curTypes = { "FIRE" },
      curStats = enemyMon.stats, stages = {}, isPlayer = false },
    moveDef = function(self, move) return self.data.moves[move.id] end,
    effectRecord = function(self, effect)
      return effect == "SLEEP_EFFECT" and { kind = "primary" } or { kind = "full" }
    end,
    computeDamage = function(self, user, target, def)
      return def.testDamage or 0, { typeMult = 10 }
    end,
  }
end

run.loader.modOptions[MOD_ID] = { autoBattle = true, autoCatch = false }
for iteration = 1, 150 do
  local battle = battleWith(30, "trainer")
  local action = exports.chooseAction(battle)
  T.eq(action.kind, "move", "AUTO BATTLE chooses a move " .. iteration)
  T.eq(action.move.id, "KO", "AUTO BATTLE maximizes damage " .. iteration)
end

run.loader.modOptions[MOD_ID] = { autoBattle = true, autoCatch = true }
for iteration = 1, 150 do
  local battle = battleWith(10, "wild")
  local action = exports.chooseCatchAction(battle)
  T.eq(action.move.id, "SLEEP", "AUTO CATCH starts with status " .. iteration)
  battle.enemy.mon.status = "SLP"
  battle.enemy.mon.hp = 10
  action = exports.chooseCatchAction(battle)
  T.eq(action.move.id, "SAFE", "AUTO CATCH avoids a knockout " .. iteration)
  battle.enemy.mon.hp = 1
  action = exports.chooseCatchAction(battle)
  T.eq(action.kind, "ball", "AUTO CATCH throws at one HP " .. iteration)
end

run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoCatchNewOnly = true,
}
local alreadyCaughtBattle = battleWith(1, "wild")
alreadyCaughtBattle.enemy.mon.status = "SLP"
alreadyCaughtBattle.game.save.pokedex = { owned = { FIXMON_B = true } }
T.eq(exports.chooseCatchAction(alreadyCaughtBattle), nil,
  "CATCH NEW ONLY skips an already caught RBY species")
local newSpeciesBattle = battleWith(1, "wild")
newSpeciesBattle.enemy.mon.status = "SLP"
newSpeciesBattle.game.save.pokedex = { owned = {} }
T.eq(exports.chooseCatchAction(newSpeciesBattle).kind, "ball",
  "CATCH NEW ONLY still catches a new RBY species")

for _, mode in ipairs({ "best", "worst", "poke-ball-only" }) do
  run.loader.modOptions[MOD_ID] = {
    autoBattle = true, autoCatch = true, autoCatchBall = mode,
  }
  for iteration = 1, 100 do
    local battle = battleWith(1, "wild")
    battle.enemy.mon.status = "SLP"
    battle.game.save.inventory = {
      MASTER_BALL = 1, ULTRA_BALL = 1, GREAT_BALL = 1, POKE_BALL = 1,
    }
    local action = exports.chooseCatchAction(battle)
    T.eq(action.kind, "ball",
      "AUTO CATCH BALL returns a ball for " .. mode .. " " .. iteration)
    local expected = mode == "best" and "MASTER_BALL"
      or mode == "worst" and "POKE_BALL" or "POKE_BALL"
    T.eq(action.ball, expected,
      "AUTO CATCH BALL selects " .. mode .. " " .. iteration)
  end
end

-- Safety stops are opt-in and hand control back without changing the AUTO
-- BATTLE setting. Toggling AUTO BATTLE on clears the pause for a deliberate
-- resume.
run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoStopLowHp = true,
}
local lowHpBattle = battleWith(30, "trainer")
lowHpBattle.game.save.party[1].hp = 7
T.eq(exports.chooseAction(lowHpBattle), nil,
  "STOP LOW HP pauses when the party needs rest")
T.eq(exports.safetyStatus(), "low HP",
  "STOP LOW HP reports its pause reason")
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "autoBattle", value = true })
run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoStopNoBalls = true,
}
local noBallsBattle = battleWith(1, "wild")
noBallsBattle.enemy.mon.status = "SLP"
noBallsBattle.game.save.inventory = {}
T.eq(exports.chooseAction(noBallsBattle), nil,
  "STOP NO BALLS pauses before a ball-less catch attempt")
T.eq(exports.safetyStatus(), "no balls",
  "STOP NO BALLS reports its pause reason")
run.loader.events:emit("mod.options_changed",
  { mod = MOD_ID, key = "autoBattle", value = true })

-- Battle presentation must not require a real button press once AUTO BATTLE
-- owns the battle. Cover the native CONT wait, finished-page prompt, choice
-- box, forced replacement menu, and Mimic's mid-move menu repeatedly.
local legacyBattleState = require("src.battle.BattleState")
local statBoxType = legacyBattleState[table.concat({ "Stat", "Box" })]
T.check(type(statBoxType) == "table" and type(statBoxType.new) == "function",
  "AUTO BATTLE test fixture resolves the Gen 1 level-up stat box")
for iteration = 1, 100 do
  local battle = battleWith(20, "trainer")
  local stack = { states = { battle } }
  function stack:top() return self.states[#self.states] end
  function stack:pop() return table.remove(self.states) end
  battle.game.stack = stack
  T.eq(exports.activeBattle(battle.game), battle,
    "AUTO BATTLE finds the battle under presentation state " .. iteration)

  battle.phase = "messages"
  battle.lines = { { codes = { 1 }, cont = false },
    { codes = { 2 }, cont = false } }
  battle.shown, battle.lineIndex = { { 1 } }, 1
  battle.beginMsgLine = function(self) self.lineIndex = self.lineIndex + 1 end
  battle.msgWaiting, battle.msgPreWait = true, 0
  T.check(exports.advance(battle),
    "AUTO BATTLE advances CONT text " .. iteration)
  T.eq(battle.msgWaiting, nil,
    "AUTO BATTLE clears CONT text wait " .. iteration)
  T.eq(battle.lineIndex, 2,
    "AUTO BATTLE starts the next message line " .. iteration)

  battle.current, battle.msgPrompt, battle.msgPromptWait = {}, true, 0
  T.check(exports.advance(battle),
    "AUTO BATTLE advances finished message " .. iteration)
  T.eq(battle.current, nil,
    "AUTO BATTLE clears finished message " .. iteration)

  local chosen
  local choice = { onChoose = function(yes) chosen = yes end }
  stack.states = { battle, choice }
  battle.waitingUI = true
  T.check(exports.advance(battle),
    "AUTO BATTLE resolves the trainer SHIFT prompt " .. iteration)
  T.eq(chosen, false,
    "AUTO BATTLE declines the trainer SHIFT prompt, keeping its mon " .. iteration)
  T.eq(#stack.states, 1,
    "AUTO BATTLE closes the SHIFT prompt " .. iteration)

  -- A wild "Use next POKéMON?" prompt must still be answered YES so the
  -- battle continues instead of attempting to run.
  local wildBattle2 = battleWith(20, "wild")
  wildBattle2.game.stack = stack
  local wildChosen
  local wildChoice = { onChoose = function(yes) wildChosen = yes end }
  stack.states = { wildBattle2, wildChoice }
  wildBattle2.waitingUI = true
  T.check(exports.advance(wildBattle2),
    "AUTO BATTLE resolves the wild 'Use next' prompt " .. iteration)
  T.eq(wildChosen, true,
    "AUTO BATTLE stays in the wild battle on 'Use next' " .. iteration)

  local poolChoice
  local poolPrompt = { _qolSuiteMovePoolPrompt = true }
  local poolBox = { onChoose = function(yes)
    poolChoice = yes
    stack:pop() -- the TextBox under the ChoiceBox
  end }
  stack.states = { battle, poolPrompt, poolBox }
  battle.waitingUI = true
  T.check(exports.advance(battle),
    "AUTO BATTLE dismisses the SWAP MOVES prompt " .. iteration)
  T.eq(poolChoice, false,
    "AUTO BATTLE keeps the new move in the pool " .. iteration)
  T.eq(#stack.states, 1,
    "AUTO BATTLE closes the SWAP MOVES prompt " .. iteration)

  local dex = {
    screenId = "DexEntryMenu",
    def = { id = "FIXMON_B" }, game = battle.game,
  }
  stack.states = { battle, dex }
  battle.waitingUI = true
  T.check(exports.advance(battle),
    "AUTO BATTLE dismisses informational Dex page " .. iteration)
  T.eq(#stack.states, 1,
    "AUTO BATTLE returns from informational Dex page " .. iteration)

  local nicknameChoice
  local nicknameText = { isTextBox = true, game = battle.game }
  local nicknameBox = {
    onChoose = function(yes)
      stack:pop()
      nicknameChoice = yes
    end,
  }
  stack.states = { battle, nicknameText, nicknameBox }
  battle.waitingUI, battle.blankForAskName = true, true
  T.check(exports.advance(battle),
    "AUTO CATCH resolves the nickname prompt " .. iteration)
  T.eq(nicknameChoice, false,
    "AUTO CATCH declines the nickname prompt " .. iteration)
  T.eq(#stack.states, 1,
    "AUTO CATCH closes the nickname prompt " .. iteration)
  battle.blankForAskName = false

  for levelUp = 1, 3 do
    local statBox = statBoxType.new(battle.game, { stats = {} })
    stack.states = { battle, statBox }
    battle.waitingUI = true
    T.check(exports.advance(battle),
      "AUTO BATTLE dismisses level-up window " .. iteration .. "." .. levelUp)
    T.eq(#stack.states, 1,
      "AUTO BATTLE resumes after level-up window " .. iteration .. "." .. levelUp)
  end

  local backup = { species = "FIXMON_C", hp = 30, stats = { hp = 30 },
    moves = { { id = "SAFE", pp = 20 } } }
  table.insert(battle.game.save.party, backup)
  battle.player.mon.hp = 0
  local switched
  local party = { battle = battle, forceSwitch = true,
    onSwitch = function(mon) switched = mon end }
  stack.states = { battle, party }
  battle.waitingUI = true
  T.check(exports.advance(battle),
    "AUTO BATTLE chooses a forced replacement " .. iteration)
  T.eq(switched, backup,
    "AUTO BATTLE selects a healthy replacement " .. iteration)

  local copied
  battle.phase = "mimicSelect"
  battle.mimicMoves = { { slot = 1, id = "SAFE" } }
  battle.mimicCtx = { user = battle.player, target = battle.enemy,
    moveInst = { id = "MIMIC", pp = 10 } }
  battle.applyMimic = function(self, user, target, moveInst, slot)
    copied = slot
  end
  T.check(exports.advance(battle),
    "AUTO BATTLE resolves Mimic selection " .. iteration)
  T.eq(copied, 1,
    "AUTO BATTLE copies the available Mimic move " .. iteration)
end

-- A battle-owned screen that merely has a Pokemon definition is not
-- necessarily a Pokedex entry (move learning and evolution can have one too).
-- Do not dismiss unknown UI by shape alone.
do
  local battle = battleWith(20, "trainer")
  local stack = { states = { battle } }
  function stack:top() return self.states[#self.states] end
  function stack:pop() return table.remove(self.states) end
  battle.game.stack = stack
  battle.waitingUI = true
  local unrelated = { def = { id = "FIXMON_B" }, game = battle.game }
  stack.states = { battle, unrelated }
  T.check(not exports.advance(battle),
    "AUTO BATTLE leaves an unidentified battle-owned screen alone")
  T.eq(battle.game.stack:top(), unrelated,
    "AUTO BATTLE does not pop non-Pokedex informational UI")
end

run.loader.modOptions[MOD_ID] = {
  autoBattle = true, autoCatch = true, autoCatchBall = "poke-ball-only",
}
local noRegularBall = battleWith(1, "wild")
noRegularBall.enemy.mon.status = "SLP"
noRegularBall.game.save.inventory = { MASTER_BALL = 1, GREAT_BALL = 1 }
local noRegularAction = exports.chooseCatchAction(noRegularBall)
T.check(noRegularAction.kind ~= "ball",
  "POKE BALL ONLY never falls back to a stronger ball")

run.loader.modOptions[MOD_ID] = nil
T.finish("auto_battle")
