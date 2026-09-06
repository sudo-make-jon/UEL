#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(pwd)}"
ROOT="$(cd "$ROOT" && pwd)"

git_ok=0
branch="none"
dirty=0
changed=0
staged=0
untracked=0
recent_subject=""
moment="discovery"
risk="low"
reasons=()

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_ok=1
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || branch="detached"

  status="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
  if [[ -n "$status" ]]; then
    dirty=1
    changed="$(printf '%s\n' "$status" | grep -vc '^??' || true)"
    untracked="$(printf '%s\n' "$status" | grep -c '^??' || true)"
    staged="$(git -C "$ROOT" diff --cached --name-only 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  fi

  recent_subject="$(git -C "$ROOT" log -1 --pretty=%s 2>/dev/null || true)"
fi

has_tests=0
if find "$ROOT" -maxdepth 3 \( -type d -name test -o -type d -name tests -o -type d -name __tests__ \) -print -quit 2>/dev/null | grep -q .; then
  has_tests=1
fi

has_ci=0
[[ -d "$ROOT/.github/workflows" ]] && has_ci=1

project_type="unknown"
if [[ -f "$ROOT/package.json" ]]; then
  project_type="javascript/typescript"
elif [[ -f "$ROOT/pyproject.toml" || -f "$ROOT/requirements.txt" ]]; then
  project_type="python"
elif [[ -f "$ROOT/Cargo.toml" ]]; then
  project_type="rust"
elif [[ -f "$ROOT/go.mod" ]]; then
  project_type="go"
elif [[ -f "$ROOT/pom.xml" || -f "$ROOT/build.gradle" || -f "$ROOT/build.gradle.kts" ]]; then
  project_type="jvm"
fi

# Moment heuristics.
if [[ "$git_ok" -eq 0 ]]; then
  moment="discovery"
  reasons+=("not a Git repository")
elif [[ "$dirty" -eq 0 ]]; then
  moment="planning"
  reasons+=("working tree is clean")
elif [[ "$staged" -gt 0 ]]; then
  moment="pre-commit"
  reasons+=("$staged staged file(s)")
else
  moment="implementation"
  reasons+=("$changed tracked change(s), $untracked untracked file(s)")
fi

case "${branch,,}" in
  *fix*|*bug*|*hotfix*)
    moment="debugging"
    reasons+=("branch name suggests bug fixing")
    ;;
  *refactor*)
    moment="refactoring"
    reasons+=("branch name suggests refactoring")
    ;;
  *release*)
    moment="release"
    reasons+=("branch name suggests release work")
    ;;
esac

# Risk heuristics based on changed paths.
changed_paths=""
if [[ "$git_ok" -eq 1 ]]; then
  changed_paths="$(
    {
      git -C "$ROOT" diff --name-only 2>/dev/null || true
      git -C "$ROOT" diff --cached --name-only 2>/dev/null || true
    } | sort -u
  )"
fi

if printf '%s\n' "$changed_paths" | grep -Eqi '(^|/)(auth|security|permissions|migration|migrations|schema|database|db|infra|terraform|k8s|kubernetes|deploy|deployment|secrets?|credentials?)(/|\.|$)'; then
  risk="high"
  reasons+=("security/data/infrastructure-sensitive paths changed")
elif [[ "$changed" -ge 15 ]]; then
  risk="high"
  reasons+=("large tracked change set")
elif [[ "$changed" -ge 5 ]]; then
  risk="medium"
  reasons+=("multi-file change set")
fi

if [[ "$has_tests" -eq 0 && "$dirty" -eq 1 ]]; then
  [[ "$risk" == "low" ]] && risk="medium"
  reasons+=("no obvious test directory found")
fi

# Recommendation mapping.
skill="repository exploration"
tools="rg / fd"
verification="inspect relevant files"

case "$moment" in
  planning)
    skill="specification / planning"
    tools="codebase-memory or LSP when architecture matters"
    verification="define acceptance criteria before implementation"
    ;;
  implementation)
    skill="implementation"
    tools="codebase-memory for impact; Context7 for external APIs; ast-grep for structural changes"
    verification="focused tests, then typecheck/lint/build as applicable"
    ;;
  debugging)
    skill="debugging / triage"
    tools="logs + codebase-memory call paths + focused search"
    verification="reproduce, add regression test, confirm fix"
    ;;
  refactoring)
    skill="refactor / implementation + review"
    tools="codebase-memory/LSP impact analysis + ast-grep"
    verification="tests before and after; review behavior-preserving diff"
    ;;
  pre-commit)
    skill="code review"
    tools="local Git diff"
    verification="tests + typecheck/lint/build; Playwright for UI changes"
    ;;
  release)
    skill="release / review"
    tools="Git + GitHub MCP when remote CI/release context is needed"
    verification="full relevant test/build/regression checks and rollback readiness"
    ;;
esac

printf 'project_type: %s\n' "$project_type"
printf 'git: %s\n' "$([[ "$git_ok" -eq 1 ]] && echo true || echo false)"
printf 'branch: %s\n' "$branch"
printf 'dirty: %s\n' "$([[ "$dirty" -eq 1 ]] && echo true || echo false)"
printf 'changed_files: %s\n' "$changed"
printf 'staged_files: %s\n' "$staged"
printf 'untracked_files: %s\n' "$untracked"
printf 'tests_detected: %s\n' "$([[ "$has_tests" -eq 1 ]] && echo true || echo false)"
printf 'ci_detected: %s\n' "$([[ "$has_ci" -eq 1 ]] && echo true || echo false)"
printf 'moment: %s\n' "$moment"
printf 'risk: %s\n' "$risk"
printf 'recommended_skill: %s\n' "$skill"
printf 'recommended_tools: %s\n' "$tools"
printf 'verification: %s\n' "$verification"
printf 'reasons:\n'
for r in "${reasons[@]}"; do
  printf '  - %s\n' "$r"
done
