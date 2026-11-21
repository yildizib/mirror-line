# MirrorLine Stitch QA Checklist

Mark every item before accepting the Stitch project.

## Package and visual system

- [ ] `00_DESIGN.md` is applied as the single visual source.
- [ ] Light mode uses Mineral Canvas, white surfaces, Charcoal Ink, and only
      Forest Signal as the accent.
- [ ] No purple/blue-neon drift, gradients, glows, glassmorphism, or pure black.
- [ ] Geist is used throughout; code and verification values use Geist Mono.
- [ ] Body and metadata text is at least 14 px.
- [ ] Every interaction target is at least 48 × 48 px.
- [ ] Dense lists use dividers/space rather than one card per row.
- [ ] No overlapping content or keyboard-covered primary actions.

## Authentication

- [ ] Signed-out Welcome shows both Sign in and Create account.
- [ ] Sign in and Create account link to each other.
- [ ] Forgot password is discoverable from Sign in.
- [ ] Registration includes email, password, confirmation, and terms/privacy.
- [ ] Password requirements update live and use text plus icons.
- [ ] Invalid fields display errors in place without clearing valid values.
- [ ] Email-already-used offers Sign in and Forgot password.
- [ ] Verification supports check again, resend, cooldown, and change email.
- [ ] Role selection is unavailable until email verification completes.
- [ ] Turkish and English auth copy has been checked for overflow.

## Roles and security

- [ ] Role selection clearly distinguishes Main and Source.
- [ ] UI never presents two active Main Phones as permitted.
- [ ] Existing-Main detection offers keep current or replace.
- [ ] Replacement explains old-session and all-pairings invalidation.
- [ ] Main replacement requires reauthentication and final confirmation.
- [ ] Source connected to a Main cannot begin a second pairing directly.
- [ ] Source removal requires warning and reauthentication.

## Pairing and device limit

- [ ] Devices shows a received current/maximum value without treating local
      counting as authoritative.
- [ ] Eligibility unavailable blocks only new pairing, not existing app use.
- [ ] Both 5/5-before-start and limit-during-completion states exist.
- [ ] Main pairing screen includes QR, short code, expiry, refresh, and cancel.
- [ ] Source includes scanner and manual-code fallback.
- [ ] Camera denial and permanently denied states have appropriate recovery.
- [ ] Human-verifiable code appears on both roles.
- [ ] Invalid, expired, mismatch, rejected, timeout, failure, and success states
      exist.

## Permissions

- [ ] Main requests notification permission only.
- [ ] Main denial does not block setup or app use.
- [ ] No Main camera, phone, call-log, SMS, contacts, notification-listener,
      battery, or auto-start permission screens exist.
- [ ] Source call, SMS, app notification, service notification, and contacts are
      separate steps.
- [ ] Source battery and auto-start are described as device recommendations.
- [ ] Source denial disables/limits only the affected feature.
- [ ] Pairing remains active after Source permission denial.
- [ ] Source Status includes Active, Limited, Disabled, Needs attention, and
      Unavailable labels with icons.

## Navigation and role separation

- [ ] Main navigation contains Inbox, Devices, Settings.
- [ ] Source navigation contains Status, Privacy, Settings.
- [ ] Main Settings and Source Settings are separate screen families.
- [ ] Source-only controls do not appear in Main Settings.
- [ ] Main replacement does not appear as a normal add-device action.
- [ ] Sign-out messaging is role specific.

## Inbox, event details, and pagination

- [ ] Every Main event row displays a Source badge.
- [ ] Inbox filters by event type and Source.
- [ ] Initial loading uses geometry-matched skeletons.
- [ ] Empty, cached/offline, no-cache failure, refresh failure, load-more,
      pagination retry, and end-of-list states exist.
- [ ] Refresh and pagination failure preserve loaded content.
- [ ] SMS conversations remain Source-scoped.
- [ ] Loading older messages preserves the scroll anchor.
- [ ] New messages do not force-scroll while reading history.
- [ ] Sending, Queued, Sent, Failed, and Expired are visually distinct.
- [ ] Stale call actions and unsupported app replies are explained without
      blocking navigation.

## Updates and feedback

- [ ] No mandatory update screen, countdown, lockout, or force-update copy.
- [ ] Available update provides Update and Later.
- [ ] Later suppresses the exact version and does not block use.
- [ ] Automatic update-check failure is silent.
- [ ] Manual update-check failure is inline and retryable.
- [ ] Existing content remains visible for recoverable failures.
- [ ] Destructive actions use explicit consequences and confirmation.
- [ ] Security-sensitive changes use reauthentication.

## Accessibility and localization

- [ ] Status is never communicated by color alone.
- [ ] Text and essential icons meet WCAG AA contrast.
- [ ] Screen-reader labels exist for icons, password visibility, QR alternatives,
      verification status, loading, errors, and snackbars.
- [ ] Focus order matches visual order.
- [ ] All flows remain usable at 200% text scale.
- [ ] Turkish is complete and uses Ana Telefon / Kaynak Telefon consistently.
- [ ] English is complete and uses Main Phone / Source Phone consistently.
- [ ] Long Turkish text does not clip buttons, dialogs, rows, or navigation.
- [ ] Reduced-motion mode retains meaning without movement.

## Scope and honesty

- [ ] No backend, API, database, relay, server dashboard, monitoring console, or
      infrastructure screen exists.
- [ ] No fake delivery guarantee, reliability percentage, zero-latency claim,
      or “serverless/zero cloud” marketing claim appears.
- [ ] Unavailable Android capabilities are stated honestly and do not enter a
      retry loop.
- [ ] No unsupported remote action is implied by decorative UI.
