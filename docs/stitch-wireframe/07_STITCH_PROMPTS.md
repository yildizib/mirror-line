# Google Stitch Generation Prompts

## How to use

1. Attach `00_DESIGN.md` as the permanent design-system source.
2. Add `01_PRODUCT_RULES.md` and `04_COMPONENT_CONTRACTS.md` as persistent
   project context where supported.
3. Run the batches below in order. Keep previously generated shared components.
4. Generate Turkish first. After approval, create English variants using
   `06_COPY_TR_EN.md` without changing layout or hierarchy.
5. Do not ask Stitch to invent backend or API behavior.

## Persistent prefix for every batch

```text
Design Android portrait mobile screens for MirrorLine. Follow 00_DESIGN.md as
the single visual source and 01_PRODUCT_RULES.md as non-negotiable behavior.
Use Turkish copy from 06_COPY_TR_EN.md. Build with reusable components from
04_COMPONENT_CONTRACTS.md. Use light mode, Geist typography, Forest Signal
#27765B as the only accent, 48px minimum targets, and 14px minimum text.
Do not generate server, API, cloud console, dashboard, infrastructure, desktop,
marketing, or mandatory-update UI. Do not use purple, neon, gradients, Inter,
glassmorphism, excessive cards, tiny text, or overlapping elements.
```

## Batch 1 — Foundation and authentication

```text
Create A01–A09 from 03_SCREEN_MANIFEST.md: Launch, Welcome, Sign in, Create
account, Verify email, Change registration email, Forgot password, Reset email
sent, and Create new password. Welcome must show Sign in and Create account as
equally discoverable choices. Use label-above inputs and preserve entered data
in all error variants. Show live password requirements, terms acceptance,
email-exists recovery, verification resend cooldown, expired verification, and
offline submission states. Keep the experience calm and security-conscious,
not promotional.
```

Acceptance: all authentication screens connect visibly; verification is
required before role selection; no generic success confetti.

## Batch 2 — Role selection and Main replacement

```text
Create R01–R07. Make Main Phone and Source Phone roles understandable without
technical terminology. Then create the security-sensitive existing-Main and
replacement journey: consequences, password reauthentication, final destructive
confirmation, processing/failure states, and Main-ready state. Clearly state
that replacing Main signs out the old Main and removes all Source pairings.
Never present a second Main as an allowed option.
```

## Batch 3 — Pairing

```text
Create P01–P16. Main first checks pairing availability and displays a received
current/maximum value such as 4/5; do not imply the app calculates authority.
Cover 5/5 before pairing and quota reached during final confirmation. Main shows
QR plus short code; Source scans or enters the code manually. Both devices show
a large verification code. Include active, expiring, expired, invalid, mismatch,
rejected, timeout, failure, and success states. A Source already connected to a
Main must be blocked from scanning until it completes remove-connection warning
and reauthentication.
```

## Batch 4 — Separate permission systems

```text
Create MP01–MP02 and SP01–SP09 as two visually related but behaviorally separate
families. Main requests notification permission only and can continue after
denial. Do not create Main permission screens for camera, phone, call log, SMS,
contacts, notification listener, battery, or auto-start. Source requests each
feature group separately: calls, SMS, selected-app notification access, service
notification, optional contacts, then battery and auto-start recommendations.
Every denied Source permission disables or limits only its feature; pairing
remains active. Finish with all-active and needs-attention summaries.
```

## Batch 5 — Main Phone core

```text
Create M01–M11 and Main bottom navigation: Inbox, Devices, Settings. Inbox is a
combined chronological feed with a Source badge on every call, SMS, and app
notification. Add event-type chips and a Source bottom-sheet filter. Generate
initial skeleton, populated, empty, cached/offline, initial failure, refresh
failure with retained content, load-more, pagination retry, and end-of-list.
Create call detail, Source-scoped SMS lists and conversation, app notification
detail, Devices, Device detail, and Remove Source confirmation. Do not invent
delivery guarantees.
```

## Batch 6 — Conversation and outgoing states

```text
Refine M05–M08 using the message and pagination contracts. Older messages load
above while the visible scroll anchor stays stable. New messages show normally
at the bottom, or a New messages chip while reading history. Create distinct
Sending, Queued, Sent, Failed with Retry, and Expired states. Create stale call
action and unsupported notification-reply states as non-blocking explanations.
```

## Batch 7 — Source Phone core

```text
Create S01–S08 and Source bottom navigation: Status, Privacy, Settings. Status
shows Main connection and feature status for calls, SMS, app notifications,
service notification, and contacts. Create active, needs-attention, paused, and
disconnected states. Privacy includes sharing categories, searchable Selected
Apps, content-preview privacy, and temporary pause with clear consequences.
Use rows and dividers rather than a dashboard grid.
```

## Batch 8 — Role-specific Settings

```text
Create MS01–MS09 and SS01–SS09 as separate Settings families. Main Settings:
notification preferences, privacy/appearance, language, storage/history,
account/security, update check, diagnostics, Main replacement, sign out. Source
Settings: Main information, Android permissions, battery/auto-start, selected
apps, storage/history, language, update check, diagnostics, remove connection,
sign out. Do not leak Source-only permission controls into Main. Diagnostics is
a readable mobile status page, never a server console.
```

## Batch 9 — Optional updates and shared states

```text
Create A10–A11 and X01–X08. The update message is dismissible, non-modal, and
offers Update and Later. There is no blocking screen, countdown, or forced
upgrade. Later suppresses that exact version; manual Settings check may still
show it. Automatic check failure is silent, while manual failure is inline with
Retry. Complete snackbar, persistent banner, inline error, empty, full-page
error, confirmation, reauthentication, and skeleton variants.
```

## Batch 10 — Consistency pass

```text
Audit all generated screens against 03_SCREEN_MANIFEST.md,
05_STATE_ERROR_MATRIX.md, and 08_QA_CHECKLIST.md. Normalize component geometry,
navigation, Source badges, permission status labels, Turkish terminology, error
placement, keyboard-safe forms, touch targets, and screen titles. Remove any
server/infrastructure UI, mandatory update behavior, Source permissions on Main,
local authoritative quota behavior, unsupported reliability claims, purple or
blue accent drift, gradients, excessive cards, or text below 14px. Produce a
final linked screen map for Main and Source journeys.
```

## English localization pass

```text
Duplicate the approved Turkish screen set using English copy from
06_COPY_TR_EN.md. Preserve component hierarchy, spacing, states, and navigation.
Allow text to wrap naturally; do not reduce body text below 14px or touch targets
below 48px. Flag any missing translation instead of inventing product behavior.
```
