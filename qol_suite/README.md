# QoL Suite

Optional quality-of-life, UI, and automation features for **Pokemon Red, Blue, Yellow, and Gold**, packaged as one installable mod for the [Gen 1 Recompilation Project](https://github.com/bryanthaboi/gen1recomp).

Everything is **opt-in and reversible**: the mod installs as a single package, each feature is a toggle in the in-game Mods menu, and dependent settings hide automatically when their parent feature is off. Nothing is forced on by default unless it is a harmless display change.

| | |
|---|---|
| **Version** | 1.2.0 |
| **Engine** | gen1recomp `>=0.1.95 <0.3.0` |
| **Games** | Red, Blue, Yellow (Gen 1) and Gold |
| **Features** | 27 (Gen 1 and Gold share most; a few are version-specific) |
| **Mod API** | 2 |

## What it does

QoL Suite groups small, well-scoped improvements that are otherwise hard to combine. Highlights:

- **Battle** — type-matchup readout, move swapping with PP retention, optional EXP sharing, an XP bar and caught-marker (Gen 1), low-health alarm control.
- **Automation** — an optional auto-battle loop with safety stops (low HP, shiny, out of balls, a chosen target species), auto-catch with ball selection, and pause-on-new-Pokédex-entry / evolution.
- **Field & bag** — direct HM use, reusable TMs, quick field moves, shorter Center healing, bag categories/search/sort/quick-use, and a tunable encounter-rate multiplier.
- **Overworld panels** — a compact party overview with ordering, an encounter tracker, a configurable minimap with Pokédex habitat tracking, and Gold's egg tracker — each with corner placement.
- **Interface** — Pokédex filters, floating menus (keep the world visible under menus), and naming controls (skip the catch-nickname prompt, rename anywhere, NPC-trade renaming).
- **Compatibility adapters** for supported voxel and Gen 3-inspired battle UIs, plus a battle-teardown guard against frame-speed leaks.

## Installation

Install from the gen1recomp Mods menu, or add the released build:

1. Download `qol_suite-<version>.zip` from [releases](https://github.com/ainen/qol_suite/releases).
2. Extract it into the game's `mods/` folder (the mod directory is `qol_suite/`).
3. Launch the game and enable **QOL SUITE** in the Mods menu.

The mod is version-gated: the launcher checks `manifest.json` / `mod.card` against the running engine and will refuse to load it outside the supported range, so it will not break a build that is too old or too new.

## Configuration

All options live in the in-game **Mods → QOL SUITE** menu. Options are grouped by area — **Battle, Automation, Field, Party, Bag, Minimap, Interface, Naming** — and each is a toggle, a choice, or a number with sensible defaults.

### Dependent options

Many options depend on a parent feature. The mod declares this with the engine's **native `visible_if`** condition (supported since gen1recomp **v0.1.95**): a dependent row is hidden while its parent is off, reappears the moment the parent turns on, and is restored to a safe value if the parent is switched back off. There is no custom visibility shim — the engine renders the dependency directly, so the in-game manager and the pre-game launcher stay in sync.

> **Note:** a few automation options form a chain (e.g. *AUTO CATCH* → *AUTO CATCH TARGET* → *STOP ON TARGET*). Each row hides with its immediate parent, and the feature logic additionally requires the full chain to be enabled before it acts — so an option that is visible but whose grandparent is off simply has no effect.

### Gen 1 vs Gold

The option set adapts to the game:

- **Gen 1 (Red/Blue/Yellow):** `XP BAR` and `CAUGHT MARKER` appear.
- **Gold:** `STOP ON SHINY`, `EGG TRACKER`, and the extra encounter-tracker detail rows (time of day, swarms, roaming, rare, headbutt, rock smash, bug contest) appear.

## Features

27 features, listed by area. A few are version-specific.

| Area | Feature |
|---|---|
| **Battle** | Type Matchup, Move Freedom (swap), Low Health Alarm, EXP Share, XP Bar*, Caught Marker* |
| **Automation** | Auto Battle, Auto Catch Target, Battle Teardown |
| **Field** | Field Abilities (quick/auto field moves), HM without Teaching, Skip Center Dialogue, Encounter Rate |
| **Party** | Party Lead, Party Overview (ordering), Egg Tracker (Gold) |
| **Bag** | Bag Categories (search/sort/quick-use), Reusable TMs |
| **Overworld** | Minimap, Tracking, Encounter Tracker |
| **Interface** | Pokédex Filters, Floating Menus, Gen 3 UI Compatibility, Voxel HUD, Overlay Layout |
| **Naming** | Naming Enhancements (skip catch-name, rename anywhere, NPC-trade rename) |

\* Gen 1 only. Gold adds `STOP ON SHINY` and `EGG TRACKER`.

## Development

The mod lives in this repository under `qol_suite/`. The gen1recomp engine is a separate project and is checked out alongside it for testing.

```sh
# Run the headless test suite against a local gen1recomp checkout
cd gen1recomp
ln -sfn ../qol_suite mods/qol_suite        # live mount (use a real symlink)
luajit mods/qol_suite/tests/<test>.lua
```

Tests are plain LuaJIT scripts; a test passes only if the process exits `0`. Two suites are version-scoped — `rby_compatibility_test` targets Red/Blue/Yellow and `gold_compatibility_test` targets Gold.

### CI

`.github/workflows/ci.yml` runs on every push and does three things:

1. **Tests the supported engine range** — the `engine_ref` matrix (currently `v0.1.95` and `v0.2.6`), cloning gen1recomp at each, live-mounting the mod, and running the headless suite.
2. **Standalone feature tests** — the full suite on the newest engine.
3. **Upstream coverage** — fails loudly if the matrix stops tracking upstream: it reads the manifest range and the matrix, then errors if the floor isn't tested, a cell is out of range, or the newest in-range upstream release is missing. This is the tripwire that stops the matrix from silently going stale.

The release workflow (`.github/workflows/release.yml`) re-runs validation on both engines, then builds and publishes `qol_suite-<version>.zip` plus `sha256sums.txt`.

## Credits

QoL Suite builds on work by the community and the Gen 1 Recompilation Project:

- **Pokemon Move Effectiveness Native** — native move-effectiveness display
- **Pokemon Move Freedom** — outside-battle move swapping
- **Pokemon Naming Enhancements** — naming quality-of-life flows
- **Pokemon Party Lead** — party-lead action
- **Gen 1 Recompilation Project** — the mod API, UI hooks, and engine

## License

See the gen1recomp project and the credited mods for their respective terms. This repository's `LICENSE` (if present) applies to the QoL Suite code.
