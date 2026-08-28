## ADDED Requirements

### Requirement: Recent pagination state is authoritative

The system SHALL reconcile the recent result during refresh so records absent
from that result are removed from the visible recent state.

#### Scenario: A single recent record is deleted

- **WHEN** a displayed recent call, SMS message, or notification is deleted
  and the provider refreshes
- **THEN** the deleted record is absent without restarting the app

#### Scenario: The last record in a group is deleted

- **WHEN** the last recent record in a displayed group is deleted
- **THEN** the empty group is absent after refresh

#### Scenario: One record in a multi-record group is deleted

- **WHEN** one recent record is deleted from a group containing other records
- **THEN** the group remains and contains only records returned by the fresh
  authoritative result, plus any preserved older records

### Requirement: Older pagination state is preserved

The system SHALL preserve events outside the recent window that were already
loaded through pagination.

#### Scenario: A recent record is deleted from a group with older history

- **WHEN** the recent record is deleted and the provider refreshes
- **THEN** older records already loaded for that group remain visible

#### Scenario: A recent refresh omits an older-only group

- **WHEN** a group exists only in a previously loaded older page
- **THEN** refreshing the recent window does not remove that group

### Requirement: Refresh is idempotent

The system SHALL not create duplicate records or groups when refresh is
repeated after deletion or update.

#### Scenario: Refresh runs repeatedly

- **WHEN** the same authoritative result is refreshed more than once
- **THEN** the visible list remains deduplicated and correctly sorted
