-- QoL Suite: keep technical machines in the bag after a successful teach.
-- HMs are already non-consumable and are intentionally left unchanged.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local isGold = GameVersion.isGold and GameVersion.isGold() == true
  local OPTION = "reusableTMs"

  local function enabled()
    return mod.options:get(OPTION) == true
  end

  local function isTM(data, itemId)
    local def = data and data.items and data.items[itemId]
    if type(def) ~= "table" then return false end
    if def.machine then return def.machine.kind == "TM" end
    return tostring(itemId):match("^TM_") ~= nil and def.teaches ~= nil
  end

  -- RBY's BagMenu consumes a machine only when ItemEffects returns "learn".
  -- Change only a successful TM result to the existing kept result; all
  -- validation, move replacement, PP initialization, and happiness behavior
  -- remain in the engine.
  local ItemEffects = require("src.inventory.ItemEffects")
  if not ItemEffects._qolSuiteReusableTMsPatched then
    local originalUse = ItemEffects.use
    function ItemEffects.use(data, save, itemId, target, battle, moveIndex, ow)
      local result, payload, extra = originalUse(data, save, itemId, target,
        battle, moveIndex, ow)
      if result == "learn" and enabled() and isTM(data, itemId) then
        result = "learnkept"
      end
      return result, payload, extra
    end
    ItemEffects._qolSuiteReusableTMsPatched = true
  end

  -- Gold's TM teaching flow consumes through Game2:consumeItem after the
  -- native learn callback.  BattleState has the same helper for any future
  -- machine path, so guard both at the final consumption point.
  if isGold then
    local Game2 = require("src.core.Game2")
    if not Game2._qolSuiteReusableTMsPatched then
      local originalConsume = Game2.consumeItem
      function Game2:consumeItem(itemId)
        if enabled() and isTM(self.data, itemId) then return end
        return originalConsume(self, itemId)
      end
      Game2._qolSuiteReusableTMsPatched = true
    end

    local BattleState = require("src.ui.gen2.BattleState")
    if not BattleState._qolSuiteReusableTMsPatched then
      local originalConsume = BattleState.consumeItem
      function BattleState:consumeItem(itemId)
        local data = self.game and self.game.data
        if enabled() and isTM(data, itemId) then return end
        return originalConsume(self, itemId)
      end
      BattleState._qolSuiteReusableTMsPatched = true
    end
  end

  mod.exports = { enabled = enabled, isTM = isTM }
end
