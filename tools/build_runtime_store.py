from __future__ import annotations
import base64, json, os, zlib
from pathlib import Path
from PIL import Image
import build_character_store as store

ROOT = Path(os.environ.get("STORE_ROOT", "."))
OUT = Path(os.environ.get("STORE_OUT", "store_build"))
RAW_BASE = os.environ.get(
    "STORE_RAW_BASE",
    "https://raw.githubusercontent.com/randyadr/Gen1Recomp-Character-Selector/character-store/store",
)
MAGIC_V2 = b"RED3DREMOTE2\n"
MAGIC_V3 = b"RED3DREMOTE3\n"


def required_files(c):
    if c.get("bundled"):
        return []
    files = {c["data"], *c.get("atlases", []), *c.get("extra", [])}
    for v in c.get("variants", []) or []:
        if v.get("data"):
            files.add(v["data"])
        if v.get("atlas"):
            files.add(v["atlas"])
        for p in v.get("atlasFrames", []) or []:
            files.add(p)
    return sorted(files)


def build_one(c):
    if c.get("bundled"):
        return None
    missing = [p for p in required_files(c) if not (ROOT / p).is_file()]
    if missing:
        print("SKIP RUNTIME", c["id"], "missing:", ", ".join(missing))
        return None

    model_paths = []
    atlas_paths = []
    if c.get("data"):
        model_paths.append(c["data"])
    atlas_paths.extend(c.get("atlases", []))
    for v in c.get("variants", []) or []:
        if v.get("data"):
            model_paths.append(v["data"])
        if v.get("atlas"):
            atlas_paths.append(v["atlas"])
        atlas_paths.extend(v.get("atlasFrames", []) or [])
    selector_idle = None
    if c.get("id") == "BELLESTARMON" and c.get("extra"):
        selector_idle = c["extra"][0]
        model_paths.append(selector_idle)

    model_paths = list(dict.fromkeys(model_paths))
    atlas_paths = list(dict.fromkeys(atlas_paths))

    files = []
    payload = bytearray()
    for rel in model_paths:
        raw = (ROOT / rel).read_bytes()
        packed = zlib.compress(raw, 9)
        files.append({
            "path": rel,
            "kind": "lua",
            "codec": "zlib",
            "length": len(packed),
        })
        payload.extend(packed)

    for rel in atlas_paths:
        image = Image.open(ROOT / rel).convert("RGBA")
        raw = image.tobytes()
        packed = zlib.compress(raw, 9)
        files.append({
            "path": rel,
            "kind": "rgba8",
            "codec": "zlib",
            "width": image.width,
            "height": image.height,
            "length": len(packed),
        })
        payload.extend(packed)

    fields = dict(c.get("fields", {}))
    header = {
        "schema": 2,
        "id": c["id"],
        "name": c["name"],
        "category": c["category"],
        "section": c.get("section", "MISC"),
        "data": c.get("data"),
        "atlases": c.get("atlases", []),
        "fields": fields,
        "variants": c.get("variants", []),
        "selector_idle": selector_idle,
        "files": files,
    }
    header_bytes = json.dumps(header, separators=(",", ":")).encode("utf-8")
    binary_v2 = MAGIC_V2 + str(len(header_bytes)).encode("ascii") + b"\n" + header_bytes + payload

    # v3 is deliberately ASCII-only. On Windows Gen1Recomp's curl GET body
    # travels through a text-mode popen pipe; an arbitrary binary 0x1A can be
    # interpreted as EOF before the engine's HTTP status marker. Base64 keeps
    # the exact proven v2 packet while making the transport safe on every host.
    body = MAGIC_V3 + base64.b64encode(binary_v2) + b"\n"

    out = OUT / "runtime" / (c["id"].lower() + ".r3dchar")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(body)
    assert all(b in b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\r\nRED3MOT" for b in body)
    print("runtime", out.name, round(len(body) / 1048576, 2), "MiB", "text-safe")
    return out


def main():
    index_path = OUT / "index.json"
    doc = json.loads(index_path.read_text())
    by_id = {row.get("id"): row for row in doc.get("characters", [])}
    for c in store.CHARS:
        out = build_one(c)
        row = by_id.get(c.get("id"))
        if row is not None and out is not None:
            row["runtime_url"] = RAW_BASE + "/runtime/" + out.name
            row["runtime_size"] = out.stat().st_size
            row["hot_load"] = True
            row["runtime_format"] = 3
        elif row is not None:
            row["hot_load"] = False
    index_path.write_text(json.dumps(doc, indent=2) + "\n")


if __name__ == "__main__":
    main()
