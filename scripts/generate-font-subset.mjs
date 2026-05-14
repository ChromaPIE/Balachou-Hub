import { readFile, writeFile, unlink } from 'node:fs/promises';
import subset from 'subset-font';

const GITHUB_TREE_API = 'https://api.github.com/repos/ChromaPIE/Balachou/git/trees/main?recursive=1';
const SOURCE_FONT = 'assets/SarasaMonoSlabSC-Regular.ttf';
const OUTPUT_FONT = 'assets/SarasaMonoSlabSC-Regular.woff2';
const RAW_BASE = 'https://raw.githubusercontent.com/ChromaPIE/Balachou/main';

const ASCII_RANGES = [
  [0x0020, 0x007E],
  [0x00A0, 0x00FF],
  [0x2000, 0x206F],
];

async function fetchTree() {
  const resp = await fetch(GITHUB_TREE_API, {
    headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!resp.ok) throw new Error(`tree fetch failed: HTTP ${resp.status}`);
  const data = await resp.json();
  return data.tree
    .filter(item => item.type === 'blob')
    .map(item => item.path);
}

async function collectTextFromFiles(filePaths) {
  const luaFiles = filePaths.filter(p => p.endsWith('.lua'));
  const allText = [];
  for (const p of luaFiles) {
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

const filePaths = await fetchTree();
const content = await collectTextFromFiles(filePaths);
const charString = collectUniqueChars(content);
console.log(`Collected ${charString.length} unique characters from ${content.length.toLocaleString()} chars of text`);

const sourceBuffer = await readFile(SOURCE_FONT);
const subsetBuffer = await subset(sourceBuffer, charString, { targetFormat: 'woff2' });
await writeFile(OUTPUT_FONT, subsetBuffer);
await unlink(SOURCE_FONT);
console.log(`Generated font subset: ${(subsetBuffer.length / 1024).toFixed(1)} KB`);
