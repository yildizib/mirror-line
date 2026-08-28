## Context

The current discovery callbacks use `_selfDiscoveryId ?? _peer?.id`, so a
missing local self ID causes the remote paired ID to be broadcast as if it were
local. The coordinator then rejects the resulting beacon because it expects
the same ID as the remote peer. Separately, the Settings screenshot displays a
`v1:` value for the paired name, indicating that a stored encrypted value is
being treated as display data or has been encrypted more than once. The peer
record also retains `192.168.1.113` while valid beacons arrive from
`192.168.1.101`.

## Goals

- Make local and remote identity roles explicit at every discovery and socket
  entry point.
- Recover missing local identity deterministically and persist it before any
  beacon or authenticated transport starts.
- Decode legacy storage exactly once; never show ciphertext as a device name.
- Accept endpoint changes only after identity/authentication validation, then
  persist the new address and cancel obsolete reconnect work.
- Preserve fail-closed behavior for unauthenticated identity changes.

## Decisions

1. Add a single facade-owned identity resolver that returns a valid local ID
   and name, creating and persisting them when absent. Discovery and source
   broadcasting must require this resolver; there is no remote-ID fallback.
2. Keep the paired record as remote identity. `applyPairedPeer` may update the
   remote record only after the existing pairing or authenticated transport
   proves the received ID/public key relationship.
3. Add a storage-repair path for legacy `v1:`/double-encrypted display fields.
   If a value cannot be safely decoded, retain the record for diagnostics but
   use a non-secret fallback such as `Paired device` in UI; never log key
   material.
4. Route accepted beacon/address updates through the existing facade and
   invalidate stale reconnect attempts so the old IP cannot continue winning.
5. Keep UI initialization non-blocking and expose a stable loading/disconnected
   state while identity repair and discovery run.

## Risks and Mitigations

- Repairing ambiguous legacy ciphertext could produce the wrong name. Only
  values decryptable with the current key and format are repaired; otherwise a
  safe fallback is shown and re-pairing remains available.
- Automatically accepting a changed peer ID could weaken pairing security.
  Beacon-only changes remain rejected; recovery requires the existing
  authenticated key/identity binding.
- Endpoint updates can race with reconnect callbacks. Use the existing socket
  ownership/token pattern and test replacement races.

## Compatibility

No schema migration or dependency change is expected. Existing valid peer and
self identities remain unchanged. Invalid records are repaired lazily or
marked unavailable without deleting user data.
