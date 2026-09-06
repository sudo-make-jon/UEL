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

VERSION="1.0.0"

POCOCK_REPO="${POCOCK_REPO:-https://github.com/mattpocock/skills.git}"
KARPATHY_REPO="${KARPATHY_REPO:-https://github.com/emavv/karpathy-guidelines.git}"

PROJECT_ROOT="$(pwd)"
CONFIGURE_HERMES=1
CREATE_CONTEXT=1
FORCE=0
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
  remove               Remove only files/blocks managed by this script

Options:
  --project PATH        Target project; default is current directory
  --no-hermes-config    Do not modify ~/.hermes/config.yaml
  --no-context          Do not create CONTEXT.md
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
    --force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      fail "Unknown option: $1"; usage; exit 2 ;;
  esac
done

case "$COMMAND" in
  install|update|status|doctor|remove) ;;
  *) fail "Unknown command: $COMMAND"; usage; exit 2 ;;
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
    printf 'karpathy_repo=%q\n' "$KARPATHY_REPO"
    printf 'pocock_repo=%q\n' "$POCOCK_REPO"
  } > "$STATE_FILE"
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
  printf 'Project: %s\n\n' "$PROJECT_ROOT"

  [[ -f "$AGENTS_DIR/ENGINEERING.md" ]] && ok ".agents/ENGINEERING.md" || warn ".agents/ENGINEERING.md missing"
  [[ -f "$SKILLS_DIR/karpathy-guidelines/SKILL.md" ]] && ok "Karpathy baseline" || warn "Karpathy baseline missing"

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
  [[ -f "$SKILLS_DIR/karpathy-guidelines/SKILL.md" ]] && ok "Karpathy skill present" || { fail "Karpathy skill missing"; problems=$((problems+1)); }

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
  rm -f "$AGENTS_DIR/ENGINEERING.md" "$AGENTS_DIR/SKILLS.md"

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

  if ! is_git_repo; then
    warn "Target is not currently a Git repository. Continuing anyway."
  fi

  mkdir -p "$AGENTS_DIR" "$SKILLS_DIR" "$STATE_DIR"

  install_upstream_skills
  write_engineering_policy
  generate_skill_index
  write_context_template

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
  remove)
    remove_cmd
    ;;
esac
