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
