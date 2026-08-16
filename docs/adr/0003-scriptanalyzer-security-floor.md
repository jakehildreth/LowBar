# ADR-003: ScriptAnalyzer security floor is non-negotiable

## Status
Accepted (2026-08-16)

## Context
Module.ScriptAnalyzer.Tests.ps1 falls back to a PSScriptAnalyzerSettings.psd1 at the module root when one exists. Without a guard, a module could ship a settings file that disables security rules — PSAvoidUsingPlainTextForPassword, PSAvoidUsingConvertToSecureStringWithPlainText, PSAvoidUsingInvokeExpression — and the baseline would silently pass insecure code.

Style and convention rules are legitimately module-specific. Security rules are not: a module that handles credentials insecurely endangers every consumer, regardless of the module author's local preferences.

## Decision
The baseline defines a security floor: a named set of ScriptAnalyzer rules that local settings files cannot disable. Local PSScriptAnalyzerSettings.psd1 files may add rules, raise severity, or relax style rules, but the suite merges settings such that floor rules remain enabled. The floor initially contains:
- PSAvoidUsingPlainTextForPassword
- PSAvoidUsingConvertToSecureStringWithPlainText
- PSAvoidUsingInvokeExpression

## Consequences
- Module authors retain control over style rules (OTBS-adjacent, whitespace, naming hints) while losing the ability to silently disable credential-safety checks.
- The settings-merge logic adds complexity to the ScriptAnalyzer test. It must detect local attempts to exclude floor rules and fail with a clear message.
- New security rules can be added to the floor as ScriptAnalyzer evolves; this is a deliberate maintenance point.
