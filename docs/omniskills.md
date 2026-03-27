# OmniSkills

`OmniSkills` is the repo-wide skill system used by the root agent, provider-parity tools, shell environments, Codergen, ACP workers, Attractor workflows, and nested worker delegation.

## Package Layout

An OmniSkill is a directory or installed package containing `omniskill.json` and optional assets:

```text
omniskill.json
prompt.md
codergen.md
attractor.md
shell/
tools/
```

The manifest supports:

- `skillID`, `version`, `displayName`, `summary`
- supported scopes: `system`, `workspace`, `mission`
- activation policy: `explicit`, `suggested`, `auto_eligible`
- projection surfaces: `root_prompt`, `tool_registry`, `shell_env`, `codergen`, `acp`, `attractor`
- capability metadata: required capabilities and allowed domains
- budget hints such as preferred model tier
- shell asset paths and worker-tool definitions

## Installation And Activation

The control plane stores durable installation and activation records in `SkillStore`.

- install with `install_skill`
- activate with `activate_skill`
- deactivate with `deactivate_skill`
- inspect with `list_skills` and `skill_status`

High-privilege skills require root-owned approval before activation. Approval is triggered when the manifest requests capabilities such as `filesystem`, `network`, `secrets`, `mcp`, `shell`, or `worker_tools`.

## Projection Surfaces

One activation record fans out into multiple projections:

- root prompt overlay for `RootAgentRuntime`
- Claude/Gemini parity skill tools via `OmniSkillRegistry`
- `ShellToolLocalSkill` / `ShellToolContainerSkill` compatibility
- Codergen and Attractor context overlays
- ACP worker prompt/context overlays
- worker MCP tool registration through projected tool definitions

The control plane exposes the compiled bundle through `WorkspaceSkillStore.activeProjection(...)`.

## Legacy Compatibility

Legacy sources are importable through the same registry:

- `.claude/commands/*.md`
- `.gemini/skills/**/SKILL.md`
- `skills/<skill-id>/omniskill.json`

Legacy skill files are projected into in-memory OmniSkill packages so new runtime code does not need a second registry path.

## Operator Notes

- System-scope skills are visible across all workspaces.
- Workspace-scope skills are visible only inside one workspace.
- Mission-scope skills appear only when the mission ID is provided during projection.
- Remote workers receive skill overlays and projected worker tools through durable task metadata.
- Nested delegation inherits active skill metadata from the parent task.

## Minimal Manifest Example

```json
{
  "skillID": "repo.helper",
  "version": "1.0.0",
  "displayName": "Repo Helper",
  "summary": "Repository-aware coding guidance.",
  "supportedScopes": ["workspace", "mission"],
  "activationPolicy": "explicit",
  "projectionSurfaces": ["root_prompt", "tool_registry", "shell_env", "codergen", "attractor"],
  "requiredCapabilities": ["filesystem"],
  "allowedDomains": ["github.com"],
  "budgetHints": {
    "preferredModelTier": "codergen"
  },
  "promptFile": "prompt.md",
  "codergenPromptFile": "codergen.md",
  "attractorPromptFile": "attractor.md",
  "shellPaths": ["shell/bootstrap.sh"],
  "workerTools": [
    {
      "name": "review_findings",
      "description": "Return the review rubric.",
      "instructionFile": "tools/review.md"
    }
  ]
}
```
