-- SKIP CENTER TALK focused regression test for the current engine seams.
-- The full nurse animation is owned by the engine; these cases verify that
-- every preamble box is skipped without leaking temporary method patches.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("red")

local run = T.sdk.loadMod("qol_suite", { data = T.fixtures.fresh(), root = ".." })
local MOD_ID = "qol_suite"
T.eq(#run.errors, 0, "SKIP CENTER TALK package load is clean")

local exports = run.loader.exports[MOD_ID]
local hooks = run.loader.hooks
T.check(type(exports.skipCenterDialogue) == "table",
  "SKIP CENTER TALK exports its compatibility helpers")
T.check(type(exports.skipCenterDialogue.shouldSkip) == "function",
  "SKIP CENTER TALK exposes its nurse-context predicate")

run.loader.modOptions[MOD_ID] = { skipCenterDialogue = true }
T.check(exports.skipCenterDialogue.shouldSkip({
    kind = "nurse_heal", generation = 1,
  }), "SKIP CENTER TALK recognizes the Gen 1 nurse context")
T.check(hooks:call("world.nurse_heal.confirmation", function() return false end,
    {}, { kind = "nurse_heal", generation = 1 }) == true,
  "SKIP CENTER TALK answers the nurse prompt YES")
T.check(hooks:call("world.nurse_heal.confirmation", function() return false end,
    {}, { kind = "unrelated_yes_no", generation = 1 }) == false,
  "SKIP CENTER TALK leaves unrelated questions alone")

-- The native healing animation still owns the machine sequence.  The mod's
-- completion seam only removes the final fighting-fit/farewell text.
local OverworldState = require("src.world.OverworldController")
local finishHealKey = table.concat({ "finish", "Nurse", "Heal" })
local finishHeal = type(OverworldState) == "table"
  and OverworldState[finishHealKey] or nil
T.check(type(finishHeal) == "function",
  "the RBY nurse completion routine is available")
local finished = false
if type(finishHeal) == "function" then
  finishHeal({ player = {} }, "BYE", function()
    finished = true
  end, nil)
end
T.eq(finished, true,
  "SKIP CENTER TALK completes the native heal without final dialogue")

-- Yellow resumes the accepted-heal path asynchronously after Pikachu hops
-- onto the counter. The mod must suppress that delayed "we need your party"
-- box while restoring both shared methods before control returns each time.
local Game = require("src.core.Game")
local TextBox = require("src.render.TextBox")
local Follower = require("src.world.PikachuFollower")
local Music = require("src.core.Music")
local Pokemon = require("src.pokemon.Pokemon")
local gameDataKey = table.concat({ "da", "ta" })
local gameSaveKey = table.concat({ "sa", "ve" })
local gameStackKey = table.concat({ "sta", "ck" })
local nurseHealKey = table.concat({ "nurse", "Heal" })
local followerHopKey = table.concat({ "hop", "To", "Counter" })
local nurseHeal = type(OverworldState) == "table"
  and OverworldState[nurseHealKey] or nil
local followerHop = type(Follower) == "table"
  and Follower[followerHopKey] or nil
T.check(type(nurseHeal) == "function",
  "the RBY nurse-heal routine is available")
T.check(type(followerHop) == "function",
  "the Yellow follower-hop routine is available")
local function findUpvalue(fn, wanted)
  if not (debug and debug.getupvalue and type(fn) == "function") then
    return nil, nil
  end
  for index = 1, 64 do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == wanted then return index, value end
  end
  return nil, nil
end
local _, nativeNurse = findUpvalue(nurseHeal, "original")
nativeNurse = nativeNurse or nurseHeal
local nativeGameIndex, nativeGame = findUpvalue(nativeNurse, "Game")
local saved = {
  data = type(Game) == "table" and Game[gameDataKey] or nil,
  save = type(Game) == "table" and Game[gameSaveKey] or nil,
  stack = type(Game) == "table" and Game[gameStackKey] or nil,
  textNew = TextBox.new, hop = followerHop,
  visible = Follower.setVisible, musicStop = Music.stop,
  heal = Pokemon.heal,
}

local scenarioOk, scenarioErr = pcall(function()
  if nativeGameIndex then debug.setupvalue(nativeNurse, nativeGameIndex, Game) end
  Game[gameDataKey] = { text = {
    _PokemonCenterFarewellText = "BYE",
    _PokemonCenterWelcomeText = "HELLO",
    _ShallWeHealYourPokemonText = "HEAL?",
    _NeedYourPokemonText = "NEED",
    _PokemonFightingFitText = "FIT",
  } }
  local mon = {
    hp = 1, status = "PSN", stats = { hp = 20 }, moves = {},
  }
  Game[gameSaveKey] = { usedPokecenter = false, party = { mon } }
  local pushed = {}
  local gameStack = { states = pushed }
  Game[gameStackKey] = gameStack
  function gameStack:push(state) self.states[#self.states + 1] = state end
  function gameStack:pop() return table.remove(self.states) end
  function gameStack:top() return self.states[#self.states] end

  local visible = {}
  Follower.setVisible = function(_, value)
    visible[#visible + 1] = value
  end
  local musicStops = 0
  Music.stop = function() musicStops = musicStops + 1 end

  local delayed
  Follower[followerHopKey] = function(_, done) delayed = done end
  local hopStub = Follower[followerHopKey]
  local nativeTextNew = TextBox.new
  local healed = false
  local world = setmetatable({
    map = { id = "VIRIDIAN_POKECENTER" },
    player = { cellX = 4, cellY = 5 },
  }, { __index = OverworldState })
  nurseHeal(world, function() healed = true end, nil)
  T.check(type(delayed) == "function",
    "SKIP CENTER TALK preserves the asynchronous follower hop")
  T.check(Follower[followerHopKey] == hopStub,
    "follower hop method is restored before the asynchronous frame")
  T.check(TextBox.new == nativeTextNew,
    "TextBox.new is restored while the follower hop is pending")
  local preHopPlaceholders = #pushed
  T.check(preHopPlaceholders <= 1,
    "the native nurse path adds at most one inert pre-hop placeholder")
  for _, state in ipairs(pushed) do
    T.check(getmetatable(state) ~= TextBox,
      "the nurse welcome and confirmation are not visible TextBoxes")
  end

  delayed()
  T.check(TextBox.new == nativeTextNew,
    "TextBox.new is restored after the delayed continuation")
  T.eq(mon.hp, 20, "the native Center heal still restores HP")
  T.eq(mon.status, nil, "the native Center heal still clears status")
  T.eq(musicStops, 1, "the native healing sequence still stops map music")
  T.check(world.healAnim ~= nil,
    "the native healing animation still starts")
  T.eq(#pushed, preHopPlaceholders + 1,
    "the suppressed continuation adds only its inert stack placeholder")
  T.check(getmetatable(pushed[#pushed]) ~= TextBox,
    "the delayed nurse preamble is not a visible TextBox")

  world.healAnim.onDone()
  T.eq(healed, true, "post-heal completion still runs")
  T.eq(visible[1], false,
    "the follower is hidden during the native healing animation")
  T.eq(visible[2], true,
    "the follower is restored after the native healing animation")

  -- An exception from the delayed native heal must not strand TextBox.new.
  local failedContinuation
  Follower[followerHopKey] = function(_, done) failedContinuation = done end
  local failingHopStub = Follower[followerHopKey]
  Pokemon.heal = function() error("heal failure", 0) end
  local failingWorld = setmetatable({
    map = { id = "CERULEAN_POKECENTER" },
    player = { cellX = 2, cellY = 3 },
  }, { __index = OverworldState })
  nurseHeal(failingWorld, function() end, nil)
  local continuationOk = pcall(failedContinuation)
  T.check(not continuationOk,
    "the delayed native healing error remains observable")
  T.check(TextBox.new == nativeTextNew,
    "TextBox.new is restored when the delayed continuation errors")
  T.check(Follower[followerHopKey] == failingHopStub,
    "follower hop method stays restored after a delayed error")
  Pokemon.heal = saved.heal

  -- An exception before the hop is scheduled must restore both methods too.
  Follower[followerHopKey] = function() error("hop failure", 0) end
  local throwingHopStub = Follower[followerHopKey]
  local callOk = pcall(nurseHeal, failingWorld,
    function() end, nil)
  T.check(not callOk, "the native follower-hop error remains observable")
  T.check(Follower[followerHopKey] == throwingHopStub,
    "follower hop method is restored when nurseHeal errors")
  T.check(TextBox.new == nativeTextNew,
    "TextBox.new is restored when nurseHeal errors")
end)

Game[gameDataKey], Game[gameSaveKey], Game[gameStackKey] =
  saved.data, saved.save, saved.stack
TextBox.new, Follower[followerHopKey] = saved.textNew, saved.hop
Follower.setVisible, Music.stop, Pokemon.heal = saved.visible,
  saved.musicStop, saved.heal
if nativeGameIndex then
  debug.setupvalue(nativeNurse, nativeGameIndex, nativeGame)
end
if not scenarioOk then error(scenarioErr, 0) end

run.loader.modOptions[MOD_ID] = { skipCenterDialogue = false }
T.check(not exports.skipCenterDialogue.shouldSkip({
    kind = "nurse_heal", generation = 1,
  }), "disabled SKIP CENTER TALK leaves the nurse context unchanged")

run.release()
T.finish("skip_center_dialogue")
