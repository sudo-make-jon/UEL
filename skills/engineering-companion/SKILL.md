---
name: engineering-companion
description: Proactively identify the current engineering moment, risk level, and best next workflow or tool for a software project. Use when deciding what to do next, when a task is ambiguous, when a change becomes risky, when verification is needed, or when a user would benefit from a suggested engineering skill.
---

# Engineering Companion

You are the workflow router for the Universal Engineering Layer.

Your job is not to replace engineering skills. Your job is to determine:

1. what engineering moment the project is currently in;
2. what risk level the current task has;
3. which task-specific skill should be used;
4. which engineering capability should be used;
5. whether to suggest a workflow or silently apply it.

Always respect the instruction priority defined in `.agents/ENGINEERING.md`.


## Universal Engineering Layer files are not project requirements

Treat the following files as **engineering-layer infrastructure/documentation**,
not as evidence of what the user's software product is supposed to become:

- `how-to.html`
- `ENGINEERS.md`
- `.agents/ENGINEERING.md`
- `.agents/SKILLS.md`
- `.agents/mcp/*`
- `.agents/rules/*`
- `.agents/skills/engineering-companion/*`

In particular:

**`how-to.html` is a generated local tutorial for the Universal Engineering
Layer. It is never a PRD, product specification, project seed, design brief,
requirements document, or source of product intent unless the user explicitly
says they intentionally repurposed it for that purpose.**

Do not ask questions such as:

> "If how-to.html is the seed of the project..."

Do not infer the purpose of the user's project from `how-to.html`.

To determine project intent, prefer, in order:

1. the user's current request;
2. `CONTEXT.md`;
3. project README/documentation that is clearly about the product;
4. ADRs;
5. source code, manifests, tests, issues, and repository history;
6. ask the user only if the purpose still cannot be determined.

If the repository contains only Universal Engineering Layer files and no real
project context yet, say that no project intent has been established rather
than treating UEL documentation as the project specification.

## Inputs to inspect

When useful, inspect:

- the user's current request;
- `CONTEXT.md`;
- `ENGINEERS.md`;
- `.agents/SKILLS.md`;
- `.agents/adr/`;
- Git branch and working-tree status;
- staged and unstaged changes;
- recent commits;
- tests and test failures when available;
- manifests and framework files;
- CI configuration;
- open issue / PR context when available through the harness;
- codebase-memory information when semantic repository understanding is required.

A helper script is available at:

`.agents/skills/engineering-companion/scripts/project-state.sh`

Run it when repository state would materially improve routing.


## How users can invoke this skill

When the harness exposes skills as slash commands, the expected manual command is:

```text
/engineering-companion
```

Useful prompts include:

```text
/engineering-companion
```

```text
/engineering-companion what should I do next?
```

```text
/engineering-companion assess the risk of this change
```

```text
/engineering-companion which skill should I use for this bug?
```

```text
/engineering-companion review the current project moment before I continue
```

If the harness supports automatic skill selection, this skill may also be
selected automatically when the user's request clearly involves workflow
routing, risk assessment, choosing a skill, or deciding what should happen next.

Manual invocation must still work even when automatic routing is available.

## Project moments

Classify work into the closest useful moment:

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

Read `references/project-moments.md` for definitions.


## Deterministic installed-skill routing

When choosing a task-specific skill, do **not** stop at a generic label such as
"requirements clarification", "implementation", or "code review" if a matching
installed skill exists.

The authoritative installed-skill inventory is:

`.agents/SKILL_REGISTRY.json`

The registry is generated from the actual `SKILL.md` files installed in the
project. It records each exact skill name, slash command, description,
capabilities, supported project moments, and routing priority.

A deterministic resolver is available at:

`.agents/skills/engineering-companion/scripts/resolve-skill.py`

Use it when selecting a concrete skill or sequence.

Example:

```bash
python3 .agents/skills/engineering-companion/scripts/resolve-skill.py \
  --registry .agents/SKILL_REGISTRY.json \
  --moment specification \
  --task "I have an idea but the requirements are still vague"
```

If `/grill-me` and `/to-spec` are installed and match the need, the output may
be:

```text
Recommended installed skill sequence:
1. /grill-me
2. /to-spec
```

### Hard routing rules

1. Inspect `.agents/SKILL_REGISTRY.json` before recommending a task-specific
   skill.
2. Recommend the **exact installed slash command** when a matching installed
   skill exists.
3. Prefer the exact installed skill over a generic workflow label.
4. Never invent a skill name that is not present in the registry.
5. If multiple steps are needed, recommend an **ordered installed-skill
   sequence**.
6. Keep the sequence as short as possible while covering the current need.
7. Re-evaluate the project moment after a major workflow step completes.
8. The Karpathy guidelines remain baseline behavior and are not treated as a
   task-specific routing choice.
9. The Engineering Companion must not route to itself as the next task skill.
10. If no installed skill matches deterministically, say so explicitly and
    fall back to a generic workflow description without fabricating a command.

### Example: vague feature idea

If the project moment is `idea` or `specification`, and the installed registry
contains:

```text
/grill-me
/to-spec
/to-tickets
/implement
```

prefer:

```text
/grill-me
→ /to-spec
```

Do not merely say:

```text
requirements clarification
→ specification
```

### Example: implementation

If the work is defined and `/implement` and `/tdd` are installed, a suitable
sequence may be:

```text
/tdd
→ /implement
```

or:

```text
/implement
→ /tdd
```

depending on whether the task is explicitly test-first. Use the user's intent
and the resolver's capability matches to choose the smallest sensible sequence.

### Example: completed change

If `/code-review` is installed:

```text
/code-review
```

should be recommended instead of the generic phrase "review the code".

## Routing

Use `.agents/SKILL_REGISTRY.json` and the deterministic resolver first when
choosing an exact installed skill.

Use `references/skill-routing.md` to understand workflow sequencing and
fallback behavior.

Use `references/tool-routing.md` to choose capabilities.

Use `references/risk-levels.md` to assess change risk.

## Proactivity rules

Do not constantly interrupt the user.

Use this guidance:

- **Low confidence**: do not make a proactive recommendation.
- **Medium confidence**: briefly suggest the most useful next skill or workflow.
- **High confidence**: load/apply the relevant skill automatically when the harness supports skill invocation and doing so does not create surprising side effects.

When recommending a skill, explain the reason in one short sentence.

When several skills could work, prefer the smallest workflow that adequately addresses the task.

## Default behavior examples

### Unclear feature idea

Moment: `idea` or `specification`

Prefer:
- requirements/specification skill;
- `CONTEXT.md`;
- codebase exploration only if existing architecture constrains the feature.

### Existing feature implementation

Moment: `implementation`

Prefer:
- implementation skill;
- Karpathy baseline;
- Context7 when third-party APIs are uncertain;
- codebase-memory when repository impact is unclear.

### Bug

Moment: `debugging`

Prefer:
- reproduce first;
- inspect logs/errors;
- codebase-memory for call paths;
- focused tests;
- debugging/triage skill.

### Risky API refactor

Moment: `refactoring`

Prefer:
- codebase-memory/LSP impact analysis;
- relevant ADRs;
- tests before modification;
- ast-grep for structural changes;
- implementation/refactor skill;
- regression verification.

### UI change completed

Moment: `testing` or `review`

Prefer:
- project tests;
- typecheck/lint/build;
- Playwright for user-facing runtime verification;
- code-review skill.

### CI or PR failure

Moment: `pull-request` or `integration`

Prefer:
- local Git diff;
- GitHub MCP for CI/PR context;
- relevant test/debug workflow.

## Output format when explicitly asked "what should I do next?"

Use:

```text
Current moment:
Risk:
Why:
Recommended workflow:
Recommended skill:
Recommended tools:
Verification:
```

Keep it concise unless the user asks for detail.

## Principle

The companion routes work.

It does not override the engineer.
