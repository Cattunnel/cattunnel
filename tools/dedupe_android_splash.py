#!/usr/bin/env python3
"""Deduplicate byte-identical Android splash resources after splash generation.

Run after flutter_native_splash:create. No pixels, scaling, or theme colors change.
Use --check to verify without writing. Fails before writing if artwork differs.
"""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'android/app/src/main/res'
    duplicates = sorted(root.glob('drawable-*/android12splash.png'))
    for duplicate in duplicates:
        density = duplicate.parent.name.split('-')[-1]
        original = root / f'drawable-{density}/splash.png'
        if not original.exists() or duplicate.read_bytes() != original.read_bytes():
            raise SystemExit(f'Refusing to change distinct artwork: {duplicate.relative_to(root)}')
    styles = [root / 'values-v31/styles.xml', root / 'values-night-v31/styles.xml']
    references = [p for p in styles if '@drawable/android12splash' in p.read_text()]
    if args.check:
        if duplicates or references:
            raise SystemExit(f'{len(duplicates)} byte-identical duplicate splash PNGs; {len(references)} old references')
        print('OK: Android splash artwork is shared across OS versions and themes')
        return
    saved = sum(p.stat().st_size for p in duplicates)
    for style in references:
        style.write_text(style.read_text().replace('@drawable/android12splash', '@drawable/splash'))
    for duplicate in duplicates:
        duplicate.unlink()
    print(f'Removed {len(duplicates)} byte-identical files ({saved} source bytes); preserved each density and theme')


if __name__ == '__main__':
    main()
