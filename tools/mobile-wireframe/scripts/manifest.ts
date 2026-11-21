import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface ManifestEntry {
  id: string;
  variants: string[];
}

const manifestPath = resolve(process.cwd(), '../../docs/stitch-wireframe/03_SCREEN_MANIFEST.md');

export function readManifest(): ManifestEntry[] {
  const source = readFileSync(manifestPath, 'utf8');
  return source
    .split('\n')
    .filter((line) => /^\|\s*[A-Z]+\d{2}\s*\|/.test(line))
    .map((line) => {
      const cells = line
        .split('|')
        .map((cell) => cell.trim())
        .filter(Boolean);
      const variants = cells.length >= 4
        ? cells[3].split(',').map((item) => item.trim())
        : cells[0].startsWith('X')
          ? cells[2].split(',').map((item) => item.trim())
          : ['default'];
      return { id: cells[0], variants };
    });
}

export const normalizeVariant = (value: string): string =>
  value.replace(/[–—]/g, '–').trim().toLowerCase();
