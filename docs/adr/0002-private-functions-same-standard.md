# ADR-002: Private functions held to the same standard as public

## Status
Accepted (2026-08-16)

## Context
Conventionally, private functions in a module are treated as implementation detail: no comment-based help, relaxed naming, multiple helpers crammed into one file. The argument is that consumers never see them.

In practice, private functions are where modules rot. They are read and modified by maintainers far more often than by consumers, and undocumented helpers become the least-understood code in the module. Agent-assisted maintenance also depends on CBH and file layout conventions to navigate the codebase.

## Decision
All baseline checks that apply to functions apply equally to public and private functions: comment-based help, one-function-per-file with filename matching, approved verbs, PascalCase, [CmdletBinding()], typed parameters, and advanced-function quality rules. Public/private scope is determined by configurable paths (default: Public/ and Private/), and only public functions participate in manifest-alignment checks.

## Consequences
- Writing a private helper costs the same as writing a public function. This is intentional: it discourages proliferating undocumented helpers and encourages inlining trivial logic.
- Modules with large existing Private/ folders will need remediation when adopting the baseline.
- PublicFunctionPaths/PrivateFunctionPaths remain configurable for non-standard layouts, but the defaults encode the convention.
