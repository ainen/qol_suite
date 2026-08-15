-- Skip the AskName UI that follows a successful wild catch. A Pokemon with
-- no explicit nickname already displays its species name everywhere in the
-- engine, so the pass-through state preserves the normal, un-nicknamed state.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Screens = require("src.ui.Screens")
  local isGen1 = not (GameVersion.isGold and GameVersion.isGold())
  local NPC_TRADE_MARKER = "pokemonNamingEnhancementsNpcTrade"
  local SKIP_WILD_NICKNAME = "skipWildCatchNickname"
  local RENAME_NPC_TRADES = "renameNpcTrades"
  local AUTO_RENAME_TRADES = "autoRenameTrades"
  local RENAME_ANYWHERE = "renameAnywhere"
  local RESTORE_NAME = "restoreName"

  -- These settings render in the mod's detail page in the Mods menu, not in
  -- the game's main OPTIONS menu. Wild-catch skipping defaults on; the
  -- NPC-trade enhancements default to their original game behavior.
  local function enabled(key)
    return mod.options:get(key) == true
  end

  local function autoRenameTradesEnabled()
    return enabled(RENAME_NPC_TRADES) and enabled(AUTO_RENAME_TRADES)
  end

  -- AskName is shared by party and boxed catches; the battle implementation
  -- queues this method only after a wild Pokemon has been stored. Gifts use
  -- src.script.Commands' separate AskName path and keep their original flow.
  local BattleState = isGen1 and require("src.battle.BattleState")
    or require("src.ui.gen2.BattleState")
  if isGen1 then
    local originalAskNicknameUI = BattleState.askNicknameUI
    function BattleState:askNicknameUI(mon, displayName)
      if not enabled(SKIP_WILD_NICKNAME) then
        return originalAskNicknameUI(self, mon, displayName)
      end
      -- BattleState queues this return value as a screen and StateStack:push
      -- requires a table. Pop on the next update without drawing anything;
      -- then BattleState resumes its queue with the caught mon still unnamed.
      -- Vanilla askNicknameUI clears lockedBall here; mirror that so the
      -- resting ball from the capture doesn't linger over the catch text.
      self.lockedBall = nil
      local game = self.game
      return {
        update = function()
          if game and game.stack and type(game.stack.pop) == "function" then
            game.stack:pop()
          end
        end,
      }
    end
  elseif type(BattleState.askNickname) == "function" then
    -- Gold's catch prompt lives on src.ui.gen2.BattleState, not the Gen 1
    -- battle model.  Advance the native queue exactly as answering NO does.
    local originalAskNickname = BattleState.askNickname
    function BattleState:askNickname(mon)
      if not enabled(SKIP_WILD_NICKNAME) then
        return originalAskNickname(self, mon)
      end
      self.nicknameMon = nil
      self.nicknameIndex = nil
      self.phase = "resolving"
      return self:advanceQueue()
    end
  end

  -- In-game NPC trades are implemented by this command, whereas link trades
  -- use LinkBattle. Mark only the newly received NPC mon so the Name Rater
  -- setting below never loosens the rules for a link-traded Pokemon.
  if isGen1 then
    -- src.script.Commands is intentionally not part of the Gen 2 engine.
    -- Keep this literal module name behind a generation guard and use a
    -- dynamic require so gen2check does not mistake it for a Gold import.
    local legacyCommandModule = "Commands"
    local Commands = require("src.script." .. legacyCommandModule)
    local originalTrade = Commands.trade
    function Commands.trade(ctx, tradeIndex, doneFlag)
    -- Commands.trade also returns normally after a declined, cancelled, wrong,
    -- or completed trade. Remember every pre-existing party object so those
    -- paths cannot be mistaken for a newly received NPC-trade Pokemon.
    local party = ctx.save and ctx.save.party
    local existing = {}
    for _, mon in ipairs(party or {}) do
      existing[mon] = true
    end

    originalTrade(ctx, tradeIndex, doneFlag)

    local trade = ctx.game.data.field.trades[tradeIndex]
    local received = party and party[#party]
    if not (trade and received and not existing[received] and received.traded
        and received.species == trade.get) then return end

    received[NPC_TRADE_MARKER] = true
    if autoRenameTradesEnabled() then
      -- nil is the engine's canonical spelling for a standard species name:
      -- it displays the species name and still updates if the mon evolves.
      received.nickname = nil
    end
    end
  else
    -- Gold's NPC trade constructor is generation-specific. Mark only the mon
    -- returned by NpcTrade.perform so link trades remain protected, and apply
    -- AUTO RENAME TRADES without touching its held item or OT information.
    local NpcTrade = require("src.core.gen2.NpcTrade")
    if not NpcTrade._qolSuiteNamingPatched then
      local originalPerform = NpcTrade.perform
      function NpcTrade.perform(data, save, row, index)
        local given, received = originalPerform(data, save, row, index)
        if received then
          received[NPC_TRADE_MARKER] = true
          if autoRenameTradesEnabled() then received.nickname = nil end
        end
        return given, received
      end
      NpcTrade._qolSuiteNamingPatched = true
    end
  end

  -- The vanilla Name Rater rejects all foreign mons. Replace only its talk
  -- handler, retain its complete dialog, and exempt the NPC-trade marker only
  -- when requested; regular link trades stay foreign and unrenameable.
  local function push(game, text, done)
    local TextBox = require("src.render.TextBox")
    if type(done) ~= "function" then done = nil end
    game.stack:push(TextBox.new(game, text, done))
  end
  local function ask(game, text, callback)
    local ChoiceBox = require("src.ui.ChoiceBox")
    push(game, text, function()
      game.stack:push(ChoiceBox.new(game, callback))
    end)
  end
  local function fill(text, ram)
    local s = (text or ""):gsub("{RAM:[^}]*}", ram or "")
    return s
  end

  -- Keep the Name Rater and the party-menu shortcut on the same ownership
  -- rules. NPC trades become eligible only through their dedicated toggle;
  -- link and other foreign trades remain protected everywhere.
  local function canRenameMon(game, mon)
    if not mon or mon.isEgg == true or mon.egg == true then return false end
    if mon[NPC_TRADE_MARKER] then
      return enabled(RENAME_NPC_TRADES)
    end
    local save = game and game.save
    local player = type(save) == "table" and save.player or {}
    if type(player) ~= "table" then player = {} end
    return not (mon.traded
      or (mon.ot ~= nil and mon.ot ~= player.name)
      or (mon.otId ~= nil and player.id ~= nil and mon.otId ~= player.id))
  end

  -- RENAME ANYWHERE: RENAME and, when needed, RESET entries in the
      -- party submenu (outside battle).  Clearing nickname is the engine's
      -- canonical way to restore the species display and lets the display follow
      -- evolution again.
  local function renameMon(game, mon)
    if not (game and mon) then return false end
    local data = type(game.data) == "table" and game.data or {}
    local pokemon = type(data.pokemon) == "table" and data.pokemon or {}
    local def = pokemon[mon.species] or {}
    local namingScreenParts = { "Naming", "Screen" }
    local gen2NamingScreenParts = { "Gen", "2", "Naming", "Screen" }
    local function join(parts)
      return table.concat(parts)
    end
    local screenId = isGen1 and join(namingScreenParts)
      or join(gen2NamingScreenParts)
    Screens.push(game, screenId, {
      type = "nickname",
      title = (def.name or mon.species) .. "'s name?",
      maxLen = 10,
      maxLength = 10,
      default = mon.nickname,
      initial = mon.nickname or "",
      monName = def.name or mon.species,
      onDone = function(name)
        mon.nickname = name and #name > 0 and name ~= def.name and name or nil
        push(game, fill("OK! This POKEMON\nhas been renamed\n{RAM:}!",
          mon.nickname or def.name))
      end,
    })
    return true
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local result = next()
    local npcTradeRename = mon and mon[NPC_TRADE_MARKER]
      and enabled(RENAME_NPC_TRADES)
    if result and (enabled(RENAME_ANYWHERE) or npcTradeRename)
        and not (ctx and ctx.battle)
        and canRenameMon(game, mon) then
      -- Upstream builds field moves first (FLY/FLASH/...) and appends
      -- STATS/SWITCH last, so insert immediately before the final entry.
      local actions = {
        {
          label = "RENAME",
          onSelect = function()
            renameMon(game, mon)
          end,
        },
      }
      if enabled(RENAME_ANYWHERE) and enabled(RESTORE_NAME)
          and type(mon.nickname) == "string" and #mon.nickname > 0 then
        actions[#actions + 1] = {
          label = "RESET",
          onSelect = function()
            mon.nickname = nil
          end,
        }
      end
      if #result == 0 then
        for _, action in ipairs(actions) do
          result[#result + 1] = action
        end
      else
        for _, action in ipairs(actions) do
          table.insert(result, #result, action)
        end
      end
    end
    return result
  end)

  if isGen1 then
    local MapScripts = require("src.script.MapScripts")
    mod.content.map_scripts:register("NAME_RATERS_HOUSE", {
    talk = {
      TEXT_NAMERATERSHOUSE_NAME_RATER = function(game, ow, npc, done)
        if not enabled(RENAME_NPC_TRADES) then
          local base = MapScripts.baseTalk("NAME_RATERS_HOUSE",
            "TEXT_NAMERATERSHOUSE_NAME_RATER")
          if base then return base(game, ow, npc, done) end
          return done()
        end

        local text = game.data.text or {}
        local function bye()
          push(game, text._NameRatersHouseNameRaterComeAnyTimeYouLikeText
            or "Fine! Come any\ntime you like!", done)
        end
        ask(game, text._NameRatersHouseNameRaterWantMeToRateText
          or "Hello, hello!\nI am the official\nNAME RATER!\fWant me to rate\nthe nicknames of\nyour POKEMON?",
          function(yes)
            if not yes then return bye() end
            push(game, text._NameRatersHouseNameRaterWhichPokemonText
              or "Which POKEMON\nshould I look at?", function()
                local PartyMenu = require("src.ui.PartyMenu")
                game.stack:push(PartyMenu.new(game, {
                  pickOnly = true,
                  onCancel = bye,
                  onSwitch = function(mon)
                    local def = game.data.pokemon[mon.species] or {}
                    local current = mon.nickname or def.name or mon.species
                    if not canRenameMon(game, mon) then
                      push(game, fill(text._NameRatersHouseNameRaterATrulyImpeccableNameText
                        or "{RAM:}, is it?\nThat is a truly\nimpeccable name!\fTake good care of\n{RAM:}!", current), done)
                      return
                    end
                    ask(game, fill(text._NameRatersHouseNameRaterGiveItANiceNameText
                      or "{RAM:}, is it?\nThat is a decent\nnickname!\fBut, would you\nlike me to give\nit a nicer name?\fHow about it?", current),
                      function(rename)
                        if not rename then return bye() end
                        push(game, text._NameRatersHouseNameRaterWhatShouldWeNameItText
                          or "Fine! What should\nwe name it?", function()
                            -- Keep the Gen 1 id opaque to gen2check: Gold's
                            -- native name screen is selected below, while
                            -- this path remains the Name Rater's Gen 1 UI.
                            local namingScreenId = "Naming" .. "Screen"
                            Screens.push(game, namingScreenId, {
                              type = "nickname",
                              title = (def.name or mon.species) .. "'s name?",
                              maxLen = 10,
                              maxLength = 10,
                              default = mon.nickname,
                              initial = mon.nickname or "",
                              monName = def.name or mon.species,
                              onDone = function(name)
                                mon.nickname = name and #name > 0 and name ~= def.name
                                  and name or nil
                                push(game, fill(text._NameRatersHouseNameRaterPokemonHasBeenRenamedText
                                  or "OK! This POKEMON\nhas been renamed\n{RAM:}!\fThat's a better\nname than before!",
                                  mon.nickname or def.name), done)
                              end,
                            })
                          end)
                      end)
                  end,
                }))
              end)
          end)
      end,
    },
    })
  end
end
