# Nuzi Core v1.0.0

## Highlights

- Promoted `nuzi-core` to `1.0.0` as the stable shared runtime for the current Nuzi addon stack.
- Consolidated shared addon infrastructure into one maintained dependency for loading, logging, events, commands, settings, scheduler, render gating, and shared UI helpers.
- Replaced `addonlibrary` as the dependency target for migrated Nuzi release manifests.

## Included Library Features

- Settings stores with defaults, legacy migration, mirror writes, backups, and profiles.
- Tickers and multi-loop schedulers for throttled `UPDATE` work.
- Managed event registration and cleanup helpers.
- Local chat command routing helpers.
- Shared widget and saved-position helpers for draggable UI.

## Credits

- Original AddonLibrary UI widget and Base64 pieces remain credited to Misosoup and contributors.
