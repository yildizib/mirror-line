# MirrorLine Stitch Wireframe Package

This directory is a self-contained input package for generating the MirrorLine
mobile application in Google Stitch. It describes mobile UI and UX only. It
must not generate backend dashboards, API consoles, server diagrams, or
infrastructure screens.

## Use order

1. Add `00_DESIGN.md` to the Stitch project as the permanent design source.
2. Add `01_PRODUCT_RULES.md` and `02_USER_FLOWS.md` as product context.
3. Generate screens in the order defined by `07_STITCH_PROMPTS.md`.
4. Use `03_SCREEN_MANIFEST.md` to verify screen coverage.
5. Use `05_STATE_ERROR_MATRIX.md` to generate missing state variants.
6. Apply copy from `06_COPY_TR_EN.md`; Turkish is the default preview language.
7. Complete the review in `08_QA_CHECKLIST.md` before accepting the project.

## Package contents

- `00_DESIGN.md` — visual system and anti-patterns.
- `01_PRODUCT_RULES.md` — non-negotiable product behavior.
- `02_USER_FLOWS.md` — complete Mermaid flow definitions.
- `03_SCREEN_MANIFEST.md` — screen inventory and required variants.
- `04_COMPONENT_CONTRACTS.md` — reusable component behavior.
- `05_STATE_ERROR_MATRIX.md` — loading, empty, error, and edge states.
- `06_COPY_TR_EN.md` — approved Turkish and English UI copy.
- `07_STITCH_PROMPTS.md` — copy-ready Stitch generation batches.
- `08_QA_CHECKLIST.md` — visual and flow acceptance checklist.

The approved target manifest contains exactly 97 IDs. The seven target-only
entries (`A12`–`A14`, `R08`, `P17`, `SS10`, and `X09`) document future
server-backed security and synchronization UX; they are not implemented by the
current React wireframe in this contract-only change.

## Global boundary

The package may mention that the mobile UI receives device eligibility,
pairing, or update results. It must never invent endpoint names, wire formats,
admin interfaces, infrastructure controls, transport protocols, or server
implementation details.
