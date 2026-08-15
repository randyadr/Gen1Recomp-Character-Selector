# Gen1Recomp Character Store

This branch is the remote catalog for the 3D Character Selector.

## Goals

- Keep the core Character Selector mod small.
- Let players browse a grid of characters with thumbnail previews.
- Let players download only the character packs they want.
- Keep every character free.
- Allow characters to be updated independently from the core selector.

## Catalog

`store/index.json` is the machine-readable catalog. The selector should fetch this file with Gen1Recomp's `mod.fetch` API and render its `characters` array as the in-game store grid.

The raw catalog URL is:

`https://raw.githubusercontent.com/randyadr/Gen1Recomp-Character-Selector/character-store/store/index.json`

## Character entry fields

- `id`: stable selector/runtime id.
- `name`: display name.
- `category`: Pokemon Trainers, Anime, or Random.
- `version`: character-pack version.
- `thumbnail`: path relative to `store/` for the grid preview.
- `package`: downloadable character-pack URL. `null` means the pack has not been published yet.
- `bundled`: true only for characters that remain inside the core mod.

## Planned package layout

Each downloadable character should be a self-contained `.red3dchar`/ZIP payload containing its generated model Lua, atlas images, optional variant atlases/models, metadata, and any selector-only data required by that character. Source FBXs do not need to ship inside the downloadable runtime pack.

Large packs should be published as GitHub Release assets instead of ordinary Git objects. The catalog's `package` field should point at the release asset URL.

## Thumbnails

Place store preview images in `store/thumbnails/` using the names referenced by `index.json`. Thumbnails should be small, square PNGs suitable for a grid view. They are previews only; runtime model assets belong in the downloadable pack.
