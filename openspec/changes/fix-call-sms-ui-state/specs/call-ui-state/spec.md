## Purpose

Ensures call screens consistently reflect the latest persisted call state and
offer call actions only while the corresponding call is active.

## ADDED Requirements

### Requirement: Call views converge on terminal status
The system SHALL replace a displayed ringing state with the latest terminal
state for the same call across all call views.

#### Scenario: Incoming call becomes missed
- **WHEN** an incoming call previously shown as ringing is reported as missed
- **THEN** every call view displays the call as missed without requiring the user to reopen the view

#### Scenario: Refreshed call retains one current state
- **WHEN** refreshed call data contains a newer state for an already displayed call identifier
- **THEN** the system displays one current call record and does not retain the older state

### Requirement: Reject action follows active call state
The system SHALL expose the Reject action only for a call that is currently
ringing.

#### Scenario: Missed call has no Reject action
- **WHEN** a ringing call transitions to missed
- **THEN** the Reject action is removed from that call presentation

#### Scenario: Ringing call remains rejectable
- **WHEN** a call is currently ringing
- **THEN** the call presentation offers the Reject action for that active call
