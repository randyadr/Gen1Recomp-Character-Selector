from pathlib import Path
import build_character_store as store


def required_files(c):
    if c.get("bundled"):
        return ["data/model.lua", "assets/red_atlas.png"]
    files = {c["data"], *c.get("atlases", []), *c.get("extra", [])}
    for variant in c.get("variants", []):
        if variant.get("data"):
            files.add(variant["data"])
        if variant.get("atlas"):
            files.add(variant["atlas"])
        for path in variant.get("atlasFrames", []) or []:
            files.add(path)
    return sorted(files)


available = []
for character in store.CHARS:
    if character.get("id") == "DEXTERS_MOM":
        print("SKIP DEXTERS_MOM: disabled until model is rebuilt")
        continue
    missing = [p for p in required_files(character) if not (store.ROOT / p).is_file()]
    if missing:
        print("SKIP", character["id"], "missing:", ", ".join(missing))
    else:
        print("BUILD", character["id"])
        available.append(character)

store.CHARS = available
store.main()
