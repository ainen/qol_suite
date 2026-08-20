# QoL Suite

Optional quality-of-life, UI, and automation features for **Pokemon Red, Blue,
Yellow, and Gold**, packaged as one installable mod for the
[Gen 1 Recompilation Project](https://github.com/bryanthaboi/gen1recomp).

Everything is **opt-in and reversible**: the mod installs as a single package,
each feature is a toggle in the in-game Mods menu, and dependent settings hide
automatically when their parent feature is off. Nothing is forced on by default
unless it is a harmless display change.

## Compatibility

QoL Suite targets a **single engine range** and is version-gated at launch: the
launcher checks the mod against the running engine and refuses to load it
outside the supported range.

| | |
|---|---|
| **Mod version** | 1.4.0 |
| **Supported engine** | gen1recomp `>=0.1.95 <0.3.0` |
| **Newest tested engine** | **v0.2.12** (the current gen1recomp release) |
| **Minimum engine** | **v0.1.95** (the first release with native option-row `visible_if`) |
| **Games** | Red, Blue, Yellow (Gen 1) and Gold |

The engine range matters for two reasons:

- **Native option-row `visible_if`** — since gen1recomp **v0.1.95** the engine
  natively hides a dependent option row while its parent is off, re-shows it the
  moment the parent turns on, and restores a safe value when the parent is
  switched back off. QoL Suite 1.2.0 relies on this native behaviour, so it has
  **no custom visibility shim** — the in-game manager and the pre-game launcher
  stay in sync, and dependent rows never appear orphaned.
- **`>=0.1.95 <0.3.0`** — the floor is v0.1.95 (native `visible_if`), and the
  range is tested against both the floor and the current release (**v0.2.12**).

**Gen 1 vs Gold.** The option set adapts to the game:

- **Gen 1 (Red/Blue/Yellow):** `XP BAR`, `CAUGHT MARKER`, and `WALL BUMP SOUND`
  are available (Gold has its own native versions of the first two, so those
  are hidden there; Gold currently emits no movement-path bump cue).
- **Gold:** `STOP ON SHINY`, `CATCH SHINY ONLY`, `EGG TRACKER`, and the extra
  encounter-tracker detail rows (`SHOW TIME OF DAY`, `SHOW SWARMS`, `SHOW
  ROAMING`, `SHOW RARE`, `SHOW HEADBUTT`, `SHOW ROCK SMASH`, `SHOW BUG
  CONTEST`) are available; they are hidden in Gen 1.

**Renderer compatibility.** The Gen 1 XP bar and caught marker follow the
battle layout when `DRAMALESS_SHAPE`, `PotatoVoxel`, or `BATTLE ART VOXEL FORK`
is installed. Gold's Stadium 2 / Gen2 3D-Sprites renderer is supported too:
screen-space QoL overlays stay above its composed 3D frame while Gold-native
battle graphics remain native. The Gen 3-inspired UI Overhaul is supported as
well — its custom battle HUD renders first, then QoL's caught marker,
type-matchup label, and AUTO CATCH ball counts are placed in its screen-space
layout.

## Features

All features are opt-in and grouped by area. Dependent rows (marked with their
parent) hide automatically until the parent is enabled.

### Battle

- **TYPE MATCHUP** — Shows and colors the move's effectiveness.
- **LOW HEALTH ALARM** — Keeps or silences the low-HP battle siren.
- **EXP SHARE** — Gives battling Pokémon half of the battle's experience and
  splits the other half between non-fainted party members, like EXP.ALL.
- **SWAP MOVES** — Keeps newly learned moves in a pool and lets you swap one in
  immediately or equip it later from the party's MOVES action.
- **KEEP MOVE PP** — Keeps current PP when using SWAP MOVES. Requires SWAP
  MOVES.
- **AUTO BATTLE** — Chooses moves, switches when needed, and advances battle
  menus and messages.
- **STOP LOW HP** — Pauses AUTO BATTLE when the active Pokémon's HP gets low.
  Requires AUTO BATTLE.
- **PAUSE NEW ENTRY** — Pauses AUTO BATTLE on a new Pokédex entry. Requires
  AUTO BATTLE.
- **PAUSE EVOLUTION** — Pauses AUTO BATTLE when an evolution is offered.
  Requires AUTO BATTLE.
- **AUTO CATCH** — During wild battles, lowers HP, uses available status moves,
  and throws a Poké Ball. Requires AUTO BATTLE.
- **CATCH NEW ONLY** — Makes AUTO CATCH skip species already registered as
  caught. Requires AUTO CATCH.
- **CATCH SHINY ONLY** *(Gold only)* — Makes AUTO CATCH fire only against a
  shiny wild Pokémon; non-shiny encounters decline the catch. Requires AUTO
  CATCH.
- **AUTO CATCH TARGET** — Limits AUTO CATCH to one species selected in the
  Pokédex. Requires AUTO CATCH.
- **AUTO CATCH BALL** — Uses the best ball, worst ball, or Poké Balls only.
  Requires AUTO CATCH.
- **STOP NO BALLS** — Stops AUTO CATCH when no balls remain. Requires AUTO
  CATCH.
- **STOP ON TARGET** — Stops AUTO CATCH once the selected target species is
  caught. Requires AUTO CATCH TARGET.
- **SHOW BALL COUNTS** — Shows total and per-kind ball counts during AUTO
  CATCH. Requires AUTO BATTLE and AUTO CATCH.
- **XP BAR** *(Gen 1 only)* — Adds a Gold-style XP bar to Gen 1 battles.
- **CAUGHT MARKER** *(Gen 1 only)* — Enables the native caught marker in Gen 1
  battles. Older and external layouts derive the same marker from the player's
  imported battle assets, so no marker image is packaged.

### Automation (Gold)

- **STOP ON SHINY** *(Gold only)* — Pauses AUTO BATTLE on a shiny encounter.
  Requires AUTO BATTLE.
- **CATCH SHINY ONLY** *(Gold only)* — AUTO CATCH fires only against a shiny
  wild Pokémon. Requires AUTO CATCH.

### Field and bag

- **QUICK FIELD MOVES** — Adds quick overworld use for SURF, CUT, and STRENGTH
  in RBY. In Gold, it also removes the extra confirmation for HEADBUTT, ROCK
  SMASH, WHIRLPOOL, and WATERFALL when AUTO FIELD MOVES is enabled. FLASH is
  offered automatically when entering a dark area.
- **AUTO FIELD MOVES** — Uses supported field moves without the confirmation
  prompt. Requires QUICK FIELD MOVES.
- **USE HMs DIRECTLY** — Uses owned HMs without teaching them to a Pokémon.
  Badges and field conditions still apply.
- **SKIP CENTER TALK** — Skips the nurse's healing dialogue while keeping the
  normal healing animation and party restoration.
- **ENCOUNTER RATE** — Multiplies the normal step-based wild encounter rate,
  up to 200X. Fishing is unchanged.
- **BAG CATEGORIES** — Splits the bag into BALLS, TM/HM, KEY ITEMS, and ITEMS.
- **BAG SEARCH** — Searches the field bag by part of an item name.
- **AUTO SORT BAG** — Sorts bag items alphabetically when the bag opens.
- **QUICK USE ITEMS** — Opens repels, healing items, or field items with a
  shortcut from the field bag.
- **REUSABLE TMs** — Keeps TMs in the bag after a successful teach.

### Party

- **PARTY OVERVIEW** — Shows party HP, status, and move PP on the overworld.
- **PARTY CORNER** — Chooses the party overview corner. The party panel stacks
  cleanly with the minimap and encounter tracker when they share a corner.
- **PARTY ORDER** — Provides NATIVE, HEALTHY FIRST, LEVEL HIGH, and TYPE ORDER
  presets.
- **AUTO PARTY ORDER** — Applies the selected preset while roaming and moves
  fainted or low-HP Pokémon to the back. Requires PARTY OVERVIEW.
- **ENABLE TO FRONT** — Adds a TO FRONT action to the party menu.
- **EGG TRACKER** *(Gold only)* — Panel showing egg status, steps remaining,
  and Day-Care parents when available.

### Overworld

- **MINIMAP** — Shows a player-centered map with nearby connected areas,
  terrain, exits, item markers, and the player position.
- **MINIMAP CORNER** — Chooses the minimap corner.
- **MAP TRANSPARENCY** — Sets minimap transparency.
- **MINIMAP SIZE** — Sets the minimap size from 50% to 200%.
- **MINIMAP ZOOM** — Sets the minimap zoom from 50% to 200%.
- **MAP BORDER** — Chooses a rounded, square, or hidden border.
- **TRACKING** — Tracks a seen Pokédex entry and highlights its habitat on the
  minimap. Requires MINIMAP.
- **ENCOUNTER TRACKER** — Lists Pokémon available in the current area. Choose
  which land, surfing, fishing, tracked, rare, swarm, roaming, headbutt, Rock
  Smash, Bug-Catching Contest, and time-of-day sections are shown. Gold-only
  sections are hidden on Gen 1.
- **TRACKER CORNER** — Chooses the encounter tracker corner. Requires
  ENCOUNTER TRACKER.
- **WALL BUMP SOUND** *(Gen 1 only)* — Keeps or silences the sound played when
  the player walks into an impassable tile or overworld entity. It is enabled
  by default to preserve the native behavior.

### Interface and naming

- **POKÉDEX FILTERS** — Filters the Pokédex by seen, caught, unseen, current
  area, generation, and type.
- **FLOATING MENUS** — Removes the black area around menus while keeping the
  menu panels white.
- **SKIP CATCH NAME** — Skips the nickname prompt after catching a Pokémon.
- **RENAME NPC MON** — Allows eligible Pokémon from in-game trades to be
  renamed.
- **AUTO RENAME TRADES** — Restores the species name for eligible traded
  Pokémon. Requires RENAME NPC MON.
- **RENAME ANYWHERE** — Adds RENAME to the party menu.
- **RESET NAME** — Adds RESET to the party menu for nicknamed Pokémon.
  Requires RENAME ANYWHERE.

## Installation

Download the latest `qol_suite-*.zip` from
[GitHub Releases](https://github.com/ainen/qol_suite/releases) and import it
with **MODS > Import mod .zip**, or extract it to `mods/qol_suite/`. Enable
**QoL Suite** in the Mods menu and open its settings.

Do not install separate mods that provide the same features at the same time.

## Dependent options

Many options depend on a parent feature. QoL Suite declares this with the
engine's **native `visible_if`** condition (gen1recomp **v0.1.95**+): a
dependent row is hidden while its parent is off, reappears the moment the
parent turns on, and is restored to a safe value if the parent is switched back
off. Disabling AUTO CATCH or AUTO CATCH TARGET clears the selected catch
target.

> **Note:** a few automation options form a chain (e.g. *AUTO CATCH* → *AUTO
> CATCH TARGET* → *STOP ON TARGET*). Each row hides with its immediate parent,
> and the feature logic additionally requires the full chain to be enabled
> before it acts — so an option that is visible but whose grandparent is off
> simply has no effect.

## Development

The mod lives in this repository under `qol_suite/`. The gen1recomp engine is a
separate project and is checked out alongside it for testing.

```sh
# Run the headless test suite against a local gen1recomp checkout
cd gen1recomp
ln -sfn ../qol_suite mods/qol_suite        # live mount (use a real symlink)
luajit mods/qol_suite/tests/<test>.lua
```

Tests are plain LuaJIT scripts; a test passes only if the process exits `0`.
Two suites are version-scoped — `rby_compatibility_test` targets
Red/Blue/Yellow and `gold_compatibility_test` targets Gold.

### CI

`.github/workflows/ci.yml` runs on every push and does three things:

1. **Tests the supported engine range** — the `engine_ref` matrix (currently
   `v0.1.95` and `v0.2.10`), cloning gen1recomp at each, live-mounting the mod,
   and running the headless suite.
2. **Standalone feature tests** — the full suite on the newest engine.
3. **Upstream coverage** — fails loudly if the matrix stops tracking upstream:
   it reads the manifest range and the matrix, then errors if the floor isn't
   tested, a cell is out of range, or the newest in-range upstream release is
   missing. This is the tripwire that stops the matrix from silently going
   stale.

The release workflow (`.github/workflows/release.yml`) re-runs validation on
both engines, then builds and publishes `qol_suite-<version>.zip` plus
`sha256sums.txt`.

## Credits

QoL Suite builds on work by the community and the Gen 1 Recompilation Project:

- **Gen 1 Recompilation Project** — the mod API, UI hooks, and engine

## License

See the gen1recomp project and the credited mods for their respective terms.
This repository's `LICENSE` (if present) applies to the QoL Suite code.
