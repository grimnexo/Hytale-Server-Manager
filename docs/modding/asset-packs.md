# Asset Packs

Asset Packs are zip/folder bundles that package data and art assets for Hytale. They are enabled by placing them in the game's Mods folder or by attaching them to a world created in-game. The Asset Pack format uses a `manifest.json` file and specific folders for assets like blocks, items, models, textures, and languages.

## Manifest Summary

The manifest contains metadata and loading rules. Common fields include:

- `Name`, `Description`, `Version`, `Group`
- `Authors`, `Website`
- `Dependencies`, `OptionalDependencies`, `LoadBefore`
- `DisabledByDefault`, `IncludesAssetPack`, `SubPlugins`

Exact fields and usage are documented in the official Asset Pack documentation.

## Common Folders (Blocks Example)

From the block creation docs, a minimal block asset layout uses:

- `resources/Server/Item/Items/` for server-side item/block JSON
- `resources/Server/Languages/en-US/items.lang` for names/descriptions
- `resources/Common/Models/Blocks/` for block models
- `resources/Common/Textures/Blocks/` for block textures
- `resources/Common/Icons/Blocks/` for UI icons

## Notes For This Tool

The Mod Tools GUI uses Pathlib for filesystem paths so the same project can be created on Linux, macOS, or Windows. The mod pack root and export locations are user-configurable.

## Sources

- Asset Pack overview and manifest fields
  - https://hytalemodding.dev/en/docs/official-documentation/worldgen/pack-tutorial/asset-packs
- Creating custom blocks (folder layout, items.lang)
  - https://hytalemodding.dev/en/docs/official-documentation/modding/custom-blocks
