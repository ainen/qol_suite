-- BATTLE TEARDOWN regression coverage for NPCs missing after a fast battle.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local run = T.sdk.loadMod("qol_suite", {
  data = T.fixtures.fresh(),
  root = "..",
})
local teardown = run.loader.exports.qol_suite.battleTeardown

T.eq(#run.errors, 0, "battle teardown package load is clean")
T.check(type(teardown) == "table", "battle teardown exports are available")
T.check(type(teardown.restoreWorldEntities) == "function",
  "battle teardown exports the entity-list repair")
T.check(not teardown.updateSubscribed(),
  "battle teardown has no idle core.update hook")

local player = { name = "PLAYER" }
local npcA = { id = "ROUTE_obj_1" }
local npcB = { id = "ROUTE_obj_2" }
local follower = { id = "ROUTE_obj_pika", pikachuFollower = true }
local overworld = {
  isOverworld = true,
  player = player,
  npcs = { npcA, npcB, follower },
  -- The follower and ordinary NPCs are all missing from the draw list. A
  -- battle-return repair must restore the complete actor set.
  entities = { player },
}
local stack = { states = { overworld } }
function stack:top() return self.states[#self.states] end
local game = {
  overworld = overworld,
  stack = stack,
  save = {},
  fixedStep = {
    discarded = false,
    discardCatchup = function(clock) clock.discarded = true end,
  },
}

T.check(teardown.restoreWorldEntities(game),
  "missing ordinary NPC entities are repaired")
T.eq(#overworld.entities, 4,
  "repair keeps the player and restores every NPC, including the follower")
T.check(overworld.entities[2] == npcA,
  "repair keeps ordinary NPC order before the follower")
T.check(overworld.entities[4] == follower,
  "repair restores the Pikachu follower to the draw list")
T.check(not teardown.restoreWorldEntities(game),
  "a consistent entity list is not rebuilt repeatedly")

-- A partially rebuilt current map can lose an ordinary actor from `npcs` as
-- well as from `entities`.  The repair should use the same visible map
-- object and pool path as the engine and should not resurrect hidden objects.
local mapNpc = { id = "ROUTE_obj_3" }
overworld.map = {
  id = "ROUTE",
  def = { objects = { { index = 3 } } },
}
overworld.npcPool = {}
overworld.objectVisible = function() return true end
overworld.pooledNPC = function(pool, data, mapId, object) return mapNpc end
overworld.npcs = { npcA, follower }
overworld.entities = { player }
T.check(teardown.restoreWorldEntities(game),
  "repair restores a visible map NPC missing from both live lists")
T.check(overworld.npcs[3] == mapNpc and overworld.entities[4] == mapNpc,
  "restored map NPC is shared by the update and draw lists")

-- Return to the minimal fixture for the lifecycle assertion below.
overworld.map = nil
overworld.npcPool = nil
overworld.objectVisible = nil
overworld.pooledNPC = nil
overworld.npcs = { npcA, npcB, follower }
overworld.entities = { player }

-- Exercise the event + core.update path as it runs in the live game. The
-- battle is popped before the update returns, while one NPC is absent from
-- the draw list; the post-update repair must restore it once the overworld is
-- back on top.
overworld.entities = { player }
local battle = { isBattle = true, game = game }
stack.states = { overworld, battle }
run.loader.events:emit("battle.ended", { battle = battle })
T.check(game.fixedStep.discarded,
  "battle end discards pending fixed-step catch-up")
T.check(teardown.pending(game) and teardown.updateSubscribed(),
  "battle end installs one pending-only update hook")
stack.states = { overworld }
local result = run.loader.hooks:call("core.update", function() return "updated" end,
  game, 1 / 60)
T.eq(result, "updated", "battle teardown leaves the update result intact")
T.check(teardown.restoreWorldEntities(game) == false,
  "post-battle update leaves ordinary NPCs restored")
T.eq(#overworld.entities, 4,
  "post-battle repair restores NPCs before the next map load")
T.check(not teardown.pending(game) and not teardown.updateSubscribed(),
  "settled RBY teardown clears pending state and removes its update hook")

-- Gold owns the settled overworld as game.world with an empty state stack.
-- Run two complete cycles, including duplicate lifecycle notifications, to
-- guard both readiness and idempotent dynamic hook subscription.
local goldStack = { states = {} }
function goldStack:top() return self.states[#self.states] end
local discarded = 0
local goldGame = {
  phase = "play",
  world = { map = { id = "NEW_BARK_TOWN" }, battleActive = false },
  stack = goldStack,
  fixedStep = {
    discardCatchup = function() discarded = discarded + 1 end,
  },
}
T.check(teardown.overworldReady(goldGame) == goldGame.world,
  "Gold game.world is recognized as a settled overworld")
for cycle = 1, 2 do
  local goldBattle = {
    game = goldGame, battle = {}, submit = function() end,
  }
  goldStack.states = {}
  run.loader.events:emit("screen.popped", { state = goldBattle })
  local updateHooks = #(run.loader.hooks.chains["core.update"] or {})
  run.loader.events:emit("screen.popped", { state = goldBattle })
  T.eq(#(run.loader.hooks.chains["core.update"] or {}), updateHooks,
    "duplicate Gold teardown event does not duplicate the update hook")
  T.check(teardown.pending(goldGame) and teardown.updateSubscribed(),
    "Gold battle cycle " .. cycle .. " leaves cleanup pending")
  run.loader.hooks:call("core.update", function() end, goldGame, 1 / 60)
  T.check(not teardown.pending(goldGame),
    "Gold battle cycle " .. cycle .. " clears pending cleanup")
  T.check(not teardown.updateSubscribed(),
    "Gold battle cycle " .. cycle .. " removes the update hook")
end
T.eq(discarded, 4,
  "each explicit Gold teardown notification discards catch-up safely")

run.release()
T.finish("battle_teardown")
