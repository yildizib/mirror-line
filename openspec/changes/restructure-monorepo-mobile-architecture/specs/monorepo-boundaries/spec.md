# Monorepo boundaries

## ADDED Requirements

### Requirement: Repository applications have explicit roots

The Flutter application MUST live under `apps/mobile`, and the server MUST live
under `apps/server`. Root CI and release workflows MUST execute application
commands from the owning application directory.

#### Scenario: Mobile quality gates run

- **WHEN** CI analyzes, tests, or builds the Flutter application
- **THEN** it executes from `apps/mobile`

### Requirement: Release automation preserves protected branches

Release automation MUST NOT modify or commit `pubspec.yaml` directly on
`main`. The declared application version MUST already match the requested tag.

#### Scenario: Manual release version differs

- **WHEN** a manual release requests a version not declared in the merged mobile pubspec
- **THEN** the workflow fails without committing or tagging a modified file
