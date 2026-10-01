# Multiple Save Slots - Gen 3

Adds multiple independent save slots to Gen 3 games.

## Features

- **CONTINUE selects from the available save slots before loading.
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


### Gen 3 menu behavior

- The title/continue menu contains **SELECT SAVE** directly above **NEW GAME**.
- **SELECT SAVE** chooses the save slot that CONTINUE will load.
- **SAVE** in the in-game FireRed Start menu first asks which existing slot to overwrite or lets you create a new slot.
- The selected save slot becomes the active slot before the native FireRed save screen writes the game.
- Therefore, the most recently saved slot is always the active slot on the next launch.
- **MANAGE SAVES** is available from the save-slot picker for deleting non-active slots.
