const repository = 'apil-khadka/gazebreak';
const releasePrefix = `https://github.com/${repository}/releases/`;

export function normalizeRepository(data) {
  if (!Number.isInteger(data.stargazers_count) || data.stargazers_count < 0) {
    throw new Error('Invalid repository star count');
  }
  return { stars: data.stargazers_count, url: `https://github.com/${repository}` };
}

export function normalizeReleases(releases) {
  if (!Array.isArray(releases)) throw new Error('Expected a release list from GitHub');
  return releases.filter(release => !release.draft).map(release => {
    if (!release.html_url?.startsWith(releasePrefix)) throw new Error('Unexpected release URL');
    if (!release.tag_name || !Number.isFinite(Date.parse(release.published_at))) {
      throw new Error('Release is missing a tag or publication date');
    }
    return {
      tag: release.tag_name,
      name: release.name || release.tag_name,
      prerelease: Boolean(release.prerelease),
      publishedAt: release.published_at,
      url: release.html_url,
      notes: release.body || 'See the release on GitHub for details.',
      assets: (release.assets || []).filter(asset =>
        /\.zip(\.sha256)?$/.test(asset.name) &&
        asset.browser_download_url?.startsWith(`${releasePrefix}download/`)
      ).map(asset => ({ name: asset.name, url: asset.browser_download_url, bytes: asset.size })),
    };
  }).sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt));
}
