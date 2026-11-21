# MirrorLine Mobile Product Rules

These rules are non-negotiable across every generated screen and variant.

## Scope boundary

- Generate Android mobile UI only.
- Do not generate backend, API, server, relay, database, monitoring, admin, or
  infrastructure interfaces.
- Mobile screens may display a received eligibility, quota, pairing, sync, or
  update result without describing how it was produced.

## Account and authentication

- A signed-out user first sees both **Sign in** and **Create account**.
- Account creation uses email, password, password confirmation, and acceptance
  of terms and privacy information.
- Email verification must complete before role selection.
- Sign in, create account, resend verification, change email, forgot password,
  and reset password form one connected journey.
- Submission errors preserve valid field values.
- Password requirements are shown live and in plain language.

## Device roles and limits

- A user chooses Main Phone or Source Phone after authentication.
- An account may have exactly one active Main Phone.
- A Main Phone may have up to five Source Phones.
- The mobile app does not own or calculate the authoritative device limit. It
  displays the latest received current/maximum values and result states.
- If eligibility cannot be checked, new pairing cannot start, but existing app
  functions remain available.
- One Source Phone may be connected to only one Main Phone.
- A paired Source cannot scan a new Main pairing code until the current
  connection is explicitly removed.

## Main Phone replacement

- Activating a different Main Phone is a security-sensitive replacement, not a
  normal add-device action.
- The user sees consequences, reauthenticates, and confirms once more.
- Replacement invalidates the old Main session and all Source pairings.
- Every Source must then be paired again.
- Never imply that encryption keys or Source relationships silently transfer.

## Pairing

- Main initiates Add Source after eligibility is checked.
- Main displays a QR code and short fallback code; Source scans it.
- Both devices show a human-verifiable code before final confirmation.
- Pairing screens cover expired code, invalid code, mismatch, rejection,
  failure, quota reached before start, and quota reached during completion.
- Pairing success leads Source to its role-specific permission setup.

## Permissions

### Main Phone

- Request notification permission only.
- Denial does not block setup or app use.
- Do not request camera, phone state, call log, SMS, contacts, notification
  listener, battery exemption, or auto-start access on Main.

### Source Phone

- Explain and request each feature group separately: call monitoring, SMS read
  and reply, selected-app notification access, foreground-service notification,
  and optional contacts.
- Battery optimization and manufacturer auto-start are recommended device
  settings, not ordinary runtime permissions.
- Denial never cancels pairing. The affected feature becomes Disabled or
  Limited, and Source Home shows Needs attention with a recovery action.
- If an Android or distribution policy makes a capability unavailable, state
  that honestly and disable only that capability.

## Navigation

- Main Phone: Inbox, Devices, Settings.
- Source Phone: Status, Privacy, Settings.
- Every mirrored event on Main includes a Source label.
- Main can filter the combined feed by event type and Source.

## Updates

- Update checks never block startup or app use.
- An available update uses a dismissible message with **Update** and
  **Later**.
- Choosing Later suppresses that exact version permanently on that device.
- A newer version may be suggested again.
- Automatic check failure is silent; manual check failure is inline and
  retryable.
- Never generate a mandatory-update screen or countdown.

## Pagination and retained content

- Inbox uses bottom pagination; conversations load older items at the top.
- Refresh or load-more failure retains already visible content.
- Conversation pagination preserves the scroll anchor.
- New messages do not force-scroll a user who is reading older content.

## Feedback hierarchy

- Snackbar: short non-blocking confirmation.
- Inline message: field, row, pagination, or manual-check failure.
- Banner: persistent but non-blocking attention state.
- Full-page error: only when no useful content can be shown.
- Dialog plus reauthentication: destructive or security-sensitive action.

## Language

- Turkish is the default wireframe language.
- English copy must exist for every user-facing string.
- Use “Ana Telefon” and “Kaynak Telefon” consistently in Turkish.
- Use “Main Phone” and “Source Phone” consistently in English.
