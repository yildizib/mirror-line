import { normalizeVariant, readManifest } from './manifest';

const manifest = readManifest();
const errors: string[] = [];

if (manifest.length !== 97) {
  errors.push(`Expected 97 manifest IDs, found ${manifest.length}.`);
}

const seen = new Set<string>();
for (const entry of manifest) {
  if (seen.has(entry.id)) {
    errors.push(`Duplicate manifest ID ${entry.id}.`);
  }
  seen.add(entry.id);

  if (entry.variants.length === 0 || entry.variants.some((variant) => !normalizeVariant(variant))) {
    errors.push(`${entry.id} has no usable required variants.`);
  }
}

for (const id of ['A12', 'A13', 'A14', 'R08', 'P17', 'SS10', 'X09']) {
  if (!seen.has(id)) {
    errors.push(`Missing approved target screen ${id}.`);
  }
}

if (errors.length > 0) {
  console.error(errors.join('\n'));
  process.exit(1);
}

const variantCount = manifest.reduce((total, entry) => total + entry.variants.length, 0);
console.log(`Validated ${manifest.length} documented screen IDs and ${variantCount} required states.`);
