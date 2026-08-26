#!/usr/bin/env python3
"""
Prune stale documentation.

Deletes files under documented/ whose source no longer exists in the lich-5
repository (or is excluded by config), and removes their manifest entries.
Without this, the published site keeps documenting modules that were deleted
upstream. Also filters manifest failed_files down to entries that still
correspond to eligible source files.

Usage:
    python prune_docs.py --source lich-source/lib [--documented documented]
                         [--manifest output/latest/manifest.json]
                         [--dry-run] [--reset-failed]
"""

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

DEFAULT_EXCLUSIONS = ['/critranks/', '/creatures/']


def load_exclusions() -> list:
    """Read exclusion patterns from config.yaml if available."""
    try:
        from config import ConfigManager, get_config
        ConfigManager.load()
        return list(get_config().processing.exclusions)
    except Exception:
        return DEFAULT_EXCLUSIONS


def eligible_source_files(source_root: Path, exclusions: list) -> set:
    """Relative POSIX paths of all non-excluded .rb files under source_root."""
    eligible = set()
    for f in source_root.rglob('*.rb'):
        rel = f.relative_to(source_root).as_posix()
        if not any(pat in '/' + rel for pat in exclusions):
            eligible.add(rel)
    return eligible


def manifest_key_to_rel(key: str) -> str:
    """
    Convert a manifest key (e.g. 'lich-source/lib/common/spell.rb', possibly
    with backslashes) to a source-root-relative POSIX path.
    """
    norm = key.replace('\\', '/')
    marker = '/lib/'
    idx = norm.find(marker)
    if idx != -1:
        return norm[idx + len(marker):]
    return norm.lstrip('/')


def main():
    parser = argparse.ArgumentParser(description='Prune stale documented files and manifest entries')
    parser.add_argument('--source', required=True,
                        help='Path to upstream source root (e.g. lich-source/lib)')
    parser.add_argument('--documented', default='documented',
                        help='Documented directory to prune (default: documented)')
    parser.add_argument('--manifest', default='output/latest/manifest.json',
                        help='Manifest to clean (default: output/latest/manifest.json)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Report what would be removed without removing it')
    parser.add_argument('--reset-failed', action='store_true',
                        help='Clear the manifest failed_files list entirely '
                             '(entries repopulate on future failures)')
    parser.add_argument('--strict', action='store_true',
                        help='Also delete documented files whose source still exists '
                             'upstream but is excluded by config (e.g. /creatures/). '
                             'Default keeps them (frozen but published).')
    args = parser.parse_args()

    source_root = Path(args.source)
    documented_root = Path(args.documented)
    if not source_root.is_dir():
        print(f"ERROR: source root not found: {source_root}")
        sys.exit(1)
    if not documented_root.is_dir():
        print(f"ERROR: documented directory not found: {documented_root}")
        sys.exit(1)

    exclusions = load_exclusions()
    eligible = eligible_source_files(source_root, exclusions)
    all_upstream = {f.relative_to(source_root).as_posix()
                    for f in source_root.rglob('*.rb')}
    print(f"Eligible source files: {len(eligible)} (exclusions: {exclusions})")

    # In default mode a documented file survives if its source exists upstream
    # at all (even excluded); in --strict mode it must be eligible.
    keep_set = eligible if args.strict else all_upstream

    # --- Prune documented files whose source is gone ---
    stale = []
    kept_excluded = 0
    for f in sorted(documented_root.rglob('*.rb')):
        rel = f.relative_to(documented_root).as_posix()
        if rel not in keep_set:
            stale.append((f, rel))
        elif rel not in eligible:
            kept_excluded += 1

    for f, rel in stale:
        if args.dry_run:
            print(f"  would delete: {rel}")
        else:
            f.unlink()
            print(f"  deleted: {rel}")

    if kept_excluded:
        print(f"  kept {kept_excluded} documented file(s) for config-excluded sources "
              f"(use --strict to delete)")

    # Remove directories left empty by pruning
    if not args.dry_run:
        for d in sorted((p for p in documented_root.rglob('*') if p.is_dir()),
                        key=lambda p: len(p.parts), reverse=True):
            try:
                d.rmdir()  # only succeeds when empty
                print(f"  removed empty dir: {d.relative_to(documented_root).as_posix()}")
            except OSError:
                pass

    # --- Clean the manifest ---
    manifest_path = Path(args.manifest)
    removed_processed = 0
    removed_failed = 0
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

        processed = manifest.get('processed_files', {})
        stale_keys = [k for k in processed if manifest_key_to_rel(k) not in keep_set]
        for k in stale_keys:
            if args.dry_run:
                print(f"  would remove manifest entry: {k}")
            else:
                del processed[k]
            removed_processed += 1

        failed = manifest.get('failed_files', [])
        if args.reset_failed:
            removed_failed = len(failed)
            if not args.dry_run:
                manifest['failed_files'] = []
        else:
            kept = [k for k in failed if manifest_key_to_rel(k) in keep_set]
            removed_failed = len(failed) - len(kept)
            if not args.dry_run:
                manifest['failed_files'] = kept

        if not args.dry_run and (removed_processed or removed_failed):
            manifest_path.write_text(json.dumps(manifest, indent=2, default=str),
                                     encoding='utf-8')
    else:
        print(f"WARNING: manifest not found: {manifest_path}")

    verb = 'Would prune' if args.dry_run else 'Pruned'
    print(f"\n{verb}: {len(stale)} stale documented file(s), "
          f"{removed_processed} manifest processed entr(ies), "
          f"{removed_failed} failed_files entr(ies)")


if __name__ == '__main__':
    main()
