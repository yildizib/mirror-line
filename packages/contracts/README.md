# MirrorLine Contracts

This directory is the language-neutral home for protocol schemas, compatibility
fixtures, and generated-client inputs shared by mobile and server.

The current direct LAN protocol remains implemented and regression-tested in
`apps/mobile/lib/features/sync/base/legacy_lan` and `apps/mobile/test`. It is not
duplicated here until a schema can become the authoritative source without
changing its wire representation. Future relay contracts must be introduced by
their own OpenSpec change; this skeleton does not invent account or mailbox APIs.
