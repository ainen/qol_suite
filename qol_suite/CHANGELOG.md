# Changelog

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
