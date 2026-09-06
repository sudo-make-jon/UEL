# AI Engineering Environment

This repository uses the Universal Engineering Layer.

`ENGINEERS.md` explains how the engineering tools, MCP servers, skills, and
verification layers are expected to work together. It is written for both
human engineers and AI coding agents.

## Mental model

The environment is deliberately split into three layers:

1. **Engineering behavior** — how work should be approached.
2. **Engineering workflows** — how particular tasks should be performed.
3. **Engineering capabilities** — tools the agent can use to understand,
   change, verify, and collaborate around code.

### Behavior

The Karpathy guidelines are the baseline engineering discipline:

`.agents/skills/karpathy-guidelines/SKILL.md`

They emphasize understanding before editing, minimal changes, explicit
assumptions, and verification.

### Workflows

Matt Pocock's skills provide task-specific flows such as specification,
implementation, TDD, review, prototyping, and triage.

Available skills are indexed in:

`.agents/SKILLS.md`

### Capabilities

Optional tools add engineering capabilities without replacing the behavior or
workflow layers.


## Engineering Companion

The Universal Engineering Layer also includes an orchestration skill:

`.agents/skills/engineering-companion/SKILL.md`

Its role is to identify the current **project moment**, estimate engineering
risk, and route the work toward the most appropriate workflow and capability.

Recognized moments include:

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

The companion does not replace Karpathy or Matt Pocock skills.

Instead:

```text
Karpathy
  → baseline behavior

Engineering Companion
  → project-moment and workflow routing

Matt Pocock skills
  → task-specific workflows

MCPs / CLI tools
  → engineering capabilities
```

When the harness supports skill auto-selection, it may apply the companion
automatically when workflow selection is ambiguous or a proactive next-step
suggestion would materially help.

The repository-state detector can also be run directly:

```bash
engineering-layer companion
```

It returns the probable moment, risk, recommended skill, recommended tools,
and verification strategy.

## Preferred tool hierarchy

Agents should prefer the most semantic and least ambiguous tool that fits the
task.

### Understanding the codebase

Preferred order:

1. `codebase-memory-mcp` or native LSP/symbol tools
2. `ast-grep`
3. `rg`
4. manual file traversal

Use `codebase-memory-mcp` for architecture, references, dependency chains,
callers, routes, and impact analysis.

Use `ast-grep` for syntax-aware structural search and transformations.

Use `rg` for literal or textual search.

### External library and framework knowledge

Preferred order:

1. Context7
2. official documentation
3. general web search

Context7 is for third-party APIs and version-specific docs. Do not use it to
understand this repository's own architecture.

### Verification

Preferred order:

1. project tests
2. type checking
3. linting
4. build
5. Playwright or runtime/browser verification when applicable

Playwright is especially useful for web applications, user flows, regression
checks, and UI behavior.

### Source control and collaboration

Use local Git for repository state and diffs.

Use GitHub MCP for remote collaboration concerns such as:

- issues
- pull requests
- CI / Actions
- code review context
- repository metadata
- security and dependency alerts

Prefer read-only GitHub MCP access by default. Enable write access only when
the project explicitly requires it.

## Optional capability stack

### codebase-memory-mcp

Purpose:

- persistent structural understanding of the repository
- dependency and call-chain exploration
- semantic code search
- optional auto-indexing
- optional file watching

Recommended for medium and large repositories.

Auto-indexing is useful, but can consume significant RAM on larger
repositories. Constrained machines should disable watching or use a smaller
index limit.

### Context7

Purpose:

- current third-party documentation
- version-specific library and framework guidance
- examples based on current APIs

Use it when implementing against external packages or frameworks.

### ast-grep

Purpose:

- AST-aware search
- structural refactoring
- syntax-aware code matching

It complements codebase-memory rather than replacing it.

### ripgrep (`rg`)

Purpose:

- very fast text search
- exact string matching
- fallback repository exploration

### fd

Purpose:

- fast filesystem discovery
- filename-based navigation

### jq / yq

Purpose:

- JSON and YAML inspection
- scripting and configuration analysis

### Playwright

Purpose:

- browser and UI verification
- end-to-end testing
- runtime interaction with web applications

### GitHub MCP

Purpose:

- remote repository collaboration
- issues and pull requests
- CI / Actions
- code security and Dependabot context

Default to read-only access when possible.

## Profiles

### minimal

Installs the shared engineering policy and workflow layer only:

- Karpathy guidelines
- Matt Pocock skills
- harness adapters
- `ENGINEERING.md`
- `ENGINEERS.md`
- `CONTEXT.md`
- ADR directory

### recommended

Adds the core engineering capability set:

- codebase-memory-mcp
- Context7
- ast-grep
- ripgrep
- fd
- jq
- yq

This is the recommended default for most development workstations.

### full

Adds everything in `recommended`, plus:

- Playwright capability
- GitHub MCP integration helpers

The full profile is intended for autonomous or highly agentic engineering
workflows.

## Important principle

More tools are not automatically better.

Agents should avoid using multiple overlapping tools for the same purpose when
one is sufficient. Use the preferred hierarchy above.

The engineering process remains:

```text
Human request
  ↓
Project instructions
  ↓
Karpathy baseline
  ↓
Relevant Pocock workflow
  ↓
Code intelligence / external knowledge
  ↓
Implement
  ↓
Tests / build / runtime verification
  ↓
Git / GitHub collaboration
```

The tools support the process. They do not replace it.


## Attribution and license boundaries

Universal Engineering Layer is an independent project created by
`@sudo-make-jon`.

The Karpathy Guidelines, Matt Pocock Skills, codebase-memory-mcp, Context7,
Playwright MCP, GitHub MCP Server, and other third-party projects remain
independent upstream works under their own licenses.

See the repository's `THIRD_PARTY.md` for detailed attribution.

The Universal Engineering Layer MIT license covers its original integration,
orchestration, Engineering Companion, documentation, and installer code. The
installer does not modify the license of the target project.
