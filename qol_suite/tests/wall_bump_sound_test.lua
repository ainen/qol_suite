-- WALL BUMP SOUND: the optional Gen 1 wall-collision cue can be disabled
-- without affecting unrelated collision sounds or the default behavior.
-- Run from the gen1recomp checkout:
--   luajit ../qol_suite/tests/wall_bump_sound_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Game = require("src.core.Game")
local Sound = require("src.core.Sound")
local GameVersion = require("src.core.GameVersion")

GameVersion.set("red")
local run = T.sdk.loadMod("qol_suite", {
  data = T.fixtures.fresh(), root = "..",
})
local schema = run.loader.optionSchemas.qol_suite
local byKey = {}
for _, row in ipairs(schema) do byKey[row.key] = row end

local option = byKey.wallCollisionSound
T.check(option ~= nil, "RBY schema exposes WALL BUMP SOUND")
if option then
  T.eq(option.label, "WALL BUMP SOUND", "WALL BUMP SOUND label is clear")
  T.eq(option.type, "toggle", "WALL BUMP SOUND is a toggle")
  T.eq(option.default, true, "WALL BUMP SOUND preserves the native default")
end

local exports = run.loader.exports.qol_suite
T.check(type(exports.wallBumpSound) == "table",
  "WALL BUMP SOUND exports its runtime helper")

-- Use a small isolated feature instance to prove the sound suppression path:
-- a blocked player collision arms one pending cue, and the matching Collision
-- SFX is stopped; unrelated movers and unrelated SFX are left alone.
local values = { wallCollisionSound = false }
local hooks, events = Hooks.new(), Events.new()
local mod = {
  id = "wall_bump_test", hooks = hooks, events = events,
  options = { get = function(_, key) return values[key] end },
}
local player = {}
Game.overworld = { player = player }
local oldStop = Sound.stop
local stopped = {}
Sound.stop = function(name) stopped[#stopped + 1] = name end

local feature = assert(loadfile("../qol_suite/features/wall_bump_sound.lua"))()
feature(mod)
local function collision(allowed, mover, reason)
  return hooks:call("movement.collision", function(value) return value end,
    allowed, { mover = mover, reason = reason or "tile" })
end

collision(false, player)
events:emit("sound.played", { kind = "sfx", name = "Collision" })
T.eq(stopped[1], "Collision",
  "disabled WALL BUMP SOUND stops the matching collision cue")

collision(false, player)
events:emit("sound.played", { kind = "sfx", name = "Press_AB" })
T.eq(#stopped, 1, "disabled WALL BUMP SOUND leaves unrelated SFX alone")

values.wallCollisionSound = true
collision(false, player)
events:emit("sound.played", { kind = "sfx", name = "Collision" })
T.eq(#stopped, 1, "enabled WALL BUMP SOUND preserves the collision cue")

values.wallCollisionSound = false
collision(false, {})
events:emit("sound.played", { kind = "sfx", name = "Collision" })
T.eq(#stopped, 1, "non-player collisions do not consume the wall cue")

Sound.stop = oldStop
Game.overworld = nil
T.finish("wall_bump_sound")
