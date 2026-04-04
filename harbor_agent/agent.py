"""
AttractorCLI Agent for Harbor Framework / Terminal Bench 2.0

This agent wraps AttractorCLI to execute multi-model consensus workflows
for solving terminal-based tasks.

Usage:
    harbor run -d terminal-bench@2.0 --agent-import-path harbor_agent:AttractorAgent
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

from harbor.agents.installed.base import BaseInstalledAgent, ExecInput

if TYPE_CHECKING:
    from harbor.agents.base import AgentContext


class AttractorAgent(BaseInstalledAgent):
    """
    Harbor agent that uses AttractorCLI's consensus workflow.

    The agent runs a multi-model DOT workflow where:
    1. Three models independently create plans
    2. Plans are debated and consolidated
    3. Implementation is done by Opus
    4. All three models review the work
    5. On failure, a postmortem is conducted and the loop restarts
    """

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

        commands = [
            ExecInput(command="mkdir -p .ai"),
            ExecInput(
                command=f"cat > .ai/task_instruction.txt << 'TASK_EOF'\n{instruction}\nTASK_EOF"
            ),
            ExecInput(
                command=(
                    "trap 'cp -r .ai /logs/agent/attractor-artifacts 2>/dev/null || true' EXIT; "
                    "export task=\"$(cat .ai/task_instruction.txt | tr '\\n' ' ')\" && "
                    "export definition_of_done='' && "
                    "/opt/attractor/bin/AttractorCLI run "
                    "--logs-root .ai/attractor_logs "
                    "/opt/attractor/workflows/consensus_task.dot 2>&1; "
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
