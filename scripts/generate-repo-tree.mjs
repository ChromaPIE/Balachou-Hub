import { writeFile } from 'node:fs/promises';

const GITHUB_TREE_API = 'https://api.github.com/repos/ChromaPIE/Balachou/git/trees/main?recursive=1';

const headers = {
  'Accept': 'application/vnd.github+json',
  'User-Agent': 'Balachou-Hub-Netlify-Build',
};

if (process.env.GITHUB_TOKEN) {
  headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
}

const response = await fetch(GITHUB_TREE_API, { headers });

if (!response.ok) {
  const body = await response.text();
  throw new Error(`GitHub tree fetch failed: HTTP ${response.status} ${body}`);
}

const data = await response.json();
const files = data.tree
  .filter(item => item.type === 'blob')
  .map(item => ({ p: item.path, t: 'f', s: item.size || 0 }))
  .sort((a, b) => a.p.localeCompare(b.p));

if (!files.length) {
  throw new Error('GitHub tree fetch returned no files');
}

await writeFile('repo-tree.json', `${JSON.stringify(files, null, 2)}\n`, 'utf8');
console.log(`Generated repo-tree.json with ${files.length} files`);
