# MirrorLine Screen Manifest

Each ID represents a distinct screen or a required state variant. Generate
Turkish first, then verify English expansion. Unless specified, screens use the
global design system and Android portrait dimensions.

## A. Account and authentication

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| A01 | Launch | Branded but restrained startup while local session is read | default, slow startup |
| A02 | Welcome | Product name, concise purpose, Sign in, Create account | default |
| A03 | Sign in | Email, password, visibility toggle, forgot password, submit, create-account link | default, submitting, wrong credentials, offline |
| A04 | Create account | Email, password, confirmation, live requirements, terms/privacy acceptance | default, validation errors, submitting, email exists, offline |
| A05 | Verify email | Destination email, check-again, resend, change email, sign out | pending, cooldown, expired, verified, resend failed |
| A06 | Change registration email | New email and confirmation action | default, invalid, already used, submitting |
| A07 | Forgot password | Email and send-reset action | default, invalid, submitting, accepted, failed |
| A08 | Reset email sent | Neutral confirmation without revealing account existence | default |
| A09 | Create new password | New password, confirmation, requirements | default, invalid, expired link, success |
| A10 | Update banner | Non-blocking message over current destination | visible, dismissed |
| A11 | Update detail | Installed/latest version, Update and Later | available, check failed, current |

## B. Role selection and Main security

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| R01 | Choose role | Main and Source choices with plain-language descriptions | default |
| R02 | Confirm role | Explain what the selected phone will do | Main, Source |
| R03 | Existing Main detected | State that only one Main is permitted | default |
| R04 | Replace Main consequences | Old session and Source pairings will be invalidated | default |
| R05 | Reauthenticate | Password confirmation for replacement | default, failed, submitting |
| R06 | Final replacement confirmation | Destructive final choice with explicit consequences | default, processing, failed |
| R07 | Main ready | Main is active; guide toward adding Sources | zero Sources, returning Main |

## C. Pairing

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| P01 | Source list | Received current/maximum count and Add Source | 0, 1–4, 5 of 5, unavailable |
| P02 | Pairing eligibility | Skeleton while current eligibility is checked | checking, failed |
| P03 | Limit reached | Explain 5-of-5 state and link to device management | default |
| P04 | Pairing introduction | Explain both phones, privacy, and next steps | default |
| P05 | Main pairing code | QR, short code, expiry, cancel | active, expiring, expired, refreshing |
| P06 | Source QR scanner | Camera frame, manual-code alternative, back | default, permission denied, unavailable |
| P07 | Enter short code | Segmented code input and submit | default, invalid, expired, submitting |
| P08 | Pairing code invalid | Specific recovery and new-code action | invalid, expired |
| P09 | Verification comparison | Large human-verifiable code and Match/Does not match | Main, Source |
| P10 | Review Source | Source name, device label, final confirm | default, submitting |
| P11 | Pairing success | Source name, next action | Main, Source |
| P12 | Pairing failed | Reason, retry, cancel | generic, rejected, timed out, quota changed |
| P13 | Source already paired | Current Main and blocked scan explanation | connected, Main unavailable |
| P14 | Remove current Main warning | Consequences before Source unpairs | default |
| P15 | Unpair reauthentication | Password confirmation | default, failed, processing |
| P16 | Connection removed | Safe success and Start new pairing | default |

## D. Main Phone permissions

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| MP01 | Main permission intro | Explain that Main only needs notifications | default |
| MP02 | Notification result | Permission status and continue | granted, denied, permanently denied |

Do not generate Main screens for camera, call log, phone state, SMS, contacts,
notification listener, battery exemption, or auto-start.

## E. Source Phone permissions

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| SP01 | Permission overview | Progress list for all Source capability groups | fresh, partially complete, complete |
| SP02 | Call monitoring | Rationale and request | not requested, granted, denied, unavailable |
| SP03 | SMS access | Read/reply rationale and request | not requested, granted, denied, unavailable |
| SP04 | App notification access | Notification Listener rationale and Open Settings | off, checking, on, unavailable |
| SP05 | Service notification | Ongoing-status notification rationale | not requested, granted, denied |
| SP06 | Optional contacts | Contact-name enhancement and Skip | not requested, granted, skipped, denied |
| SP07 | Battery recommendation | Explain reliability tradeoff and Open Settings | unknown, optimized, exempt, unavailable |
| SP08 | Auto-start recommendation | Manufacturer-specific guidance | available, enabled, unavailable |
| SP09 | Permission summary | Feature-by-feature result and Finish | all active, partial, needs attention |

## F. Main Phone application

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| M01 | Inbox | Combined chronological feed with Source badge | loading, populated, empty, cached, failed |
| M02 | Inbox filters | Event-type tabs and Source selector | all, one Source, no Sources |
| M03 | Inbox pagination | Bottom loading/end/error rows | loading more, retry, end |
| M04 | Call detail | Source, identity, timing, duration, status, valid action | ringing, answered, missed, ended, stale action |
| M05 | SMS thread list | Source-scoped conversations | loading, populated, empty, failed |
| M06 | SMS conversation | Source badge, bubbles, composer, top pagination | populated, loading older, retry, new-message chip |
| M07 | Message send state | Per-message delivery feedback | sending, queued, sent, failed, expired |
| M08 | App notification detail | Source/app/time/content/privacy and optional reply | reply supported, view only, hidden content |
| M09 | Devices | Source list and current/maximum display | 0, 1–4, 5 of 5, unavailable |
| M10 | Device detail | Source name, feature status, last activity, remove | healthy, limited, inactive |
| M11 | Remove Source | Explicit confirmation | default, processing, failed |

## G. Source Phone application

| ID | Screen | Purpose and required content | Required variants |
|---|---|---|---|
| S01 | Source status | Protection summary and Main connection | active, needs attention, paused, disconnected |
| S02 | Feature status list | Calls, SMS, app notifications, service, contacts | all active, mixed, unavailable |
| S03 | Attention detail | Missing capabilities and recovery actions | one, several |
| S04 | Privacy overview | Sharing categories and current privacy choices | default, paused |
| S05 | Selected apps | Searchable application list with toggles | loading, populated, empty search, failed |
| S06 | Content privacy | Hide previews and related content options | default |
| S07 | Pause forwarding | Duration selection and consequences | select duration, active pause, resume |
| S08 | Main information | Connected Main and remove action | connected, unavailable |

## H. Main Phone settings

| ID | Screen | Required rows and actions |
|---|---|---|
| MS01 | Main Settings | Account, notification preferences, privacy/appearance, language, storage/history, updates, diagnostics, security, sign out |
| MS02 | Notification preferences | Per-event notification toggles and system permission status |
| MS03 | Privacy and appearance | Preview visibility and supported display preferences |
| MS04 | Storage and history | Local history/storage summary and clear action |
| MS05 | Account and security | Verified email, sessions, password change, Main replacement |
| MS06 | Language | Turkish and English selection |
| MS07 | Update check | Installed version, checking/current/available/failed |
| MS08 | Diagnostics | Readable mobile status and copy-report action; no server console |
| MS09 | Sign out | Explain local consequences and confirm |

## I. Source Phone settings

| ID | Screen | Required rows and actions |
|---|---|---|
| SS01 | Source Settings | Main information, permissions, battery/auto-start, selected apps, storage/history, language, updates, diagnostics, remove connection, sign out |
| SS02 | Android permissions | Feature-group status and Open Settings actions |
| SS03 | Reliability settings | Battery and auto-start status with device-specific guidance |
| SS04 | Storage and history | Local storage summary and safe clear action |
| SS05 | Language | Turkish and English selection |
| SS06 | Update check | Installed version, checking/current/available/failed |
| SS07 | Diagnostics | Source capability status and copy-report action |
| SS08 | Remove connection | Security warning and reauthentication path |
| SS09 | Sign out | Explain effect on Source operation and confirm |

## J. Shared overlays and state components

| ID | Component/screen | Required variants |
|---|---|---|
| X01 | Snackbar | success, neutral, warning with action |
| X02 | Persistent banner | offline/cached, needs attention, update available |
| X03 | Inline error row | retry, settings action, unavailable |
| X04 | Empty state | no events, no Sources, no selected apps, no search results |
| X05 | Full-page error | authentication required, content unavailable, unsupported capability |
| X06 | Confirmation dialog | normal, destructive, security-sensitive |
| X07 | Reauthentication sheet | default, submitting, failed |
| X08 | Skeleton set | form, event rows, device rows, conversation rows |
