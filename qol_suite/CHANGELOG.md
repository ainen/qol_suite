# Changelog

## 1.4.0 - 2026-08-20

- Added **WALL BUMP SOUND** for Red, Blue, and Yellow. Disable it from the
  QoL Suite settings to silence the cue played when the player walks into an
  impassable tile or overworld entity; it remains enabled by default.

## 1.3.0 - 2026-08-18

- Added **CATCH SHINY ONLY** (Gold-only, under AUTO CATCH): when enabled,
  AUTO CATCH fires only against a shiny wild Pokémon; non-shiny encounters
  decline the catch and the normal auto-battle loop continues. The opposite
  policy of STOP ON SHINY (which pauses automation on a shiny).
- Fixed AUTO BATTLE swap-in bug: when a trainer swaps Pokémon the engine
  shows a "change POKéMON?" prompt; the mod now declines it (NO) instead of
  accepting (YES), which previously opened the party menu and swapped to the
  first party member. Wild-battle "Use next POKéMON?" prompts still answer YES
  (stay in battle) as before.

## 1.2.0 - 2026-08-17

- Added gen1recomp v0.2.x compatibility by widening the supported engine
  range to `>=0.1.95 <0.3.0` (the 0.2.x launcher rejected the previous
  `<0.2.0` range).
- Migrated dependent-option rows to the engine's native `visible_if` option
  rows (available since v0.1.95) and removed the custom option-visibility
  monkey-patch feature, which is now redundant. Composite auto-catch rows
  now gate on their direct parent row; the features themselves still require
  their full option chain to be enabled before activating.
- Verified against v0.2.3 (commit 4c13770e): the full headless suite passes
  across Red, Blue, Yellow, and Gold.

## 1.0.0 - 2026-08-15

Initial public release of QoL Suite for Pokémon Red, Blue, Yellow, and Gold in
gen1recomp.

### Features

- Battle information, EXP sharing, automation, catch controls, and safety
  stops.
- Quick field moves, direct HM use, reusable TMs, and flexible move
  replacement.
- Minimap, encounter and party panels, Pokédex tracking and filters, and
  floating menus.
- Bag categories, search, sorting, quick-use items, naming tools, and faster
  Center healing.
- Gold-specific egg, time, swarm, roaming, Headbutt, Rock Smash, and contest
  information.

### Release audit

- Added Gen1Recomp v0.1.92 compatibility and a v0.1.91/v0.1.92 CI matrix.
- Added dependent-option visibility to the flat v0.1.91 settings manager.
- Corrected Gold palette handling, battle cleanup, item-pocket access, and
  status immunities.
- Used gen1recomp's native Gen 1 caught-marker renderer when available.
- Improved overlay sizing, corner stacking, dynamic hooks, UI-overhaul
  compatibility, and render caching.
- Derived the Gen 1 caught marker from the player's imported assets; no marker
  graphic is distributed.
- Added deterministic packaging, CI, static compatibility checks, a feature
  graph, and focused RBY/Gold tests.
