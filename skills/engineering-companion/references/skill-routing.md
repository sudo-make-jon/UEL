# Skill Routing

The Engineering Companion must route against the **actual installed skill
inventory**, not a hypothetical list of workflow names.

Authoritative registry:

```text
.agents/SKILL_REGISTRY.json
```

Deterministic resolver:

```text
.agents/skills/engineering-companion/scripts/resolve-skill.py
```

## Exact-name rule

If an installed skill can satisfy the need, recommend its exact slash command.

Good:

```text
/grill-me
/to-spec
/code-review
```

Avoid:

```text
requirements clarification skill
specification workflow
review skill
```

unless no installed exact match exists.

Never invent a slash command.

## Typical deterministic routing

The exact available skills depend on what is installed. These examples apply
only when the named skills are present in the registry.

| Situation | Preferred installed sequence |
|---|---|
| Vague product idea | `/grill-me` → `/to-spec` |
| Existing docs need interrogation | `/grill-with-docs` → `/to-spec` |
| Clear spec needs decomposition | `/to-tickets` |
| Defined implementation | `/implement` |
| Test-first implementation | `/tdd` → `/implement` |
| Existing bug | `/triage` → `/tdd` → `/implement` |
| Unfamiliar repository | `/wayfinder` |
| Prototype / feasibility question | `/prototype` |
| Finished code | `/code-review` |
| Large feature lifecycle | `/grill-me` → `/to-spec` → `/to-tickets` → `/implement` → `/code-review` |

The resolver trims this list to skills that are actually installed.

## Capability-based matching

The generated registry assigns capabilities inferred from the exact skill
metadata and known skill semantics.

Examples:

```text
grill-me
→ requirements-clarification
→ assumption-challenging
→ product-discovery

to-spec
→ specification
→ requirements-formalization
→ acceptance-criteria

to-tickets
→ planning
→ task-decomposition
→ ticket-generation

tdd
→ test-driven-development
→ testing
→ regression-prevention

code-review
→ code-review
→ quality-review
```

This lets the companion continue to work even when additional local skills are
added.

## Routing principles

1. Karpathy remains the baseline engineering behavior.
2. The Engineering Companion is the router, not the destination.
3. Inspect the installed registry before recommending a task skill.
4. Prefer exact installed slash commands.
5. Use the smallest sequence that covers the current project moment.
6. Re-evaluate after each major transition.
7. Do not continue implementation when the moment has clearly shifted to
   testing, review, or release.
8. If no installed skill matches, say so instead of inventing one.
