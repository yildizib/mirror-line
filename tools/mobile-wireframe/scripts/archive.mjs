import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

const buildDirectory = resolve(process.cwd(), 'build');
const archive = resolve(buildDirectory, 'mirrorline-mobile-wireframes.zip');
mkdirSync(buildDirectory, { recursive: true });
rmSync(archive, { force: true });
execFileSync('zip', ['-rq', archive, 'wireframes'], { cwd: buildDirectory, stdio: 'inherit' });
console.log(`Created ${archive}.`);
