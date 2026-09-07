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


## Manual skill invocation

In skill-aware harnesses such as Claude Code, the companion can be invoked
directly:

```text
/engineering-companion
```

Examples:

```text
/engineering-companion what should I do next?
/engineering-companion assess this refactor
/engineering-companion choose the best skill for this problem
```

This is different from:

```bash
engineering-layer companion
```

The CLI command uses repository heuristics. The slash-command skill can also
reason over the user's active request and whatever context/tools the harness
provides.

## `how-to.html` is not project intent

The generated `how-to.html` file is documentation for Universal Engineering
Layer itself.

It must never be treated as:

- a PRD;
- a project seed;
- a product specification;
- a requirements document;
- a design brief;
- evidence of what the target software should become.

The companion should determine project intent from the user's request,
`CONTEXT.md`, actual product documentation, ADRs, source code, tests, issues,
and repository history.

If no project intent has been established yet, it should say so instead of
using the tutorial as a substitute.


## Self-generated files are excluded from moment detection

The repository-state detector ignores Universal Engineering Layer
infrastructure such as `.agents/`, `ENGINEERS.md`, `how-to.html`, and
harness skill symlinks when estimating the current project moment.

Installing the engineering layer into a clean repository therefore should not
by itself cause the companion to report that the product is in an
"implementation" phase.


## Deterministic exact-skill selection

The companion uses a generated installed-skill registry:

```text
.agents/SKILL_REGISTRY.json
```

The registry is built from the real `SKILL.md` files present under
`.agents/skills/`.

This means the companion can resolve a workflow such as:

```text
requirements clarification
```

to the exact installed skill:

```text
/grill-me
```

when that skill is available.

It can also return ordered sequences, for example:

```text
/grill-me
→ /to-spec
→ /to-tickets
```

The companion must not invent skill commands. If a capability has no matching
installed skill, it should state that no exact installed skill matched and
describe the fallback workflow generically.

The resolver can be invoked directly:

```bash
python3 .agents/skills/engineering-companion/scripts/resolve-skill.py \
  --registry .agents/SKILL_REGISTRY.json \
  --moment specification \
  --task "I have an idea but the requirements are vague"
```
