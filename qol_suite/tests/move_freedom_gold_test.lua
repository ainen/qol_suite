-- SWAP MOVES full-moveset regression test for Gold.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
if not (GameVersion.VERSIONS and GameVersion.VERSIONS.gold) then
  print("SKIP move_freedom_gold: requires a Gold-enabled engine checkout")
  return
end
GameVersion.set("gold")
local Data = T.fixtures.fresh()
Data.moves.FIX_POOL = {
  id = "FIX_POOL", name = "FIX POOL", pp = 20,
}

local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
T.eq(#run.errors, 0, "Gold SWAP MOVES package load is clean")
run.loader.modOptions.qol_suite = { swapMoves = true, retainPP = true }

local Game2 = require("src.core.Game2")
local mon = { species = "FIXMON_A", moves = {
  { id = "FIX_TACKLE", pp = 10 },
  { id = "FIX_SCRATCH", pp = 10 },
  { id = "FIX_EMBERISH", pp = 10 },
  { id = "FIX_CUT", pp = 10 },
} }
local function stack()
  local value = { states = {} }
  function value:push(state) self.states[#self.states + 1] = state end
  function value:pop() return table.remove(self.states) end
  function value:top() return self.states[#self.states] end
  return value
end
local game = { data = Data, stack = stack() }
function game:say(text, onDone)
  self.learnText = text
  self.learnDone = onDone
  self.stack:push(require("src.render.TextBox").new(self, text, onDone))
end
local completed
Game2.learnMoveOn(game, mon, "FIX_POOL", function(learned)
  completed = learned
end)
T.eq(#mon.moves, 4,
  "Gold SWAP MOVES leaves the active moveset unchanged")
T.check(mon.knownMoves and mon.knownMoves[#mon.knownMoves] == "FIX_POOL",
  "Gold SWAP MOVES records the new move in the pool")
local prompt = game.stack:top()
T.check(prompt.choice ~= nil,
  "Gold SWAP MOVES offers an immediate swap choice")
game.stack:pop()
prompt.choice(true)
local deleter = game.stack:top()
T.check(deleter ~= nil,
  "Gold SWAP MOVES opens the native move-slot picker")
deleter.onChoose(1)
T.eq(mon.moves[1].id, "FIX_POOL",
  "Gold SWAP MOVES immediately equips the selected new move")
T.check(game.learnText and game.learnText:find("swapped in", 1, true),
  "Gold SWAP MOVES confirms an immediate replacement")
local result = game.stack:pop()
result.onDone()
T.eq(completed, true,
  "Gold SWAP MOVES continues the party or evolution queue")

local GoldBattle = require("src.battle.gen2.Battle")
local battle = { data = Data, party = { mon }, events = {} }
GoldBattle.emit(battle, {
  kind = "choose-forget", index = 1,
  move = { id = "FIX_POOL" }, moveName = "FIX POOL",
})
T.eq(battle.events[1].kind, "choose-forget",
  "Gold battle level-up keeps the native immediate-swap prompt")
T.check(battle.events[1].qolPoolLearn == true,
  "Gold battle level-up marks the prompt for SWAP MOVES")

T.finish("move_freedom_gold")
