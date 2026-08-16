# ADR-001: Baseline suite is hygiene-only, not behavioral

## Status
Accepted (2026-08-16)

## Context
The standard module test suite could attempt to validate function behavior — calling functions and asserting on output — or restrict itself to hygiene: structure, documentation, conventions, formatting, and static analysis.

Behavioral testing in a shared baseline would require knowing each module's dependencies, test doubles, and environment. That knowledge lives with the module, not the shared suite.

## Decision
The baseline suite checks hygiene only. It verifies that each public function HAS a test file with at least one It block, but never inspects or runs those tests' assertions. Behavioral correctness is the module's own responsibility, executed via the module's own Tests/ folder.

## Consequences
- The baseline runs fast and works against any module without setup.
- A module can pass the baseline with zero meaningful behavioral coverage. This is accepted: the existence check prevents "forgot to write tests," and quality is enforced by code review, not the baseline.
- A separate publish-readiness suite may later add stronger requirements for Gallery-bound modules.
