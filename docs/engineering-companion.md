# Engineering Companion

The Engineering Companion is the orchestration skill of the Universal Engineering Layer.

It answers a simple question:

> Given the state of the repository and the user's current goal, what engineering workflow should happen next?

It combines user intent with repository state and routes work toward the most appropriate skill and capability.

## It does not replace other skills

The stack is intentionally layered:

```text
Karpathy Guidelines
  → engineering behavior

Matt Pocock Skills
  → task workflows

Engineering Companion
  → workflow/tool routing

codebase-memory / Context7 / ast-grep / Playwright / GitHub MCP
  → capabilities
```

## Project moments

The companion recognizes:

- idea
- discovery
- specification
- planning
- implementation
- debugging
- refactoring
- testing
- review
- integration
- pre-commit
- pull-request
- release
- production-incident
- maintenance

## CLI

After installation:

```bash
./universal-engineering-layer.sh companion
```

or, if installed globally:

```bash
engineering-layer companion
```

The command runs the project-state detector and prints a suggested moment, risk level, skill, tools, and verification strategy.

## Harness behavior

Harnesses that understand skills can invoke `engineering-companion` directly.

Harnesses that do not support automatic skill routing can still read:

```text
.agents/skills/engineering-companion/SKILL.md
```

and use the CLI state detector.

## Proactivity

The companion is intentionally not designed to interrupt every interaction.

- low-confidence routing: stay quiet;
- medium confidence: suggest a useful workflow;
- high confidence: automatically apply/load the relevant skill when the harness supports it and doing so is unsurprising.

This keeps the companion useful without making it noisy.
