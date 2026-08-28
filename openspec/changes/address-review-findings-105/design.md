## Context

The existing security change provides a resumable migration coordinator, but
the application never invokes it during normal startup. The socket manager
receives subscriptions from an injectable listener but discards the returned
subscription. Settings screens also bypass the documented facade/controller
boundary for native operations.

## Decisions

1. Migration will run after Flutter binding initialization and before the app
   starts using the database. A secure-storage failure will be logged and will
   leave the app in a safe, retryable state rather than silently marking the
   migration complete.
2. Socket ownership will be tied to the accepted socket instance. Teardown
   will cancel the matching subscription before destroying the socket; stale
   callbacks will remain no-ops through identity checks.
3. Settings native actions will be exposed by a controller/facade consumed by
   the screen. Provider watches will select only the fields needed by each
   section.
4. Documentation will describe the implemented single-active-peer runtime
   separately from storage support for multiple peer rows.
5. CI will verify formatting and OpenSpec requirements that are deterministic;
   two-device Android QA will remain explicitly manual and documented.

## Non-goals

- No redesign of the encryption format or pairing protocol.
- No conversion of manual Android QA into an unreliable emulator-only test.
- No change to the already-implemented deleted-pagination reconciliation.

