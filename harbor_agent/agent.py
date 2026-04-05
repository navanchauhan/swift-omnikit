"""
AttractorCLI Agent for Harbor Framework / Terminal Bench 2.0

Usage:
    harbor run -d terminal-bench@2.0 --agent-import-path harbor_agent:AttractorAgent
"""

from __future__ import annotations

import base64
import os
from pathlib import Path
from typing import TYPE_CHECKING

from harbor.agents.installed.base import BaseInstalledAgent, ExecInput

if TYPE_CHECKING:
    from harbor.agents.base import AgentContext


# Runs inside the container to inject task into the DOT file as a graph attribute.
_INJECT_SCRIPT = r"""
import base64, sys
task_b64 = open('.ai/task_b64.txt').read().strip()
task = base64.b64decode(task_b64).decode()
task_escaped = task.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
dot = open('/opt/attractor/workflows/single_agent.dot').read()
dot = dot.replace(
    'graph [',
    'graph [ task="' + task_escaped + '", definition_of_done="", ',
    1,
)
open('.ai/workflow.dot', 'w').write(dot)
print('Injected task into workflow.dot')
"""


class AttractorAgent(BaseInstalledAgent):
    """Harbor agent that uses AttractorCLI to solve Terminal Bench tasks."""

    @staticmethod
    def name() -> str:
        return "attractor"

    def version(self) -> str | None:
        return "0.0.5"

    @property
    def _install_agent_template_path(self) -> Path:
        return Path(__file__).parent / "templates" / "install.sh.j2"

    def _get_api_keys_env(self) -> dict[str, str]:
        env = {}
        for key in [
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "GEMINI_API_KEY",
            "GOOGLE_API_KEY",
        ]:
            if os.environ.get(key):
                env[key] = os.environ[key]
        return env

    def create_run_agent_commands(self, instruction: str) -> list[ExecInput]:
        api_keys = self._get_api_keys_env()
        b64_task = base64.b64encode(instruction.encode()).decode()

        commands = [
            ExecInput(command="mkdir -p .ai"),
            ExecInput(
                command=f"cat > .ai/task_instruction.txt << 'TASK_EOF'\n{instruction}\nTASK_EOF"
            ),
            ExecInput(command=f"echo '{b64_task}' > .ai/task_b64.txt"),
            ExecInput(
                command=f"cat > .ai/inject_task.py << 'PYEOF'\n{_INJECT_SCRIPT}\nPYEOF"
            ),
            ExecInput(
                command=(
                    "trap 'cp -r .ai /logs/agent/attractor-artifacts 2>/dev/null || true' EXIT; "
                    "python3 .ai/inject_task.py && "
                    "/opt/attractor/bin/AttractorCLI run "
                    "--logs-root .ai/attractor_logs "
                    ".ai/workflow.dot 2>&1; "
                    "cp -r .ai /logs/agent/attractor-artifacts || true"
                ),
                timeout_sec=36000,
                env=api_keys,
            ),
        ]

        return commands

    def populate_context_post_run(self, context: "AgentContext") -> None:
        logs_dir = self.logs_dir
        metadata = {}

        for i in range(10):
            command_dir = logs_dir / f"command-{i}"
            stdout_file = command_dir / "stdout.txt"
            if stdout_file.exists():
                content = stdout_file.read_text()
                if "PASS" in content.upper() or "review" in content.lower():
                    metadata["output"] = content[-5000:]
                    metadata["passed"] = "PASS" in content.upper() and "FAIL" not in content.upper()
                    break

        if metadata:
            context.metadata = metadata


Agent = AttractorAgent
