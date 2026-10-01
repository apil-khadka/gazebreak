import { writeFile } from 'node:fs/promises';
import { normalizeReleases, normalizeRepository } from './release-data.mjs';

const headers = { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
const releases = [];
for (let page = 1; ; page++) {
  const response = await fetch(`https://api.github.com/repos/apil-khadka/gazebreak/releases?per_page=100&page=${page}`, {
    headers, signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`GitHub release sync failed (${response.status}); use build:offline for the saved snapshot`);
  const batch = await response.json();
  if (!Array.isArray(batch)) throw new Error('Invalid GitHub release response');
  releases.push(...batch);
  if (batch.length < 100) break;
}
const repoResponse = await fetch('https://api.github.com/repos/apil-khadka/gazebreak', {
  headers, signal: AbortSignal.timeout(20000),
});
if (!repoResponse.ok) throw new Error(`Repository metadata sync failed (${repoResponse.status})`);
const data = {
  updatedAt: new Date().toISOString(),
  repository: normalizeRepository(await repoResponse.json()),
  releases: normalizeReleases(releases),
};
await writeFile(new URL('../public/releases.json', import.meta.url), `${JSON.stringify(data, null, 2)}\n`);
console.log(`Synced ${data.releases.length} published releases`);
