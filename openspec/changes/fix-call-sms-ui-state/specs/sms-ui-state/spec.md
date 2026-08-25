## Purpose

Ensures SMS screens show authoritative delivery progress and open existing
conversations reliably from the first user interaction.

## ADDED Requirements

### Requirement: Outgoing SMS status converges across views
The system SHALL replace an optimistic sending state with the latest reported
status for the same outgoing SMS in every SMS view.

#### Scenario: Successfully dispatched reply becomes sent
- **WHEN** the Source reports that an outgoing reply was dispatched successfully
- **THEN** both the conversation view and thread list display that reply as sent without requiring either view to be reopened

#### Scenario: Failed reply becomes failed
- **WHEN** the Source reports that an outgoing reply failed
- **THEN** both the conversation view and thread list replace the sending state with failed

#### Scenario: Status arrives during optimistic creation
- **WHEN** an outgoing SMS status is returned while the local optimistic record is being created
- **THEN** the final displayed and persisted status matches the returned status instead of remaining sending

### Requirement: Existing SMS thread opens on first interaction
The system SHALL keep an existing SMS thread route open while its initial
messages are being loaded.

#### Scenario: User opens a populated thread
- **WHEN** the user taps an existing SMS thread once
- **THEN** the conversation remains open and displays its messages after loading completes

#### Scenario: Initial loading state is not treated as empty
- **WHEN** an SMS thread has not completed its initial message load
- **THEN** the system keeps the conversation route open instead of navigating back

#### Scenario: Confirmed empty thread closes
- **WHEN** an SMS thread completes its initial load with no remaining messages
- **THEN** the system returns to the thread list
