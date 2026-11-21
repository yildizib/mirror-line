import { screens } from '../src/screens';
import { normalizeVariant, readManifest } from './manifest';

const manifest = readManifest();
const errors: string[] = [];
const screenMap = new Map(screens.map((screen) => [screen.id, screen]));

if (manifest.length !== 90) {
  errors.push(`Expected 90 manifest IDs, found ${manifest.length}.`);
}

for (const entry of manifest) {
  const screen = screenMap.get(entry.id);
  if (!screen) {
    errors.push(`Missing screen ${entry.id}.`);
    continue;
  }
  const expected = entry.variants.map(normalizeVariant).sort();
  const actual = screen.variants.map(normalizeVariant).sort();
  if (expected.join('|') !== actual.join('|')) {
    errors.push(`${entry.id} variants differ. Expected [${expected.join(', ')}], found [${actual.join(', ')}].`);
  }
}

for (const screen of screens) {
  if (!manifest.some((entry) => entry.id === screen.id)) {
    errors.push(`Screen ${screen.id} is not present in the manifest.`);
  }
}

if (errors.length > 0) {
  console.error(errors.join('\n'));
  process.exit(1);
}

const variantCount = screens.reduce((total, screen) => total + screen.variants.length, 0);
console.log(`Validated ${screens.length} screen IDs and ${variantCount} required states.`);
