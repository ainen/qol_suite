# QoL Suite

QoL Suite is a collection of optional quality-of-life changes for Gen 1 and
Gold. Enable the features you want from the mod's settings page.

## Features

### Battle

- **TYPE MATCHUP** — Shows and colors the move's effectiveness.
- **LOW HEALTH ALARM** — Keeps or silences the low-HP battle siren.
- **XP BAR** — Adds a Gold-style XP bar to Gen 1 battles. Hidden on Gold.
- **CAUGHT MARKER** — Enables the native caught marker in Gen 1 battles. Older
  and external layouts derive the same marker from the player's imported
  battle assets, so no marker image is packaged. Hidden on Gold.
- **EXP SHARE** — Gives battling Pokémon half of the battle's experience and
  splits the other half between non-fainted party members, like EXP.ALL.
- **AUTO BATTLE** — Chooses moves, switches when needed, and advances battle
  menus and messages.
- **AUTO BATTLE SAFETY** — Optional stops for low party HP, no balls, a caught
  target, new Pokédex entries, and evolutions. Shiny stops are Gold-only.
- **AUTO CATCH** — During wild battles, lowers HP, uses available status moves,
  and throws a Poké Ball. Requires AUTO BATTLE.
- **CATCH NEW ONLY** — Makes AUTO CATCH skip species already registered as
  caught. Requires AUTO CATCH.
- **AUTO CATCH TARGET** — Limits AUTO CATCH to one species selected in the
  Pokédex. Requires AUTO CATCH.
- **AUTO CATCH BALL** — Uses the best ball, worst ball, or Poké Balls only.
  Requires AUTO CATCH.
- **SHOW BALL COUNTS** — Shows total and per-kind ball counts during AUTO
  CATCH. Requires AUTO BATTLE and AUTO CATCH.

### Overworld and interface

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
- **POKÉDEX FILTERS** — Filters the Pokédex by seen, caught, unseen, current
  area, generation, and type.
- **FLOATING MENUS** — Removes the black area around menus while keeping the
  menu panels white.

### Party, bag, and Pokémon

- **PARTY OVERVIEW** — Shows party HP, status, and move PP on the overworld.
- **PARTY CORNER** — Chooses the party overview corner. The party panel stacks
  cleanly with the minimap and encounter tracker when they share a corner.
- **PARTY ORDER** — Provides NATIVE, HEALTHY FIRST, LEVEL HIGH, and TYPE ORDER
  presets.
- **AUTO PARTY ORDER** — Applies the selected preset while roaming and moves
  fainted or low-HP Pokémon to the back. Requires PARTY OVERVIEW.
- **EGG TRACKER** — Gold-only panel showing egg status, steps remaining, and
  Day-Care parents when available.
- **SWAP MOVES** — Keeps newly learned moves in a pool and lets you swap one in
  immediately or equip it later from the party's MOVES action.
- **KEEP MOVE PP** — Keeps current PP when using SWAP MOVES. Requires SWAP
  MOVES.
- **BAG CATEGORIES** — Splits the bag into BALLS, TM/HM, KEY ITEMS, and ITEMS.
- **BAG SEARCH** — Searches the field bag by part of an item name.
- **AUTO SORT BAG** — Sorts bag items alphabetically when the bag opens.
- **QUICK USE ITEMS** — Opens repels, healing items, or field items with a
  shortcut from the field bag.
- **REUSABLE TMs** — Keeps TMs in the bag after a successful teach.
- **ENABLE TO FRONT** — Adds a TO FRONT action to the party menu.
- **SKIP CATCH NAME** — Skips the nickname prompt after catching a Pokémon.
- **RENAME NPC MON** — Allows eligible Pokémon from in-game trades to be
  renamed.
- **AUTO RENAME TRADES** — Restores the species name for eligible traded
  Pokémon. Requires RENAME NPC MON.
- **RENAME ANYWHERE** — Adds RENAME to the party menu.
- **RESET NAME** — Adds RESET to the party menu for nicknamed Pokémon.
  Requires RENAME ANYWHERE.

## Compatibility

QoL Suite supports gen1recomp 0.1.91 through the current 0.1.x releases and is
tested against v0.1.91 and v0.1.92 for Red, Blue, Yellow, and Gold. Gold uses
its built-in XP bar and caught marker, so those Gen 1 options are hidden there.
Gold-only encounter data and EGG TRACKER are hidden in Red, Blue, and Yellow.

Dependent controls stay hidden in the in-game mod manager until their parent
feature is enabled. Settings use the release manager's single ordered list.
The pre-game launcher may show the full list because it reads settings before
mod code runs; runtime parent checks remain active. Disabling AUTO CATCH or
AUTO CATCH TARGET clears the selected catch target.

The Gen 1 XP bar and caught marker follow the battle layout when DRAMALESS_SHAPE,
PotatoVoxel, or BATTLE ART VOXEL FORK is installed. Gold's Stadium 2 / Gen2
3D-Sprites renderer is also supported: screen-space QoL overlays stay above its
composed 3D frame, while Gold-native battle graphics remain native.
The Gen 3-inspired UI Overhaul is also supported: its custom battle HUD renders
first, then QoL's caught marker, type-matchup label, and AUTO CATCH ball counts
are placed in its screen-space layout.

## Installation

Download the latest `qol_suite-*.zip` from GitHub Releases and import it with
**MODS > Import mod .zip**, or extract it to `mods/qol_suite/`. Enable **QoL
Suite** in the Mods menu and open its settings.

Do not install separate mods that provide the same features at the same time.
