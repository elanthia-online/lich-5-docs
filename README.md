# Lich 5 Documentation

YARD API documentation for the [Lich 5](https://github.com/elanthia-online/lich-5) Ruby scripting engine, published to GitHub Pages. Most of lich-5 is hand-documented upstream; AI (OpenAI, Anthropic, or Gemini) fills the gaps — and only the gaps.

## Overview

- 📚 **Searchable HTML API reference** hosted on GitHub Pages
- 🔍 **Human-reviewed**: every documentation change goes up as a pull request; nothing is published until a person reviews the diffs and merges
- 🛡️ **Non-destructive AI**: a coverage checker finds undocumented classes/methods and the AI documents *only those* — existing hand-written docs are never touched, rewritten, or duplicated
- ⚡ **Incremental**: SHA256 code hashes skip unchanged files; fully-documented files cost zero API calls
- 🚨 **Fails loudly**: a provider preflight catches dead API keys/exhausted balances before any file is attempted, and high failure rates fail the run instead of silently publishing stale docs

## The Flow

```
Pull lich-5 → diff via manifest → coverage-check changed files
  → AI documents ONLY undocumented anchors → prune docs for deleted sources
  → OPEN PULL REQUEST  ←  human reviews the diffs here
  → merge → build HTML → deploy          (automatic on merge)
```

## Quick Start

### Prerequisites

- Python 3.11+
- Ruby 3.0+ with YARD gem
- API key for OpenAI, Anthropic, or Gemini

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/elanthia-online/lich-5-docs.git
   cd lich-5-docs
   ```

2. **Install Python dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Install YARD**
   ```bash
   gem install yard
   ```

4. **Configure API key**
   ```bash
   cp .env.example .env
   # Edit .env and add your API key
   ```

### Usage

#### Generate Documentation

```bash
# Incremental build (skip unchanged files)
python scripts/generate_docs.py /path/to/lich-5/lib \
  --provider anthropic \
  --output-structure mirror

# Full rebuild (reprocess all files)
python scripts/generate_docs.py /path/to/lich-5/lib \
  --provider anthropic \
  --output-structure mirror \
  --force-rebuild

# Single file (for testing)
python scripts/generate_docs.py \
  --file /path/to/lich-5/lib/gemstone/psms/feat.rb \
  --provider anthropic \
  --output-structure mirror
```

#### Validate Documentation

```bash
# Validate all files
python scripts/validate_docs.py --dir documented

# Validate single file
python scripts/validate_docs.py --file documented/global_defs.rb
```

#### Build HTML Documentation

```bash
# Generate HTML website
python scripts/build_html.py --input ./documented --output ./docs --clean
```

## GitHub Actions Workflows

The project includes 4 GitHub Actions workflows for automated documentation:

### 1. Update Documentation (Opens PR) — use this one
**Path:** `.github/workflows/update-docs.yml`

The everyday workflow: clones lich-5, detects changes via the manifest, sends
ONLY undocumented code to the AI (changes that already carry YARD docs cost
nothing), prunes docs for deleted sources, and **opens a pull request** with
the diffs for human review. Nothing is published without a human merging the
PR — merging triggers the HTML build and Pages deploy automatically
(build-html.yml runs on push to main).

Fails the run — with no PR opened — if the provider preflight fails or too
many files error.

**Inputs:**
- `provider`: LLM provider (anthropic, openai, gemini, mock; default: anthropic)
- `source_repo`: Source repository (default: `elanthia-online/lich-5`)
- `source_branch`: Branch to document (default: `main`)

**One-time repo setting:** Settings → Actions → General → enable
*"Allow GitHub Actions to create and approve pull requests"*.

### 2. Generate Documentation
**Path:** `.github/workflows/generate-docs.yml`

Generation only — batch, or a single file via the `file_path` input. Also
**opens a pull request** for human review instead of committing to main.

**Inputs:**
- `file_path`: single file (e.g. `lib/gemstone/psms/feat.rb`); empty = batch
- `provider`, `source_repo`, `source_branch`: as above
- `full_rebuild`: reprocess all files, ignoring the manifest (still non-destructive)
- `force_regenerate`: **DESTRUCTIVE** — strip all existing YARD docs (including
  hand-written upstream docs) and regenerate from scratch

### 3. Validate Documentation
**Path:** `.github/workflows/validate-docs.yml`

Validates all documented files using YARD.

### 4. Build HTML & Deploy
**Path:** `.github/workflows/build-html.yml`

Generates the static HTML site and deploys it to GitHub Pages. Runs
**automatically when a docs PR is merged to main** (push trigger filtered to
`documented/**`, `guides/**`, `.yardopts`), and can also be dispatched
manually.

**Inputs (manual dispatch only):**
- `title`: Documentation title (default: "Lich 5 Documentation")
- `clean`: Clean output directory before building (default: `true`)
- `deploy`: Deploy to GitHub Pages after build (default: `true`)

## Project Structure

```
lich-5-docs/
├── documented/              # YARD-documented Ruby files (mirrors lich-5/lib structure)
│   ├── common/
│   ├── gemstone/
│   └── ...
├── docs/                    # Generated HTML (created/committed by build-html.yml)
├── guides/                  # Hand-written guide pages published with the site
├── yard-assets/             # Custom CSS/JS for the generated site
├── output/latest/
│   └── manifest.json        # Incremental build tracking (committed)
├── scripts/
│   ├── generate_docs.py     # Main documentation generator (gap-fill)
│   ├── prune_docs.py        # Removes docs for deleted upstream sources
│   ├── validate_docs.py     # YARD validation wrapper
│   ├── build_html.py        # HTML site builder
│   └── test_provider.py     # Provider connectivity diagnostic
├── src/
│   ├── yard_coverage.py     # Coverage checker (finds undocumented anchors)
│   ├── config.py            # config.yaml loader
│   ├── validation.py        # Pre-save YARD validation
│   └── providers/           # LLM providers (openai, anthropic, gemini, mock)
└── tests/                   # pytest suite
```

## How It Works

### 1. Generation (gap-fill)
- Clones the lich-5 repository
- Skips files whose code hash matches the manifest (SHA256 of code, comments excluded)
- For changed/new files, `src/yard_coverage.py` lists anchors (classes, modules,
  methods, non-trivial constants) that lack a YARD doc block
- The AI receives the file plus an explicit allowlist of those anchors and returns
  structured JSON: `[{line_number, anchor, indent, comment}, ...]`
- Comments are inserted **only at approved anchor lines**; anything else the AI
  returns is dropped. Existing documentation is never modified
- A file with no gaps is synced through with **zero AI calls**

### 2. Human Review
- Changes are pushed to a branch and opened as a **pull request**
- The PR body includes a review checklist; the diff should contain only added
  comment blocks (and pruned deletions)
- Nothing reaches main or the published site without a human merge

### 3. Build & Deploy (automatic on merge)
- Merging the PR triggers `build-html.yml`
- Runs `yard doc` → `docs/`, verifies output, commits, and deploys to GitHub Pages

## Configuration

### Environment Variables

```bash
# LLM Provider (anthropic, openai, gemini)
LLM_PROVIDER=anthropic

# API Keys (only one required based on provider)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
```

### Provider Options

The system supports three LLM providers (models configured in `config.yaml`):

- **Anthropic** (default): Uses `claude-haiku-4-5` model ($1/$5 per 1M tokens, see [Anthropic pricing](https://www.anthropic.com/pricing))
- **OpenAI**: Uses `gpt-4o-mini` model (paid, see [OpenAI pricing](https://openai.com/api/pricing/))
- **Gemini**: Uses `gemini-2.5-flash` model (free tier available, see [Google AI pricing](https://ai.google.dev/pricing))

Because generation is coverage-based, incremental runs against an
already-documented lich-5 tree make **zero** AI calls regardless of provider.
A preflight request runs before every batch, so a dead key, exhausted balance,
or retired model ID fails the run up front instead of failing every file.

For current pricing and rate limits, consult the provider's official documentation.

## Development

### Running Tests

```bash
pytest tests/
```

### Testing Without API Costs

```bash
# Use mock provider (no API calls)
python scripts/generate_docs.py /path/to/source --provider mock
```

### Checking Provider Status

```python
from providers import ProviderFactory

validation = ProviderFactory.validate_environment()
print(validation)  # Shows provider, API key status, warnings
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Detailed technical documentation for developers
- **[.env.example](.env.example)** - Environment variable template
- **[Generated Documentation](https://elanthia-online.github.io/lich-5-docs/)** - Live documentation website

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is independent of the Lich 5 project and is used for documentation purposes.

## Acknowledgments

- **Lich 5** - [elanthia-online/lich-5](https://github.com/elanthia-online/lich-5)
- **YARD** - Ruby documentation tool
- **OpenAI, Anthropic, Google** - AI providers for documentation generation

---

**Built with ❤️ using AI-powered documentation generation**
