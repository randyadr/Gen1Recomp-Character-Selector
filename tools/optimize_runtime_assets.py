#!/usr/bin/env python3
"""Post-conversion runtime optimizer for the Character Selector.

Keeps mesh topology intact. It only:
  * resamples overly dense embedded idle/jump matrix clips while preserving duration;
  * downsizes atlases that are vastly larger than the in-game character footprint.

The main.lua renderer performs the lossless position+UV vertex compaction at runtime.
Run this after regenerating model Lua files from source converters.
"""
from pathlib import Path
import argparse, math, re
from PIL import Image


def parse_nums(body):
    return [float(x) for x in re.split(r"[\s,]+", re.sub(r"--.*", "", body).strip()) if x]


def fmt(v):
    if abs(v) < 5e-12:
        v = 0.0
    return f"{v:.8g}"


def format_array(name, vals, per=16):
    lines = [f"  {name} = {{"]
    for i in range(0, len(vals), per):
        lines.append("    " + ", ".join(fmt(v) for v in vals[i:i + per]) + ",")
    lines.append("  },")
    return "\n".join(lines)


def resample(vals, bones, old_n, new_n):
    if len(vals) != bones * old_n * 16:
        raise ValueError(f"clip length mismatch: got {len(vals)}, expected {bones*old_n*16}")
    if new_n >= old_n:
        return vals
    out = []
    for bone in range(bones):
        base = bone * old_n * 16
        for nf in range(new_n):
            u = nf * (old_n - 1) / (new_n - 1) if new_n > 1 else 0.0
            f0 = int(math.floor(u))
            f1 = min(old_n - 1, f0 + 1)
            a = u - f0
            o0, o1 = base + f0 * 16, base + f1 * 16
            out.extend(vals[o0 + k] * (1 - a) + vals[o1 + k] * a for k in range(16))
    return out


def optimize_model(path, idle_max=180, jump_max=140):
    text = path.read_text(errors="ignore")
    bm = re.search(r"\bboneCount\s*=\s*(\d+)", text)
    if not bm:
        return []
    bones = int(bm.group(1))
    changes = []
    for clip, target in (("idle", idle_max), ("jump", jump_max)):
        cm = re.search(rf"\b{clip}FrameCount\s*=\s*(\d+)", text)
        if not cm:
            continue
        old_n = int(cm.group(1))
        if old_n <= target:
            continue
        pat = re.compile(rf"  {clip}Delta\s*=\s*\{{(.*?)\n  \}},", re.S)
        am = pat.search(text)
        if not am:
            continue
        vals = parse_nums(am.group(1))
        new_vals = resample(vals, bones, old_n, target)
        text = text[:am.start()] + format_array(clip + "Delta", new_vals) + text[am.end():]
        text = re.sub(rf"(\b{clip}FrameCount\s*=\s*){old_n}\b", rf"\g<1>{target}", text, count=1)
        changes.append(f"{clip} {old_n}->{target}")
    if changes:
        path.write_text(text)
    return changes


def resize_if_needed(path, max_size):
    if not path.exists():
        return None
    im = Image.open(path).convert("RGBA")
    if im.size == max_size:
        return None
    if im.width <= max_size[0] and im.height <= max_size[1]:
        return None
    old = im.size
    im = im.resize(max_size, Image.Resampling.LANCZOS)
    im.save(path, optimize=True)
    return old, max_size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    args = ap.parse_args()
    root = args.root
    for p in sorted((root / "data").glob("*.lua")):
        changes = optimize_model(p)
        if changes:
            print(p.name + ": " + ", ".join(changes))
    for name, size in (("yami_atlas.png", (2048, 1024)), ("ash_atlas.png", (1536, 1920))):
        change = resize_if_needed(root / "assets" / name, size)
        if change:
            print(f"{name}: {change[0]} -> {change[1]}")


if __name__ == "__main__":
    main()
