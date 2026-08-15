-- Legends Z-A style move freedom: from the party menu (outside battle) a
-- Pokemon's four moves can be rearranged freely, choosing from every move
-- it has unlocked up to its current level.  Moves that leave the moveset
-- keep their remaining PP (and PP UPs) in a per-Pokemon table that travels
-- with the mon through saves and boxes; swapping them back restores it.
--
-- The unlocked pool is the union of two sources.  The whole *current*
-- species learnset up to the mon's level -- including its level-1 starting
-- moves, which live in level1Moves -- is always available (the Z-A
-- "level-up unlocks" behavior).  On top of that, every move the Pokemon
-- has ever known is recorded persistently on the mon (a plain-table field
-- that rides through saves and boxes), so a move it used before it
-- evolved -- or one taught by TM/egg/event rather than level -- stays
-- swappable forever, exactly like Z-A's remembered pool.  The record is
-- rebuilt from the current moveset every time the pool is built and fed
-- by the engine's pokemon.move_learned event, so it is self-healing.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Runtime = require("src.mods.Runtime")
  local Strings = require("src.core.Strings")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true
  local SWAP_MOVES = "swapMoves"
  local RETAIN_PP = "retainPP"

  -- These settings render in the mod's detail page in the Mods menu, not
  -- in the game's main OPTIONS menu.  KEEP MOVE PP (default on) carries the
  -- outgoing move's remaining PP over to the incoming move as a fraction of
  -- its own max, so swapping a battered move for a fresh one cannot refresh
  -- PP for free in caves or gyms.
  local function enabled(key)
    return mod.options:get(key) == true
  end

  local function ppUpsCount(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return 0 end
    return math.max(0, math.min(3, math.floor(value)))
  end

  local function maxPP(def, ups)
    local base = tonumber(def and def.pp)
    if not base or base ~= base or base < 0 or base == math.huge then return 0 end
    base = math.floor(base)
    return base + ppUpsCount(ups) * math.floor(base / 5)
  end

  -- A per-Pokemon record of every move it has ever known, kept as a plain
  -- field on the mon object so it rides through saves and boxes with it.
  -- Grows three ways: when the pool is built (anything currently equipped
  -- is remembered), when the engine reports pokemon.move_learned, and when
  -- a move is swapped out.  This is what keeps formerly-known moves --
  -- pre-evolution, TM/egg/event learns, or simply forgotten ones -- forever
  -- swappable, matching Z-A's remembered pool.
  local function recordKnown(mon, moveId)
    if not (mon and moveId) then return end
    if type(mon.knownMoves) ~= "table" then mon.knownMoves = {} end
    for _, known in ipairs(mon.knownMoves) do
      if known == moveId then return end
    end
    mon.knownMoves[#mon.knownMoves + 1] = moveId
  end

  -- Remember everything the mon currently has equipped.
  local function recordEquipped(mon)
    for _, mv in ipairs(mon.moves or {}) do
      if mv and mv.id then recordKnown(mon, mv.id) end
    end
  end

  -- Keep the same record when the engine's full-moveset learn screen
  -- replaces a move.  The normal screen writes the new move directly into
  -- the selected slot, so without this step the outgoing move would vanish
  -- before the swap pool gets a chance to see it.
  local function rememberRemovedMove(mon, move)
    if not (mon and move and move.id) then return end
    if type(mon.masterPP) ~= "table" then mon.masterPP = {} end
    mon.masterPP[move.id] = {
      pp = move.pp or 0,
      ppUps = ppUpsCount(move.ppUps),
    }
    recordKnown(mon, move.id)
  end

  local function monName(game, mon)
    if mon.nickname then return mon.nickname end
    local species = game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    return (species and species.name) or mon.name or mon.species or "?"
  end

  local function moveName(game, moveId)
    local move = game and game.data and game.data.moves
      and game.data.moves[moveId]
    return (move and move.name) or moveId or "?"
  end

  local function poolLearnPromptText(game, mon, moveId)
    return Strings("%s learned\n%s!\fSwap it in now?",
      monName(game, mon), moveName(game, moveId))
  end

  local function poolSwapText(game, mon, moveId)
    return Strings("%s swapped in\n%s!", monName(game, mon),
      moveName(game, moveId))
  end

  local function rememberPoolLearn(game, mon, moveId)
    recordKnown(mon, moveId)
    -- Keep the normal mod event contract alive for other features/mods even
    -- though the move is intentionally not inserted into mon.moves here.
    Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
  end

  -- Ordered pool of every move the mon can swap in: the current species'
  -- starting moves, its learnset at or below its level, then the persistent
  -- record of every move it has ever known, then moves previously swapped
  -- out whose PP record keeps them usable.  The record re-reads the equipped
  -- moveset every time, so it is self-healing for anything learned before
  -- install.
  local function learnedMoves(game, mon)
    if not (game and game.data and game.data.pokemon and mon) then return {} end
    recordEquipped(mon)
    local def = game.data.pokemon[mon.species] or {}
    local pool, seen = {}, {}
    -- starting moves (the base-stats level-1 list) are unlocked for any
    -- mon of this species, even when the ROM's learnset table omits them
    -- (e.g. Yellow's starter Pikachu knows Growl, which only lives here)
    for _, moveId in ipairs(def.level1Moves or {}) do
      if moveId and not seen[moveId] then
        seen[moveId] = true
        pool[#pool + 1] = moveId
      end
    end
    -- Red/Yellow call this table learnset; Gold's extractor keeps the same
    -- rows under levelMoves.  The row shape is shared, so the rest of the
    -- swap UI can remain generation-neutral.
    for _, entry in ipairs(def.learnset or def.levelMoves or {}) do
      if tonumber(entry.level) and tonumber(mon.level)
          and tonumber(entry.level) <= tonumber(mon.level)
          and entry.move and not seen[entry.move] then
        seen[entry.move] = true
        pool[#pool + 1] = entry.move
      end
    end
    for _, moveId in ipairs(mon.knownMoves or {}) do
      if not seen[moveId] then
        seen[moveId] = true
        pool[#pool + 1] = moveId
      end
    end
    for moveId in pairs(type(mon.masterPP) == "table" and mon.masterPP or {}) do
      if not seen[moveId] then
        seen[moveId] = true
        pool[#pool + 1] = moveId
      end
    end
    return pool
  end

  -- Swap the move in mon.moves[slotIndex] for moveId (or fill an empty
  -- slot).  The outgoing move's remaining PP and PP UPs are recorded on the
  -- mon.  With the KEEP MOVE PP toggle on (default), the incoming move starts
  -- with the same fraction of its own max PP the outgoing move had
  -- remaining, so a swap cannot refill a drained move for free; with it
  -- off, the incoming move restores the absolute PP it had when last
  -- swapped out (or its full PP when new).  Picking a move that is already
  -- equipped in an occupied slot reorders the two slots in place; Picking
  -- an already known move for an empty slot is refused.
  local function swapMove(game, mon, slotIndex, moveId)
    local moves = game and game.data and game.data.moves
    local mdef = moves and moves[moveId]
    if type(mon) ~= "table" or not mdef
        or type(slotIndex) ~= "number" or slotIndex ~= slotIndex
        or slotIndex ~= math.floor(slotIndex) or slotIndex < 1 or slotIndex > 4
        or type(mon.moves) ~= "table" then
      return false
    end
    local slot = mon.moves[slotIndex]
    if slot and slot.id == moveId then return false end
    -- Where else is the picked move equipped?
    local other
    for i, mv in ipairs(mon.moves) do
      if i ~= slotIndex and mv and mv.id == moveId then other = i end
    end
    if other and slot then
      -- Reorder: exchange the two occupied slots in place, each move
      -- keeping its current PP.
      mon.moves[slotIndex], mon.moves[other] = mon.moves[other], mon.moves[slotIndex]
      return true
    end
    -- An already-equipped move cannot be duplicated into an empty slot
    -- (that would leave a hole behind), so refuse picks already known.
    if other then return false end
    -- Replace (or fill an empty) slot.  The outgoing move's remaining PP
    -- and PP UPs are recorded on the mon, and the incoming move restores
    -- the PP it had when last swapped out (or its full PP when new).
    if type(mon.masterPP) ~= "table" then mon.masterPP = {} end
    if slot and slot.id then
      rememberRemovedMove(mon, slot)
    end
    recordKnown(mon, moveId)
    local rec = mon.masterPP[moveId]
    -- KEEP MOVE PP (default on): when a slot is replaced, the incoming move
    -- starts with the same *fraction* of its max PP that the outgoing move
    -- had remaining, so a swap cannot refill PP for free (moves with
    -- different max PP stay proportional).  Off, the incoming move simply
    -- restores the PP it had when last swapped out (or full PP when new).
    local pp, ppUps
    if enabled(RETAIN_PP) and slot and slot.id then
      local outDef = moves[slot.id]
      local outMax = tonumber(slot.maxPp)
      if not outMax or outMax ~= outMax or outMax <= 0
          or outMax == math.huge then
        outMax = maxPP(outDef, slot.ppUps)
      end
      local ppUpsIn = rec and ppUpsCount(rec.ppUps) or 0
      local inMax = maxPP(mdef, ppUpsIn)
      local outgoing = tonumber(slot.pp) or 0
      if outgoing ~= outgoing or outgoing == math.huge
          or outgoing == -math.huge then outgoing = 0 end
      pp = outMax > 0 and math.floor(inMax * (outgoing / outMax)) or 0
      if pp > inMax then pp = inMax end
      if pp < 0 or pp ~= pp then pp = 0 end
      ppUps = ppUpsIn
    elseif rec then
      ppUps = ppUpsCount(rec.ppUps)
      local inMax = maxPP(mdef, ppUps)
      pp = tonumber(rec.pp) or 0
      if pp ~= pp then pp = 0 end
      pp = math.max(0, math.min(inMax, math.floor(pp)))
    else
      pp = maxPP(mdef, 0)
      ppUps = 0
    end
    local next = { id = moveId, pp = pp, maxPp = maxPP(mdef, ppUps) }
    if ppUps > 0 then next.ppUps = ppUps end
    -- Fill an empty slot at the first gap (or append): the moveset is a
    -- dense array -- every engine consumer iterates it with ipairs -- so
    -- writing at an arbitrary empty index past a gap would strand the new
    -- move where nothing can see it.
    local placed = slotIndex
    if not slot then
      local i = 1
      while mon.moves[i] do i = i + 1 end
      placed = i
    end
    mon.moves[placed] = next
    return true, placed
  end

  -- The swap screen: top box lists the four equipped slots (name + PP,
  -- cursor-select), the middle box lists the available learned pool
  -- (scrollable), and the bottom box carries a one-line hint.  A moves
  -- between the slot and the pool, B walks back one phase and closes.
  local MoveSwapMenu = {}
  MoveSwapMenu.__index = MoveSwapMenu

  local CURSOR = 0xED
  local VISIBLE = 4

  function MoveSwapMenu.new(game, mon)
    local self = setmetatable({}, MoveSwapMenu)
    self.game = game
    self.mon = mon
    self.slotIndex = 1
    self.poolIndex = 1
    self.scroll = 1
    self.phase = "slots" -- "slots" picks a slot, "pool" picks a learned move
    return self
  end

  function MoveSwapMenu:poolMoves()
    return learnedMoves(self.game, self.mon)
  end

  -- keep the selected pool row on screen
  function MoveSwapMenu:scrollIndex()
    local top = self.scroll
    if self.poolIndex < top then top = self.poolIndex end
    if self.poolIndex > top + VISIBLE - 1 then top = self.poolIndex - VISIBLE + 1 end
    if top < 1 then top = 1 end
    self.scroll = top
    return top
  end

  function MoveSwapMenu:update(dt)
    local input = self.game.input
    if self.phase == "slots" then
      if input:wasPressed("up") then
        self.slotIndex = self.slotIndex > 1 and self.slotIndex - 1 or 4
      elseif input:wasPressed("down") then
        self.slotIndex = self.slotIndex < 4 and self.slotIndex + 1 or 1
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      elseif input:wasPressed("a") then
        self.phase = "pool"
        self.poolIndex = 1
        self.scroll = 1
      end
      return
    end
    local pool = self:poolMoves()
    local n = #pool
    if input:wasPressed("up") then
      self.poolIndex = self.poolIndex > 1 and self.poolIndex - 1 or math.max(n, 1)
    elseif input:wasPressed("down") then
      self.poolIndex = self.poolIndex < n and self.poolIndex + 1 or 1
    elseif input:wasPressed("b") then
      self.phase = "slots"
    elseif input:wasPressed("a") then
      local moveId = pool[self.poolIndex]
      if moveId then
        local ok, placed = swapMove(self.game, self.mon, self.slotIndex, moveId)
        if ok then
          if placed then self.slotIndex = placed end
          self.phase = "slots"
        end
      end
    end
  end

  function MoveSwapMenu:draw()
    local Font = mod.ui.Font
    local data = self.game.data
    local mon = self.mon
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawBox(0, 0, 20, 10)
    Font.drawBox(0, 10, 20, 6)
    Font.drawBox(0, 15, 20, 3)
    -- equipped slots: two 8px rows each (name, then PP), rows 1..8 inside
    -- the (0,0,20,10) box so the bottom border stays clear
    for i = 1, 4 do
      local y = 8 + (i - 1) * 16
      local mv = mon.moves[i]
      if mv and mv.id then
        local mdef = data.moves[mv.id]
        Font.draw(mdef and mdef.name or mv.id, 16, y)
        if mdef then
          Font.draw("PP " .. math.floor(mv.pp or 0) .. "/"
            .. maxPP(mdef, mv.ppUps), 16, y + 8)
        end
      else
        Font.draw("-", 16, y)
      end
      if self.phase == "slots" and i == self.slotIndex then
        Font.drawCode(CURSOR, 8, y)
      end
    end
    -- available learned pool, five visible rows, scrollable
    local pool = self:poolMoves()
    local top = self:scrollIndex()
    for r = 1, VISIBLE do
      local moveId = pool[top + r - 1]
      if not moveId then break end
      local y = 88 + (r - 1) * 8
      local mdef = data.moves[moveId]
      Font.draw(mdef and mdef.name or moveId, 16, y)
      if self.phase == "pool" and top + r - 1 == self.poolIndex then
        Font.drawCode(CURSOR, 8, y)
      end
    end
    -- one-line hint
    local hint
    if self.phase == "slots" then
      hint = "A choose  B close"
    elseif #pool == 0 then
      hint = "No moves to swap."
    else
      hint = "A swap  B cancel"
    end
    Font.draw(hint, 8, 128)
  end

  mod.content.screens:register("MoveSwapMenu", {
    new = function(game, mon)
      return MoveSwapMenu.new(game, mon)
    end,
  })

  -- A MOVES entry in the party submenu (outside battle only) opens the
  -- swap screen for the highlighted Pokemon.
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local result = next()
    if result and enabled(SWAP_MOVES) and not (ctx and ctx.battle) then
      mod.ui.insertBefore(result, "SWITCH", {
        label = "MOVES",
        onSelect = function()
          mod.ui.push(game, "MoveSwapMenu", mon)
        end,
      })
    end
    return result
  end)

  -- A heal (Pokemon Center nurse, blackout rescue, or post-game rescue)
  -- restores the equipped moveset through Pokemon.heal; moves resting in
  -- the swap pool keep their PP in mon.masterPP outside the moveset, so
  -- top those records back up to full the same way.  Every heal site in
  -- the engine funnels through Pokemon.heal, so one patch covers them all.
  local function restoreStoredPP(mon, moves)
    if not (mon and type(mon.masterPP) == "table"
        and type(moves) == "table") then return end
    for moveId, rec in pairs(mon.masterPP) do
      local mdef = moves[moveId]
      if mdef and type(rec) == "table" then
        rec.pp = maxPP(mdef, rec.ppUps)
      end
    end
  end

  local Pokemon = require("src.pokemon.Pokemon")
  local originalHeal = Pokemon.heal
  function Pokemon.heal(mon)
    originalHeal(mon)
    local moves = require("src.core.Data").moves
    restoreStoredPP(mon, moves)
  end

  -- Gold heals through World:healParty rather than Pokemon.heal. Refill the
  -- remembered (currently unequipped) moves after that native party pass too.
  if isGold then
    local GoldWorld = require("src.world.gen2.World")
    if not GoldWorld._qolSuiteMovePoolHealPatched then
      local originalHealParty = GoldWorld.healParty
      function GoldWorld:healParty(...)
        local result = originalHealParty(self, ...)
        local game = self and self.game
        local party = game and game.save and game.save.party
        local moves = game and game.data and game.data.moves
        if type(party) == "table" then
          for _, mon in ipairs(party) do restoreStoredPP(mon, moves) end
        end
        return result
      end
      GoldWorld._qolSuiteMovePoolHealPatched = true
    end
  end

  -- MoveLearnMenu is an engine screen rather than a content registry entry.
  -- With SWAP MOVES enabled, a full moveset takes the new move into the pool
  -- immediately and offers an optional immediate swap. Saying NO keeps all
  -- four active moves unchanged; saying YES opens the familiar move-slot
  -- picker. With the toggle off, the original screen and native text remain
  -- untouched.
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  if not MoveLearnMenu._qolSuiteMoveFreedomPatchedV2 then
    local originalEnter = MoveLearnMenu.enter
    local originalUpdate = MoveLearnMenu.update
    local originalFinish = MoveLearnMenu.finish
    local originalDraw = MoveLearnMenu.draw

    local function copyMoves(moves)
      local copy = {}
      for i, move in ipairs(moves or {}) do
        if move then
          copy[i] = {
            id = move.id,
            pp = move.pp,
            ppUps = move.ppUps,
          }
        end
      end
      return copy
    end

    local function finishPoolKeep(self)
      self.selecting = false
      self._qolSuitePoolSelecting = false
      local game = self.game
      if game.stack:top() == self then game.stack:pop() end
      if self.onDone then self.onDone(true) end
    end

    local function finishPoolSwap(self)
      self.selecting = false
      self._qolSuitePoolSelecting = false
      local game = self.game
      if game.stack:top() == self then game.stack:pop() end
      game.stack:push(require("src.render.TextBox").new(
        game, poolSwapText(game, self.mon, self.newMoveId), function()
          if self.onDone then self.onDone(true) end
        end,
        { auto = { sound = function()
          return require("src.core.Sound").play(game.data, self.learnedSound)
        end } }))
    end

    local function updatePoolSelection(self)
      local input = self.game.input
      local count = #self.mon.moves
      local cancel = count + 1
      if input:wasPressed("up") then
        self.index = self.index > 1 and self.index - 1 or cancel
      elseif input:wasPressed("down") then
        self.index = self.index < cancel and self.index + 1 or 1
      elseif input:wasPressed("b") then
        finishPoolKeep(self)
      elseif input:wasPressed("a") then
        if self.index == cancel then return finishPoolKeep(self) end
        local old = self.mon.moves[self.index]
        if not old then return finishPoolKeep(self) end
        local hm = {
          CUT = true, FLY = true, SURF = true, STRENGTH = true,
          FLASH = true, WHIRLPOOL = true, WATERFALL = true,
          ROCK_SMASH = true,
        }
        if hm[old.id] then
          self.game.stack:push(require("src.render.TextBox").new(
            self.game, Strings("HM moves stay\nequipped.")))
          return
        end
        if swapMove(self.game, self.mon, self.index, self.newMoveId) then
          return self:finish(true)
        end
      end
    end

    local function learnToPool(self)
      local game = self.game
      local mon = self.mon
      local moveId = self.newMoveId
      local mdef = game and game.data and game.data.moves
        and game.data.moves[moveId]
      if not (game and mon and mdef and game.stack) then
        return originalEnter(self)
      end

      rememberPoolLearn(game, mon, moveId)
      self.selecting = false
      self._qolSuitePoolPrompt = true
      local prompt = require("src.render.TextBox").new(
        game, poolLearnPromptText(game, mon, moveId), nil, {
          choice = function(yes)
            self._qolSuitePoolPrompt = false
            if yes then
              self.selecting = true
              self._qolSuitePoolSelecting = true
              self.index = 1
            else
              finishPoolKeep(self)
            end
          end,
        })
      prompt._qolSuiteMovePoolPrompt = true
      game.stack:push(prompt)
    end

    function MoveLearnMenu:enter()
      if enabled(SWAP_MOVES) and self.mon
          and type(self.mon.moves) == "table" and #self.mon.moves >= 4 then
        return learnToPool(self)
      end
      return originalEnter(self)
    end

    function MoveLearnMenu:update(dt)
      self._pokemonMoveFreedomMovesBefore = copyMoves(self.mon and self.mon.moves)
      if self._qolSuitePoolSelecting then
        return updatePoolSelection(self)
      end
      return originalUpdate(self, dt)
    end

    function MoveLearnMenu:finish(learned)
      if self._qolSuitePoolSelecting and learned then
        return finishPoolSwap(self)
      end
      if learned then
        local before = self._pokemonMoveFreedomMovesBefore
        local index = self.index
        local old = before and before[index]
        local current = self.mon and self.mon.moves and self.mon.moves[index]
        if old and current and old.id ~= current.id
            and current.id == self.newMoveId then
          rememberRemovedMove(self.mon, old)
          recordKnown(self.mon, current.id)
        end
      end
      return originalFinish(self, learned)
    end

    function MoveLearnMenu:draw()
      originalDraw(self)
      if not self._qolSuitePoolSelecting then return end
      local Font = require("src.render.Font")
      love.graphics.setColor(0, 0, 0, 1)
      Font.drawBox(0, 12, 20, 6)
      Font.draw(Strings("Swap in for which?"), 8, 14 * 8)
      Font.draw(Strings("B keeps current."), 8, 16 * 8)
      love.graphics.setColor(1, 1, 1, 1)
    end

    MoveLearnMenu._qolSuiteMoveFreedomPatchedV2 = true
  end

  -- Gold's party/evolution/TM path owns its full-moveset prompt in Game2,
  -- while its battle experience path emits choose-forget events to the Gold
  -- BattleState. Intercept both at their shared boundaries so Gold receives
  -- the same pool-first behavior as the Gen 1 MoveLearnMenu.
  if isGold then
    local Game2 = require("src.core.Game2")
    if not Game2._qolSuiteMoveFreedomPatchedV2 then
      local originalLearnMoveOn = Game2.learnMoveOn
      function Game2:learnMoveOn(mon, moveId, onDone)
        local unique = true
        for _, move in ipairs(mon and mon.moves or {}) do
          if move and move.id == moveId then unique = false break end
        end
        if enabled(SWAP_MOVES) and unique and mon
            and type(mon.moves) == "table" and #mon.moves >= 4
            and self.data.moves[moveId] then
          rememberPoolLearn(self, mon, moveId)
          local Screens = require("src.ui.Screens")
          local TextBox = require("src.render.TextBox")
          local hm = {
            CUT = true, FLY = true, SURF = true, STRENGTH = true,
            FLASH = true, WHIRLPOOL = true, WATERFALL = true,
            ROCK_SMASH = true,
          }
          local finishKeep = function()
            if onDone then onDone(true) end
          end
          local pushList
          pushList = function()
            Screens.push(self, "Gen2MoveDeleter", {
              mon = mon, moves = self.data.moves,
              onCancel = function()
                self.stack:pop()
                finishKeep()
              end,
              onChoose = function(slot)
                self.stack:pop()
                local old = mon.moves[slot]
                if old and hm[old.id] then
                  return self:say("HM moves stay\nequipped.", pushList)
                end
                if swapMove(self, mon, slot, moveId) then
                  return self:say(poolSwapText(self, mon, moveId), finishKeep)
                end
                finishKeep()
              end,
            })
          end
          local prompt = TextBox.new(self,
            poolLearnPromptText(self, mon, moveId), nil, {
              choice = function(yes)
                if yes then return pushList() end
                finishKeep()
              end,
            })
          prompt._qolSuiteMovePoolPrompt = true
          return self.stack:push(prompt)
        end
        return originalLearnMoveOn(self, mon, moveId, onDone)
      end
      Game2._qolSuiteMoveFreedomPatchedV2 = true
    end

    local GoldBattle = require("src.battle.gen2.Battle")
    if not GoldBattle._qolSuiteMoveFreedomPatchedV2 then
      local originalEmit = GoldBattle.emit
      function GoldBattle:emit(event)
        if enabled(SWAP_MOVES) and event and event.kind == "choose-forget"
            and event.move and event.move.id then
          local mon = self.party and self.party[event.index]
          if mon then
            rememberPoolLearn(self, mon, event.move.id)
            return originalEmit(self, {
              kind = "choose-forget",
              index = event.index, move = event.move,
              moveName = event.moveName, qolPoolLearn = true,
            })
          end
        end
        return originalEmit(self, event)
      end
      GoldBattle._qolSuiteMoveFreedomPatchedV2 = true
    end

    -- Gold battle level-ups use BattleState's event-driven replacement flow,
    -- not Game2:learnMoveOn. Reuse its native prompt and move-list phases,
    -- but give NO the pool-only behavior and make YES perform an immediate
    -- SWAP MOVES replacement.
    local GoldBattleState = require("src.ui.gen2.BattleState")
    if not GoldBattleState._qolSuiteMoveFreedomBattlePatchedV1 then
      local originalAskForget = GoldBattleState.askForget
      local originalAnswerForget = GoldBattleState.answerForgetPrompt
      local originalUpdate = GoldBattleState.update

      local function finishGoldPoolKeep(state)
        local learn = state.pendingLearn
        -- The native battle learn routine still needs its decline arm to run
        -- so it can emit the normal continuation events.  The move remains
        -- available through SWAP MOVES because it was recorded before this
        -- cleanup; this only tells the battle queue that no active slot was
        -- changed.
        if learn and state.battle
            and type(state.battle.declineForget) == "function" then
          state.battle:declineForget(learn.index, learn.moveName)
        end
        state.pendingLearn = nil
        state.qolPoolPrompt = nil
        state.qolPoolSelecting = nil
        state.phase = "resolving"
        state:pushAll(state.battle:takeEvents())
        state:advanceQueue()
      end

      local function updateGoldPoolSelection(state, input)
        if state.messageTimer > 0 then
          if input:wasPressed("a") or input:wasPressed("b") then
            state.messageTimer = 0
          end
          return
        end
        local learn = state.pendingLearn
        local mon = learn and state.battle and state.battle.party[learn.index]
        local moves = (mon and mon.moves) or {}
        if input:wasPressed("up") then
          state.forgetIndex = state.forgetIndex > 1
            and state.forgetIndex - 1 or #moves
        elseif input:wasPressed("down") then
          state.forgetIndex = state.forgetIndex < #moves
            and state.forgetIndex + 1 or 1
        elseif input:wasPressed("b") then
          return finishGoldPoolKeep(state)
        elseif input:wasPressed("a") then
          local slot = moves[state.forgetIndex]
          if not (learn and mon and slot) then
            return finishGoldPoolKeep(state)
          end
          local hm = {
            CUT = true, FLY = true, SURF = true, STRENGTH = true,
            FLASH = true, WHIRLPOOL = true, WATERFALL = true,
            ROCK_SMASH = true,
          }
          if hm[slot.id] then
            state.message = "HM moves stay\nequipped."
            state.messageTimer = 48
            state.forgetIndex = 1
            return
          end
          if not swapMove(state.game, mon, state.forgetIndex, learn.move.id) then
            return finishGoldPoolKeep(state)
          end
          state.pendingLearn = nil
          state.qolPoolPrompt = nil
          state.qolPoolSelecting = nil
          state.phase = "resolving"
          state:push({ kind = "message",
            text = poolSwapText(state.game, mon, learn.move.id) })
          state:advanceQueue()
        end
      end

      -- AUTO BATTLE uses this explicit keep action so it can dismiss the
      -- optional immediate-swap prompt without depending on the visible
      -- message page or a physical button press.
      GoldBattleState.qolPoolKeep = finishGoldPoolKeep

      function GoldBattleState:askForget()
        local learn = self.pendingLearn
        if learn and learn.qolPoolLearn then
          local mon = self.battle and self.battle.party[learn.index]
          self.forgetChoice = 1
          self.qolPoolPrompt = true
          self:showPages(poolLearnPromptText(self.game, mon, learn.move.id))
          self.phase = self.messagePages and "learn-intro" or "ask-forget"
          return
        end
        return originalAskForget(self)
      end

      function GoldBattleState:answerForgetPrompt(yes)
        if self.qolPoolPrompt then
          if not yes then return finishGoldPoolKeep(self) end
          self.qolPoolPrompt = false
          self.qolPoolSelecting = true
          self.forgetIndex = 1
          self.phase = "choose-forget"
          self.message = nil
          self.messageTimer = 0
          return
        end
        return originalAnswerForget(self, yes)
      end

      function GoldBattleState:update(dt)
        if self.qolPoolSelecting and self.phase == "choose-forget" then
          return updateGoldPoolSelection(self, self.game.input)
        end
        return originalUpdate(self, dt)
      end

      GoldBattleState._qolSuiteMoveFreedomBattlePatchedV1 = true
    end
  end

  -- Remember every move the engine reports as learned so the pool keeps
  -- growing as the Pokemon levels up (the record also self-heals from the
  -- equipped moveset at pool-build time, so this is belt and braces).
  mod.events:on("pokemon.move_learned", function(event)
    if event and event.mon then recordKnown(event.mon, event.moveId) end
  end)

  mod.exports = {
    learnedMoves = learnedMoves,
    swapMove = swapMove,
    restoreStoredPP = restoreStoredPP,
    maxPP = maxPP,
  }
end
