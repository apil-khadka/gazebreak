import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeReleases, normalizeRepository } from './release-data.mjs';

const release = (tag, date, extra = {}) => ({
  tag_name: tag, published_at: date,
  html_url: `https://github.com/apil-khadka/gazebreak/releases/tag/${tag}`,
  ...extra,
});

test('drafts are excluded, publication dates sort releases, preview labels are preserved', () => {
  const result = normalizeReleases([
    release('v1', '2026-01-01T00:00:00Z'),
    release('draft', '2026-10-01T00:00:00Z', { draft: true }),
    release('self-v2', '2026-09-01T00:00:00Z', { prerelease: true }),
  ]);
  assert.deepEqual(result.map(item => [item.tag, item.prerelease]), [['self-v2', true], ['v1', false]]);
});

test('only repository ZIPs/checksums are exposed, never arbitrary asset URLs', () => {
  const result = normalizeReleases([release('v1', '2026-01-01T00:00:00Z', { assets: [
    { name: 'app.zip', browser_download_url: 'https://github.com/apil-khadka/gazebreak/releases/download/v1/app.zip', size: 100 },
    { name: 'app.zip', browser_download_url: 'javascript:alert(1)' },
    { name: 'token.txt', browser_download_url: 'https://github.com/apil-khadka/gazebreak/releases/download/v1/token.txt' },
  ] })]);
  assert.equal(result[0].assets.length, 1);
  assert.equal(result[0].assets[0].bytes, 100);
});

test('invalid API responses fail instead of publishing empty or misleading data', () => {
  assert.throws(() => normalizeReleases({ message: 'rate limited' }));
  assert.throws(() => normalizeReleases([release('v1', 'not a date')]));
  assert.throws(() => normalizeReleases([release('v1', '2026-01-01T00:00:00Z', { html_url: 'https://example.com' })]));
});

test('repository metadata keeps zero stars and rejects invalid counts', () => {
  assert.equal(normalizeRepository({ stargazers_count: 0 }).stars, 0);
  assert.equal(normalizeRepository({ stargazers_count: 125 }).stars, 125);
  for (const value of [-1, '10', null, 1.5, undefined]) {
    assert.throws(() => normalizeRepository({ stargazers_count: value }));
  }
});
