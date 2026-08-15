-- QoL Suite inventory improvements.
--
-- Gen 1's bag is a single native ListMenu; Gold's bag is the native pocketed
-- PackMenu.  Both wrappers leave item effects, party targeting, tossing,
-- registration, and battle use in the engine.  They only narrow/reorder the
-- rows before the native menu acts on them.
return function(mod)
  local BAG_CATEGORIES = "bagCategories"
  local BAG_SEARCH = "bagSearch"
  local BAG_AUTO_SORT = "bagAutoSort"
  local QUICK_USE_ITEMS = "quickUseItems"

  local Bag = require("src.inventory.Bag")
  local ItemEffects = require("src.inventory.ItemEffects")
  local OriginalBagMenu = require("src.ui.BagMenu")
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")

  local originalOrder = Bag.order
  local activeBag

  local categories = {
    { key = "balls", label = "BALLS",
      filter = function(id) return ItemEffects.isBall(id) end },
    { key = "tmhm", label = "TM/HM",
      filter = function(_, def) return def and def.machine ~= nil end },
    { key = "key", label = "KEY ITEMS",
      filter = function(_, def) return def and def.keyItem end },
    { key = "all", label = "ITEMS", filter = function() return true end },
  }

  -- These are the field-use families exposed by the shortcut chords.  The
  -- engine remains responsible for deciding whether a selected item works in
  -- the current place and for choosing a party target when one is needed.
  local QUICK_FILTERS = {
    repel = {
      REPEL = true, SUPER_REPEL = true, MAX_REPEL = true,
    },
    healing = {
      POTION = true, SUPER_POTION = true, HYPER_POTION = true,
      MAX_POTION = true, FULL_RESTORE = true, REVIVE = true,
      MAX_REVIVE = true, FRESH_WATER = true, SODA_POP = true,
      LEMONADE = true, ANTIDOTE = true, BURN_HEAL = true,
      ICE_HEAL = true, AWAKENING = true, PARLYZ_HEAL = true,
      FULL_HEAL = true, ETHER = true, MAX_ETHER = true,
      ELIXER = true, MAX_ELIXER = true, PP_UP = true,
    },
    field = {
      BICYCLE = true, ESCAPE_ROPE = true, TOWN_MAP = true,
      ITEMFINDER = true, POKE_FLUTE = true, OLD_ROD = true,
      GOOD_ROD = true, SUPER_ROD = true, COIN_CASE = true,
    },
  }

  local function option(key)
    return mod.options:get(key) == true
  end

  local quickUseEnabled = option(QUICK_USE_ITEMS)
  local syncQuickUseHook
  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and event.key == QUICK_USE_ITEMS then
      quickUseEnabled = event.value == true
      if syncQuickUseHook then syncQuickUseHook() end
    end
  end)

  local function itemName(game, id, def)
    def = def or (game and game.data and game.data.items
      and game.data.items[id])
    return (def and def.name) or tostring(id):gsub("_", " ")
  end

  local function normalized(value)
    return tostring(value or ""):upper():gsub("[^A-Z0-9 ]", "")
  end

  local function matchesSearch(game, id, query, def)
    query = normalized(query)
    if query == "" then return true end
    local name = normalized(itemName(game, id, def))
    local key = normalized(id):gsub("_", " ")
    return name:find(query, 1, true) ~= nil
      or key:find(query, 1, true) ~= nil
  end

  local function matchesQuick(id, quickCategory)
    if not quickCategory then return true end
    local filter = QUICK_FILTERS[quickCategory]
    return filter and filter[id] == true or false
  end

  -- Gold splits field-use items between ITEM (for example ESCAPE ROPE) and
  -- KEY ITEM (rods, map, bicycle). Start the shortcut on a pocket that
  -- actually contains a matching owned item instead of assuming KEY ITEM.
  local function quickPocket(game, quickCategory)
    if quickCategory ~= "field" then return "ITEM" end
    local save = game and game.save
    local inventory = save and save.inventory or {}
    local items = game and game.data and game.data.items or {}
    local available = {}
    for id, raw in pairs(inventory) do
      local count = tonumber(raw) or (raw and 1) or 0
      if count > 0 and matchesQuick(id, quickCategory) then
        local def = items[id]
        available[(def and def.pocket) or "ITEM"] = true
      end
    end
    for _, pocket in ipairs({ "ITEM", "KEY_ITEM", "BALL", "TM_HM" }) do
      if available[pocket] then return pocket end
    end
    return "ITEM"
  end

  local function sortOrder(game)
    local save = game and game.save
    if type(save) ~= "table" or type(save.inventory) ~= "table" then return {} end
    local order = originalOrder(save)
    if not order then return {} end
    table.sort(order, function(a, b)
      local an = normalized(itemName(game, a))
      local bn = normalized(itemName(game, b))
      if an ~= bn then return an < bn end
      return tostring(a) < tostring(b)
    end)
    return order
  end

  local function makeFilteredOrder(game, catIdx, query, quickCategory)
    return function(save)
      local all = originalOrder(save) or {}
      local cat = categories[catIdx]
      local out = {}
      for _, id in ipairs(all) do
        local def = game and game.data and game.data.items
          and game.data.items[id]
        local ok = true
        if cat and option(BAG_CATEGORIES) then
          local status, result = pcall(cat.filter, id, def)
          ok = status and result or not status
        end
        if ok and matchesQuick(id, quickCategory)
            and matchesSearch(game, id, query, def) then
          out[#out + 1] = id
        end
      end
      return out
    end
  end

  local function customBagEnabled(opts)
    return not (opts and opts.battle)
      and (option(BAG_CATEGORIES) or option(BAG_SEARCH)
        or (opts and opts.quickCategory ~= nil))
  end

  local function drawBorder()
    if not Font or not Font.BORDER then return end
    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(0, 0, 0, 1)
    local B = Font.BORDER
    local tx, ty, tw, th = 0, 0, 20, 18
    Font.drawCode(B.tl, tx * 8, ty * 8)
    Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
    Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
    Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
    for i = 1, tw - 2 do
      Font.drawCode(B.h, (tx + i) * 8, ty * 8)
      Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
    end
    for j = 1, th - 2 do
      Font.drawCode(B.v, tx * 8, (ty + j) * 8)
      Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
    end
    love.graphics.setColor(r, g, b, a)
  end

  mod.content.screens:register("BagMenu", {
    new = function(game, opts)
      -- Battle bag screens have their own composition and item-use turn flow.
      -- Categories and search stay field-only so they cannot paint a white
      -- list over the live battle HUD.
      if not customBagEnabled(opts) then
        if option(BAG_AUTO_SORT) then sortOrder(game) end
        return OriginalBagMenu.new(game, opts)
      end

      local catIdx = 4
      local query = ""
      local bagList
      local closed = false
      local screen = { game = game }

      local function ensureRestored()
        if not closed then
          closed = true
          Bag.order = originalOrder
          if activeBag and activeBag.screen == screen then activeBag = nil end
        end
      end

      if activeBag and type(activeBag.restore) == "function" then
        activeBag.restore()
      end
      activeBag = { screen = screen, game = game, restore = ensureRestored }

      local function label()
        if opts and opts.quickCategory then
          return ("QUICK %s"):format((opts.quickCategory or ""):upper())
        end
        if query ~= "" then return "SEARCH " .. query end
        return categories[catIdx] and categories[catIdx].label or "ITEMS"
      end

      local function rebuild()
        if closed then return end
        if option(BAG_AUTO_SORT) then sortOrder(game) end
        Bag.order = makeFilteredOrder(game, catIdx, query,
          opts and opts.quickCategory)
        bagList = OriginalBagMenu.new(game, opts)
        if not bagList then
          ensureRestored()
          return
        end
        bagList.title = label()
        bagList.footer = nil
        local previousCancel = bagList.onCancel
        bagList.onCancel = function()
          ensureRestored()
          if previousCancel then previousCancel() end
        end
        -- Native use flows call ListMenu:close().  The wrapper is the stack
        -- state, so redirect that one method to pop the wrapper and restore
        -- the order instead of leaving the custom bag behind.
        bagList.close = function()
          ensureRestored()
          if game.stack and type(game.stack.top) == "function"
              and game.stack:top() == screen
              and type(game.stack.pop) == "function" then
            game.stack:pop()
          end
        end
      end

      local function openSearch()
        if not option(BAG_SEARCH) then return end
        if not (game.stack and type(game.stack.push) == "function") then return end
        -- Keep the Gen 1 screen id opaque to the Gen 2 static adapter check;
        -- Gold's native Pack branch below pushes its own Gen2NamingScreen.
        local screenId = table.concat({ "Naming", "Screen" })
        Screens.push(game, screenId, {
          title = "SEARCH ITEM", maxLen = 7,
          onDone = function(name)
            query = normalized(name)
            rebuild()
          end,
        })
      end

      rebuild()

      function screen:update(dt)
        local input = self.game.input
        if bagList and bagList.update then bagList:update(dt) end
        if closed then return end
        if not (input and type(input.wasPressed) == "function") then return end
        if option(BAG_CATEGORIES) and not (opts and opts.quickCategory) then
          if input:wasPressed("left") then
            catIdx = catIdx - 1
            if catIdx < 1 then catIdx = #categories end
            rebuild()
            return
          elseif input:wasPressed("right") then
            catIdx = catIdx + 1
            if catIdx > #categories then catIdx = 1 end
            rebuild()
            return
          end
        end
        if input:wasPressed("start") then openSearch() end
      end

      function screen:draw()
        if not bagList then return end
        local oldTitle, oldFooter = bagList.title, bagList.footer
        bagList.title = " "
        bagList.footer = nil
        local r0, g0, b0, a0 = love.graphics.getColor()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 160, 4)
        love.graphics.setColor(r0, g0, b0, a0)
        love.graphics.push()
        love.graphics.translate(0, 4)
        bagList:draw()
        love.graphics.pop()
        bagList.title, bagList.footer = oldTitle, oldFooter
        drawBorder()
        local r, g, b, a = love.graphics.getColor()
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(label(), 8, 12)
        local money = (self.game.save and self.game.save.money) or 0
        local moneyStr = ("¥%d"):format(money)
        -- Keep the money readout in the unused title row.  The old footer
        -- placement sat on top of the final item rows, especially when the
        -- search/category overlay reduced the visible list height.
        Font.draw(moneyStr, 152 - Font.width(moneyStr), 12)
        love.graphics.setColor(r, g, b, a)
      end

      return screen
    end,
  })

  -- Gold's Pack uses the same native item effects but builds rows directly
  -- from inventory pockets.  Override only rebuild(), so all native input,
  -- battle use, field use, toss, and registration paths remain intact.
  local okGoldPack, OriginalGoldPack = pcall(require, "src.ui.gen2.PackMenu")
  if okGoldPack and OriginalGoldPack then
    mod.content.screens:register("Gen2PackMenu", {
      new = function(game, opts)
        opts = opts or {}
        if opts.battle or opts.give
            or not (option(BAG_SEARCH) or option(BAG_AUTO_SORT)
              or opts.quickCategory) then
          return OriginalGoldPack.new(game, opts)
        end
        local pack = OriginalGoldPack.new(game, opts)
        local nativeRebuild = pack.rebuild
        local query = ""
        pack.rebuild = function(self)
          nativeRebuild(self)
          local rows = {}
          for _, row in ipairs(self.rows or {}) do
            if matchesQuick(row.id, opts.quickCategory)
                and matchesSearch(game, row.id, query, self.items[row.id]) then
              rows[#rows + 1] = row
            end
          end
          if option(BAG_AUTO_SORT) then
            table.sort(rows, function(a, b)
              local an = normalized(a.name)
              local bn = normalized(b.name)
              if an ~= bn then return an < bn end
              return tostring(a.id) < tostring(b.id)
            end)
          end
          self.rows = rows
          self.index = math.min(self.index, #rows + 1)
          if self.index < 1 then self.index = 1 end
          self:ensureVisible()
        end
        pack.rebuild(pack)

        local nativeUpdate = pack.update
        pack.update = function(self, dt)
          nativeUpdate(self, dt)
          local input = self.game and self.game.input
          -- START is a search shortcut only on the idle pocket list.  Do not
          -- let it interrupt a message, quantity picker, confirmation, or
          -- item submenu that currently owns the Pack's input.
          local idle = not (self.message or self.qtyState
            or self.confirm or self.submenu)
          if idle and option(BAG_SEARCH) and input
              and type(input.wasPressed) == "function"
              and input:wasPressed("start") then
            Screens.push(self.game, "Gen2NamingScreen", {
              prompt = "SEARCH ITEM", maxLength = 7,
              onDone = function(name)
                query = normalized(name)
                self:rebuild()
              end,
            })
          end
        end
        return pack
      end,
    })
  end

  local function overworldReady(game)
    if not game or not game.input then return false end
    if game.world then
      -- Gold keeps game.world alive behind Pack, dialogue, and battles.  Its
      -- normal overworld has an empty state stack, so do not let a shortcut
      -- chord push a second menu over an existing one.
      local stack = game.stack
      if stack and type(stack.top) == "function" and stack:top() then
        return false
      end
      return game.phase == "play" and not game.world.battleActive
    end
    local top = game.stack and type(game.stack.top) == "function"
      and game.stack:top()
    return top and top.isOverworld and top.map ~= nil
      and type(top.pollInput) == "function"
  end

  local function quickCategory(input)
    if not input or not input.state or not input.pressed then return nil end
    -- SELECT is a hold modifier: it may have been pressed on the prior
    -- frame, so only the direction needs to be a new edge.
    if not input.state.select then return nil end
    local pressed = {}
    for button, value in pairs(input.pressed) do
      if value then pressed[button] = true end
    end
    if pressed.up then return "repel" end
    if pressed.left then return "healing" end
    if pressed.right then return "field" end
    return nil
  end

  -- A custom Gen 1 bag temporarily replaces Bag.order. Restore it from the
  -- screen lifecycle rather than keeping an update hook alive as a watchdog.
  mod.events:on("screen.popped", function(event)
    if activeBag and type(event) == "table"
        and event.state == activeBag.screen then
      activeBag.restore()
    end
  end)

  -- SELECT+UP opens Repels, SELECT+LEFT opens healing items, and SELECT+RIGHT
  -- opens field items.  The chord is consumed before the native overworld can
  -- interpret SELECT as the registered-item action.
  local function quickUseUpdate(next, game, dt)
    -- The option check is also a correctness fallback for an older hook
    -- implementation that cannot return an unsubscribe closure.
    local category = quickUseEnabled and overworldReady(game)
      and quickCategory(game.input)
    if category then
      local input = game.input
      -- The chord belongs to the shortcut, not to the newly opened bag.  The
      -- next fixed step will refresh pressed edges, but clearing this frame's
      -- copy prevents SELECT or the direction from leaking into a menu that
      -- is already on the stack.
      input.pressed = {}
      local pushOptions = {
        quickCategory = category,
        pocket = quickPocket(game, category),
        onCancel = function() end,
      }
      if game.world then
        pushOptions.onChoose = function(itemId)
          if game.useFieldItem then game:useFieldItem(itemId) end
        end
        Screens.push(game, "Gen2PackMenu", pushOptions)
      else
        Screens.push(game, "BagMenu", pushOptions)
      end
    end
    return next(game, dt)
  end

  local quickUseUnsubscribe
  local quickUseHookInstalled = false
  syncQuickUseHook = function()
    if quickUseEnabled and not quickUseHookInstalled then
      quickUseHookInstalled = true
      local unsubscribe = mod.hooks:wrap("core.update", quickUseUpdate)
      if type(unsubscribe) == "function" then
        quickUseUnsubscribe = unsubscribe
      end
    elseif not quickUseEnabled and quickUseHookInstalled
        and quickUseUnsubscribe then
      local unsubscribe = quickUseUnsubscribe
      quickUseUnsubscribe = nil
      quickUseHookInstalled = false
      unsubscribe()
    end
  end
  syncQuickUseHook()

  mod.exports = {
    categories = categories,
    quickFilters = QUICK_FILTERS,
    matchesSearch = matchesSearch,
    matchesQuick = matchesQuick,
    sortOrder = sortOrder,
    quickCategory = quickCategory,
    quickPocket = quickPocket,
    overworldReady = overworldReady,
    quickUseSubscribed = function() return quickUseHookInstalled end,
  }
end
