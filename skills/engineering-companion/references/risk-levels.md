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
