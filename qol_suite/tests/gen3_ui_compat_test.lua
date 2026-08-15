-- Compatibility bridge regression test. The external overhaul is optional,
-- so the suite must remain fully native when it is not installed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local run = T.sdk.loadMod("qol_suite", {
  data = T.fixtures.fresh(), root = "..",
})
local compat = run.loader.exports.qol_suite.gen3UICompat

T.eq(#run.errors, 0, "Gen 3 UI compatibility bridge loads clean")
T.check(type(compat) == "table", "Gen 3 UI compatibility helper is exported")
T.check(compat.installed == false,
  "native test fixture does not pretend the optional overhaul is installed")
T.check(not compat.battleUIActive({ stack = { states = {} } }),
  "native battle presentation remains selected without the overhaul")
T.check(compat.option({}, "revampedBattleUI") == true,
  "overhaul battle UI defaults to enabled when its options are unavailable")

local viewport = { width = 1024, height = 768 }
local enemy = compat.enemyGeometry(viewport, {})
T.check(enemy and enemy.scale > 1,
  "compatibility geometry scales the enemy plate on a desktop viewport")
T.check(enemy.x > 0 and enemy.y > 0 and enemy.w > 0 and enemy.h > 0,
  "compatibility geometry keeps the enemy plate in the window")

local moves = compat.moveGeometry(viewport, {})
T.check(moves and moves.x >= 0 and moves.y >= 0,
  "compatibility move geometry stays on-screen")
T.check(moves.x + moves.w <= viewport.width + 1
  and moves.y + moves.h <= viewport.height + 1,
  "compatibility move geometry fits the viewport")

local called = false
T.check(compat.registerBattleOverlay("test", function() called = true end),
  "compatibility bridge accepts post-render overlays")
T.check(not called,
  "optional post-render overlays stay dormant without the external UI")

-- A same-priority overhaul can initialize after QoL Suite. The bridge must
-- discover it lazily instead of permanently committing to the native path.
run.loader.mods.gen3_battle_ui = {
  enabled = true, manifest = { id = "gen3_battle_ui", version = "test" },
}
run.loader.exports.gen3_battle_ui = {}
local externalGame = { save = {}, stack = { states = {} } }
local externalBattle = { game = externalGame }
externalGame.stack.states[1] = externalBattle
run.loader.hooks:call("battle.overlay", function() end, externalBattle)
run.loader.hooks:call("render.hud", function() end, externalGame, viewport)
T.check(compat.installed == true,
  "compatibility bridge discovers a later-loaded external UI")
T.check(called,
  "later-loaded external UI receives registered post-render overlays")

T.finish("gen3_ui_compat")
