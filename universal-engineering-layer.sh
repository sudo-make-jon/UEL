#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# Universal Engineering Layer
# ============================================================================
# Installs one canonical, project-local engineering skill layer and adapters
# for multiple AI coding harnesses.
#
# Canonical layer:
#   .agents/ENGINEERING.md
#   .agents/SKILLS.md
#   .agents/skills/*
#
# Adapters:
#   Codex / generic agents : AGENTS.md
#   Claude Code            : CLAUDE.md + .claude/skills symlink
#   Google Antigravity     : .agents/skills (native) + .agents/rules
#   Hermes Agent           : external skill directory registration
#   GitHub Copilot / VSCode: .github/copilot-instructions.md
#   OpenCode / others      : generic AGENTS.md + optional symlink adapters
#
# Commands:
#   ./universal-engineering-layer.sh install
#   ./universal-engineering-layer.sh update
#   ./universal-engineering-layer.sh status
#   ./universal-engineering-layer.sh doctor
#   ./universal-engineering-layer.sh companion
#   ./universal-engineering-layer.sh remove
#
# Options:
#   --project PATH          Target project (default: current directory)
#   --no-hermes-config      Do not alter ~/.hermes/config.yaml
#   --no-context            Do not create CONTEXT.md template
#   --force                 Replace managed symlinks/files when safe
#   --help                  Show help
#
# The script is designed to be idempotent. Existing project instructions
# outside managed marker blocks are preserved.
# ============================================================================

VERSION="3.1.0"

POCOCK_REPO="${POCOCK_REPO:-https://github.com/mattpocock/skills.git}"
KARPATHY_REPO="${KARPATHY_REPO:-https://github.com/emavv/karpathy-guidelines.git}"

PROJECT_ROOT="$(pwd)"
CONFIGURE_HERMES=1
CREATE_CONTEXT=1
FORCE=0
PROFILE="minimal"
INSTALL_TOOLS=1
COMMAND="install"

BEGIN_AGENT="<!-- BEGIN UNIVERSAL-ENGINEERING-LAYER -->"
END_AGENT="<!-- END UNIVERSAL-ENGINEERING-LAYER -->"
BEGIN_CLAUDE="<!-- BEGIN UNIVERSAL-ENGINEERING-LAYER -->"
END_CLAUDE="<!-- END UNIVERSAL-ENGINEERING-LAYER -->"
BEGIN_COPILOT="<!-- BEGIN UNIVERSAL-ENGINEERING-LAYER -->"
END_COPILOT="<!-- END UNIVERSAL-ENGINEERING-LAYER -->"
BEGIN_ANTIGRAVITY="<!-- BEGIN UNIVERSAL-ENGINEERING-LAYER -->"
END_ANTIGRAVITY="<!-- END UNIVERSAL-ENGINEERING-LAYER -->"

C_RESET='\033[0m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_DIM='\033[2m'

info()    { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*"; }
ok()      { printf "${C_GREEN}[ OK ]${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*"; }
fail()    { printf "${C_RED}[FAIL]${C_RESET} %s\n" "$*" >&2; }
dim()     { printf "${C_DIM}%s${C_RESET}\n" "$*"; }

usage() {
  cat <<EOF
Universal Engineering Layer v${VERSION}

Usage:
  $(basename "$0") [install|update|status|doctor|remove] [options]

Commands:
  install              Install the engineering layer (default)
  update               Refresh upstream skills and adapters
  status               Show installation and harness status
  doctor               Validate files, links, skills, and harness integration
  companion            Analyze project state and recommend the next workflow
  remove               Remove only files/blocks managed by this script

Options:
  --project PATH        Target project; default is current directory
  --no-hermes-config    Do not modify ~/.hermes/config.yaml
  --no-context          Do not create CONTEXT.md
  --profile NAME        Install profile: minimal, recommended, full
  --no-tools             Skip optional engineering-tool installation
  --force               Replace conflicting managed symlinks where safe
  -h, --help            Show this help

Environment overrides:
  POCOCK_REPO           Alternate Matt Pocock skills Git URL
  KARPATHY_REPO         Alternate Karpathy guidelines Git URL
EOF
}

# ----------------------------- argument parsing ------------------------------

if [[ $# -gt 0 && "$1" != -* ]]; then
  COMMAND="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { fail "--project requires a path"; exit 2; }
      PROJECT_ROOT="$2"; shift 2 ;;
    --no-hermes-config)
      CONFIGURE_HERMES=0; shift ;;
    --no-context)
      CREATE_CONTEXT=0; shift ;;
    --profile)
      [[ $# -ge 2 ]] || { fail "--profile requires minimal, recommended, or full"; exit 2; }
      PROFILE="$2"; shift 2 ;;
    --no-tools)
      INSTALL_TOOLS=0; shift ;;
    --force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      fail "Unknown option: $1"; usage; exit 2 ;;
  esac
done

case "$COMMAND" in
  install|update|status|doctor|companion|remove) ;;
  *) fail "Unknown command: $COMMAND"; usage; exit 2 ;;
esac

case "$PROFILE" in
  minimal|recommended|full) ;;
  *) fail "Unknown profile: $PROFILE (expected minimal, recommended, or full)"; exit 2 ;;
esac

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
  fail "Project path does not exist: $PROJECT_ROOT"
  exit 1
}

AGENTS_DIR="$PROJECT_ROOT/.agents"
SKILLS_DIR="$AGENTS_DIR/skills"
STATE_DIR="$AGENTS_DIR/.universal-engineering-layer"
STATE_FILE="$STATE_DIR/state"
TMP_DIR=""

cleanup() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    fail "Required command not found: $1"
    exit 1
  }
}

has() { command -v "$1" >/dev/null 2>&1; }

is_git_repo() {
  git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# ----------------------------- managed blocks --------------------------------

replace_managed_block() {
  local file="$1" begin="$2" end="$3" content_file="$4"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  python3 - "$file" "$begin" "$end" "$content_file" <<'PY'
from pathlib import Path
import sys

file_path, begin, end, content_path = sys.argv[1:]
p = Path(file_path)
text = p.read_text(encoding="utf-8") if p.exists() else ""
block = Path(content_path).read_text(encoding="utf-8").rstrip() + "\n"

s = text.find(begin)
e = text.find(end)

if s != -1 and e != -1 and e >= s:
    e += len(end)
    before = text[:s].rstrip()
    after = text[e:].lstrip("\n")
    out = (before + ("\n\n" if before else "") + block +
           (("\n" + after) if after else ""))
else:
    base = text.rstrip()
    out = (base + ("\n\n" if base else "") + block)

p.write_text(out.rstrip() + "\n", encoding="utf-8")
PY
}

remove_managed_block() {
  local file="$1" begin="$2" end="$3"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$begin" "$end" <<'PY'
from pathlib import Path
import sys

path, begin, end = sys.argv[1:]
p = Path(path)
text = p.read_text(encoding="utf-8")
s = text.find(begin)
e = text.find(end)

if s == -1 or e == -1 or e < s:
    raise SystemExit(0)

e += len(end)
out = (text[:s].rstrip() + "\n\n" + text[e:].lstrip()).strip()

if out:
    p.write_text(out + "\n", encoding="utf-8")
else:
    p.unlink()
PY
}

safe_link_dir() {
  local target="$1" link="$2"

  mkdir -p "$(dirname "$link")"

  if [[ -L "$link" ]]; then
    local current
    current="$(readlink "$link")"
    if [[ "$current" == "$target" ]]; then
      return 0
    fi
    if [[ "$FORCE" -eq 1 ]]; then
      rm "$link"
      ln -s "$target" "$link"
      return 0
    fi
    warn "Symlink already exists with another target: $link -> $current"
    return 1
  fi

  if [[ -e "$link" ]]; then
    warn "Not replacing existing path: $link"
    return 1
  fi

  ln -s "$target" "$link"
}

# ----------------------------- install skills --------------------------------

locate_karpathy_skill() {
  local repo="$1"
  local candidate

  for candidate in \
    "$repo/codex/karpathy-guidelines" \
    "$repo/karpathy-guidelines" \
    "$repo/skills/karpathy-guidelines"
  do
    if [[ -f "$candidate/SKILL.md" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  local found
  found="$(find "$repo" -type f -name SKILL.md -path '*karpathy*' -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] || return 1
  dirname "$found"
}

install_upstream_skills() {
  need git
  need python3

  TMP_DIR="$(mktemp -d)"

  info "Fetching Karpathy engineering guidelines..."
  git clone --quiet --depth=1 "$KARPATHY_REPO" "$TMP_DIR/karpathy"
  local kp
  kp="$(locate_karpathy_skill "$TMP_DIR/karpathy")" || {
    fail "Could not locate Karpathy SKILL.md in upstream repository."
    exit 1
  }

  mkdir -p "$SKILLS_DIR"
  rm -rf "$SKILLS_DIR/karpathy-guidelines"
  cp -a "$kp" "$SKILLS_DIR/karpathy-guidelines"
  ok "Karpathy guidelines installed."

  info "Fetching Matt Pocock skills..."
  git clone --quiet --depth=1 "$POCOCK_REPO" "$TMP_DIR/pocock"

  local count=0
  while IFS= read -r -d '' sf; do
    local dir name
    dir="$(dirname "$sf")"
    name="$(basename "$dir")"

    [[ "$name" == "karpathy-guidelines" ]] && continue
    [[ "$dir" == *"/node_modules/"* ]] && continue

    rm -rf "$SKILLS_DIR/$name"
    cp -a "$dir" "$SKILLS_DIR/$name"
    count=$((count + 1))
  done < <(find "$TMP_DIR/pocock" -type f -name SKILL.md -print0)

  if [[ "$count" -eq 0 ]]; then
    fail "No Matt Pocock SKILL.md files were found."
    exit 1
  fi

  ok "Installed ${count} Matt Pocock skill directories."

  mkdir -p "$STATE_DIR"
  {
    printf 'version=%q\n' "$VERSION"
    printf 'installed_at=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'pocock_count=%q\n' "$count"
    printf 'profile=%q\n' "$PROFILE"
    printf 'karpathy_repo=%q\n' "$KARPATHY_REPO"
    printf 'pocock_repo=%q\n' "$POCOCK_REPO"
  } > "$STATE_FILE"
}

install_engineering_companion() {
  local base="$SKILLS_DIR/engineering-companion"
  mkdir -p "$base/references" "$base/scripts"

  cat > "$base/SKILL.md" <<'UEL_SKILL_MD'
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

## Routing

Use `references/skill-routing.md` to choose task workflows.

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
UEL_SKILL_MD
  cat > "$base/references/project-moments.md" <<'UEL_REFERENCES_PROJECT_MOMENTS_MD'
# Project Moments

## idea
The user has a goal or feature concept, but scope and constraints are not yet clear.

## discovery
The task requires understanding an unfamiliar repository, subsystem, dependency, or architecture.

## specification
The desired behavior needs to be made explicit before coding.

## planning
Requirements are sufficiently known and work should be decomposed into implementation units.

## implementation
A defined change is actively being coded.

## debugging
Observed behavior differs from expected behavior and the cause is unknown.

## refactoring
Behavior should remain largely stable while structure, interfaces, or implementation changes.

## testing
The main goal is increasing confidence through automated or runtime verification.

## review
A change exists and needs correctness, maintainability, security, or scope review.

## integration
Multiple components, services, branches, APIs, or dependencies need to work together.

## pre-commit
Implementation is mostly complete and the next step is local validation and diff hygiene.

## pull-request
Work is in remote review/CI or preparing to enter it.

## release
The change is being prepared for deployment, packaging, tagging, or publication.

## production-incident
A real deployed system has an active failure or regression.

## maintenance
The work is dependency upkeep, security maintenance, cleanup, technical debt, or routine evolution.
UEL_REFERENCES_PROJECT_MOMENTS_MD
  cat > "$base/references/skill-routing.md" <<'UEL_REFERENCES_SKILL_ROUTING_MD'
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
UEL_REFERENCES_SKILL_ROUTING_MD
  cat > "$base/references/tool-routing.md" <<'UEL_REFERENCES_TOOL_ROUTING_MD'
# Tool Routing

## Own-code understanding

Preferred order:

1. codebase-memory-mcp or native LSP/symbol tools
2. ast-grep
3. ripgrep
4. manual traversal

Use codebase-memory for architecture, dependencies, call chains, callers, routes, and impact analysis.

Use ast-grep for syntax-aware structural search and transformation.

Use ripgrep for exact text, configuration values, comments, or fast fallback search.

## External APIs and libraries

Preferred order:

1. Context7
2. official documentation
3. web search

Do not use Context7 as the primary source for understanding the project's own architecture.

## Verification

Preferred order:

1. focused project tests
2. broader project tests
3. typecheck
4. lint
5. build
6. Playwright/runtime verification when user-visible behavior is relevant

## Collaboration

Use local Git for:
- working-tree state
- diffs
- branches
- commits

Use GitHub MCP for:
- issues
- pull requests
- CI/Actions
- code review context
- remote metadata
- security/dependency alerts

Prefer read-only remote access by default.

## Avoid unnecessary overlap

Do not invoke several tools merely because they are available. Pick the most semantic tool that can answer the question efficiently.
UEL_REFERENCES_TOOL_ROUTING_MD
  cat > "$base/references/risk-levels.md" <<'UEL_REFERENCES_RISK_LEVELS_MD'
# Engineering Risk Levels

## low

Typical examples:
- documentation-only edits;
- isolated tests;
- small internal change with strong coverage;
- local formatting changes.

Recommended behavior:
- minimal workflow;
- focused verification.

## medium

Typical examples:
- feature changes across several files;
- dependency upgrade;
- new endpoint;
- database query changes;
- moderate refactor.

Recommended behavior:
- inspect dependencies;
- use relevant workflow skill;
- tests + lint/type/build as appropriate.

## high

Typical examples:
- public API/schema change;
- authentication/authorization;
- persistence or migration changes;
- concurrency;
- security-sensitive code;
- many callers/dependents;
- cross-service integration;
- release/deployment changes.

Recommended behavior:
- codebase-memory/LSP impact analysis;
- ADR/context review;
- explicit plan;
- tests before and after;
- review;
- runtime verification where applicable.

## critical

Typical examples:
- active production incident;
- destructive migration;
- credential/security boundary changes;
- production data mutation;
- infrastructure change with broad blast radius.

Recommended behavior:
- preserve evidence;
- minimize changes;
- identify rollback;
- require strong verification;
- avoid speculative refactors;
- use production/observability context only with appropriate authorization.
UEL_REFERENCES_RISK_LEVELS_MD
  cat > "$base/scripts/project-state.sh" <<'UEL_SCRIPTS_PROJECT_STATE_SH'
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
UEL_SCRIPTS_PROJECT_STATE_SH
  chmod +x "$base/scripts/project-state.sh"
  ok "Engineering Companion skill installed."
}

ensure_how_to_gitignored() {
  local gi="$PROJECT_ROOT/.gitignore"
  local entry="how-to.html"
  touch "$gi"

  if ! grep -Fxq "$entry" "$gi"; then
    if [[ -s "$gi" && "$(tail -c 1 "$gi" | wc -l)" -eq 0 ]]; then
      printf '\n' >> "$gi"
    fi
    printf '\n# Universal Engineering Layer local tutorial\n%s\n' "$entry" >> "$gi"
    ok "Added how-to.html to .gitignore."
  else
    ok "how-to.html already ignored."
  fi
}

write_how_to() {
  cat > "$PROJECT_ROOT/how-to.html" <<'UEL_HOW_TO_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Universal Engineering Layer — How To</title>
  <meta name="description" content="Interactive tutorial for the Universal Engineering Layer, its skill stack, and the Engineering Companion meta-skill." />
  <style>
    :root{
      --bg:#0b0d10;
      --panel:#11151a;
      --panel-2:#151a21;
      --text:#eef2f6;
      --muted:#99a6b5;
      --line:#24303c;
      --accent:#7dd3fc;
      --accent-2:#c4b5fd;
      --good:#86efac;
      --warn:#fde68a;
      --danger:#fda4af;
      --shadow:0 24px 80px rgba(0,0,0,.36);
      --radius:22px;
      --max:1180px;
    }
    *{box-sizing:border-box}
    html{scroll-behavior:smooth}
    body{
      margin:0;
      background:
        radial-gradient(circle at 10% 0%, rgba(125,211,252,.10), transparent 28%),
        radial-gradient(circle at 90% 10%, rgba(196,181,253,.10), transparent 30%),
        var(--bg);
      color:var(--text);
      font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
      line-height:1.6;
    }
    a{color:inherit;text-decoration:none}
    code,pre{font-family:"SFMono-Regular",Consolas,"Liberation Mono",monospace}
    .shell{
      display:grid;
      grid-template-columns:280px minmax(0,1fr);
      min-height:100vh;
    }
    aside{
      position:sticky;
      top:0;
      height:100vh;
      border-right:1px solid var(--line);
      background:rgba(10,13,17,.84);
      backdrop-filter:blur(18px);
      padding:28px 22px;
      overflow:auto;
    }
    .brand{
      display:flex;
      gap:12px;
      align-items:center;
      margin-bottom:26px;
    }
    .logo{
      width:42px;height:42px;border-radius:14px;
      background:linear-gradient(135deg,var(--accent),var(--accent-2));
      color:#061018;
      display:grid;place-items:center;
      font-weight:900;
      box-shadow:0 12px 35px rgba(125,211,252,.2);
    }
    .brand strong{display:block;font-size:14px;letter-spacing:.02em}
    .brand span{display:block;color:var(--muted);font-size:12px}
    nav{display:grid;gap:6px}
    nav a{
      color:var(--muted);
      padding:10px 12px;
      border-radius:12px;
      font-size:14px;
      transition:.18s ease;
    }
    nav a:hover,nav a.active{
      color:var(--text);
      background:var(--panel-2);
    }
    .aside-note{
      margin-top:28px;
      border:1px solid var(--line);
      background:var(--panel);
      border-radius:16px;
      padding:14px;
      color:var(--muted);
      font-size:12px;
    }
    main{min-width:0}
    .wrap{max-width:var(--max);margin:auto;padding:56px 42px 96px}
    .hero{
      position:relative;
      overflow:hidden;
      border:1px solid var(--line);
      background:linear-gradient(180deg,rgba(255,255,255,.035),rgba(255,255,255,.015));
      border-radius:30px;
      padding:54px;
      box-shadow:var(--shadow);
    }
    .hero:after{
      content:"";
      position:absolute;inset:auto -10% -55% 45%;
      height:430px;
      background:radial-gradient(circle,rgba(125,211,252,.18),transparent 62%);
      pointer-events:none;
    }
    .eyebrow{
      display:inline-flex;
      gap:8px;align-items:center;
      color:var(--accent);
      font-size:12px;
      font-weight:800;
      text-transform:uppercase;
      letter-spacing:.15em;
      margin-bottom:14px;
    }
    h1{
      margin:0;
      max-width:840px;
      font-size:clamp(42px,7vw,82px);
      line-height:.98;
      letter-spacing:-.055em;
    }
    .lede{
      max-width:760px;
      margin:24px 0 0;
      color:#c6d0da;
      font-size:19px;
    }
    .hero-grid{
      display:grid;
      grid-template-columns:repeat(3,1fr);
      gap:14px;
      margin-top:34px;
    }
    .metric{
      border:1px solid var(--line);
      background:rgba(7,11,15,.48);
      border-radius:16px;
      padding:18px;
    }
    .metric b{display:block;font-size:22px}
    .metric span{color:var(--muted);font-size:13px}
    section{padding-top:72px;scroll-margin-top:26px}
    .section-head{
      display:flex;justify-content:space-between;align-items:end;gap:20px;
      margin-bottom:24px;
    }
    h2{margin:0;font-size:34px;letter-spacing:-.035em}
    h3{margin:0 0 8px;font-size:18px}
    p{color:#c7d0da}
    .muted{color:var(--muted)}
    .grid-2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
    .grid-3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}
    .card{
      border:1px solid var(--line);
      background:linear-gradient(180deg,var(--panel),#0f1318);
      border-radius:var(--radius);
      padding:24px;
    }
    .card p:last-child{margin-bottom:0}
    .tag{
      display:inline-block;
      border:1px solid var(--line);
      border-radius:999px;
      padding:4px 9px;
      font-size:11px;
      color:var(--muted);
      margin-bottom:12px;
    }
    .flow{
      display:grid;
      gap:10px;
      margin-top:18px;
    }
    .flow-row{
      display:grid;
      grid-template-columns:150px 1fr;
      gap:16px;align-items:start;
      border:1px solid var(--line);
      background:var(--panel);
      border-radius:16px;
      padding:16px;
    }
    .flow-row strong{color:var(--accent)}
    pre{
      margin:16px 0 0;
      background:#080b0e;
      border:1px solid var(--line);
      border-radius:16px;
      padding:18px;
      overflow:auto;
      color:#d9e5ef;
    }
    .timeline{
      position:relative;
      padding-left:26px;
      display:grid;gap:16px;
    }
    .timeline:before{
      content:"";
      position:absolute;left:8px;top:10px;bottom:10px;width:2px;background:var(--line);
    }
    .moment{
      position:relative;
      border:1px solid var(--line);
      background:var(--panel);
      border-radius:16px;padding:18px;
    }
    .moment:before{
      content:"";
      position:absolute;left:-23px;top:23px;width:10px;height:10px;border-radius:50%;
      background:var(--accent);
      box-shadow:0 0 0 5px var(--bg);
    }
    .moment b{font-size:15px}
    .moment span{display:block;color:var(--muted);font-size:13px;margin-top:4px}
    .decision{
      border:1px solid var(--line);
      border-radius:22px;
      overflow:hidden;
    }
    .decision .row{
      display:grid;
      grid-template-columns:180px 1fr;
      gap:20px;
      padding:18px 20px;
      background:var(--panel);
      border-bottom:1px solid var(--line);
    }
    .decision .row:last-child{border-bottom:0}
    .decision .label{color:var(--muted);font-size:13px}
    .decision .value{font-weight:700}
    .callout{
      border:1px solid rgba(134,239,172,.28);
      background:rgba(134,239,172,.055);
      border-radius:18px;
      padding:18px 20px;
    }
    .callout strong{color:var(--good)}
    .steps{
      counter-reset:step;
      display:grid;
      gap:14px;
    }
    .step{
      counter-increment:step;
      display:grid;
      grid-template-columns:48px 1fr;
      gap:16px;
      border:1px solid var(--line);
      border-radius:18px;
      padding:18px;
      background:var(--panel);
    }
    .step:before{
      content:counter(step);
      width:36px;height:36px;border-radius:12px;
      display:grid;place-items:center;
      background:linear-gradient(135deg,var(--accent),var(--accent-2));
      color:#071019;font-weight:900;
    }
    .profile{
      border:1px solid var(--line);
      border-radius:20px;padding:22px;background:var(--panel);
    }
    .profile.recommended{outline:1px solid rgba(125,211,252,.35)}
    .profile ul{padding-left:18px;color:#c7d0da}
    footer{
      margin-top:86px;
      padding-top:26px;
      border-top:1px solid var(--line);
      display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap;
      color:var(--muted);font-size:13px;
    }
    .creator{color:var(--text);font-weight:800}
    .kbd{
      display:inline-block;
      border:1px solid var(--line);
      background:#0a0d11;
      border-bottom-width:2px;
      border-radius:7px;
      padding:1px 6px;
      font-family:monospace;font-size:12px;
    }
    @media (max-width:920px){
      .shell{grid-template-columns:1fr}
      aside{display:none}
      .wrap{padding:28px 18px 72px}
      .hero{padding:30px}
      .hero-grid,.grid-2,.grid-3{grid-template-columns:1fr}
      .flow-row,.decision .row{grid-template-columns:1fr}
      h1{font-size:48px}
    }
  </style>
</head>
<body>
  <div class="shell">
    <aside>
      <div class="brand">
        <div class="logo">UEL</div>
        <div>
          <strong>Universal Engineering Layer</strong>
          <span>Engineering Companion Tutorial</span>
        </div>
      </div>
      <nav id="nav">
        <a href="#overview">Overview</a>
        <a href="#stack">The skill stack</a>
        <a href="#companion">Engineering Companion</a>
        <a href="#moments">Project moments</a>
        <a href="#routing">How routing works</a>
        <a href="#profiles">Profiles</a>
        <a href="#workflow">Typical workflow</a>
        <a href="#commands">Commands</a>
        <a href="#mental-model">Mental model</a>
        <a href="#attribution">Attribution</a>
      </nav>
      <div class="aside-note">
        Local tutorial file.<br>
        It is added to <code>.gitignore</code> automatically so each developer can keep it without committing generated docs.
      </div>
    </aside>

    <main>
      <div class="wrap">
        <section id="overview" style="padding-top:0">
          <div class="hero">
            <div class="eyebrow">Universal Engineering Layer · How To</div>
            <h1>Your AI engineering system, explained.</h1>
            <p class="lede">
              The Universal Engineering Layer gives coding agents a shared engineering discipline,
              a set of task workflows, a modern tool hierarchy, and an Engineering Companion that
              recommends what to do next based on the current moment of the project.
            </p>
            <div class="hero-grid">
              <div class="metric"><b>1</b><span>canonical engineering layer</span></div>
              <div class="metric"><b>Many</b><span>supported harnesses & IDEs</span></div>
              <div class="metric"><b>Dynamic</b><span>workflow routing by project moment</span></div>
            </div>
          </div>
        </section>

        <section id="stack">
          <div class="section-head">
            <div>
              <div class="eyebrow">Architecture</div>
              <h2>The skill stack</h2>
            </div>
          </div>

          <div class="grid-3">
            <article class="card">
              <span class="tag">Always active</span>
              <h3>Karpathy Guidelines</h3>
              <p>Defines engineering behavior: understand first, keep changes surgical, surface assumptions, and verify the result.</p>
            </article>
            <article class="card">
              <span class="tag">Dynamic routing</span>
              <h3>Engineering Companion</h3>
              <p>Identifies the current project moment, estimates risk, and routes the task toward the best workflow and tools.</p>
            </article>
            <article class="card">
              <span class="tag">On demand</span>
              <h3>Matt Pocock Skills</h3>
              <p>Provides task-specific workflows such as specification, implementation, TDD, review, prototyping, and triage.</p>
            </article>
          </div>

          <div class="flow">
            <div class="flow-row"><strong>Behavior</strong><div>Karpathy → how the agent should behave while engineering.</div></div>
            <div class="flow-row"><strong>Routing</strong><div>Engineering Companion → what kind of work is happening now and what should happen next.</div></div>
            <div class="flow-row"><strong>Workflow</strong><div>Matt Pocock skills → the specific process for the task.</div></div>
            <div class="flow-row"><strong>Capabilities</strong><div>codebase-memory, Context7, ast-grep, Playwright, GitHub MCP, and other tools → what the agent can actually inspect or verify.</div></div>
          </div>
        </section>

        <section id="companion">
          <div class="section-head">
            <div>
              <div class="eyebrow">Meta skill</div>
              <h2>Engineering Companion</h2>
            </div>
          </div>

          <div class="grid-2">
            <div class="card">
              <h3>What it looks at</h3>
              <p>When useful, the companion can inspect the user's request, Git state, branch name, changed files, tests, CI presence, project manifests, ADRs, context docs, and semantic code information.</p>
              <pre>engineering-layer companion</pre>
            </div>
            <div class="card">
              <h3>What it returns</h3>
              <div class="decision">
                <div class="row"><div class="label">Current moment</div><div class="value">implementation</div></div>
                <div class="row"><div class="label">Risk</div><div class="value">medium</div></div>
                <div class="row"><div class="label">Recommended skill</div><div class="value">implementation / TDD</div></div>
                <div class="row"><div class="label">Recommended tools</div><div class="value">codebase-memory + Context7</div></div>
                <div class="row"><div class="label">Verification</div><div class="value">tests → typecheck → lint → build</div></div>
              </div>
            </div>
          </div>

          <div class="callout" style="margin-top:18px">
            <strong>Important:</strong>
            The companion routes the work. It does not override the engineer, project rules, or explicit human instructions.
          </div>
        </section>

        <section id="moments">
          <div class="section-head">
            <div>
              <div class="eyebrow">Project awareness</div>
              <h2>Project moments</h2>
            </div>
            <p class="muted">The companion re-evaluates the moment as the work evolves.</p>
          </div>

          <div class="timeline">
            <div class="moment"><b>Idea</b><span>The concept exists, but scope and constraints are still fuzzy.</span></div>
            <div class="moment"><b>Discovery</b><span>The repository, subsystem, or dependency needs to be understood.</span></div>
            <div class="moment"><b>Specification</b><span>Expected behavior needs to be made explicit before coding.</span></div>
            <div class="moment"><b>Planning</b><span>Known work should be decomposed into implementation units.</span></div>
            <div class="moment"><b>Implementation</b><span>A defined change is actively being built.</span></div>
            <div class="moment"><b>Debugging</b><span>Observed behavior differs from expected behavior and the cause is unknown.</span></div>
            <div class="moment"><b>Refactoring</b><span>Structure changes while behavior should remain stable.</span></div>
            <div class="moment"><b>Testing / Review</b><span>The main goal becomes confidence rather than new code.</span></div>
            <div class="moment"><b>Integration / PR</b><span>Components, CI, review, or remote collaboration become the focus.</span></div>
            <div class="moment"><b>Release / Production Incident</b><span>Deployment, rollback, observability, and blast radius matter most.</span></div>
          </div>
        </section>

        <section id="routing">
          <div class="section-head">
            <div>
              <div class="eyebrow">Tool hierarchy</div>
              <h2>How routing works</h2>
            </div>
          </div>

          <div class="grid-2">
            <div class="card">
              <h3>Understand your own code</h3>
              <pre>1. codebase-memory / LSP
2. ast-grep
3. ripgrep
4. manual traversal</pre>
              <p class="muted">Use the most semantic tool that can answer the question cleanly.</p>
            </div>
            <div class="card">
              <h3>Understand external libraries</h3>
              <pre>1. Context7
2. official docs
3. web search</pre>
              <p class="muted">Context7 is for third-party APIs, not for understanding your own repository.</p>
            </div>
            <div class="card">
              <h3>Verify a change</h3>
              <pre>1. focused tests
2. broader tests
3. typecheck
4. lint
5. build
6. Playwright</pre>
            </div>
            <div class="card">
              <h3>Collaborate</h3>
              <pre>Local Git → diffs / branches / commits
GitHub MCP → issues / PRs / CI</pre>
              <p class="muted">Prefer read-only remote access by default.</p>
            </div>
          </div>
        </section>

        <section id="profiles">
          <div class="section-head">
            <div>
              <div class="eyebrow">Installation modes</div>
              <h2>Profiles</h2>
            </div>
          </div>

          <div class="grid-3">
            <div class="profile">
              <span class="tag">Lightweight</span>
              <h3>Minimal</h3>
              <ul>
                <li>Karpathy guidelines</li>
                <li>Engineering Companion</li>
                <li>Matt Pocock skills</li>
                <li>Harness adapters</li>
                <li>ENGINEERS.md</li>
              </ul>
              <pre>engineering-layer install --profile minimal</pre>
            </div>
            <div class="profile recommended">
              <span class="tag">Recommended</span>
              <h3>Recommended</h3>
              <ul>
                <li>Everything in Minimal</li>
                <li>codebase-memory-mcp</li>
                <li>ast-grep</li>
                <li>ripgrep / fd</li>
                <li>jq / yq</li>
                <li>Context7 guidance</li>
              </ul>
              <pre>engineering-layer install --profile recommended</pre>
            </div>
            <div class="profile">
              <span class="tag">Agentic</span>
              <h3>Full</h3>
              <ul>
                <li>Everything in Recommended</li>
                <li>Playwright guidance</li>
                <li>GitHub MCP guidance</li>
                <li>Broader autonomous verification</li>
              </ul>
              <pre>engineering-layer install --profile full</pre>
            </div>
          </div>
        </section>

        <section id="workflow">
          <div class="section-head">
            <div>
              <div class="eyebrow">Example</div>
              <h2>A typical workflow</h2>
            </div>
          </div>

          <div class="steps">
            <div class="step"><div><h3>User asks for a change</h3><p>The harness reads project rules and the shared engineering layer.</p></div></div>
            <div class="step"><div><h3>Companion detects the moment</h3><p>It decides whether this is discovery, implementation, debugging, refactoring, review, release, or another moment.</p></div></div>
            <div class="step"><div><h3>Karpathy baseline applies</h3><p>The work stays minimal, explicit, and verifiable.</p></div></div>
            <div class="step"><div><h3>The right workflow skill is selected</h3><p>Specification, TDD, implementation, code review, triage, or another relevant skill is loaded.</p></div></div>
            <div class="step"><div><h3>The right capabilities are used</h3><p>Semantic code tools, external docs, structural search, browser verification, or GitHub context are used only when they add value.</p></div></div>
            <div class="step"><div><h3>Verification becomes the final moment</h3><p>Tests, typecheck, lint, build, runtime behavior, and diff review close the loop.</p></div></div>
          </div>
        </section>

        <section id="commands">
          <div class="section-head">
            <div>
              <div class="eyebrow">CLI</div>
              <h2>Useful commands</h2>
            </div>
          </div>

          <div class="grid-2">
            <div class="card"><h3>Install</h3><pre>engineering-layer install --profile recommended</pre></div>
            <div class="card"><h3>Ask the companion</h3><pre>engineering-layer companion</pre></div>
            <div class="card"><h3>Validate</h3><pre>engineering-layer doctor</pre></div>
            <div class="card"><h3>Refresh</h3><pre>engineering-layer update --profile recommended</pre></div>
          </div>
        </section>

        <section id="mental-model">
          <div class="section-head">
            <div>
              <div class="eyebrow">Remember this</div>
              <h2>The mental model</h2>
            </div>
          </div>

          <div class="card">
            <pre>MODEL != ENGINEERING PROCESS
HARNESS != ENGINEERING PROCESS

PROJECT
  │
  ▼
ENGINEERING POLICY
  │
  ▼
ENGINEERING COMPANION
  │
  ▼
TASK WORKFLOW
  │
  ▼
ENGINEERING CAPABILITIES
  │
  ├── Codex
  ├── Claude
  ├── Hermes
  ├── Antigravity
  ├── Copilot
  ├── OpenCode
  └── future agents</pre>
            <p>
              The goal is not to force one AI tool on a project. The goal is to make the project carry its own engineering discipline,
              so different agents can work under the same rules.
            </p>
          </div>
        </section>

        <section id="attribution">
          <div class="section-head">
            <div>
              <div class="eyebrow">Open source</div>
              <h2>Upstream projects & attribution</h2>
            </div>
          </div>
          <div class="card">
            <p>
              Universal Engineering Layer is an independent integration project created by
              <strong>@sudo-make-jon</strong>. It installs or integrates with independent
              open-source projects and does not claim authorship of them.
            </p>
            <div class="decision">
              <div class="row"><div class="label">Matt Pocock Skills</div><div class="value">Task workflows · MIT</div></div>
              <div class="row"><div class="label">Karpathy Guidelines</div><div class="value">Engineering baseline · MIT declared by upstream skill</div></div>
              <div class="row"><div class="label">codebase-memory-mcp</div><div class="value">Code intelligence · MIT</div></div>
              <div class="row"><div class="label">Context7 by Upstash</div><div class="value">External documentation · MIT</div></div>
              <div class="row"><div class="label">Playwright MCP by Microsoft</div><div class="value">Browser verification · Apache-2.0</div></div>
              <div class="row"><div class="label">GitHub MCP Server</div><div class="value">GitHub integration · MIT</div></div>
            </div>
            <p class="muted" style="margin-top:16px">
              Each upstream project remains governed by its own license. The Universal
              Engineering Layer MIT license applies only to its original installer,
              Engineering Companion, routing logic, documentation, tutorial, and integration
              code. See THIRD_PARTY.md in the Universal Engineering Layer repository for
              detailed attribution.
            </p>
          </div>
        </section>

        <footer>
          <div>Universal Engineering Layer · Local tutorial</div>
          <div class="creator">Made by @sudo-make-jon</div>
        </footer>
      </div>
    </main>
  </div>

  <script>
    const links = [...document.querySelectorAll('#nav a')];
    const sections = links.map(a => document.querySelector(a.getAttribute('href'))).filter(Boolean);
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if(entry.isIntersecting){
          links.forEach(a => a.classList.toggle('active', a.getAttribute('href') === '#' + entry.target.id));
        }
      });
    }, {rootMargin:'-30% 0px -60% 0px', threshold:0});
    sections.forEach(s => observer.observe(s));
  </script>
</body>
</html>
UEL_HOW_TO_HTML
  ok "Created how-to.html tutorial."
}

write_engineering_policy() {
  mkdir -p "$AGENTS_DIR/adr" "$PROJECT_ROOT/docs"

  cat > "$AGENTS_DIR/ENGINEERING.md" <<'EOF'
# Universal Engineering Policy

This repository uses a shared engineering layer for AI development agents.

## Instruction priority

When instructions conflict, follow this order:

1. Explicit instructions from the human.
2. Repository-specific requirements and safety constraints.
3. Existing architecture and accepted architectural decisions.
4. The baseline engineering guidelines.
5. Task-specific skills.
6. General model or harness defaults.

## Baseline engineering behavior

Read and follow:

`.agents/skills/karpathy-guidelines/SKILL.md`

Use it as the default engineering discipline for software work.

In particular:

- Understand relevant code before changing it.
- Make assumptions explicit when they materially affect the solution.
- Prefer the smallest correct change.
- Reuse existing project patterns before introducing new abstractions.
- Avoid unrelated refactors.
- Define what success means before substantial changes.
- Verify work with the strongest available checks.
- Never claim a test, build, lint, or verification step was run when it was not.

## Engineering Companion

The orchestration/meta-skill is:

`.agents/skills/engineering-companion/SKILL.md`

Use it when the current project moment, next workflow, or best engineering
tool is unclear. It may recommend a task-specific skill and a verification
strategy based on the user's request and repository state.

## Engineering environment

Human engineers and AI agents should also read:

`ENGINEERS.md`

It explains the preferred hierarchy for code intelligence, external
documentation, structural search, testing, browser verification, and remote
repository collaboration.

## Task-specific skills

Skills live under:

`.agents/skills/`

Before substantial work, inspect `.agents/SKILLS.md` and load the skill or
skills that match the task.

Task skills extend the baseline. They do not override explicit human or
project-specific requirements.

## Default feature workflow

For non-trivial features, prefer:

1. Understand the request and repository context.
2. Inspect existing architecture and ADRs.
3. Clarify requirements from available context.
4. Produce or update a specification when useful.
5. Break work into small implementation units.
6. Implement the smallest coherent unit.
7. Test it.
8. Review the diff.
9. Verify against the original goal.
10. Update documentation when behavior or architecture changed.

For small fixes, use the shortest version of this workflow that still gives
reasonable confidence.

## Change discipline

Do not:

- Rewrite unrelated code.
- Introduce dependencies without a concrete reason.
- Add abstractions only for hypothetical future needs.
- Silently alter public APIs, schemas, configuration formats, or persistence.
- Delete working functionality without justification.
- Bypass existing tests merely to make a change pass.

## Architectural decisions

Important architectural decisions belong in:

`.agents/adr/`

Read existing ADRs before making a major architectural change.

## Project context

If present, read:

`CONTEXT.md`

It should summarize architecture, constraints, commands, deployment, and
repository-specific knowledge.

## Verification

Before considering a development task complete:

- Re-read the original request.
- Review the final diff.
- Run relevant tests where possible.
- Run lint/type/build checks where appropriate.
- Check for unintended modifications.
- State anything that could not be verified.

## Harness portability

`.agents/` is the canonical source of engineering skills and policy.

Harness-specific files should point to or expose this canonical layer rather
than maintain independent copies.
EOF
}

write_engineers_guide() {
  cat > "$PROJECT_ROOT/ENGINEERS.md" <<'EOF'
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
EOF
}

generate_skill_index() {
  local idx="$AGENTS_DIR/SKILLS.md"
  cat > "$idx" <<'EOF'
# Engineering Skill Index

Canonical skill directory: `.agents/skills/`

Baseline:
- `karpathy-guidelines`

Available skills:
EOF

  local d
  while IFS= read -r -d '' d; do
    local name desc
    name="$(basename "$d")"
    desc="$(python3 - "$d/SKILL.md" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r'(?m)^description:\s*(.+?)\s*$', text)
if m:
    print(m.group(1).strip().strip("'\""))
PY
)"
    if [[ -n "$desc" ]]; then
      printf -- '- `%s` — %s\n' "$name" "$desc" >> "$idx"
    else
      printf -- '- `%s`\n' "$name" >> "$idx"
    fi
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

write_context_template() {
  [[ "$CREATE_CONTEXT" -eq 1 ]] || return 0
  [[ ! -e "$PROJECT_ROOT/CONTEXT.md" ]] || return 0

  cat > "$PROJECT_ROOT/CONTEXT.md" <<'EOF'
# Project Context

## Purpose

Describe what the project does and who it serves.

## Architecture

Describe the major components and how they communicate.

## Technology Stack

List languages, frameworks, databases, infrastructure, and important versions.

## Important Constraints

Document security, compatibility, performance, product, and operational
constraints that agents must preserve.

## Development Commands

### Install

```bash
# command
```

### Development

```bash
# command
```

### Test

```bash
# command
```

### Lint / Typecheck

```bash
# command
```

### Build

```bash
# command
```

## Important Paths

Document important directories, configuration files, entry points, and data
locations.

## Deployment

Describe deployment and rollback procedures.

## Notes for AI Agents

Add repository-specific facts that reduce guesswork and prevent unsafe or
unnecessary changes.
EOF
  ok "Created CONTEXT.md template."
}

write_codex_generic_adapter() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
$BEGIN_AGENT

# Universal Engineering Layer

This repository uses the canonical AI engineering layer under \`.agents/\`.

Before software-development work:

1. Read \`.agents/ENGINEERING.md\`.
2. Read \`.agents/skills/karpathy-guidelines/SKILL.md\`.
3. Inspect \`.agents/SKILLS.md\` for task-specific skills.
4. Read \`CONTEXT.md\` when present.
5. Read relevant files under \`.agents/adr/\`.

Explicit human instructions and repository-specific constraints take
precedence over this shared layer.

Do not duplicate the canonical skills into another folder unless the current
harness requires an adapter.

$END_AGENT
EOF
  replace_managed_block "$PROJECT_ROOT/AGENTS.md" "$BEGIN_AGENT" "$END_AGENT" "$tmp"
  rm -f "$tmp"
}

write_claude_adapter() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
$BEGIN_CLAUDE

# Universal Engineering Layer

@.agents/ENGINEERING.md
@ENGINEERS.md
@.agents/SKILLS.md

For engineering tasks, use \`.agents/skills/karpathy-guidelines/SKILL.md\` as
the baseline and load task-specific skills from \`.agents/skills/\` when
relevant.

Read \`CONTEXT.md\` when present and relevant ADRs under \`.agents/adr/\`.

$END_CLAUDE
EOF
  replace_managed_block "$PROJECT_ROOT/CLAUDE.md" "$BEGIN_CLAUDE" "$END_CLAUDE" "$tmp"
  rm -f "$tmp"

  mkdir -p "$PROJECT_ROOT/.claude"
  safe_link_dir "../.agents/skills" "$PROJECT_ROOT/.claude/skills" || true
}

write_antigravity_adapter() {
  # Antigravity natively discovers .agents/skills. Add an always-on rule-style
  # markdown file as an additional compatibility hint.
  mkdir -p "$PROJECT_ROOT/.agents/rules"
  local f="$PROJECT_ROOT/.agents/rules/universal-engineering-layer.md"
  cat > "$f" <<EOF
$BEGIN_ANTIGRAVITY
# Universal Engineering Layer

Use \`.agents/ENGINEERING.md\` as the repository engineering policy.

For software-development tasks:
- apply \`.agents/skills/karpathy-guidelines/SKILL.md\` as the baseline;
- inspect \`.agents/SKILLS.md\` for relevant task-specific skills;
- read \`CONTEXT.md\` and relevant ADRs when applicable.

Human and repository-specific instructions have higher priority.
$END_ANTIGRAVITY
EOF
}

write_copilot_vscode_adapter() {
  mkdir -p "$PROJECT_ROOT/.github"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
$BEGIN_COPILOT

# Universal Engineering Layer

Before making substantial code changes, read:

- \`.agents/ENGINEERING.md\`
- \`.agents/skills/karpathy-guidelines/SKILL.md\`
- \`.agents/SKILLS.md\`
- \`CONTEXT.md\`, when present
- relevant ADRs under \`.agents/adr/\`

Use task-specific skills from \`.agents/skills/\` when they match the work.
Prefer small, verifiable changes and preserve project conventions.

$END_COPILOT
EOF
  replace_managed_block "$PROJECT_ROOT/.github/copilot-instructions.md" "$BEGIN_COPILOT" "$END_COPILOT" "$tmp"
  rm -f "$tmp"
}

write_optional_symlink_adapters() {
  # These are harmless compatibility affordances for harnesses that look in
  # a project-specific skills directory. Existing real directories are never
  # replaced unless --force is explicitly used.
  mkdir -p "$PROJECT_ROOT/.codex" "$PROJECT_ROOT/.opencode" "$PROJECT_ROOT/.openclaw"
  safe_link_dir "../.agents/skills" "$PROJECT_ROOT/.codex/skills" || true
  safe_link_dir "../.agents/skills" "$PROJECT_ROOT/.opencode/skills" || true
  safe_link_dir "../.agents/skills" "$PROJECT_ROOT/.openclaw/skills" || true
}

# ----------------------------- Hermes adapter --------------------------------

hermes_config_path() {
  if [[ -n "${HERMES_HOME:-}" ]]; then
    printf '%s/config.yaml\n' "$HERMES_HOME"
  else
    printf '%s/.hermes/config.yaml\n' "$HOME"
  fi
}

configure_hermes_external_dir() {
  [[ "$CONFIGURE_HERMES" -eq 1 ]] || {
    warn "Hermes config integration skipped by --no-hermes-config."
    return 0
  }

  # Only touch a Hermes config if Hermes appears installed or ~/.hermes exists.
  if ! has hermes && [[ ! -d "${HERMES_HOME:-$HOME/.hermes}" ]]; then
    return 0
  fi

  local cfg
  cfg="$(hermes_config_path)"
  mkdir -p "$(dirname "$cfg")"
  [[ -f "$cfg" ]] || touch "$cfg"

  local backup="${cfg}.uel-backup-$(date +%Y%m%d%H%M%S)"
  cp -a "$cfg" "$backup"

  if ! python3 - "$cfg" "$SKILLS_DIR" <<'PY'
from pathlib import Path
import sys, re

cfg = Path(sys.argv[1])
path = str(Path(sys.argv[2]).resolve())
text = cfg.read_text(encoding="utf-8") if cfg.exists() else ""

# If exact path already appears as a YAML list entry, no change.
entry_re = re.compile(r'(?m)^\s*-\s*' + re.escape(path) + r'\s*(?:#.*)?$')
if entry_re.search(text):
    raise SystemExit(0)

lines = text.splitlines()

def indent_of(s):
    return len(s) - len(s.lstrip(" "))

# Locate top-level skills:
skills_i = None
for i, line in enumerate(lines):
    if re.match(r'^skills:\s*(?:#.*)?$', line):
        skills_i = i
        break

if skills_i is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines += ["skills:", "  external_dirs:", f"    - {path}"]
else:
    # Find end of top-level skills mapping.
    end = len(lines)
    for j in range(skills_i + 1, len(lines)):
        if lines[j].strip() and indent_of(lines[j]) == 0 and not lines[j].lstrip().startswith("#"):
            end = j
            break

    ext_i = None
    for j in range(skills_i + 1, end):
        if re.match(r'^\s{2}external_dirs:\s*(?:#.*)?$', lines[j]):
            ext_i = j
            break

    if ext_i is None:
        lines[skills_i + 1:skills_i + 1] = ["  external_dirs:", f"    - {path}"]
    else:
        # Find end of external_dirs list.
        insert_at = ext_i + 1
        while insert_at < len(lines):
            line = lines[insert_at]
            if not line.strip() or line.lstrip().startswith("#"):
                insert_at += 1
                continue
            ind = indent_of(line)
            if ind <= 2:
                break
            insert_at += 1
        lines.insert(insert_at, f"    - {path}")

cfg.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY
  then
    cp -a "$backup" "$cfg"
    fail "Hermes config patch failed; restored backup."
    return 1
  fi

  # Minimal structural validation for the inserted path.
  if grep -Fq -- "- $SKILLS_DIR" "$cfg"; then
    ok "Registered project skills as a Hermes external skill directory."
    rm -f "$backup"
  else
    cp -a "$backup" "$cfg"
    fail "Hermes config validation failed; restored backup."
    return 1
  fi
}

remove_hermes_external_dir() {
  [[ "$CONFIGURE_HERMES" -eq 1 ]] || return 0
  local cfg
  cfg="$(hermes_config_path)"
  [[ -f "$cfg" ]] || return 0

  python3 - "$cfg" "$SKILLS_DIR" <<'PY'
from pathlib import Path
import sys, re

cfg = Path(sys.argv[1])
path = str(Path(sys.argv[2]).resolve())
lines = cfg.read_text(encoding="utf-8").splitlines()
rx = re.compile(r'^\s*-\s*' + re.escape(path) + r'\s*(?:#.*)?$')
out = [line for line in lines if not rx.match(line)]
cfg.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY
}

# ------------------------ optional engineering tools --------------------------

install_cli_if_missing() {
  local cmd="$1"
  shift
  if has "$cmd"; then
    ok "$cmd already installed."
    return 0
  fi
  "$@" || {
    warn "Could not automatically install $cmd. Install it manually if needed."
    return 1
  }
}

install_engineering_tools() {
  [[ "$INSTALL_TOOLS" -eq 1 ]] || {
    warn "Optional engineering tools skipped by --no-tools."
    return 0
  }

  [[ "$PROFILE" != "minimal" ]] || return 0

  info "Installing/checking recommended engineering tools..."

  # Native distro packages where possible. We intentionally keep this
  # conservative and only auto-install when a known package manager exists.
  if has apt-get; then
    sudo apt-get update -y || true
    sudo apt-get install -y ripgrep fd-find jq || true
    if ! has fd && has fdfind; then
      mkdir -p "$HOME/.local/bin"
      ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
      export PATH="$HOME/.local/bin:$PATH"
    fi
    # yq package naming varies; install only if available.
    sudo apt-get install -y yq 2>/dev/null || true
  elif has dnf; then
    sudo dnf install -y ripgrep fd-find jq yq || true
  elif has pacman; then
    sudo pacman -Sy --needed --noconfirm ripgrep fd jq yq || true
  elif has brew; then
    brew install ripgrep fd jq yq || true
  fi

  # ast-grep
  if ! has ast-grep && ! has sg; then
    if has cargo; then
      cargo install ast-grep --locked || true
    elif has npm; then
      npm install -g @ast-grep/cli || true
    else
      warn "ast-grep not installed; install Cargo or Node.js, or install ast-grep manually."
    fi
  fi

  # codebase-memory-mcp
  if ! has codebase-memory-mcp; then
    if has uvx; then
      uvx --from codebase-memory-mcp codebase-memory-mcp --help >/dev/null 2>&1 || true
    elif has pipx; then
      pipx install codebase-memory-mcp || true
    elif has pip3; then
      python3 -m pip install --user codebase-memory-mcp || true
    else
      warn "codebase-memory-mcp not installed; Python package tooling not found."
    fi
  fi

  if has codebase-memory-mcp; then
    # Conservative defaults. Auto-index on; watcher off to avoid surprise RAM/CPU.
    codebase-memory-mcp config set auto_index true >/dev/null 2>&1 || true
    codebase-memory-mcp config set auto_watch false >/dev/null 2>&1 || true
    codebase-memory-mcp config set auto_index_limit 20000 >/dev/null 2>&1 || true
    ok "codebase-memory-mcp configured with conservative auto-indexing defaults."
  fi

  # Context7 is generally consumed through MCP-capable harness configuration.
  # We create documentation/config hints rather than assuming one global client.
  mkdir -p "$AGENTS_DIR/mcp"
  cat > "$AGENTS_DIR/mcp/README.md" <<'EOF'
# MCP Capability Notes

This directory documents recommended MCP capabilities for the project.

Recommended:
- codebase-memory-mcp — local code intelligence and persistent indexing
- Context7 — current third-party library/framework documentation

Full profile additions:
- Playwright — browser/runtime verification
- GitHub MCP — remote repository collaboration

Exact MCP registration differs between harnesses. Keep credentials and
machine-specific secrets out of the repository.
EOF

  if [[ "$PROFILE" == "full" ]]; then
    info "Preparing full-profile capability notes..."
    cat > "$AGENTS_DIR/mcp/FULL-PROFILE.md" <<'EOF'
# Full Profile

## Playwright

Use Playwright for browser and end-to-end verification of web applications.

Install via the mechanism supported by your harness or Node.js environment.

## GitHub MCP

Use GitHub MCP for issues, pull requests, CI/Actions, code review context, and
repository metadata.

Prefer read-only access by default. Do not commit tokens or credentials.

Because MCP registration formats differ between Codex, Claude Code, Hermes,
Antigravity, OpenCode, and other clients, the Universal Engineering Layer does
not write secrets or global MCP credentials into the repository.
EOF
  fi
}

# ----------------------------- status / doctor -------------------------------

detect_harnesses() {
  printf '%-24s %s\n' "Harness" "Detected / integration"
  printf '%-24s %s\n' "------------------------" "------------------------------"

  if has codex; then printf '%-24s %s\n' "Codex" "installed"; else printf '%-24s %s\n' "Codex" "not detected"; fi
  if has claude; then printf '%-24s %s\n' "Claude Code" "installed"; else printf '%-24s %s\n' "Claude Code" "not detected"; fi
  if has hermes; then printf '%-24s %s\n' "Hermes" "installed"; else printf '%-24s %s\n' "Hermes" "not detected"; fi
  if has antigravity; then printf '%-24s %s\n' "Antigravity CLI" "installed"; else printf '%-24s %s\n' "Antigravity CLI" "not detected/GUI-only"; fi
  if has code; then printf '%-24s %s\n' "VS Code" "installed"; else printf '%-24s %s\n' "VS Code" "not detected"; fi
  if has opencode; then printf '%-24s %s\n' "OpenCode" "installed"; else printf '%-24s %s\n' "OpenCode" "not detected"; fi
  if has openclaw; then printf '%-24s %s\n' "OpenClaw" "installed"; else printf '%-24s %s\n' "OpenClaw" "not detected"; fi
}

status_cmd() {
  printf '\nUniversal Engineering Layer v%s\n' "$VERSION"
  printf 'Project: %s\n' "$PROJECT_ROOT"
  printf 'Profile: %s\n\n' "$PROFILE"

  [[ -f "$AGENTS_DIR/ENGINEERING.md" ]] && ok ".agents/ENGINEERING.md" || warn ".agents/ENGINEERING.md missing"
  [[ -f "$SKILLS_DIR/karpathy-guidelines/SKILL.md" ]] && ok "Karpathy baseline" || warn "Karpathy baseline missing"
  [[ -f "$SKILLS_DIR/engineering-companion/SKILL.md" ]] && ok "Engineering Companion" || warn "Engineering Companion missing"

  local n=0
  [[ -d "$SKILLS_DIR" ]] && n="$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
  printf 'Skills discovered: %s\n\n' "$n"

  detect_harnesses

  printf '\nAdapters:\n'
  [[ -f "$PROJECT_ROOT/AGENTS.md" ]] && printf '  AGENTS.md                     present\n' || printf '  AGENTS.md                     missing\n'
  [[ -f "$PROJECT_ROOT/CLAUDE.md" ]] && printf '  CLAUDE.md                     present\n' || printf '  CLAUDE.md                     missing\n'
  [[ -f "$PROJECT_ROOT/.agents/rules/universal-engineering-layer.md" ]] && printf '  Antigravity rule             present\n' || printf '  Antigravity rule             missing\n'
  [[ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]] && printf '  Copilot/VS Code instructions present\n' || printf '  Copilot/VS Code instructions missing\n'
}

check_link() {
  local link="$1" expected="$2" label="$3"
  if [[ -L "$link" ]]; then
    if [[ "$(readlink "$link")" == "$expected" ]]; then
      ok "$label"
      return 0
    fi
    fail "$label points to $(readlink "$link"), expected $expected"
    return 1
  elif [[ -e "$link" ]]; then
    warn "$label is a real path rather than the managed symlink"
    return 0
  else
    warn "$label missing"
    return 1
  fi
}

doctor_cmd() {
  local problems=0
  printf '\nUniversal Engineering Layer doctor\n'
  printf 'Project: %s\n\n' "$PROJECT_ROOT"

  need python3
  need git

  [[ -f "$AGENTS_DIR/ENGINEERING.md" ]] && ok "Engineering policy present" || { fail "Engineering policy missing"; problems=$((problems+1)); }
  [[ -f "$AGENTS_DIR/SKILLS.md" ]] && ok "Skill index present" || { fail "Skill index missing"; problems=$((problems+1)); }
  [[ -f "$PROJECT_ROOT/ENGINEERS.md" ]] && ok "ENGINEERS.md present" || { fail "ENGINEERS.md missing"; problems=$((problems+1)); }
  [[ -f "$PROJECT_ROOT/how-to.html" ]] && ok "how-to.html tutorial present" || { fail "how-to.html missing"; problems=$((problems+1)); }
  grep -Fxq "how-to.html" "$PROJECT_ROOT/.gitignore" 2>/dev/null && ok "how-to.html is gitignored" || { fail "how-to.html is not gitignored"; problems=$((problems+1)); }
  [[ -f "$SKILLS_DIR/karpathy-guidelines/SKILL.md" ]] && ok "Karpathy skill present" || { fail "Karpathy skill missing"; problems=$((problems+1)); }
  [[ -f "$SKILLS_DIR/engineering-companion/SKILL.md" ]] && ok "Engineering Companion skill present" || { fail "Engineering Companion skill missing"; problems=$((problems+1)); }
  [[ -x "$SKILLS_DIR/engineering-companion/scripts/project-state.sh" ]] && ok "Companion project-state detector executable" || { fail "Companion state detector missing/not executable"; problems=$((problems+1)); }

  local total bad=0
  total="$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  while IFS= read -r -d '' sf; do
    if ! grep -q '^description:' "$sf"; then
      warn "Skill has no top-level description: ${sf#$PROJECT_ROOT/}"
      bad=$((bad+1))
    fi
  done < <(find "$SKILLS_DIR" -type f -name SKILL.md -print0 2>/dev/null)

  if [[ "$total" -gt 0 ]]; then ok "$total SKILL.md files discovered"; else fail "No skills discovered"; problems=$((problems+1)); fi
  [[ "$bad" -eq 0 ]] || warn "$bad skill(s) may have weaker cross-harness discovery metadata."

  grep -Fq "$BEGIN_AGENT" "$PROJECT_ROOT/AGENTS.md" 2>/dev/null && ok "Codex/generic AGENTS.md adapter" || { fail "AGENTS.md managed block missing"; problems=$((problems+1)); }
  grep -Fq "$BEGIN_CLAUDE" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null && ok "Claude Code adapter" || { fail "CLAUDE.md managed block missing"; problems=$((problems+1)); }
  grep -Fq "$BEGIN_ANTIGRAVITY" "$PROJECT_ROOT/.agents/rules/universal-engineering-layer.md" 2>/dev/null && ok "Antigravity adapter" || { fail "Antigravity rule missing"; problems=$((problems+1)); }
  grep -Fq "$BEGIN_COPILOT" "$PROJECT_ROOT/.github/copilot-instructions.md" 2>/dev/null && ok "VS Code/Copilot adapter" || { fail "Copilot instructions missing"; problems=$((problems+1)); }

  check_link "$PROJECT_ROOT/.claude/skills" "../.agents/skills" "Claude skills link" || true
  check_link "$PROJECT_ROOT/.codex/skills" "../.agents/skills" "Codex skills compatibility link" || true

  if has hermes || [[ -d "${HERMES_HOME:-$HOME/.hermes}" ]]; then
    local cfg
    cfg="$(hermes_config_path)"
    if [[ -f "$cfg" ]] && grep -Fq -- "- $SKILLS_DIR" "$cfg"; then
      ok "Hermes external skill directory registered"
    else
      warn "Hermes detected but project skill directory is not registered."
      problems=$((problems+1))
    fi
  fi

  printf '\n'
  if [[ "$problems" -eq 0 ]]; then
    ok "Overall status: HEALTHY"
    return 0
  else
    warn "Overall status: $problems issue(s) need attention"
    return 1
  fi
}

# ----------------------------- companion -------------------------------------

companion_cmd() {
  local detector="$SKILLS_DIR/engineering-companion/scripts/project-state.sh"

  if [[ ! -x "$detector" ]]; then
    fail "Engineering Companion is not installed in this project."
    printf 'Run: %s install --project %q\n' "$(basename "$0")" "$PROJECT_ROOT"
    return 1
  fi

  printf '\nUniversal Engineering Companion\n'
  printf 'Project: %s\n\n' "$PROJECT_ROOT"

  "$detector" "$PROJECT_ROOT"

  printf '\n'
  dim "Tip: ask your coding harness 'what should I do next?' and point it to"
  dim ".agents/skills/engineering-companion/SKILL.md for richer intent-aware routing."
}

# ----------------------------- remove ----------------------------------------

remove_cmd() {
  info "Removing managed Universal Engineering Layer adapters..."

  remove_managed_block "$PROJECT_ROOT/AGENTS.md" "$BEGIN_AGENT" "$END_AGENT"
  remove_managed_block "$PROJECT_ROOT/CLAUDE.md" "$BEGIN_CLAUDE" "$END_CLAUDE"
  remove_managed_block "$PROJECT_ROOT/.github/copilot-instructions.md" "$BEGIN_COPILOT" "$END_COPILOT"

  rm -f "$PROJECT_ROOT/.agents/rules/universal-engineering-layer.md"

  for link in \
    "$PROJECT_ROOT/.claude/skills" \
    "$PROJECT_ROOT/.codex/skills" \
    "$PROJECT_ROOT/.opencode/skills" \
    "$PROJECT_ROOT/.openclaw/skills"
  do
    if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "../.agents/skills" ]]; then
      rm "$link"
    fi
  done

  remove_hermes_external_dir || true

  # Remove only canonical UEL content. Preserve ADRs because they may contain
  # real project decisions authored after installation.
  rm -rf "$SKILLS_DIR" "$STATE_DIR"
  rm -f "$AGENTS_DIR/ENGINEERING.md" "$AGENTS_DIR/SKILLS.md" "$PROJECT_ROOT/ENGINEERS.md"
  rm -f "$PROJECT_ROOT/how-to.html"

  if [[ -f "$PROJECT_ROOT/.gitignore" ]]; then
    python3 - "$PROJECT_ROOT/.gitignore" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").splitlines()
out = []
skip_comment = False
for line in lines:
    if line.strip() == "# Universal Engineering Layer local tutorial":
        skip_comment = True
        continue
    if skip_comment and line.strip() == "how-to.html":
        skip_comment = False
        continue
    skip_comment = False
    out.append(line)
text = "\n".join(out).rstrip()
if text:
    p.write_text(text + "\n", encoding="utf-8")
else:
    p.unlink()
PY
  fi

  ok "Managed layer removed."
  warn "CONTEXT.md and .agents/adr/ were intentionally preserved."
}

# ----------------------------- main install ----------------------------------

install_cmd() {
  need git
  need python3

  printf '\n'
  info "Universal Engineering Layer v$VERSION"
  info "Project: $PROJECT_ROOT"
  info "Profile: $PROFILE"

  if ! is_git_repo; then
    warn "Target is not currently a Git repository. Continuing anyway."
  fi

  mkdir -p "$AGENTS_DIR" "$SKILLS_DIR" "$STATE_DIR"

  install_upstream_skills
  install_engineering_companion
  write_engineering_policy
  write_engineers_guide
  write_how_to
  ensure_how_to_gitignored
  generate_skill_index
  write_context_template
  install_engineering_tools

  info "Creating harness adapters..."
  write_codex_generic_adapter
  write_claude_adapter
  write_antigravity_adapter
  write_copilot_vscode_adapter
  write_optional_symlink_adapters
  configure_hermes_external_dir || warn "Hermes adapter needs manual attention; run doctor for details."

  ok "Harness adapters installed."

  printf '\n'
  printf 'Canonical layer:\n'
  printf '  .agents/ENGINEERING.md\n'
  printf '  .agents/SKILLS.md\n'
  printf '  ENGINEERS.md\n'
  printf '  how-to.html (gitignored local tutorial)\n'
  printf '  .agents/skills/\n'
  printf '\n'
  printf 'Adapters:\n'
  printf '  Codex / generic agents : AGENTS.md\n'
  printf '  Claude Code            : CLAUDE.md + .claude/skills\n'
  printf '  Antigravity            : .agents/skills + .agents/rules\n'
  printf '  Hermes                 : skills.external_dirs when detected\n'
  printf '  VS Code / Copilot      : .github/copilot-instructions.md\n'
  printf '  Other harnesses        : AGENTS.md + compatibility skill links\n'
  printf '\n'
  ok "Installation complete."
  printf 'Run: %s doctor --project %q\n' "$(basename "$0")" "$PROJECT_ROOT"
}

case "$COMMAND" in
  install)
    install_cmd
    ;;
  update)
    install_cmd
    ;;
  status)
    status_cmd
    ;;
  doctor)
    doctor_cmd
    ;;
  companion)
    companion_cmd
    ;;
  remove)
    remove_cmd
    ;;
esac
