-- QoL Suite dependent-row visibility for supported gen1recomp 0.1.x releases.
--
-- The release manager consumes a flat schema and does not evaluate visibleIf.
-- Filter this mod's rows before the manager builds them, then rebuild the page
-- whenever a parent setting changes.
return function(mod, schema)
  local ManagerState = require("src.mods.ManagerState")
  if type(ManagerState) ~= "table"
      or type(ManagerState.buildOptionRows) ~= "function"
      or type(ManagerState.setOption) ~= "function" then
    error("QOL_SUITE: supported gen1recomp option manager is unavailable", 0)
  end

  local STATE_KEY = "_qolSuiteOptionVisibility"
  local state = rawget(ManagerState, STATE_KEY)
  if type(state) ~= "table" then
    state = {
      schemas = {},
      rebuilding = setmetatable({}, { __mode = "k" }),
      suppress = setmetatable({}, { __mode = "k" }),
      originalBuild = ManagerState.buildOptionRows,
      originalSet = ManagerState.setOption,
    }
    rawset(ManagerState, STATE_KEY, state)
  end
  state.schemas[mod.id] = schema

  local function rowsByKey(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
      if type(row) == "table" and type(row.key) == "string" then
        out[row.key] = row
      end
    end
    return out
  end

  local function conditionVisible(condition, valueFor)
    if condition == nil then return true end
    if type(condition) ~= "table" then return condition ~= false end
    if condition.key ~= nil then
      local expected = condition.equals
      if expected == nil then expected = true end
      return valueFor(condition.key) == expected
    end
    if type(condition.all) == "table" then
      for _, child in ipairs(condition.all) do
        if not conditionVisible(child, valueFor) then return false end
      end
    end
    if type(condition.any) == "table" then
      local matched = false
      for _, child in ipairs(condition.any) do
        if conditionVisible(child, valueFor) then
          matched = true
          break
        end
      end
      if not matched then return false end
    end
    if condition["not"] ~= nil
        and conditionVisible(condition["not"], valueFor) then
      return false
    end
    return true
  end

  local function visibleRows(self, modId, rows)
    local byKey = rowsByKey(rows)
    local function valueFor(key)
      return self:optionValue(modId, byKey[key] or { key = key })
    end
    local filtered = {}
    for _, row in ipairs(rows or {}) do
      if conditionVisible(row.visibleIf, valueFor) then
        filtered[#filtered + 1] = row
      end
    end
    return filtered
  end

  local function rebuild(self, modId)
    if state.suppress[self] or state.rebuilding[self]
        or self.screen ~= "options" then return end
    local current = self.currentMod
    if type(current) ~= "table" or current.id ~= modId then return end
    local full = state.schemas[modId]
    if type(full) ~= "table" then return end

    local selected = self.optionRows and self.optionRows[self.cursor or 1]
    selected = selected and selected.id
    state.rebuilding[self] = true
    local ok, rows = pcall(self.buildOptionRows, self, current, full)
    state.rebuilding[self] = nil
    if not ok then error(rows, 0) end
    self.optionRows = rows

    local cursor = math.max(1, math.min(tonumber(self.cursor) or 1, #rows))
    if selected then
      for index, row in ipairs(rows) do
        if row.id == selected then
          cursor = index
          break
        end
      end
    end
    self.cursor = cursor
    self.scroll = math.max(0, math.min(tonumber(self.scroll) or 0,
      math.max(0, #rows - 1)))
  end

  if not state.patched then
    ManagerState.buildOptionRows = function(self, manifest, incoming)
      local modId = manifest and manifest.id
      local full = modId and state.schemas[modId]
      if type(full) ~= "table" then
        return state.originalBuild(self, manifest, incoming)
      end

      local rows = state.originalBuild(self, manifest,
        visibleRows(self, modId, full))
      for _, built in ipairs(rows) do
        if built.id == "__reset" then
          built.activate = function()
            state.suppress[self] = true
            local ok, err = pcall(function()
              for _, row in ipairs(full) do
                if row.type == "toggle" or row.type == "choice"
                    or row.type == "number" or row.type == "text" then
                  state.originalSet(self, modId, row.key, row.default)
                end
              end
            end)
            state.suppress[self] = nil
            if not ok then error(err, 0) end
            if type(self.notify) == "function" then
              self:notify("DEFAULTS RESTORED")
            end
            rebuild(self, modId)
          end
          break
        end
      end
      return rows
    end

    ManagerState.setOption = function(self, modId, key, value)
      local result = state.originalSet(self, modId, key, value)
      if state.schemas[modId] then rebuild(self, modId) end
      return result
    end
    state.patched = true
  end

  mod.exports = {
    target = "v0.1.x",
    visible = conditionVisible,
    filter = visibleRows,
  }
end
