#!/usr/bin/env python3
"""
YARD HTML Documentation Builder

Generates HTML documentation from documented Ruby files using YARD.
Outputs to docs/ directory for GitHub Pages hosting.

Usage:
    python build_html.py                           # Build from default documented/ dir
    python build_html.py --input ./documented      # Build from custom input dir
    python build_html.py --output ./docs           # Build to custom output dir
    python build_html.py --title "My Project"      # Custom documentation title
"""

import argparse
import re
import subprocess
import sys
import os
import tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from pathlib import Path
import logging
import shutil

# Import config (optional)
try:
    from config import ConfigManager, get_config
    HAS_CONFIG = True
except ImportError:
    HAS_CONFIG = False
    ConfigManager = None
    get_config = None

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# Receiver-style class method definitions (`def Char.name` inside
# `class Char`) make YARD invent a nested namespace (Lich::Common::Char::Char)
# and hang every method there, leaving the real class page empty. Upstream
# lich-5 uses this style pervasively (Lich, Script, Char, Win32, Spell, ...).
# The build rewrites them to the equivalent `def self.name` in a throwaway
# shadow copy of the input tree - committed sources stay byte-identical to
# upstream. In Ruby the two forms are identical inside the class body.
_BLOCK_OPEN_RE = re.compile(r'^(\s*)(?:class|module)\s+((?:\w+::)*[A-Z]\w*)\b')
_CLASS_SELF_RE = re.compile(r'^(\s*)class\s*<<\s*self\b')
_END_RE = re.compile(r'^(\s*)end\b')
_RECEIVER_DEF_RE = re.compile(r'^(\s*)def\s+([A-Z]\w*)\.')


def fix_receiver_defs(source: str):
    """
    Rewrite `def Foo.bar` to `def self.bar` on lines nested inside
    `class Foo` / `module Foo`.

    Receiver defs whose receiver is NOT the innermost enclosing class or
    module are left untouched (they legitimately target another constant).
    Tracking is indentation-based: an `end` whose indent equals the opener's
    indent closes the block, so def/if/begin bodies (indented deeper) never
    pop the stack early.

    Returns:
        (transformed_source, rewrite_count)
    """
    lines = source.split('\n')
    stack = []  # (indent, innermost class/module name or None for class << self)
    count = 0

    for i, line in enumerate(lines):
        m = _CLASS_SELF_RE.match(line)
        if m:
            stack.append((len(m.group(1)), None))
            continue

        m = _BLOCK_OPEN_RE.match(line)
        if m:
            stack.append((len(m.group(1)), m.group(2).split('::')[-1]))
            continue

        m = _END_RE.match(line)
        if m:
            if stack and stack[-1][0] == len(m.group(1)):
                stack.pop()
            continue

        m = _RECEIVER_DEF_RE.match(line)
        if m and stack and stack[-1][1] == m.group(2):
            lines[i] = line.replace('def %s.' % m.group(2), 'def self.', 1)
            count += 1

    return '\n'.join(lines), count


def _get_timeout(timeout_name: str, default: int) -> int:
    """Get timeout value from config or use default."""
    if HAS_CONFIG:
        try:
            config = get_config()
            return getattr(config.timeouts, timeout_name, default)
        except Exception:
            pass
    return default


class YARDHTMLBuilder:
    def __init__(self, input_dir: Path = None, output_dir: Path = None,
                 title: str = None, readme_file: Path = None, guides_dir: Path = None):
        """
        Initialize YARD HTML builder.

        Args:
            input_dir: Directory containing documented Ruby files
            output_dir: Output directory for HTML documentation
            title: Project title for documentation
            readme_file: Path to README file for documentation homepage
            guides_dir: Directory containing guide markdown files
        """
        self.input_dir = input_dir or Path(__file__).parent / "output" / "latest" / "documented"
        self.output_dir = output_dir or Path(__file__).parent / "docs"
        self.title = title or "Lich 5 Documentation"

        # Default to docs-readme.md if it exists and no readme specified
        if readme_file:
            self.readme_file = readme_file
        else:
            default_readme = Path(__file__).parent / "docs-readme.md"
            self.readme_file = default_readme if default_readme.exists() else None

        # Default to guides/ directory if it exists
        if guides_dir:
            self.guides_dir = guides_dir
        else:
            default_guides = Path(__file__).parent / "guides"
            self.guides_dir = default_guides if default_guides.exists() else None

        # Ensure input directory exists
        if not self.input_dir.exists():
            raise FileNotFoundError(f"Input directory not found: {self.input_dir}")

    def _yard_command(self) -> str:
        """Resolve the yard executable (handles yard.bat on Windows)."""
        return shutil.which('yard') or 'yard'

    def check_yard_installed(self) -> bool:
        """Check if YARD is installed and available."""
        try:
            timeout = _get_timeout('yard_version_check', 10)
            result = subprocess.run(
                [self._yard_command(), '--version'],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            if result.returncode == 0:
                logger.info(f"YARD version: {result.stdout.strip()}")
                return True
            else:
                logger.error("YARD command failed")
                return False
        except FileNotFoundError:
            logger.error("YARD is not installed. Install with: gem install yard")
            return False
        except subprocess.TimeoutExpired:
            logger.error("YARD version check timed out")
            return False

    def count_ruby_files(self) -> int:
        """Count Ruby files in input directory."""
        return len(list(self.input_dir.rglob("*.rb")))

    def prepare_shadow_tree(self) -> Path:
        """
        Copy the input tree to a temp directory and rewrite receiver-style
        class method defs (see fix_receiver_defs) in the copy.

        The shadow directory keeps the input dir's basename and YARD runs
        with the temp parent as cwd, so the '# File' source paths recorded
        in the generated HTML are identical to a direct build.

        Returns:
            The temp parent directory (caller must clean it up).
        """
        tmp_parent = Path(tempfile.mkdtemp(prefix='yard-shadow-'))
        shadow = tmp_parent / self.input_dir.name
        shutil.copytree(self.input_dir, shadow)

        total_rewrites = 0
        touched_files = 0
        for rb in shadow.rglob('*.rb'):
            with open(rb, 'r', encoding='utf-8') as f:
                source = f.read()
            fixed, count = fix_receiver_defs(source)
            if count:
                with open(rb, 'w', encoding='utf-8') as f:
                    f.write(fixed)
                total_rewrites += count
                touched_files += 1

        logger.info(
            f"Receiver-def fix: rewrote {total_rewrites} 'def Class.method' "
            f"defs to 'def self.method' in {touched_files} files (shadow copy only)"
        )
        return tmp_parent

    def build_html(self) -> bool:
        """
        Build HTML documentation using YARD.

        Returns:
            True if successful, False otherwise
        """
        ruby_file_count = self.count_ruby_files()
        if ruby_file_count == 0:
            logger.error(f"No Ruby files found in {self.input_dir}")
            return False

        logger.info(f"Found {ruby_file_count} Ruby files to document")
        logger.info(f"Building HTML documentation...")
        logger.info(f"  Input: {self.input_dir}")
        logger.info(f"  Output: {self.output_dir}")
        logger.info(f"  Title: {self.title}")

        # Build YARD command
        # Use 'doc' command to generate documentation
        # --output-dir: where to write HTML
        # --title: project title
        # --readme: README file for homepage
        # --files: additional files to include (if any)
        # The files to document are specified as positional arguments

        # Build in a shadow copy with receiver-style defs rewritten so YARD
        # attaches class methods to the right class (see fix_receiver_defs).
        # cwd is the shadow's parent and the input path stays relative, so
        # '# File' paths in the HTML match a direct build of input_dir.
        shadow_parent = self.prepare_shadow_tree()
        yard_cmd = [
            self._yard_command(), 'doc',
            str(Path(self.input_dir.name) / '**' / '*.rb'),
            '--output-dir', str(self.output_dir.resolve()),
            '--title', self.title,
            '--no-private',  # Don't document private methods
            '--protected',   # Document protected methods
        ]

        # Add README if provided
        if self.readme_file and self.readme_file.exists():
            yard_cmd.extend(['--readme', str(self.readme_file.resolve())])
            logger.info(f"  Using README: {self.readme_file}")

        # Add guides if directory exists
        if self.guides_dir and self.guides_dir.exists():
            guide_files = list(self.guides_dir.glob('*.md'))
            if guide_files:
                # YARD --files takes comma-separated list or multiple --files flags
                yard_cmd.extend(['--files', ','.join(str(f.resolve()) for f in guide_files)])
                logger.info(f"  Including {len(guide_files)} guide(s) from {self.guides_dir}")

        try:
            # Run YARD
            logger.info("Running YARD documentation generator...")
            timeout = _get_timeout('yard_doc_build', 300)
            result = subprocess.run(
                yard_cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(shadow_parent)
            )

            # Log YARD output
            if result.stdout:
                logger.info("YARD output:")
                for line in result.stdout.split('\n'):
                    if line.strip():
                        logger.info(f"  {line}")

            # Log YARD warnings/errors
            if result.stderr:
                logger.warning("YARD warnings/errors:")
                for line in result.stderr.split('\n'):
                    if line.strip():
                        logger.warning(f"  {line}")

            if result.returncode == 0:
                logger.info(f"✅ HTML documentation built successfully!")
                logger.info(f"📄 Output directory: {self.output_dir}")

                # Check if index.html was created
                index_file = self.output_dir / 'index.html'
                if index_file.exists():
                    logger.info(f"📖 Open {index_file} in a browser to view documentation")
                else:
                    logger.warning("index.html not found in output directory")

                return True
            else:
                logger.error(f"YARD failed with return code {result.returncode}")
                return False

        except subprocess.TimeoutExpired:
            logger.error("YARD command timed out (exceeded 5 minutes)")
            return False
        except Exception as e:
            logger.error(f"Error running YARD: {e}")
            return False
        finally:
            shutil.rmtree(shadow_parent, ignore_errors=True)

    def clean_output(self):
        """Remove existing output directory."""
        if self.output_dir.exists():
            logger.info(f"Cleaning existing output: {self.output_dir}")
            shutil.rmtree(self.output_dir)

    def copy_theme_assets(self):
        """Copy theme CSS to output directory."""
        assets_dir = Path(__file__).parent.parent / 'yard-assets'
        theme_css = assets_dir / 'css' / 'theme.css'

        if not theme_css.exists():
            logger.warning(f"Theme CSS not found: {theme_css}")
            return

        # Create css directory in output
        css_dir = self.output_dir / 'css'
        css_dir.mkdir(exist_ok=True)

        # Copy theme CSS
        shutil.copy(theme_css, css_dir / 'theme.css')
        logger.info(f"Copied theme CSS to {css_dir / 'theme.css'}")

    def inject_nav_helper(self) -> int:
        """
        Inject navigation helper JavaScript into generated HTML files.

        Returns:
            Number of files modified
        """
        assets_dir = Path(__file__).parent.parent / 'yard-assets'
        nav_helper = assets_dir / 'js' / 'nav-helper.js'

        if not nav_helper.exists():
            logger.warning(f"Navigation helper not found: {nav_helper}")
            return 0

        # Copy theme assets first
        self.copy_theme_assets()

        # Read the JavaScript
        with open(nav_helper, 'r', encoding='utf-8') as f:
            js_content = f.read()

        # Create the script tag to inject
        script_tag = f'<script type="text/javascript">\n{js_content}\n</script>\n</body>'

        # Find all HTML files
        html_files = list(self.output_dir.rglob("*.html"))
        modified_count = 0

        for html_file in html_files:
            try:
                with open(html_file, 'r', encoding='utf-8') as f:
                    content = f.read()

                # Replace </body> with script + </body>
                if '</body>' in content and 'quick-nav' not in content:
                    new_content = content.replace('</body>', script_tag)
                    with open(html_file, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    modified_count += 1
            except Exception as e:
                logger.warning(f"Could not inject nav helper into {html_file}: {e}")

        logger.info(f"Injected navigation helper into {modified_count} HTML files")
        return modified_count

    def verify_output(self) -> dict:
        """
        Verify the generated HTML documentation.

        Returns:
            Dictionary with verification results
        """
        if not self.output_dir.exists():
            return {'valid': False, 'error': 'Output directory does not exist'}

        index_file = self.output_dir / 'index.html'
        if not index_file.exists():
            return {'valid': False, 'error': 'index.html not found'}

        # Count generated HTML files
        html_files = list(self.output_dir.rglob("*.html"))
        css_files = list(self.output_dir.rglob("*.css"))
        js_files = list(self.output_dir.rglob("*.js"))

        return {
            'valid': True,
            'html_files': len(html_files),
            'css_files': len(css_files),
            'js_files': len(js_files),
            'index_file': index_file
        }


def main():
    parser = argparse.ArgumentParser(
        description='Build HTML documentation from documented Ruby files using YARD',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python build_html.py                                    # Build with defaults
  python build_html.py --input ./documented               # Custom input directory
  python build_html.py --output ./public                  # Custom output directory
  python build_html.py --title "My Ruby Project"          # Custom title
  python build_html.py --readme README.md                 # Include README
  python build_html.py --clean                            # Clean output first
        """
    )

    parser.add_argument(
        '--input',
        help='Input directory containing documented Ruby files (default: output/latest/documented)'
    )

    parser.add_argument(
        '--output',
        help='Output directory for HTML documentation (default: docs/)'
    )

    parser.add_argument(
        '--title',
        help='Project title for documentation (default: "Lich 5 Documentation")'
    )

    parser.add_argument(
        '--readme',
        help='Path to README file for documentation homepage'
    )

    parser.add_argument(
        '--clean',
        action='store_true',
        help='Clean output directory before building'
    )

    parser.add_argument(
        '--verify',
        action='store_true',
        help='Verify output after building'
    )

    parser.add_argument(
        '--config',
        help='Path to config.yaml file (default: config.yaml in repo root)'
    )

    args = parser.parse_args()

    # Load config if specified or available
    if HAS_CONFIG:
        if args.config:
            ConfigManager.load(args.config)
            logger.info(f"Loaded configuration from {args.config}")
        else:
            try:
                ConfigManager.load()
            except Exception:
                pass

    # Initialize builder
    try:
        input_dir = Path(args.input) if args.input else None
        output_dir = Path(args.output) if args.output else None
        readme_file = Path(args.readme) if args.readme else None

        builder = YARDHTMLBuilder(
            input_dir=input_dir,
            output_dir=output_dir,
            title=args.title,
            readme_file=readme_file
        )
    except FileNotFoundError as e:
        logger.error(str(e))
        sys.exit(1)

    # Check YARD installation
    if not builder.check_yard_installed():
        sys.exit(1)

    # Clean output if requested
    if args.clean:
        builder.clean_output()

    # Build HTML documentation
    success = builder.build_html()

    if not success:
        logger.error("Failed to build HTML documentation")
        sys.exit(1)

    # Inject navigation helper
    builder.inject_nav_helper()

    # Verify output if requested
    if args.verify:
        logger.info("Verifying generated documentation...")
        verification = builder.verify_output()

        if verification['valid']:
            logger.info("✅ Documentation verification passed")
            logger.info(f"  HTML files: {verification['html_files']}")
            logger.info(f"  CSS files: {verification['css_files']}")
            logger.info(f"  JS files: {verification['js_files']}")
            logger.info(f"  Index: {verification['index_file']}")
        else:
            logger.error(f"❌ Documentation verification failed: {verification['error']}")
            sys.exit(1)

    logger.info("Build complete!")
    sys.exit(0)


if __name__ == '__main__':
    main()
