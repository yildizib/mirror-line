# Architecture verification

## ADDED Requirements

### Requirement: Architecture boundaries are verified
Tests MUST prevent UI-to-infrastructure direct dependencies. Tests MUST cover fake gateway/controller behavior for settings, permissions, and installed apps. The existing test suite and debug APK build MUST pass before the change is considered complete.

#### Scenario: Architecture regression is introduced
- **WHEN** a UI file imports a concrete infrastructure service
- **THEN** the architecture verification test or static check reports the violation

#### Scenario: Architecture regression is introduced

- **WHEN** a UI file imports a concrete infrastructure service
- **THEN** the architecture verification test or static check reports the violation
