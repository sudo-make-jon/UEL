# Universal Engineering Layer

A single, reusable engineering-skills layer for AI coding agents.

**Universal Engineering Layer** installs a shared set of engineering guidelines and workflow skills into a software project, then exposes them to multiple AI coding harnesses through lightweight adapters.

The goal is simple:

> Keep one canonical engineering policy and skill set in your repository, while allowing Codex, Claude Code, Antigravity, Hermes, VS Code agents, OpenCode, OpenClaw, and other compatible harnesses to work from the same engineering rules.

---

## Why this exists

Different AI coding agents use different project-instruction formats.

One may look for `AGENTS.md`, another for `CLAUDE.md`, another for `.agents/skills/`, while others use their own skill directories or configuration files.

Without a shared layer, the same project can easily end up with duplicated or contradictory instructions:

```text
.claude/skills/
.codex/skills/
.hermes/skills/
.antigravity/skills/
```

Universal Engineering Layer avoids that duplication.

It creates **one canonical source of truth**:

```text
.agents/
├── ENGINEERING.md
├── SKILLS.md
├── adr/
├── rules/
└── skills/
```

Harness-specific files then point back to that shared layer.

---

## What gets installed

The installer combines two complementary engineering approaches.

### Karpathy Guidelines

Used as the **baseline engineering behavior**.

Typical principles include:

- Understand the code before modifying it.
- Prefer small, surgical changes.
- Avoid unnecessary abstractions.
- Make important assumptions explicit.
- Preserve existing behavior unless change is required.
- Define success before substantial work.
- Verify the result.
- Never claim tests or validation were performed when they were not.

Conceptually:

```text
Karpathy Guidelines
        ↓
How the agent should behave
```

---

### Matt Pocock Skills

Used as **task-specific engineering workflows**.

Depending on the upstream repository version, these may include skills for areas such as:

- specification
- implementation
- TDD
- code review
- prototyping
- triage
- ticket creation
- repository exploration
- documentation
- requirement clarification

Conceptually:

```text
Matt Pocock Skills
        ↓
How the agent should perform a specific engineering task
```

---

## Combined model

The two layers work together:

```text
                    HUMAN REQUEST
                          │
                          ▼
               Project-specific rules
                          │
                          ▼
              Karpathy engineering baseline
                          │
                          ▼
             Relevant task-specific skill
                          │
                          ▼
                 Inspect / understand
                          │
                          ▼
                 Plan / specify
                          │
                          ▼
                    Implement
                          │
                          ▼
                  Test / review
                          │
                          ▼
                     Verify
```

The baseline tells the agent **how to behave**.

The task skill tells the agent **which workflow to use**.

---

# Supported harnesses

The installer is designed to work with multiple coding-agent environments.

| Harness / environment | Integration |
|---|---|
| OpenAI Codex | `AGENTS.md` + `.codex/skills` compatibility link |
| Claude Code | `CLAUDE.md` + `.claude/skills` |
| Google Antigravity | Native `.agents/skills/` + `.agents/rules/` |
| Hermes Agent | Registers `.agents/skills/` as an external skill directory when Hermes is detected |
| VS Code | Shared adapters plus `.github/copilot-instructions.md` |
| GitHub Copilot | `.github/copilot-instructions.md` |
| OpenCode | `.opencode/skills` compatibility link |
| OpenClaw | `.openclaw/skills` compatibility link |
| Other agents | `AGENTS.md` and canonical `.agents/` structure provide a generic fallback |

Not every AI extension or harness supports the same discovery mechanism, so compatibility can vary.

The important design principle is that **all adapters refer back to the same canonical engineering layer**.

---

# Repository structure after installation

A typical project will look like this:

```text
my-project/
│
├── AGENTS.md
├── CLAUDE.md
├── CONTEXT.md
│
├── .agents/
│   ├── ENGINEERING.md
│   ├── SKILLS.md
│   ├── adr/
│   ├── rules/
│   │   └── universal-engineering-layer.md
│   │
│   └── skills/
│       ├── karpathy-guidelines/
│       │   └── SKILL.md
│       │
│       ├── ...
│       └── [Matt Pocock skills]
│
├── .claude/
│   └── skills -> ../.agents/skills
│
├── .codex/
│   └── skills -> ../.agents/skills
│
├── .opencode/
│   └── skills -> ../.agents/skills
│
├── .openclaw/
│   └── skills -> ../.agents/skills
│
├── .github/
│   └── copilot-instructions.md
│
├── docs/
├── src/
└── tests/
```

---

# Installation

Download the script into your project:

```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPOSITORY/main/universal-engineering-layer.sh
```

Make it executable:

```bash
chmod +x universal-engineering-layer.sh
```

Install the engineering layer:

```bash
./universal-engineering-layer.sh install
```

The current directory is used as the target project.

---

## Install into another project

You can run the installer from anywhere:

```bash
./universal-engineering-layer.sh install --project ~/projects/my-project
```

---

# Commands

## Install

```bash
./universal-engineering-layer.sh install
```

Installs:

- Karpathy engineering guidelines
- Matt Pocock skills
- shared engineering policy
- skill index
- harness adapters
- optional project context template
- Hermes external skill registration when applicable

The command is designed to be **idempotent**.

Running it again updates the managed sections rather than blindly duplicating them.

---

## Update

```bash
./universal-engineering-layer.sh update
```

Refreshes the upstream engineering skills and rewrites the managed adapters.

Because the project uses one canonical skill directory, all supported harnesses see the updated layer without maintaining separate copies.

---

## Status

```bash
./universal-engineering-layer.sh status
```

Shows information such as:

```text
Universal Engineering Layer v1.0.0
Project: /home/user/projects/example

[ OK ] .agents/ENGINEERING.md
[ OK ] Karpathy baseline

Skills discovered: 12

Harness
------------------------ ------------------------------
Codex                    installed
Claude Code              installed
Hermes                    installed
Antigravity CLI           not detected/GUI-only
VS Code                   installed
OpenCode                  not detected
OpenClaw                  not detected
```

It also reports whether the expected adapters exist.

---

## Doctor

```bash
./universal-engineering-layer.sh doctor
```

Validates the installation.

Checks include:

- canonical engineering policy
- skill index
- Karpathy skill
- discovered `SKILL.md` files
- skill metadata
- Codex / generic adapter
- Claude Code adapter
- Antigravity adapter
- VS Code / Copilot adapter
- compatibility symlinks
- Hermes external-skill registration when applicable

Example:

```text
Universal Engineering Layer doctor

[ OK ] Engineering policy present
[ OK ] Skill index present
[ OK ] Karpathy skill present
[ OK ] 12 SKILL.md files discovered
[ OK ] Codex/generic AGENTS.md adapter
[ OK ] Claude Code adapter
[ OK ] Antigravity adapter
[ OK ] VS Code/Copilot adapter
[ OK ] Claude skills link
[ OK ] Codex skills compatibility link
[ OK ] Hermes external skill directory registered

[ OK ] Overall status: HEALTHY
```

---

## Remove

```bash
./universal-engineering-layer.sh remove
```

Removes only content managed by Universal Engineering Layer.

It intentionally preserves:

```text
CONTEXT.md
.agents/adr/
```

These files may contain real project knowledge or architectural decisions created after installation.

Existing custom content outside the managed blocks in files such as `AGENTS.md`, `CLAUDE.md`, and Copilot instructions is preserved.

---

# Options

## Target another project

```bash
--project PATH
```

Example:

```bash
./universal-engineering-layer.sh install --project ~/projects/notyssia
```

---

## Do not modify Hermes configuration

```bash
--no-hermes-config
```

Example:

```bash
./universal-engineering-layer.sh install --no-hermes-config
```

Useful if you prefer to configure Hermes manually.

---

## Do not create `CONTEXT.md`

```bash
--no-context
```

Example:

```bash
./universal-engineering-layer.sh install --no-context
```

---

## Force compatible symlink replacement

```bash
--force
```

Example:

```bash
./universal-engineering-layer.sh install --force
```

Use this only when you understand the existing project layout.

The script still avoids replacing unrelated real directories.

---

# Environment variables

The upstream repositories can be overridden.

## Matt Pocock skills repository

```bash
export POCOCK_REPO="https://github.com/mattpocock/skills.git"
```

---

## Karpathy guidelines repository

```bash
export KARPATHY_REPO="https://github.com/emavv/karpathy-guidelines.git"
```

Then run normally:

```bash
./universal-engineering-layer.sh update
```

This can also be useful if you maintain internal forks.

---

# Harness integration

## Codex

Codex receives repository-level instructions through:

```text
AGENTS.md
```

The managed section instructs the agent to read:

```text
.agents/ENGINEERING.md
.agents/SKILLS.md
.agents/skills/karpathy-guidelines/SKILL.md
CONTEXT.md
.agents/adr/
```

A compatibility link is also created:

```text
.codex/skills -> ../.agents/skills
```

---

## Claude Code

Claude Code receives:

```text
CLAUDE.md
```

The generated block references the canonical engineering files.

The installer also creates:

```text
.claude/skills -> ../.agents/skills
```

This keeps Claude-specific integration separate from the canonical skill source.

---

## Google Antigravity

Antigravity can use the canonical location directly:

```text
.agents/skills/
```

The installer additionally creates:

```text
.agents/rules/universal-engineering-layer.md
```

This provides an always-visible repository rule that points Antigravity back to the shared engineering policy.

---

## Hermes Agent

Hermes uses its own skills system.

When Hermes is detected, the installer attempts to register:

```text
/project/path/.agents/skills
```

as an external skill directory in:

```text
~/.hermes/config.yaml
```

Conceptually:

```yaml
skills:
  external_dirs:
    - /absolute/path/to/project/.agents/skills
```

The installer:

1. creates a backup of the Hermes configuration;
2. patches the YAML conservatively;
3. validates that the expected path appears;
4. restores the backup if validation fails.

To disable this behavior:

```bash
./universal-engineering-layer.sh install --no-hermes-config
```

---

## VS Code

VS Code itself can host many different AI coding agents, so there is no single VS Code-wide agent instruction format.

The installer therefore provides multiple compatible entry points.

For GitHub Copilot it creates:

```text
.github/copilot-instructions.md
```

If Codex, Claude Code, Hermes, or another supported harness is used from inside VS Code, that harness uses its own adapter while still reading from the same `.agents/` layer.

---

## OpenCode

A compatibility link is created:

```text
.opencode/skills -> ../.agents/skills
```

`AGENTS.md` also provides a generic repository-level entry point.

---

## OpenClaw

A compatibility link is created:

```text
.openclaw/skills -> ../.agents/skills
```

Again, the canonical copy remains under `.agents/skills/`.

---

# Canonical source of truth

The most important architectural principle of this project is:

```text
.agents/skills/
```

is the authoritative location.

Do **not** maintain independent copies such as:

```text
.claude/skills/copy
.codex/skills/copy
.hermes/skills/copy
.openclaw/skills/copy
```

Instead:

```text
                      .agents/skills/
                            │
             ┌──────────────┼──────────────┐
             │              │              │
           Codex         Claude         Hermes
             │              │              │
          OpenCode      Antigravity      OpenClaw
             │              │              │
             └──────────────┼──────────────┘
                            │
                         VS Code
```

This prevents skill drift and contradictory instructions.

---

# Instruction priority

The generated engineering policy uses the following priority order:

```text
1. Explicit human instructions
2. Project-specific requirements and safety constraints
3. Existing architecture and accepted decisions
4. Karpathy engineering guidelines
5. Task-specific engineering skills
6. General model / harness defaults
```

This means the shared layer should never override a specific instruction given by the developer or an important repository-specific constraint.

---

# Recommended engineering workflow

For substantial features:

```text
REQUEST
   │
   ▼
UNDERSTAND
   │
   ▼
INSPECT EXISTING CODE
   │
   ▼
SPECIFY / CLARIFY
   │
   ▼
PLAN
   │
   ▼
IMPLEMENT SMALL CHANGE
   │
   ▼
TEST
   │
   ▼
REVIEW DIFF
   │
   ▼
VERIFY AGAINST ORIGINAL GOAL
```

For small fixes, agents are encouraged to use the shortest version of the workflow that still gives reasonable confidence.

---

# `CONTEXT.md`

When it does not already exist, the installer creates a template:

```text
CONTEXT.md
```

It is intended to capture project-specific knowledge such as:

- purpose
- architecture
- technology stack
- constraints
- install commands
- test commands
- lint commands
- build commands
- important paths
- deployment
- information useful to coding agents

Example:

```markdown
# Project Context

## Purpose

Self-hosted project-management system for humans and AI agents.

## Technology Stack

- TypeScript
- Next.js
- PostgreSQL
- Docker Compose

## Development Commands

### Test

```bash
npm test
```

### Build

```bash
npm run build
```
```

The better `CONTEXT.md` is, the less an AI coding agent needs to guess.

---

# Architecture Decision Records

The installer creates:

```text
.agents/adr/
```

This directory is intentionally **not deleted** when removing the engineering layer.

It can contain important project decisions such as:

```text
.agents/adr/
├── 001-use-postgresql.md
├── 002-use-markdown-storage.md
└── 003-agent-authentication.md
```

Coding agents are instructed to inspect relevant ADRs before making major architectural changes.

---

# Existing files are preserved

Universal Engineering Layer uses clearly delimited managed blocks.

For example:

```markdown
<!-- BEGIN UNIVERSAL-ENGINEERING-LAYER -->

Managed instructions here.

<!-- END UNIVERSAL-ENGINEERING-LAYER -->
```

If your project already has:

```text
AGENTS.md
CLAUDE.md
.github/copilot-instructions.md
```

the installer updates only its managed section.

Your existing custom instructions outside that block remain intact.

---

# Suggested GitHub repository layout

For this repository itself:

```text
universal-engineering-layer/
│
├── README.md
├── LICENSE
├── universal-engineering-layer.sh
│
├── examples/
│   ├── AGENTS.md
│   ├── CLAUDE.md
│   └── CONTEXT.md
│
└── docs/
    ├── architecture.md
    ├── harness-compatibility.md
    └── troubleshooting.md
```

Only the shell script is required for the initial release.

---

# Quick start

The shortest possible workflow:

```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPOSITORY/main/universal-engineering-layer.sh
chmod +x universal-engineering-layer.sh
./universal-engineering-layer.sh install
./universal-engineering-layer.sh doctor
```

Then open the project using your preferred coding agent.

---

# Updating all your projects

If you keep the installer globally:

```bash
mkdir -p ~/bin
cp universal-engineering-layer.sh ~/bin/engineering-layer
chmod +x ~/bin/engineering-layer
```

Make sure `~/bin` is on your `PATH`.

Then any project becomes:

```bash
cd ~/projects/my-project

engineering-layer install
```

Later:

```bash
engineering-layer update
```

And validation becomes:

```bash
engineering-layer doctor
```

This makes it practical to maintain the same engineering discipline across many repositories.

---

# Safety

The installer is intentionally conservative.

It:

- preserves existing instruction files;
- writes only inside managed blocks where possible;
- avoids replacing existing real directories;
- uses symlinks for compatible skill adapters;
- backs up Hermes configuration before modification;
- restores Hermes configuration if its validation fails;
- preserves project ADRs during removal;
- preserves `CONTEXT.md` during removal.

As with any script that modifies project files, review it before running it on important repositories.

Version control is strongly recommended.

---

# Requirements

Minimum:

```text
bash
git
python3
```

Recommended:

```text
Git repository
Unix-like environment
```

The installer is primarily intended for Linux and other Unix-like systems.

---

# Upstream projects

This project integrates or references engineering material from:

- **Matt Pocock Skills**
  - https://github.com/mattpocock/skills

- **Karpathy Guidelines**
  - https://github.com/emavv/karpathy-guidelines

Those projects remain owned and licensed by their respective authors.

Universal Engineering Layer is an integration and orchestration layer around those upstream resources.

Before redistributing upstream content, review and comply with the licenses of all included projects.

---

# Philosophy

AI coding agents are becoming interchangeable.

A project may be worked on using:

```text
Codex today
Claude Code tomorrow
Hermes on a server
Antigravity for another task
VS Code with Copilot
OpenCode from the terminal
```

The engineering discipline of the project should not change every time the harness changes.

Universal Engineering Layer treats engineering policy as part of the repository itself:

```text
MODEL != ENGINEERING PROCESS
HARNESS != ENGINEERING PROCESS
```

Instead:

```text
PROJECT
   │
   ▼
SHARED ENGINEERING POLICY
   │
   ▼
SHARED SKILLS
   │
   ├── Codex
   ├── Claude
   ├── Hermes
   ├── Antigravity
   ├── Copilot
   ├── OpenCode
   └── other agents
```

The harness becomes an implementation detail.

---

# Contributing

Contributions are welcome.

Useful areas include:

- support for additional coding harnesses;
- better harness autodetection;
- Windows / PowerShell support;
- safer configuration adapters;
- additional `doctor` checks;
- testing across Linux distributions;
- automated integration tests;
- version pinning;
- rollback support;
- centralized multi-project management.

When adding a harness, prefer an **adapter** over duplicating the canonical skill directory.

---

# Roadmap

Possible future improvements:

- [ ] `--version`
- [ ] upstream version pinning
- [ ] lockfile for installed skill revisions
- [ ] update-diff preview
- [ ] dry-run mode
- [ ] automatic rollback
- [ ] shell completion
- [ ] centralized multi-project updater
- [ ] CI tests
- [ ] Windows PowerShell installer
- [ ] additional harness adapters
- [ ] harness-specific diagnostics
- [ ] project templates
- [ ] optional organization-wide policy layer

---

# License

Choose a license for the Universal Engineering Layer script itself before publishing the repository.

A permissive license such as MIT or Apache-2.0 may be appropriate for this kind of developer tooling.

Remember that upstream skills and guidelines remain subject to their own licenses.

---

# Disclaimer

Universal Engineering Layer is an independent integration project.

It is not an official product of OpenAI, Anthropic, Google, Nous Research, Matt Pocock, Andrej Karpathy, GitHub, or the maintainers of the supported coding harnesses.

Compatibility may change as those tools evolve.
