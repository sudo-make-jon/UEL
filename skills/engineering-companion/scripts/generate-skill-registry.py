#!/usr/bin/env python3
"""Build a deterministic capability registry from installed SKILL.md files."""

from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

KNOWN = {
    "grill-me": {
        "capabilities": ["requirements-clarification", "assumption-challenging", "product-discovery", "specification"],
        "moments": ["idea", "discovery", "specification"],
        "priority": 100,
    },
    "grill-with-docs": {
        "capabilities": ["requirements-clarification", "assumption-challenging", "document-analysis", "specification"],
        "moments": ["discovery", "specification"],
        "priority": 100,
    },
    "to-spec": {
        "capabilities": ["specification", "requirements-formalization", "acceptance-criteria"],
        "moments": ["specification", "planning"],
        "priority": 95,
    },
    "to-tickets": {
        "capabilities": ["planning", "task-decomposition", "ticket-generation"],
        "moments": ["planning"],
        "priority": 90,
    },
    "implement": {
        "capabilities": ["implementation", "feature-development"],
        "moments": ["implementation", "integration"],
        "priority": 90,
    },
    "tdd": {
        "capabilities": ["test-driven-development", "testing", "regression-prevention", "implementation"],
        "moments": ["implementation", "testing", "debugging", "refactoring"],
        "priority": 95,
    },
    "code-review": {
        "capabilities": ["code-review", "quality-review", "maintainability-review"],
        "moments": ["review", "pre-commit", "pull-request"],
        "priority": 95,
    },
    "prototype": {
        "capabilities": ["prototyping", "feasibility", "exploration"],
        "moments": ["idea", "discovery"],
        "priority": 85,
    },
    "triage": {
        "capabilities": ["debugging", "triage", "root-cause-analysis"],
        "moments": ["debugging", "production-incident"],
        "priority": 95,
    },
    "wayfinder": {
        "capabilities": ["repository-exploration", "codebase-navigation", "discovery"],
        "moments": ["discovery"],
        "priority": 90,
    },
}

CAPABILITY_KEYWORDS = {
    "requirements-clarification": ["clarif", "requirements", "grill", "question", "ambigu"],
    "assumption-challenging": ["assumption", "challenge", "grill", "interrogate"],
    "product-discovery": ["discovery", "product idea", "idea", "requirements"],
    "specification": ["spec", "specification", "requirements", "acceptance criteria"],
    "requirements-formalization": ["formalize", "spec", "requirements"],
    "acceptance-criteria": ["acceptance", "criteria"],
    "planning": ["plan", "planning", "break down", "decompose"],
    "task-decomposition": ["ticket", "task", "decompose", "break down"],
    "ticket-generation": ["ticket", "issue"],
    "implementation": ["implement", "implementation", "build", "code"],
    "feature-development": ["feature", "implement"],
    "test-driven-development": ["tdd", "test driven", "red green refactor"],
    "testing": ["test", "testing", "verify"],
    "regression-prevention": ["regression", "test"],
    "code-review": ["code review", "review code", "review"],
    "quality-review": ["quality", "review"],
    "maintainability-review": ["maintainability", "review"],
    "prototyping": ["prototype", "spike", "proof of concept"],
    "feasibility": ["feasibility", "prototype", "spike"],
    "exploration": ["explore", "discovery", "prototype"],
    "debugging": ["debug", "bug", "error", "failure", "fix"],
    "triage": ["triage", "bug", "incident"],
    "root-cause-analysis": ["root cause", "debug", "trace"],
    "repository-exploration": ["repository", "codebase", "explore", "wayfind"],
    "codebase-navigation": ["navigate", "repository", "codebase", "find"],
    "document-analysis": ["document", "docs", "prd", "brief"],
}

MOMENT_KEYWORDS = {
    "idea": ["idea", "concept", "brainstorm", "prototype"],
    "discovery": ["discover", "explore", "understand", "repository", "codebase"],
    "specification": ["spec", "requirements", "acceptance", "clarify", "grill"],
    "planning": ["plan", "tickets", "tasks", "decompose"],
    "implementation": ["implement", "build", "feature", "code"],
    "debugging": ["bug", "debug", "error", "failure", "broken", "fix"],
    "refactoring": ["refactor", "cleanup", "restructure"],
    "testing": ["test", "verify", "coverage", "regression"],
    "review": ["review", "audit", "quality"],
    "integration": ["integrate", "integration", "connect"],
    "pre-commit": ["pre-commit", "before commit", "staged"],
    "pull-request": ["pull request", "pr", "ci"],
    "release": ["release", "deploy", "publish"],
    "production-incident": ["production", "incident", "outage", "hotfix"],
    "maintenance": ["maintenance", "dependency", "upgrade", "technical debt"],
}


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    out: dict[str, str] = {}
    for line in parts[1].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip("'\"")
    return out


def infer(name: str, description: str, text: str) -> tuple[list[str], list[str], int]:
    known = KNOWN.get(name, {})
    capabilities = set(known.get("capabilities", []))
    moments = set(known.get("moments", []))
    priority = int(known.get("priority", 50))

    # Known upstream skills use curated routing semantics so generic words in
    # their descriptions do not accidentally make them match unrelated stages.
    # Unknown/local skills still get capability inference from their metadata.
    if not known:
        hay = f"{name} {description} {text[:4000]}".lower()

        for cap, words in CAPABILITY_KEYWORDS.items():
            if any(w in hay for w in words):
                capabilities.add(cap)

        for moment, words in MOMENT_KEYWORDS.items():
            if any(w in hay for w in words):
                moments.add(moment)

    if name == "engineering-companion":
        capabilities.update(["workflow-routing", "skill-selection", "risk-assessment"])
        moments.update(MOMENT_KEYWORDS)
        priority = 10

    if name == "karpathy-guidelines":
        capabilities.update(["engineering-baseline", "change-discipline", "verification"])
        priority = 5

    return sorted(capabilities), sorted(moments), priority


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    skills_dir = Path(args.skills_dir)
    output = Path(args.output)
    entries = []

    for skill_file in sorted(skills_dir.glob("*/SKILL.md")):
        text = skill_file.read_text(encoding="utf-8", errors="replace")
        meta = parse_frontmatter(text)
        folder = skill_file.parent.name
        name = meta.get("name") or folder
        description = meta.get("description", "")
        capabilities, moments, priority = infer(name, description, text)

        entries.append({
            "name": name,
            "folder": folder,
            "command": f"/{name}",
            "description": description,
            "capabilities": capabilities,
            "moments": moments,
            "routing_priority": priority,
            "path": str(skill_file),
            "source": (
                "universal-engineering-layer"
                if name in {"engineering-companion"}
                else "installed-upstream-or-local"
            ),
        })

    registry = {
        "schema_version": 1,
        "purpose": "Deterministic installed-skill routing registry for Engineering Companion",
        "rules": {
            "exact_installed_names_only": True,
            "prefer_installed_skill_over_generic_workflow_label": True,
            "allow_ordered_sequences": True,
            "exclude_from_task_skill_routing": ["engineering-companion", "karpathy-guidelines"],
        },
        "skills": entries,
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} skills to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
