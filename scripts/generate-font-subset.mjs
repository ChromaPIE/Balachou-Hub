import { readFile, writeFile, unlink } from 'node:fs/promises';
import subset from 'subset-font';

const REPO_TREE_PATH = 'repo-tree.json';
const SOURCE_FONT = 'assets/SarasaMonoSlabSC-Regular.ttf';
const OUTPUT_FONT = 'assets/SarasaMonoSlabSC-Regular.woff2';
const RAW_BASE = 'https://raw.githubusercontent.com/ChromaPIE/Balachou/main';

const ASCII_RANGES = [
  [0x0020, 0x007E],  // Basic Latin
  [0x00A0, 0x00FF],  // Latin-1 Supplement
  [0x2000, 0x206F],  // General Punctuation
];

async function collectTextFromFiles() {
  const manifest = JSON.parse(await readFile(REPO_TREE_PATH, 'utf8'));
  const luaFiles = manifest
    .filter(item => item.p.endsWith('.lua') && item.t === 'f');

  const allText = [];
  for (const { p } of luaFiles) {
    try {
      const url = `${RAW_BASE}/${encodeURI(p)}`;
      const resp = await fetch(url);
      if (resp.ok) allText.push(await resp.text());
    } catch {
      // skip unavailable files
    }
  }
  return allText.join('');
}

function collectUniqueChars(text) {
  const set = new Set(text);
  for (const [lo, hi] of ASCII_RANGES) {
    for (let cp = lo; cp <= hi; cp++) set.add(String.fromCodePoint(cp));
  }
  return [...set].sort().join('');
}

const sourceBuffer = await readFile(SOURCE_FONT);
const content = await collectTextFromFiles();
const charString = collectUniqueChars(content);
console.log(`Collected ${charString.length} unique characters from ${content.length.toLocaleString()} chars of text`);

const subsetBuffer = await subset(sourceBuffer, charString, { targetFormat: 'woff2' });
await writeFile(OUTPUT_FONT, subsetBuffer);
await unlink(SOURCE_FONT);
console.log(`Generated font subset: ${(subsetBuffer.length / 1024).toFixed(1)} KB`);
