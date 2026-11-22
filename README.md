# MirrorLine website

The bilingual project website for MirrorLine, built with [Eleventy](https://www.11ty.dev/).

## Local development

```bash
npm install
npm run dev
```

Open `http://127.0.0.1:8080/mirror-line/`. This local preview serves the same
path prefix as GitHub Pages. Re-run the command after editing source files.

## Verification

```bash
npm test
```

The command builds the site and validates both Turkish and English output,
essential links, and static assets.

## Deployment

`.github/workflows/pages.yml` builds `_site` and deploys it with GitHub Pages.
Enable **GitHub Actions** as the Pages source in the repository settings before
the first deployment.
