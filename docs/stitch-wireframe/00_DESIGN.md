# Design System: MirrorLine Mobile

## 1. Visual Theme & Atmosphere

MirrorLine is a calm, security-conscious Android utility for managing events
from several phones without making the experience feel like a technical admin
console. The interface is compact but never cramped: **density 6/10**,
**variance 3/10**, and **motion 2/10**. Structure is predictable, legibility is
high, and important device or permission states are visible at a glance.

The visual character is restrained and dependable: pale mineral backgrounds,
crisp white working surfaces, deep charcoal text, and one forest-green accent.
Use negative space and dividers more often than nested cards. Security warnings
must be direct and sober, never alarming without cause.

This is a mobile product, not a marketing site. Do not generate hero sections,
decorative imagery, charts, desktop sidebars, or promotional feature grids.

## 2. Color Palette & Roles

- **Mineral Canvas** (`#F8FAF9`) — default application background.
- **Pure Surface** (`#FFFFFF`) — forms, sheets, dialogs, and elevated rows.
- **Charcoal Ink** (`#1C2522`) — primary text and high-emphasis icons.
- **Muted Moss** (`#66716C`) — descriptions, metadata, placeholders.
- **Whisper Border** (`#E4E9E6`) — 1 px separators and input borders.
- **Forest Signal** (`#27765B`) — the single accent; primary actions, selected
  navigation, focus rings, progress, and active status.
- **Forest Wash** (`#E5F2EC`) — selected rows and low-emphasis accent surfaces.
- **Success Ink** (`#216A45`) / **Success Wash** (`#E4F4EA`) — completed or
  healthy states. Do not use success color as a second accent.
- **Warning Ink** (`#8A5A12`) / **Warning Wash** (`#FFF1D6`) — limited service,
  missing permission, delayed item, or recoverable attention state.
- **Danger Ink** (`#A33A35`) / **Danger Wash** (`#FCE9E7`) — destructive actions,
  authentication failures, and unrecoverable errors.
- **Scrim** (`rgba(28, 37, 34, 0.48)`) — modal background only.

Never use pure black, purple, blue-neon accents, gradient fills, or glowing
shadows. Dark mode is outside this wireframe package; generate light mode only.

## 3. Typography Rules

- **Display and headings:** Geist, weight 600–700, tight tracking (`-0.02em`).
- **Body and controls:** Geist, weight 400–600, relaxed line height 1.4–1.55.
- **Codes and technical metadata:** Geist Mono, weight 500.
- **Screen title:** 24 px / 30 px, weight 650.
- **Section title:** 18 px / 24 px, weight 650.
- **Row title and button:** 16 px / 22 px, weight 550–650.
- **Body:** 15 px / 22 px, weight 400.
- **Metadata and helper text:** 14 px / 20 px, never smaller.
- **Verification code:** 28 px / 34 px, Geist Mono, weight 650, letter-spaced.

Use sentence case. Avoid all-caps labels. Keep body copy under 65 characters per
line. Never use Inter, generic serif fonts, or condensed display fonts.

## 4. Spacing, Shape, and Elevation

- Base spacing unit: 4 px.
- Screen horizontal inset: 20 px.
- Major vertical section gap: 24–32 px.
- Related control gap: 12–16 px.
- Compact row internal gap: 8 px.
- Input and button minimum height: 52 px.
- Every interactive target: at least 48 × 48 px.
- Standard corner radius: 14 px.
- Compact chip radius: 999 px pill.
- Dialog and bottom-sheet radius: 24 px on exposed corners.
- Cards: use only when grouping needs elevation; radius 18 px and a subtle
  green-tinted shadow (`0 8px 24px rgba(28, 64, 49, 0.07)`).
- Dense lists: white surface with 1 px dividers, not one card per row.

Respect Android safe areas and the on-screen keyboard. No element may overlap
another element or rely on absolute positioning.

## 5. Layout Principles

- Mobile-first single-column layouts for 360–480 px widths.
- Primary actions stay within thumb reach but never cover scrollable content.
- Forms use labels above fields; helper or error text sits below the field.
- Long forms scroll; the primary action follows the form content rather than
  floating over the keyboard.
- Lists preserve context during refresh and pagination.
- Main Phone navigation: bottom navigation with Inbox, Devices, Settings.
- Source Phone navigation: bottom navigation with Status, Privacy, Settings.
- Use a top app bar only when a screen has back navigation, contextual actions,
  or a concise title. Do not duplicate the title in the body.
- Use full-screen states only when no useful content can remain visible.
- Use bottom sheets for filters and low-risk selections; dialogs for security
  confirmation and destructive choices.

## 6. Component Stylings

### Buttons

- Primary: Forest Signal fill, white text, 52 px height, 14 px radius.
- Secondary: white or transparent surface, Forest Signal text, 1 px border.
- Destructive: Danger Ink text or fill only after explicit confirmation.
- Active feedback: scale to 0.98 and reduce opacity slightly; no glow.
- One primary action per visual region.

### Inputs

- Persistent label above input; no floating labels.
- White fill, Whisper Border, 14 px radius, 52 px minimum height.
- Forest Signal 2 px focus ring.
- Error border and one concise error line in Danger Ink.
- Preserve valid values when another field or network submission fails.

### Lists and cards

- Device, event, permission, and settings rows share a stable leading-content-
  trailing structure.
- Use a source badge on every mirrored event.
- Status is communicated by icon, label, and color together.
- Swipe actions are optional shortcuts; every action must also be discoverable.

### Loading, empty, and error states

- Use skeletons matching the target row or form shape; no generic central
  spinner for page loading.
- Button submission may use a compact inline progress indicator while retaining
  the button label context.
- Empty states include a specific explanation and one relevant next action.
- Recoverable errors appear inline and preserve existing content.

## 7. Motion & Interaction

Motion is restrained and functional:

- Standard transition: 180–240 ms with spring-like easing.
- Press feedback: transform and opacity only.
- New list rows: subtle 8 px upward fade, staggered by at most 30 ms.
- Skeleton shimmer may loop; active connection status may use a very soft pulse.
- Respect reduced-motion settings by removing movement and retaining opacity-only
  transitions.
- Never animate width, height, top, or left. Never use bouncing prompts,
  celebratory confetti, or perpetual decorative movement.

## 8. Accessibility and Localization

- Minimum touch target: 48 × 48 px.
- Text and essential icons meet WCAG AA contrast.
- Never rely on color alone for status.
- Support text scaling to 200% without clipped controls.
- Turkish is the default preview language; English is the alternate.
- Allow Turkish strings to expand by at least 35%.
- Keyboard focus order follows visual order.
- Password visibility, field errors, verification status, loading, and snackbars
  must have accessible labels and announcements.

## 9. Anti-Patterns (Banned)

- No emojis.
- No Inter or generic serif typography.
- No pure black.
- No purple, neon blue, gradients, outer glows, or glassmorphism.
- No decorative phone mockups inside the app UI.
- No overlapping content.
- No three-column equal-card layouts.
- No card around every row.
- No tiny grey text below 14 px.
- No icon-only destructive actions without a label or confirmation.
- No generic placeholder identities such as John Doe or Acme.
- No fake reliability percentages or performance claims.
- No copywriting clichés such as “seamless,” “next-gen,” or “zero latency.”
- No claims that pairing, delivery, or remote actions are guaranteed.
- No blocking mandatory-update screen.
- No server, API, cloud-console, or infrastructure UI.
