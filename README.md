# DawnCrystalTracker (WoW Retail AddOn)

Lightweight, **read-only** informational tracker for the L'ura encounter’s **Dawn Crystal** mechanic.

It treats **Extra Action Button presence** as the authoritative signal:
- Extra Action Button shown = you have the crystal
- Extra Action Button hidden = you do not have the crystal

## Install

1. Copy the folder `DawnCrystalTracker` into:
   - `World of Warcraft/_retail_/Interface/AddOns/`
2. Restart WoW or run `/reload`.

## Use

- `/dct` toggle tracker enabled/disabled
- `/dct debug` toggle debug mode
- `/dct test` simulate gain/loss
- `/dct reset` reset tracker position
- `/dct dump` dump last detection metadata

## Safety / Compliance

This addon only observes UI / aura / action state and displays information.
It does **not** click buttons, cast spells, use secure actions, or automate gameplay.

