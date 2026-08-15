-- Inventory improvements: search matching, deterministic sorting, quick-use
-- chord routing, and AUTO CATCH ball totals.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local exports = run.loader.exports.qol_suite
local MOD_ID = "qol_suite"

T.eq(#run.errors, 0, "inventory improvements load clean")

local function updateHookCount()
  return #(run.loader.hooks.chains["core.update"] or {})
end
run.loader.modOptions[MOD_ID] = run.loader.modOptions[MOD_ID] or {}
local options = run.loader.modOptions[MOD_ID]
options.quickUseItems = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "quickUseItems", value = false,
})
local idleUpdateHooks = updateHookCount()
T.check(not exports.bagCategories.quickUseSubscribed(),
  "QUICK USE ITEMS has no update hook while disabled")
options.quickUseItems = true
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "quickUseItems", value = true,
})
T.check(exports.bagCategories.quickUseSubscribed(),
  "QUICK USE ITEMS installs its update hook when enabled")
T.eq(updateHookCount(), idleUpdateHooks + 1,
  "enabling QUICK USE ITEMS adds exactly one update hook")
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "quickUseItems", value = true,
})
T.eq(updateHookCount(), idleUpdateHooks + 1,
  "repeating the enabled option event does not duplicate its hook")
options.quickUseItems = false
run.loader.events:emit("mod.options_changed", {
  mod = MOD_ID, key = "quickUseItems", value = false,
})
T.eq(updateHookCount(), idleUpdateHooks,
  "disabling QUICK USE ITEMS removes its update hook")
T.check(not exports.bagCategories.quickUseSubscribed(),
  "QUICK USE ITEMS reports no subscription after a toggle cycle")

local game = {
  data = Data,
  save = {
    bagOrder = { "FIX_TM", "FIX_POTION", "FIX_BALL" },
    inventory = { FIX_TM = 1, FIX_POTION = 2, FIX_BALL = 3 },
  },
}

T.check(exports.bagCategories.matchesSearch(game, "FIX_POTION", "potion"),
  "BAG SEARCH matches an item name")
T.check(exports.bagCategories.matchesSearch(game, "FIX_POTION", "fix_pot"),
  "BAG SEARCH matches a partial item name")
T.check(not exports.bagCategories.matchesSearch(game, "FIX_POTION", "ball"),
  "BAG SEARCH excludes non-matching items")

local sorted = exports.bagCategories.sortOrder(game)
T.eq(sorted[1], "FIX_BALL", "AUTO SORT BAG orders by item name")
T.eq(sorted[2], "FIX_POTION", "AUTO SORT BAG keeps alphabetical order")
T.eq(sorted[3], "FIX_TM", "AUTO SORT BAG sorts all inventory entries")

T.check(exports.bagCategories.matchesQuick("REPEL", "repel"),
  "quick-use Repels include REPEL")
T.check(exports.bagCategories.matchesQuick("POTION", "healing"),
  "quick-use healing items include POTION")
T.check(exports.bagCategories.matchesQuick("TOWN_MAP", "field"),
  "quick-use field items include TOWN MAP")
T.check(not exports.bagCategories.matchesQuick("POKE_BALL", "healing"),
  "quick-use healing items exclude balls")

local pocketGame = {
  data = { items = {
    ESCAPE_ROPE = { pocket = "ITEM" },
    TOWN_MAP = { pocket = "KEY_ITEM" },
  } },
  save = { inventory = { ESCAPE_ROPE = 2, TOWN_MAP = 1 } },
}
T.eq(exports.bagCategories.quickPocket(pocketGame, "field"), "ITEM",
  "Gold field shortcut finds ESCAPE ROPE in the ITEM pocket")
pocketGame.save.inventory.ESCAPE_ROPE = 0
T.eq(exports.bagCategories.quickPocket(pocketGame, "field"), "KEY_ITEM",
  "Gold field shortcut finds rods and tools in the KEY ITEM pocket")
T.eq(exports.bagCategories.quickPocket(pocketGame, "healing"), "ITEM",
  "Gold healing shortcut starts in the ITEM pocket")

local input = { state = { select = true }, pressed = { up = true } }
T.eq(exports.bagCategories.quickCategory(input), "repel",
  "SELECT+UP opens the Repel shortcut")
input.pressed = { left = true }
T.eq(exports.bagCategories.quickCategory(input), "healing",
  "SELECT+LEFT opens the healing shortcut")
input.pressed = { right = true }
T.eq(exports.bagCategories.quickCategory(input), "field",
  "SELECT+RIGHT opens the field-item shortcut")

local goldTop
local goldGame = {
  input = {}, phase = "play", world = { battleActive = false },
  stack = { top = function() return goldTop end },
}
T.check(exports.bagCategories.overworldReady(goldGame),
  "Gold quick-use accepts free roam")
goldTop = { menu = true }
T.check(not exports.bagCategories.overworldReady(goldGame),
  "Gold quick-use rejects an already-open menu")
goldTop = nil
goldGame.world.battleActive = true
T.check(not exports.bagCategories.overworldReady(goldGame),
  "Gold quick-use rejects an active battle")

local counts = exports.autoBattle.ballCounts({ save = { inventory = {
  POKE_BALL = 10, GREAT_BALL = 2, ULTRA_BALL = 1, MASTER_BALL = 0,
} } })
T.eq(counts.total, 13, "AUTO CATCH ball total includes every ball tier")
T.eq(exports.autoBattle.formatBallCounts({ save = { inventory = {
  POKE_BALL = 10, GREAT_BALL = 2, ULTRA_BALL = 1,
} } }), "P10 G2 U1 M0", "AUTO CATCH formats ball counts compactly")

T.finish("inventory_improvements")
