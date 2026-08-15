-- Pokemon Party Lead: move the selected party Pokemon to slot one without
-- entering the vanilla swap mode.
return function(mod)
  local LABEL = "TO FRONT"
  local OPTION = "toFront"

  local function indexOf(party, mon)
    for i, candidate in ipairs(party) do
      if candidate == mon then return i end
    end
    return nil
  end

  local function setLead(game, mon)
    local party = game and game.save and game.save.party
    if type(party) ~= "table" or not mon then return end

    local selected = indexOf(party, mon)
    if not selected then return end

    if selected > 1 then
      -- Match the vanilla SWITCH flow: the chosen Pokemon exchanges places
      -- with slot one, so every other slot keeps its relative contents.
      party[1], party[selected] = party[selected], party[1]
    end

    -- PartyMenu remembers its cursor between openings.  Keep the live menu
    -- and the next opening aligned with the Pokemon that is now in slot one.
    game.partyMenuSavedIndex = 1
    local stack = game.stack
    local menu = stack and type(stack.top) == "function" and stack:top()
    if menu and menu.game == game and type(menu.index) == "number" then
      menu.index = 1
    end
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local result = next(game, items, mon, ctx)
    if type(result) ~= "table" or mod.options:get(OPTION) ~= true
        or (ctx and ctx.battle) then
      return result
    end

    local party = game and game.save and game.save.party
    if type(party) ~= "table" or indexOf(party, mon) == 1 then
      return result
    end
    for _, entry in ipairs(result) do
      if entry.label == LABEL then return result end
    end

    return mod.ui.insertBefore(result, "SWITCH", {
      label = LABEL,
      onSelect = function(selected, currentGame)
        if mod.options:get(OPTION) == true then
          setLead(currentGame, selected)
        end
      end,
    })
  end)
end
