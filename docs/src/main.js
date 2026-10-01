import '../styles.css';

for (const button of document.querySelectorAll('[data-copy]')) {
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = 'Copied';
      button.classList.add('is-copied');
    } catch {
      button.textContent = 'Select + copy';
    }
    setTimeout(() => { button.textContent = 'Copy'; button.classList.remove('is-copied'); }, 1800);
  });
}

const starLinks = document.querySelectorAll('[data-repo-stars]');
function showStars(count) {
  if (!Number.isInteger(count) || count < 0) return;
  for (const link of starLinks) link.textContent = `${count.toLocaleString('en')} ${count === 1 ? 'star' : 'stars'}`;
}

// Show the build snapshot first. Refresh stars live without requiring a token.
fetch('https://api.github.com/repos/apil-khadka/gazebreak', { signal: AbortSignal.timeout(5000) })
  .then(response => { if (!response.ok) throw new Error('Repository unavailable'); return response.json(); })
  .then(repo => { liveStars = repo.stargazers_count; showStars(liveStars); })
  .catch(() => {}); // Keep the snapshot when offline or GitHub's API is rate-limited.
let liveStars;

const releaseList = document.querySelector('[data-release-list]');
const releaseSummary = document.querySelector('[data-release-summary]');
const latestReleases = document.querySelector('[data-latest-releases]');
try {
  const response = await fetch(`${import.meta.env.BASE_URL}releases.json`);
  if (!response.ok) throw new Error('Release snapshot unavailable');
  const data = await response.json();
  showStars(liveStars ?? data.repository?.stars);
  const stable = data.releases.find(release => !release.prerelease);
  const preview = data.releases.find(release => release.prerelease);
  if (releaseSummary) {
    releaseSummary.textContent = stable ? `Latest release: ${stable.tag}${preview ? ` / Preview: ${preview.tag}` : ''}` : 'Explore the latest releases';
  }
  if (latestReleases) {
    latestReleases.replaceChildren();
    for (const release of [stable, preview].filter(Boolean)) {
      const row = document.createElement('article');
      row.className = 'release-row';
      const info = document.createElement('div');
      const channel = document.createElement('p');
      channel.className = 'section-label';
      channel.textContent = release.prerelease ? 'Latest experimental preview' : 'Latest non-preview release';
      const heading = document.createElement('h3');
      heading.textContent = release.name;
      const date = document.createElement('p');
      date.className = 'release-date';
      date.textContent = new Date(release.publishedAt).toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' });
      info.append(channel, heading, date);
      const link = document.createElement('a');
      link.className = 'text-link';
      link.href = `releases.html#${encodeURIComponent(release.tag)}`;
      link.textContent = 'Downloads and notes →';
      row.append(info, link);
      latestReleases.append(row);
    }
    if (!data.releases.length) latestReleases.textContent = 'No public releases yet.';
  }
  if (releaseList) {
    const { renderReleases } = await import('./releases.js');
    renderReleases(releaseList, data);
  }
} catch {
  if (releaseSummary) releaseSummary.textContent = 'Release history on GitHub';
  if (releaseList) releaseList.textContent = 'Release information is temporarily unavailable. Follow the GitHub releases link below for downloads and notes.';
}
