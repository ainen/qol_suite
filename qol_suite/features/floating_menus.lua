-- FLOATING MENUS: let the scene beneath actual gameplay menus remain visible
-- while preserving their white paper and Game Boy-style borders.
return function(mod)
  local OPTION = "floatingMenus"
  local Renderer = require("src.render.Renderer")

  -- Be deliberately conservative. Anything not known to be a gameplay menu
  -- keeps its native opaque composition: title/intro scenes, scripted
  -- cutscenes, evolution and trade animation, credits, minigames and Gold's
  -- egg hatch all fall outside this allowlist.
  local MENU_SCREENS = {
    BagMenu = true,
    BindingsMenu = true,
    BoxMenu = true,
    DexEntryMenu = true,
    FlyMenu = true,
    ListMenu = true,
    ManagerState = true,
    MoveLearnMenu = true,
    NamingScreen = true,
    OptionsMenu = true,
    PartyMenu = true,
    PlayerPC = true,
    PokedexMenu = true,
    ShopMenu = true,
    StartMenu = true,
    SummaryMenu = true,
    TouchControlsEditor = true,
    TownMap = true,
    TrainerCard = true,

    Gen2BoxMenu = true,
    Gen2CenterPcMenu = true,
    Gen2DecorationMenu = true,
    Gen2HeldItemMenu = true,
    Gen2ItemPcMenu = true,
    Gen2MailCompose = true,
    Gen2MailMenu = true,
    Gen2MailRead = true,
    Gen2MailboxMenu = true,
    Gen2MartMenu = true,
    Gen2MoveDeleter = true,
    Gen2NamePick = true,
    Gen2NamingScreen = true,
    Gen2OptionsMenu = true,
    Gen2PackMenu = true,
    Gen2PartyMenu = true,
    Gen2PcMenu = true,
    Gen2PokedexMenu = true,
    Gen2Pokegear = true,
    Gen2SaveMenu = true,
    Gen2ScriptMenu = true,
    Gen2StartMenu = true,
    Gen2SummaryMenu = true,
    Gen2TrainerCard = true,
  }

  -- Renderer.beginFrame and LOVE's rectangle primitive are not mod hooks. Keep
  -- one process-wide dispatcher and swap only its active controller on reload;
  -- this prevents direct wrappers and stale transparency flags from stacking
  -- every time development hot reload runs the entry chunk again.
  local PATCH_KEY = "_qolSuiteFloatingMenusPatch"
  local patch = rawget(Renderer, PATCH_KEY)
  if not patch then
    patch = {
      originalBeginFrame = Renderer.beginFrame,
      originalRectangle = love.graphics.rectangle,
    }
    patch.beginFrame = function(self, transparent, ...)
      local controller = patch.controller
      local floating = controller and controller.floatingVisible == true
      if controller then controller.floatingVisible = false end
      return patch.originalBeginFrame(self, transparent or floating, ...)
    end
    patch.rectangle = function(mode, x, y, w, h, ...)
      local controller = patch.controller
      if controller and controller.runtimeEnabled
          and controller.suppressBlackBackground
          and mode == "fill" and x == 0 and y == 0
          and w == 160 and h == 144 then
        local r, g, b, a = love.graphics.getColor()
        local black = r and r <= 0.02 and g <= 0.02 and b <= 0.02
          and (a == nil or a > 0)
        if black then return end
      end
      return patch.originalRectangle(mode, x, y, w, h, ...)
    end
    Renderer.beginFrame = patch.beginFrame
    love.graphics.rectangle = patch.rectangle
    rawset(Renderer, PATCH_KEY, patch)
  end

  local controller = {
    runtimeEnabled = false,
    floatingVisible = false,
    suppressBlackBackground = false,
    originalOpaque = setmetatable({}, { __mode = "k" }),
    seen = setmetatable({}, { __mode = "k" }),
    screenUnsubscribe = nil,
  }

  local function originalOpacity(state)
    if controller.seen[state] then return controller.originalOpaque[state] end
    return state and state.isOpaque
  end

  local function floatingState(state)
    if type(state) ~= "table" or state.isBattle or state.isOverworld then
      return false
    end
    if originalOpacity(state) ~= true then return false end
    return MENU_SCREENS[state.screenId] == true
  end

  local function restoreStates()
    for state in pairs(controller.seen) do
      state.isOpaque = controller.originalOpaque[state]
    end
    controller.originalOpaque = setmetatable({}, { __mode = "k" })
    controller.seen = setmetatable({}, { __mode = "k" })
  end

  local function renderVisible(nextFn, state)
    if state and not controller.seen[state] then
      controller.seen[state] = true
      controller.originalOpaque[state] = state.isOpaque
    end
    local visible = nextFn(state)
    local floats = controller.runtimeEnabled and floatingState(state)
    controller.suppressBlackBackground = floats == true
    if floats then
      controller.floatingVisible = true
      state.isOpaque = false
    elseif state and controller.seen[state] then
      state.isOpaque = controller.originalOpaque[state]
    end
    return visible
  end

  function controller:deactivate()
    self.runtimeEnabled = false
    self.floatingVisible = false
    self.suppressBlackBackground = false
    if type(self.screenUnsubscribe) == "function" then
      self.screenUnsubscribe()
      self.screenUnsubscribe = nil
    end
    restoreStates()
  end

  function controller:setEnabled(value)
    -- A listener owned by a discarded loader must never reactivate its stale
    -- controller after a hot reload installs a replacement.
    if patch.controller ~= self then return end
    value = value == true
    if not value then
      self:deactivate()
      return
    end
    self.runtimeEnabled = true
    if self.screenUnsubscribe == nil then
      local unsubscribe = mod.hooks:wrap("screen.render_visible",
        renderVisible)
      self.screenUnsubscribe = type(unsubscribe) == "function"
        and unsubscribe or false
    end
  end

  if patch.controller and type(patch.controller.deactivate) == "function" then
    patch.controller:deactivate()
  end
  patch.controller = controller
  controller:setEnabled(mod.options:get(OPTION) == true)

  mod.events:on("mod.options_changed", function(event)
    if type(event) == "table" and event.mod == mod.id
        and event.key == OPTION then
      controller:setEnabled(event.value)
    end
  end)

  mod.exports = {
    enabled = function() return controller.runtimeEnabled end,
    floating = floatingState,
    screenHookActive = function()
      return controller.screenUnsubscribe ~= nil
    end,
    state = function()
      return {
        enabled = controller.runtimeEnabled,
        floatingVisible = controller.floatingVisible,
        suppressBlackBackground = controller.suppressBlackBackground,
        screenHookActive = controller.screenUnsubscribe ~= nil,
      }
    end,
  }
end
