#!/usr/bin/env python3
"""Resolve the best exact installed skill(s) for a project moment and task."""

from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

MOMENT_TARGETS = {
    "idea": ["requirements-clarification", "assumption-challenging", "product-discovery", "prototyping"],
    "discovery": ["repository-exploration", "codebase-navigation", "product-discovery", "exploration"],
    "specification": ["requirements-clarification", "assumption-challenging", "specification", "requirements-formalization"],
    "planning": ["planning", "task-decomposition", "ticket-generation", "specification"],
    "implementation": ["implementation", "test-driven-development", "feature-development"],
    "debugging": ["debugging", "triage", "root-cause-analysis", "regression-prevention"],
    "refactoring": ["test-driven-development", "implementation", "code-review", "regression-prevention"],
    "testing": ["testing", "test-driven-development", "regression-prevention", "code-review"],
    "review": ["code-review", "quality-review", "maintainability-review"],
    "integration": ["implementation", "testing", "code-review"],
    "pre-commit": ["code-review", "testing", "quality-review"],
    "pull-request": ["code-review", "testing", "quality-review"],
    "release": ["code-review", "testing", "quality-review"],
    "production-incident": ["triage", "debugging", "root-cause-analysis", "regression-prevention"],
    "maintenance": ["code-review", "testing", "implementation"],
}

PREFERRED_EXACT_SEQUENCES = {
    "idea": ["grill-me", "prototype", "to-spec"],
    "discovery": ["wayfinder", "grill-with-docs", "prototype"],
    "specification": ["grill-me", "grill-with-docs", "to-spec"],
    "planning": ["to-spec", "to-tickets"],
    "implementation": ["implement"],
    "debugging": ["triage", "tdd", "implement"],
    "refactoring": ["tdd", "implement", "code-review"],
    "testing": ["tdd", "code-review"],
    "review": ["code-review"],
    "integration": ["implement", "code-review"],
    "pre-commit": ["code-review"],
    "pull-request": ["code-review"],
    "release": ["code-review"],
    "production-incident": ["triage", "tdd", "implement"],
    "maintenance": ["code-review", "implement"],
}

TASK_SIGNALS = {
    "requirements-clarification": ["unclear", "vague", "not sure", "idea", "requirements", "clarify", "questions", "grill"],
    "assumption-challenging": ["challenge assumptions", "grill", "poke holes", "question me", "stress test idea"],
    "specification": ["spec", "specification", "prd", "requirements", "acceptance criteria"],
    "planning": ["plan", "roadmap", "steps"],
    "task-decomposition": ["tickets", "tasks", "break down", "decompose"],
    "ticket-generation": ["tickets", "issues"],
    "implementation": ["implement", "build", "code", "add feature"],
    "test-driven-development": ["tdd", "test first", "red green", "regression test"],
    "testing": ["test", "verify", "coverage"],
    "code-review": ["review", "code review", "audit"],
    "prototyping": ["prototype", "proof of concept", "spike"],
    "debugging": ["bug", "debug", "broken", "error", "fails", "failure"],
    "triage": ["triage", "incident", "production bug"],
    "repository-exploration": ["understand codebase", "explore repo", "where is", "how does this code"],
    "codebase-navigation": ["find in codebase", "navigate", "where is"],
}


def task_targets(task: str) -> list[str]:
    t = task.lower()
    found = []
    for cap, signals in TASK_SIGNALS.items():
        if any(sig in t for sig in signals):
            found.append(cap)
    return found


def score(skill: dict, targets: list[str], moment: str) -> tuple[int, list[str]]:
    caps = set(skill.get("capabilities", []))
    matches = [t for t in targets if t in caps]
    s = len(matches) * 100
    if moment and moment in skill.get("moments", []):
        s += 35
    s += int(skill.get("routing_priority", 0))
    return s, matches


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", required=True)
    ap.add_argument("--moment", default="")
    ap.add_argument("--task", default="")
    ap.add_argument("--limit", type=int, default=4)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    data = json.loads(Path(args.registry).read_text(encoding="utf-8"))
    excluded = set(data.get("rules", {}).get("exclude_from_task_skill_routing", []))
    moment = args.moment.strip().lower()
    targets = list(MOMENT_TARGETS.get(moment, []))
    for t in task_targets(args.task):
        if t not in targets:
            targets.insert(0, t)

    ranked = []
    for skill in data.get("skills", []):
        if skill.get("name") in excluded:
            continue
        s, matches = score(skill, targets, moment)
        if s > int(skill.get("routing_priority", 0)):  # require at least one semantic/moment signal
            ranked.append({
                "name": skill["name"],
                "command": skill.get("command", "/" + skill["name"]),
                "description": skill.get("description", ""),
                "score": s,
                "matched_capabilities": matches,
                "moment_match": moment in skill.get("moments", []),
            })

    ranked.sort(key=lambda x: (-x["score"], x["name"]))

    # Deterministic workflow sequencing:
    # 1) prefer curated exact upstream skill sequences when those skills exist;
    # 2) only include exact names present in the installed registry;
    # 3) use capability-ranked fallback for unknown/local skills.
    by_name = {x["name"]: x for x in ranked}
    installed = {
        x["name"]: x for x in data.get("skills", [])
        if x.get("name") not in excluded
    }

    preferred = list(PREFERRED_EXACT_SEQUENCES.get(moment, []))

    # Explicit test-first intent moves /tdd before /implement.
    task_lower = args.task.lower()
    if moment == "implementation" and any(
        sig in task_lower for sig in ["tdd", "test first", "test-driven", "red green"]
    ):
        preferred = ["tdd", "implement"]

    sequence = []
    used = set()

    for name in preferred:
        if name in installed and name in by_name and name not in used:
            sequence.append(by_name[name])
            used.add(name)
        if len(sequence) >= args.limit:
            break

    # Fill only if the preferred exact sequence did not adequately resolve the
    # request. Unknown/local skills can still participate via capabilities.
    if not sequence:
        for candidate in ranked:
            if candidate["name"] not in used:
                sequence.append(candidate)
                used.add(candidate["name"])
            if len(sequence) >= args.limit:
                break

    result = {
        "moment": moment or None,
        "task": args.task or None,
        "target_capabilities": targets,
        "recommended_sequence": sequence,
        "all_ranked_matches": ranked[:10],
        "fallback": (
            None if ranked else
            "No installed task-specific skill matched deterministically. Use the closest project workflow manually; do not invent a skill name."
        ),
    }

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        if sequence:
            print("Recommended installed skill sequence:")
            for i, x in enumerate(sequence, 1):
                caps = ", ".join(x["matched_capabilities"]) or "moment match"
                print(f"{i}. {x['command']}  [{caps}]")
        else:
            print(result["fallback"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
