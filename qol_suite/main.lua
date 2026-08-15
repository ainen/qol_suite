-- QoL Suite: one package containing the supported quality-of-life
-- features. Feature modules are loaded through mod:read so the
-- package works when mounted from a .modpkg or .zip archive.
return function(mod)

local schemaSource = mod:read("options_schema.lua")
if not schemaSource then
  error("QOL_SUITE: missing options_schema.lua", 0)
end
local schemaChunk, schemaErr = load(schemaSource,
  "@" .. mod.path .. "/options_schema.lua")
if not schemaChunk then
  error("QOL_SUITE: options schema did not compile: " .. tostring(schemaErr), 0)
end
local optionSchema = schemaChunk()
if type(optionSchema) ~= "table" then
  error("QOL_SUITE: options schema must return a table", 0)
end

mod.options:define(optionSchema)

local function loadFeature(relativePath, ...)
  local source = mod:read(relativePath)
  if not source then
    error("QOL_SUITE: missing feature " .. relativePath, 0)
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. relativePath)
  if not chunk then
    error("QOL_SUITE: feature did not compile " .. relativePath
      .. ": " .. tostring(err), 0)
  end
  local feature = chunk()
  if type(feature) ~= "function" then
    error("QOL_SUITE: feature must return an initializer: " .. relativePath, 0)
  end
  feature(mod, ...)
  return mod.exports
end

-- Supported 0.1.x releases use a flat schema but do not evaluate visibleIf
-- metadata. Add dependent-row filtering to the in-game manager.
local optionVisibilityExports = loadFeature(
  "features/option_visibility.lua", optionSchema)

-- The Dramatic Shape family helper must load first so the XP bar and caught
-- marker can follow the HUD panels into those mods' world canvas.
local voxelHud = loadFeature("features/voxel_hud.lua")
local overlayLayoutExports = loadFeature("features/overlay_layout.lua")
-- The Gen 3-inspired UI overhaul owns the final battle presentation.  Load
-- this internal bridge before battle overlays so those features can register
-- small post-render decorations without replacing the overhaul's UI.
local gen3UICompat = loadFeature("features/gen3_ui_compat.lua")
-- Registration order is intentional and deterministic.
loadFeature("features/move_effectiveness_native.lua", gen3UICompat)
local effectivenessExports = mod.exports
local moveFreedomExports = loadFeature("features/move_freedom.lua")
loadFeature("features/naming_enhancements.lua")
loadFeature("features/party_lead.lua")
local partyOverviewExports = loadFeature("features/party_overview.lua", overlayLayoutExports)
local eggTrackerExports = loadFeature("features/egg_tracker.lua", overlayLayoutExports)
loadFeature("features/low_health_alarm.lua")
loadFeature("features/experience_bar.lua", voxelHud, gen3UICompat)
local experienceBarExports = mod.exports
loadFeature("features/caught_indicator.lua", voxelHud, gen3UICompat)
local caughtIndicatorExports = mod.exports
loadFeature("features/field_abilities.lua")
local fieldAbilitiesExports = mod.exports
local hmWithoutTeachingExports = loadFeature("features/hm_without_teaching.lua", fieldAbilitiesExports)
local reusableTMsExports = loadFeature("features/reusable_tms.lua")
local skipCenterDialogueExports = loadFeature("features/skip_center_dialogue.lua")
local encounterRateExports = loadFeature("features/encounter_rate.lua")
loadFeature("features/bag_categories.lua")
local bagCategoriesExports = mod.exports
local trackingExports = loadFeature("features/tracking.lua")
local encounterTrackerExports = loadFeature("features/encounter_tracker.lua", trackingExports)
local pokedexFiltersExports = loadFeature("features/pokedex_filters.lua", encounterTrackerExports)
loadFeature("features/minimap.lua", trackingExports, encounterTrackerExports,
  overlayLayoutExports)
local minimapExports = mod.exports
local expShareExports = loadFeature("features/exp_share.lua")
local autoCatchTargetExports = loadFeature("features/auto_catch_target.lua", trackingExports)
local autoBattleExports = loadFeature("features/auto_battle.lua", autoCatchTargetExports,
  gen3UICompat)
local battleTeardownExports = loadFeature("features/battle_teardown.lua")
local floatingMenusExports = loadFeature("features/floating_menus.lua")

mod.exports = {
  packageId = "qol_suite",
  optionVisibility = optionVisibilityExports,
  moveEffectiveness = effectivenessExports,
  moveFreedom = moveFreedomExports,
  experienceBar = experienceBarExports,
  caughtIndicator = caughtIndicatorExports,
  gen3UICompat = gen3UICompat,
  voxelHud = voxelHud,
  overlayLayout = overlayLayoutExports,
  fieldAbilities = fieldAbilitiesExports,
  hmWithoutTeaching = hmWithoutTeachingExports,
  reusableTMs = reusableTMsExports,
  skipCenterDialogue = skipCenterDialogueExports,
  encounterRate = encounterRateExports,
  bagCategories = bagCategoriesExports,
  partyOverview = partyOverviewExports,
  eggTracker = eggTrackerExports,
  tracking = trackingExports,
  encounterTracker = encounterTrackerExports,
  pokedexFilters = pokedexFiltersExports,
  minimap = minimapExports,
  expShare = expShareExports,
  autoCatchTarget = autoCatchTargetExports,
  autoBattle = autoBattleExports,
  battleTeardown = battleTeardownExports,
  floatingMenus = floatingMenusExports,
  features = {
    "option_visibility",
    "voxel_hud",
    "overlay_layout",
    "gen3_ui_compat",
    "move_effectiveness_native",
    "move_freedom",
    "naming_enhancements",
    "party_lead",
    "party_overview",
    "egg_tracker",
    "low_health_alarm",
    "experience_bar",
    "caught_indicator",
    "field_abilities",
    "hm_without_teaching",
    "reusable_tms",
    "skip_center_dialogue",
    "encounter_rate",
    "bag_categories",
    "tracking",
    "encounter_tracker",
    "pokedex_filters",
    "minimap",
    "exp_share",
    "auto_catch_target",
    "auto_battle",
    "battle_teardown",
    "floating_menus",
  },
}
end
