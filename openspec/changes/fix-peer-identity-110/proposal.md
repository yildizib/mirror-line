## Why

Issue #110 reports that a previously paired device became undiscoverable after
its displayed name changed. The logs show a stale peer endpoint, a broadcaster
using the remote peer ID as the local ID, and a persisted device name rendered
as `v1:` ciphertext. Together these leave discovery rejecting valid beacons and
reconnecting to an obsolete address.

## What Changes

- Preserve a distinct, stable local self identity and never fall back to the
  remote `peer.id` when broadcasting or authenticating.
- Repair or safely invalidate malformed/double-encrypted persisted peer display
  fields without exposing ciphertext in Settings.
- Update the stored remote endpoint only from an accepted, validated beacon or
  authenticated connection; stop retrying the stale endpoint once replaced.
- Keep discovery identity checks fail-closed while allowing authenticated
  recovery when the remote identity is explicitly verified.
- Prevent connection recovery work from blocking the Settings/Home UI and add
  regression coverage for the black/empty screen symptom.

## Capabilities

### New Capabilities

- `peer-identity-recovery`: Defines stable local identity, safe peer-record
  repair, and authenticated endpoint recovery.

## Impact

Expected areas are `ConnectionFacade`, `PeerDiscoveryCoordinator`,
`PeerFacade`, `KeyStore`, `PeerDao`, `LocalStorageCrypto`, Settings UI, and
their tests. No cryptographic algorithm, pairing protocol, or database schema
change is intended.

## Non-goals

- Clearing all app data or Bluetooth pairings as a workaround.
- Replacing the existing pairing protocol.
- Removing cryptographic protection from stored keys or peer records.
