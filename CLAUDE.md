# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository generates YARD documentation for the **Lich 5 Ruby project** (elanthia-online/lich-5) and publishes it to GitHub Pages. Most of upstream lich-5 is already hand-documented; the AI's job is to **fill gaps only** — it must never touch, rewrite, or duplicate existing documentation.

**Documentation Flow:**
```
Pull lich-5 → diff via manifest hashes → coverage-check changed files
  → AI documents ONLY undocumented anchors → prune stale docs
  → OPEN PULL REQUEST (human reviews the diffs)
  → human merges → build HTML → deploy   (automatic on merge)
```

**Nothing reaches main or the published site without a human merging a PR.**

## Core Principles (do not regress these)

1. **Non-destructive by default.** `generate_docs.py` runs the coverage checker
   ([src/yard_coverage.py](src/yard_coverage.py)) on each file and sends the AI an explicit
   allowlist of undocumented anchors. Entries resolving anywhere else are dropped at
   insertion time. A fully-documented file costs **zero** API calls. The old
   strip-everything-and-regenerate behavior still exists but only behind
   `--force-regenerate` (destructive, opt-in).
2. **Fail loudly.** A provider **preflight check** runs before any batch (catches dead
   API keys / exhausted balances / retired models). The script exits non-zero when all
   attempted files fail or the failure rate exceeds `--fail-threshold` (default 0.25),
   which fails the CI job before anything is committed or deployed. This exists because
   the 2026-08-17 run failed all ~265 files on a zero-credit OpenAI account while the
   workflow stayed green and deployed stale docs.
3. **The hash algorithm is frozen.** `compute_code_hash()` hashes code only (comments
   excluded). Changing it invalidates every hash in the committed manifest and forces a
   full paid reprocess. Tests document this intentionally.
4. **Human verification gate.** Generation workflows never push to main - they open a
   PR (peter-evans/create-pull-request) containing only `documented/**` and the
   manifest, with review instructions in the body. `build-html.yml` triggers on push
   to main (paths-filtered to source content, not `docs/`), so merging the PR is what
   builds and deploys. Do not add direct-commit paths back into generation workflows.

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| **update-docs.yml** | manual | The everyday pipeline: clone lich-5 → incremental generate (gap-fill) → prune → **open PR** for human review. Use this one. |
| **generate-docs.yml** | manual | Generation only (batch or single file via `file_path`) → **opens PR**. Inputs: `provider`, `source_repo`, `source_branch`, `full_rebuild` (ignore manifest; still non-destructive), `force_regenerate` (DESTRUCTIVE strip+regen). |
| **build-html.yml** | **auto on merge to main** (paths: documented/**, guides/**, .yardopts) + manual | Build docs/ + deploy Pages. This is the post-merge deploy step. |
| **validate-docs.yml** | manual | YARD validation report (`warnings.txt` artifact). |

**One-time repo setting:** Settings → Actions → General → enable
*"Allow GitHub Actions to create and approve pull requests"* — required for the
PR-opening workflows.

## Key Scripts (all in scripts/, importing from src/)

- **scripts/generate_docs.py** — generator. Gap-fill by default; `--force-regenerate`
  for destructive rebuild; `--fail-threshold` controls hard-fail; preflight before
  batches. Parallel workers per provider (config.yaml). Non-interactive-safe in CI.
- **src/yard_coverage.py** — coverage checker. CLI:
  `python src/yard_coverage.py file.rb` or `--dir lib [--uncovered]`.
  Finds documentable anchors (class/module/def/non-trivial constants), skips private
  sections and `:nodoc:`/`@!visibility` code, and reports which lack doc blocks.
- **scripts/prune_docs.py** — deletes `documented/` files whose upstream source is gone
  and cleans their manifest entries; `--strict` also removes docs for config-excluded
  sources (e.g. `/creatures/`); `--reset-failed` clears the failed list.
- **scripts/validate_docs.py** — YARD validation wrapper (exit 0 unless `--strict`).
- **scripts/build_html.py** — `yard doc` from documented/ → docs/ (`--clean` recommended).
- **scripts/test_provider.py** — provider connectivity diagnostic.

## Incremental Build System

- **Manifest:** `output/latest/manifest.json` (committed). Maps source path →
  SHA256-of-code hash. `is_file_processed()` checks the committed `documented/` dir at
  repo root (NOT `output/latest/documented/`).
- **failed_files** is self-maintaining: a later success removes the entry
  (`mark_file_processed`). Entries are paths like `lich-source/lib/...`.
- Changed upstream file → hash mismatch → file re-synced from upstream + gaps filled →
  new hash stored. Comment-only upstream changes do NOT trigger reprocessing (by design).

## Directory Structure

```
documented/               # Committed YARD-documented Ruby files (mirrors lich-5/lib)
docs/                     # Generated HTML (created/committed by build-html.yml on merge)
guides/                   # Hand-written guide pages published with the site
yard-assets/              # Custom CSS/JS used by scripts/build_html.py
output/latest/manifest.json  # Incremental tracking (committed; everything else ignored)
scripts/                  # All pipeline entry points (generate/prune/validate/build)
src/yard_coverage.py      # Coverage checker
src/providers/            # LLM providers (openai, anthropic, gemini, mock)
tests/                    # pytest suite - keep green (python -m pytest tests/)
```

## Local Commands

```bash
pip install -r requirements.txt
gem install yard                     # for validation + HTML build

# Everyday incremental run (gap-fill only; $0 when everything is documented)
python scripts/generate_docs.py /path/to/lich-5/lib --provider openai --output-structure mirror

# Coverage report
python src/yard_coverage.py --dir /path/to/lich-5/lib --uncovered

# Prune stale docs after upstream deletions
python scripts/prune_docs.py --source /path/to/lich-5/lib --dry-run

# Pipeline test without API calls (mock returns valid JSON)
python scripts/generate_docs.py /path/to/lich-5/lib --provider mock --output /tmp/test

# Tests
python -m pytest tests/
```

## Provider Costs & Models (config.yaml)

- **openai** `gpt-4o-mini` — default
- **anthropic** `claude-haiku-4-5` — $1/$5 per 1M tokens (claude-3-haiku retired Apr 2026)
- **gemini** `gemini-2.5-flash` — verify ID before use; severe rate limits
- **mock** — free; returns schema-valid JSON; used for pipeline testing

Incremental runs on documented upstream cost ~$0 (coverage checker skips AI calls).
The preflight check catches retired model IDs and dead keys before the batch starts.

## Gitignore Pattern for Manifest

```gitignore
output/*                      # Ignore all in output/
!output/latest/               # But allow latest/ subdirectory
output/latest/*               # Ignore everything in latest/
!output/latest/manifest.json  # Except manifest.json
```
Required because you cannot un-ignore a file inside an ignored directory.

## Troubleshooting

- **"Output file missing, reprocessing" for all files** → `is_file_processed()` must
  check `Path('documented')`, not `self.output_dir / 'documented'`.
- **Everything failing / preflight fails** → API key dead, balance exhausted, or model
  retired. The run aborts before attempting files; fix credentials, re-run.
- **AI duplicated an existing doc block** → should be impossible: insertion is
  restricted to coverage-checker-approved lines and `has_doc_block()` re-checks at
  insertion. If it happens, treat as a bug in `src/yard_coverage.py` classification.
- **Docs exist for deleted upstream files** → run prune (part of both batch workflows).
- **YARD "Cannot resolve link" warnings** at build → expected; references to Lich core
  runtime objects outside the documented set.
- **`def ClassName.method` YARD crash** → replace with `def self.method` upstream.

## Maintenance

When lich-5 changes: run **update-docs.yml**, then **review and merge the PR it
opens**. The merge triggers build + deploy automatically. The run fails visibly (no
PR) if generation is broken.

PR review checklist (also in the PR body):
- Diffs should be comment additions above undocumented code + pruned deletions only
- Any modified or deleted CODE line means a pipeline bug - don't merge, investigate
- Read the AI-written comments for accuracy; the AI is instructed never to invent
  behavior, but the human gate exists precisely to catch it if it does
