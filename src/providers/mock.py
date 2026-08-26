"""
Mock Provider for Testing
Simulates LLM responses without making API calls
"""

import json
import logging
import re
import time
from typing import Optional
from .base import LLMProvider, ProviderConfig

logger = logging.getLogger(__name__)


class MockProvider(LLMProvider):
    """Mock provider for testing and dry runs"""

    def __init__(self, config: Optional[ProviderConfig] = None):
        if config is None:
            config = ProviderConfig(
                name="mock",
                model="mock-model",
                max_tokens=4096,
                temperature=0.0,
                # Simulate rate limits for testing
                requests_per_minute=15,
                requests_per_day=1500
            )

        super().__init__(config)
        self.response_template = """
# Mock Documentation Generated

## Class: {class_name}

Mock documentation for testing purposes.

### Methods

# {method_name}
# Mock description of the method
#
# @param param1 [String] mock parameter description
# @return [Object] mock return value
# @example
#   # Mock example usage
#   result = {method_name}("test")
# @note This is mock documentation for testing
"""

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """
        Generate a mock response that matches what the pipeline expects:
        - preflight/health-check prompts get "OK"
        - documentation prompts get a VALID JSON array of comment entries,
          derived from the target list (gap-fill mode) or the numbered
          source listing (force-regenerate mode)

        Args:
            prompt: The user prompt (analyzed to generate relevant mock data)
            system_prompt: Optional system prompt

        Returns:
            Mock response text
        """
        # Simulate rate limiting
        self._enforce_rate_limit()

        logger.info(f"[MOCK] Generating response for prompt of {len(prompt)} chars")

        # Simulate processing time
        time.sleep(0.1)

        # Preflight / health-check prompt
        if 'health check' in prompt.lower() or (system_prompt and 'health check' in system_prompt.lower()):
            return "OK"

        entries = []

        # Gap-fill mode: parse the explicit target list
        # lines look like: "   - line 18: def initialize(input: $stdin, output: $stdout)"
        for m in re.finditer(r'^\s*-\s*line\s+(\d+):\s*(.+)$', prompt, re.MULTILINE):
            line_number = int(m.group(1))
            signature = m.group(2).strip()
            anchor = ' '.join(signature.split()[:2])
            entries.append({
                'line_number': line_number,
                'anchor': anchor,
                'indent': 0,
                'comment': '# Mock documentation for testing.\n# @return [void]'
            })

        # Force-regenerate mode: no target list, parse numbered source lines
        if not entries:
            for m in re.finditer(r'^\s*(\d+):\s*(\s*)((?:def|class|module)\s+\S+)', prompt, re.MULTILINE):
                entries.append({
                    'line_number': int(m.group(1)),
                    'anchor': m.group(3).strip(),
                    'indent': len(m.group(2)),
                    'comment': '# Mock documentation for testing.\n# @return [void]'
                })
                if len(entries) >= 10:
                    break

        mock_response = json.dumps(entries, indent=2)

        # Track mock cost (zero)
        self._track_cost(prompt, mock_response)

        logger.info(f"[MOCK] Generated {len(entries)} mock documentation entries")

        return mock_response

    def generate_realistic_yard(self, code: str) -> str:
        """
        Generate more realistic YARD documentation based on actual code

        Args:
            code: Ruby code to analyze

        Returns:
            Mock but structured YARD documentation
        """
        lines = code.split('\n')
        documented_lines = []
        i = 0

        while i < len(lines):
            line = lines[i]
            stripped = line.strip()

            # Add YARD docs before class definitions
            if stripped.startswith('class '):
                class_name = stripped.split('class ')[1].split('<')[0].strip()
                documented_lines.append(line[:len(line) - len(line.lstrip())] + f"# {class_name} class")
                documented_lines.append(line[:len(line) - len(line.lstrip())] + "#")
                documented_lines.append(line[:len(line) - len(line.lstrip())] + "# Mock documentation for testing")
                documented_lines.append(line)

            # Add YARD docs before method definitions
            elif stripped.startswith('def '):
                method_parts = stripped.split('def ')[1].split('(')
                method_name = method_parts[0].strip()
                indent = line[:len(line) - len(line.lstrip())]

                documented_lines.append(indent + f"# {method_name.replace('_', ' ').title()} method")
                documented_lines.append(indent + "#")

                # Add parameter docs if there are parameters
                if len(method_parts) > 1 and method_parts[1]:
                    params = method_parts[1].rstrip(')').split(',')
                    for param in params:
                        param_name = param.strip().split('=')[0]
                        documented_lines.append(indent + f"# @param {param_name} [Object] mock parameter")

                documented_lines.append(indent + "# @return [Object] mock return value")
                documented_lines.append(indent + "# @example")
                documented_lines.append(indent + f"#   {method_name}()")
                documented_lines.append(line)

            else:
                documented_lines.append(line)

            i += 1

        return '\n'.join(documented_lines)