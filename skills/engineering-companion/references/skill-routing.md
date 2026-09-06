# Skill Routing

The exact Matt Pocock skill names may change upstream. Match by purpose, not only by filename.

| Situation | Preferred workflow |
|---|---|
| Unclear idea | requirements / clarification / specification |
| Defined feature | implementation |
| Behavior-first change | TDD |
| Existing bug | debugging / triage |
| Major structural change | planning + implementation/refactor |
| Finished code | code review |
| Large task | specification → tickets/tasks → implementation |
| Prototype/unknown feasibility | prototype |
| Repository unfamiliar | exploration / wayfinding |
| Documentation change | documentation workflow |

## Routing principles

1. Apply the Karpathy baseline continuously.
2. Load only the task-specific skill(s) needed for the current moment.
3. Avoid stacking multiple overlapping workflows unless the task genuinely spans them.
4. Re-evaluate the moment after a major transition.
5. When implementation completes, transition toward testing/review rather than continuing to generate code.
