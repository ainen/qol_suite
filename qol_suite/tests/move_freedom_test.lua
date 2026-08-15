-- SWAP MOVES full-moveset regression test for Red/Blue/Yellow.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("red")
local Data = T.fixtures.fresh()
Data.moves.FIX_POOL = {
  id = "FIX_POOL", name = "FIX POOL", pp = 20,
}

local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
T.eq(#run.errors, 0, "SWAP MOVES package load is clean")
run.loader.modOptions.qol_suite = { swapMoves = true, retainPP = true }

local MoveLearnMenu = require("src.ui.MoveLearnMenu")

local function stack()
  local value = { states = {} }
  function value:push(state) self.states[#self.states + 1] = state end
  function value:pop() return table.remove(self.states) end
  function value:top() return self.states[#self.states] end
  return value
end

local mon = { species = "FIXMON_A", moves = {
  { id = "FIX_TACKLE", pp = 10 },
  { id = "FIX_SCRATCH", pp = 10 },
  { id = "FIX_EMBERISH", pp = 10 },
  { id = "FIX_CUT", pp = 10 },
} }
local game = { data = Data, save = { options = {} }, input = {}, stack = stack() }
function game.input:wasPressed(_) return false end
local completed
local menu = MoveLearnMenu.new(game, mon, "FIX_POOL",
  function(learned) completed = learned end, "Level_Up")
game.stack:push(menu)
menu:enter()

T.eq(#game.stack.states, 2,
  "SWAP MOVES keeps the move screen under its immediate-swap prompt")
local prompt = game.stack:top()
T.check(prompt.choice ~= nil,
  "SWAP MOVES offers an immediate swap choice")
T.check(prompt.pages and prompt.pages[1][1]:find("learned", 1, true),
  "SWAP MOVES explains that the new move was learned")
T.check(prompt.pages[2][1]:find("Swap it in now", 1, true),
  "SWAP MOVES clearly asks whether to swap immediately")
T.eq(#mon.moves, 4,
  "SWAP MOVES leaves the active moveset unchanged")
T.check(mon.knownMoves and mon.knownMoves[#mon.knownMoves] == "FIX_POOL",
  "SWAP MOVES records the new move in the pool")

-- YES closes the prompt and opens the familiar move-slot picker.
game.stack:pop()
prompt.choice(true)
T.check(menu._qolSuitePoolSelecting,
  "SWAP MOVES opens the slot picker after YES")
game.input.wasPressed = function(_, key) return key == "a" end
menu:update(0)
T.eq(mon.moves[1].id, "FIX_POOL",
  "SWAP MOVES immediately equips the selected new move")
T.check(mon.knownMoves and mon.knownMoves[#mon.knownMoves] == "FIX_TACKLE",
  "SWAP MOVES remembers the replaced move")
local resultBox = game.stack:top()
local resultText = ""
for _, page in ipairs(resultBox.pages or {}) do
  for _, line in ipairs(page) do resultText = resultText .. line end
end
T.check(resultText:find("swapped in", 1, true) ~= nil,
  "SWAP MOVES confirms an immediate replacement")
resultBox.done = true
for _ = 1, 5 do resultBox:update(0) end
T.eq(completed, true,
  "SWAP MOVES continues the battle or evolution queue")
T.eq(game.stack:top(), nil,
  "SWAP MOVES closes its temporary result screen")

run.loader.modOptions.qol_suite = { swapMoves = false }
local nativeMon = { species = "FIXMON_A", moves = {
  { id = "FIX_TACKLE", pp = 10 },
  { id = "FIX_SCRATCH", pp = 10 },
  { id = "FIX_EMBERISH", pp = 10 },
  { id = "FIX_CUT", pp = 10 },
} }
local nativeGame = { data = Data, save = { options = {} }, input = {}, stack = stack() }
local nativeMenu = MoveLearnMenu.new(nativeGame, nativeMon, "FIX_POOL")
nativeMenu:enter()
T.check(nativeGame.stack:top().choice ~= nil,
  "disabling SWAP MOVES restores the native replacement prompt")

T.finish("move_freedom")
