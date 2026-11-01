# SuQing's Fixed Gunshop Buyback | 蘇清的枪械商店固定收购模组

[中文](README.md) | English

A **Build 42.21 single-player** add-on for the ModernFirearmsSystem radio shop. Version **1.1.0** adds a fixed 122-item buyback list while retaining the original balance, random equipment stock and 12-hour refresh rule. Watches and precious-metal materials are enabled by default.

Carry a radio, use the weapon's **Inspect Weapon** context action and open the radio icon. Only currently sellable items are listed by default; disable that filter to inspect the full catalog.

**Sell All** settles eligible carried items across all categories in one transaction, including ordinary carried bags. It shows the count and expected payment and is independent of the current category filter. Favorite, worn and held items remain protected. Version 1.1.0 also settles single-player transactions directly through the shared trade logic instead of waiting up to eight seconds for a network acknowledgement after a completed sale.

Fixed currency prices are 10 for cash, 1000 for a money bundle, 50 for a silver coin and 250 for a gold coin. See the [installable mod notes](mod/SuQingMFSFixedBuyback_4221/README.txt) and [catalog manifest](docs/catalog-manifest.json) for scope and prices.

## Requirements, patches and installation

- Required original mod: [ModernFirearmsSystem](https://steamcommunity.com/sharedfiles/filedetails/?id=3633421539), Workshop ID `3633421539`, Mod ID `ModernFirearmsSystem`. Load this add-on after it. Original source code and resources are not bundled.
- This add-on's fixed Mod ID is `SuQingMFSFixedBuyback_4221`. Current version: **1.1.0**. It is maintained for Build 42.21 single-player and has no separate published Workshop item.
- Fully exit the game and protect the target save as appropriate. Copy `mod/SuQingMFSFixedBuyback_4221` into your user `Zomboid/mods` directory. Enable the original mod and this add-on in the intended save, preserve dependency order and restart. Install only one source for this Mod ID.
- [SuQing's Patch Collection](https://github.com/suching8848/suqing-project-zomboid-patches/) is **optional, not a dependency**. Its MFS optics, light and ammunition-visual fixes address separate original-mod issues; they do not supply fixed-buyback logic. Firearm Weight Charms is also independent and is not needed for this add-on.

## Repository contents

- `mod/SuQingMFSFixedBuyback_4221/`: the installable mod.
- `tools/build_catalog.py`: validates the explicitly reviewed vanilla item whitelist.
- `tools/run_backend_tests.py`: executes original MFS trade source and this add-on in the game's Kahlua VM with controlled fixtures.
- `tools/run_ui_tests.py`: executes original MFS UI source and this add-on for offline UI-logic checks.
- `tests/`: project-owned Kahlua helper source, controlled fixtures and assertions; no bundled game/MFS source.
- `docs/catalog-manifest.json`: portable whitelist evidence and source-file hashes.
- [Testing instructions](docs/TESTING.md): commands, required local sources and validation limits.
- `validation/` and `releases/`: local reports, compiled helpers and ZIPs, excluded from Git. Old personal deployment, backup and rollback scripts are also excluded and are not installation entry points.

## Behavior and validation limits

Buyback does not trust prices supplied by a client. Single-item and bulk transactions recalculate payment from the actual items. Favorite, held and worn items are protected, as are contents of favorited containers. The original character balance is reused; no new currency item is introduced.

Offline UI and inventory tests use controlled doubles. They do not establish correct rendering or persistence in a real save. This Git preparation did not launch the game, edit Workshop originals or enable other mods. Disabling the add-on restores the original MFS buyback behavior while preserving the existing balance.

All installable package files, the version and Mod ID remain unchanged during Git preparation. Offline runners invoke a Kahlua helper main class rather than the game client. Building and packaging do not deploy files to a personal save.

No open-source license has been assigned. Project Zomboid and ModernFirearmsSystem remain the work of their respective authors; this repository contains the independent add-on, project-owned verification tools and compatibility metadata.
