# MirrorLine Mobile Wireframe Prototype

Deterministic, documentation-driven mobile wireframes for the MirrorLine Android
experience. The prototype is intentionally isolated from the production Flutter
application and does not call application services or remote endpoints.

## Commands

```bash
npm install
PLAYWRIGHT_BROWSERS_PATH=.playwright-browsers npx playwright install chromium
npm run dev
npm run validate
npm test
npm run artifact
```

The gallery opens at `http://localhost:5173/#/gallery?locale=tr`. Every screen
has a stable route:

```text
/#/screen/A03?variant=offline&locale=tr
```

`npm run artifact` generates `build/mirrorline-mobile-wireframes.zip`. Generated
screenshots and reports remain outside version control.

## Sources of truth

The prototype follows the approved documents under `docs/stitch-wireframe/`.
`03_SCREEN_MANIFEST.md` is parsed during validation and must match the runtime
registry exactly.
