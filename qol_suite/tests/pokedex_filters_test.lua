-- POKEDEX FILTERS focused regression coverage.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
Data.pokemon.FIXMON_D = {
  id = "FIXMON_D", dex = 152, name = "FIXMON D", types = { "DARK" },
}
Data.constants.dexSize = 152
local run = T.sdk.loadMod("qol_suite", { data = Data, root = ".." })
local MOD_ID = "qol_suite"
local filters = run.loader.exports[MOD_ID].pokedexFilters

T.check(#run.errors == 0, "POKEDEX FILTERS package load is clean")
T.check(filters.enabled(), "POKEDEX FILTERS is enabled by default")

local rows = {
  { species = "FIXMON_A", seen = true, caught = false },
  { species = "FIXMON_B", seen = true, caught = true },
  { species = "FIXMON_C", seen = false, caught = false },
  { species = "FIXMON_D", seen = false, caught = false },
}
local function count(state, available)
  return #filters.filterRows(rows, state, Data, available or {})
end

T.eq(count({ status = "seen" }), 1,
  "SEEN ONLY keeps seen but uncaught Pokemon")
T.eq(count({ status = "caught" }), 1,
  "CAUGHT keeps owned Pokemon")
T.eq(count({ status = "unseen" }), 2,
  "UNSEEN keeps Pokemon with no seen record")
T.eq(count({ area = true }, { FIXMON_A = true, FIXMON_D = true }), 2,
  "CURRENT AREA keeps species present in the area encounter set")
T.eq(count({ type = "FIRE" }), 1,
  "TYPE keeps species with the selected type")
T.eq(count({ generation = "2" }), 1,
  "GEN keeps species from the selected generation")
T.eq(count({ status = "caught", type = "FIRE" }), 1,
  "filters combine status and type")
T.eq(filters.summary({ status = "seen", area = true,
  generation = "1", type = "FIRE" }), "SEEN ONLY AREA GEN 1 FIRE",
  "active filter summary is compact and readable")
T.eq(filters.statusMenuLabel({ status = "seen" }), "SEEN ONLY",
  "status menu label fits without a redundant prefix")

run.loader.modOptions[MOD_ID] = { pokedexFilters = true }
local game = {
  data = Data,
  save = { pokedex = {
    seen = { FIXMON_A = true, FIXMON_B = true },
    owned = { FIXMON_B = true },
  } },
  stack = {
    states = {},
    push = function(self, state) self.states[#self.states + 1] = state end,
    top = function(self) return self.states[#self.states] end,
  },
}
local pokedexMenuModule = table.concat({ "src.ui.", "Pokedex", "Menu" })
local hasPokedexMenu, PokedexMenu = pcall(require, pokedexMenuModule)
T.check(hasPokedexMenu and type(PokedexMenu) == "table"
    and type(PokedexMenu.new) == "function",
  "the Gen 1 checkout exposes its Pokedex menu capability")
if not (hasPokedexMenu and type(PokedexMenu) == "table"
    and type(PokedexMenu.new) == "function") then
  T.finish("pokedex_filters")
  return
end
local list = PokedexMenu.new(game)
T.check(type(list.onSelectKey) == "function",
  "Gen 1 Pokedex exposes the filter shortcut")
list.qolFilters.status = "caught"
list.qolApplyFilters()
T.eq(#list.items, 1, "Gen 1 Pokedex applies the CAUGHT filter")
T.eq(list.items[1].value, "FIXMON_B",
  "filtered Gen 1 list preserves the selected species action")
T.eq(list.title, "DEX CAUGHT",
  "Gen 1 shows the active filter in the title strip")
T.check(not list.footer:find("\n", 1, true),
  "Gen 1 keeps SEEN/OWN totals on one footer line")

list.onSelectKey()
local filterMenu = game.stack:top()
local generationItem, clearItem
for _, item in ipairs(filterMenu.items) do
  if item.label:find("GEN:", 1, true) == 1 then generationItem = item end
  if item.label == "CLEAR FILTERS" then clearItem = item end
end
T.check(generationItem ~= nil and clearItem ~= nil,
  "filter menu exposes generation and clear actions")
generationItem.onSelect()
T.check(generationItem.label ~= "GEN: ALL",
  "generation filter updates its live menu label")
clearItem.onSelect()
T.eq(generationItem.label, "GEN: ALL",
  "CLEAR FILTERS restores the generation label")
run.loader.modOptions[MOD_ID] = { pokedexFilters = false }
local unfiltered = PokedexMenu.new(game)
T.check(unfiltered.onSelectKey == nil,
  "disabling POKEDEX FILTERS removes the shortcut")

T.finish("pokedex_filters")
