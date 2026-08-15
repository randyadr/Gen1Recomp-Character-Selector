from __future__ import annotations
import io, urllib.request, zipfile
from pathlib import Path
import build_character_store as store

ROOT = Path('.')
PACKAGE_DIR = ROOT / 'store' / 'packages'
RELEASES = [
    'https://github.com/randyadr/Gen1Recomp-Character-Selector/releases/download/v3.1.23/red_3d_player-v3_1_23-mod.zip',
    'https://github.com/randyadr/Gen1Recomp-Character-Selector/releases/download/v3.1.21/red_3d_player-v3.1.21.zip',
    'https://github.com/randyadr/Gen1Recomp-Character-Selector/releases/download/v2.8.73/red_3d_player-v2.8.73.zip',
]


def needed_paths():
    out = set()
    for c in store.CHARS:
        if c.get('bundled'):
            continue
        if c.get('data'):
            out.add(c['data'])
        out.update(c.get('atlases', []))
        out.update(c.get('extra', []))
        for v in c.get('variants', []) or []:
            if v.get('data'):
                out.add(v['data'])
            if v.get('atlas'):
                out.add(v['atlas'])
            out.update(v.get('atlasFrames', []) or [])
    return out


def strip_root(name):
    name = name.replace('\\', '/').lstrip('/')
    parts = name.split('/')
    for marker in ('data', 'assets'):
        if marker in parts:
            i = parts.index(marker)
            return '/'.join(parts[i:])
    return name


def recover_zip_bytes(body, needed, label):
    recovered = 0
    with zipfile.ZipFile(io.BytesIO(body)) as z:
        members = {}
        for name in z.namelist():
            rel = strip_root(name)
            if rel in needed and not name.endswith('/'):
                members[rel] = name
        for rel, name in members.items():
            dst = ROOT / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(z.read(name))
            needed.discard(rel)
            recovered += 1
            print(' recovered', rel, 'from', label)
    return recovered


def main():
    needed = {p for p in needed_paths() if not (ROOT / p).is_file()}
    if not needed:
        print('all store sources already present')
        return

    # v3.3.04+: character package ZIPs are the canonical self-hosted recovery
    # source. This keeps huge models out of the core branch while allowing
    # GitHub Actions to rebuild thumbnails, packages, and runtime packets.
    if PACKAGE_DIR.is_dir():
        for zp in sorted(PACKAGE_DIR.glob('*.zip')):
            if not needed:
                break
            try:
                recover_zip_bytes(zp.read_bytes(), needed, zp.as_posix())
            except Exception as exc:
                print(' package hydrate failed:', zp, exc)

    for url in RELEASES:
        if not needed:
            break
        print('hydrate from', url)
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                body = response.read()
            recover_zip_bytes(body, needed, url)
        except Exception as exc:
            print(' hydrate failed:', exc)
    if needed:
        print('still missing:', ', '.join(sorted(needed)))


if __name__ == '__main__':
    main()
