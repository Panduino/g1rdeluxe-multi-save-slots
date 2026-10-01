# Multiple Save Slots - Gen 3

Adds multiple independent save slots to Gen 3 games.

## Features

- **CONTINUE** opens a list of existing save slots.
- **SAVE** opens a slot picker before saving.
- **NEW SAVE** creates the next numbered slot and immediately uses it for the save.
- **MANAGE** lets you delete save slots.
- The currently active slot is marked with `*`.
- Existing Gen 3 save-slot data is handled by the game's built-in `SaveData` system.

## Save layout

Slots are stored separately under the Gen 3 game's save data:

`saves/<game version>/slot1.lua`  
`saves/<game version>/slot2.lua`  
`saves/<game version>/slot3.lua`

The mod does not replace the underlying save system; it selects which built-in slot is active.

## Install

Enable the mod in the mod manager.

This version is Gen 3-only.
