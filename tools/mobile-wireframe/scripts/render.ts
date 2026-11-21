import { chromium } from '@playwright/test';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { screens, variantKey } from '../src/screens';

const root = process.cwd();
const output = resolve(root, 'build/wireframes');
const server = spawn('npm', ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '4173', '--strictPort'], {
  cwd: root,
  stdio: 'ignore',
});

const waitForServer = async () => {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch('http://127.0.0.1:4173');
      if (response.ok) return;
    } catch {
      // The preview is still starting.
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  }
  throw new Error('Wireframe preview did not start.');
};

try {
  await waitForServer();
  rmSync(output, { recursive: true, force: true });
  mkdirSync(output, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 412, height: 915 }, locale: 'tr-TR' });
  const inventory: Array<{ id: string; group: string; variant: string; file: string }> = [];

  for (const screen of screens) {
    const directory = resolve(output, screen.group, screen.id);
    mkdirSync(directory, { recursive: true });
    for (const variant of screen.variants) {
      const file = `${variantKey(variant)}.png`;
      const url = `http://127.0.0.1:4173/#/screen/${screen.id}?variant=${encodeURIComponent(variant)}&locale=tr&capture=1`;
      await page.goto(url, { waitUntil: 'networkidle' });
      await page.locator('[data-screen-id]').waitFor();
      await page.screenshot({ path: resolve(directory, file), animations: 'disabled' });
      inventory.push({ id: screen.id, group: screen.group, variant, file: `${screen.group}/${screen.id}/${file}` });
    }
  }

  await browser.close();
  writeFileSync(resolve(output, 'inventory.json'), `${JSON.stringify(inventory, null, 2)}\n`);
  writeFileSync(
    resolve(output, 'QA_REPORT.md'),
    `# MirrorLine Wireframe Render Report\n\n- Screen IDs: ${screens.length}\n- Required states: ${inventory.length}\n- Viewport: 412 × 915\n- Locale: Turkish acceptance set\n- Generated: ${new Date().toISOString()}\n\nThis report records generated artifacts only. Functional and accessibility results are reported by the automated test suite.\n`,
  );
  console.log(`Rendered ${inventory.length} PNG files to ${output}.`);
} finally {
  server.kill('SIGTERM');
}
