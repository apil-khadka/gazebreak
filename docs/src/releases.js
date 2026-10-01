import { marked } from 'marked';
import DOMPurify from 'dompurify';

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

export function renderReleases(container, data) {
  container.replaceChildren();
  const newestStable = data.releases.find(item => !item.prerelease)?.tag;
  for (const release of data.releases) {
    const card = element('article', 'release-card');
    card.id = release.tag;
    const header = element('div', 'release-heading');
    header.append(element('span', `badge ${release.prerelease ? 'badge-preview' : ''}`, release.prerelease ? 'Experimental preview' : release.tag === newestStable ? 'Latest release' : 'Release'));
    const date = element('time', '', new Date(release.publishedAt).toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' }));
    date.dateTime = release.publishedAt;
    header.append(date);
    card.append(header, element('h2', '', release.name));
    if (release.prerelease) card.append(element('p', 'release-warning', 'Development build. Ad-hoc signed, not notarized by Apple. Use for testing.'));
    if (release.tag === 'v0.1.0') card.append(element('p', 'release-warning', 'Legacy Apple Silicon build. Ad-hoc signed and not notarized by Apple.'));
    const notes = element('div', 'release-notes');
    notes.innerHTML = DOMPurify.sanitize(marked.parse(release.notes.replace(/[—–]/g, ', ').replace(/\s--\s/g, ', ')), {
      ALLOWED_TAGS: ['p', 'h1', 'h2', 'h3', 'h4', 'ul', 'ol', 'li', 'strong', 'em', 'code', 'pre', 'blockquote', 'a', 'br', 'hr'],
      ALLOWED_ATTR: ['href', 'title'],
    });
    for (const heading of notes.querySelectorAll('h1, h2, h3, h4')) {
      if (heading.tagName === 'H1' && heading.textContent.trim() === release.name) {
        heading.remove();
        continue;
      }
      const nested = element(`h${Math.min(6, Math.max(3, Number(heading.tagName[1]) + 1))}`);
      nested.append(...heading.childNodes);
      heading.replaceWith(nested);
    }
    // No remote images or executable HTML from release descriptions.
    card.append(notes);
    const actions = element('div', 'release-actions');
    const link = element('a', 'text-link', 'Full release on GitHub ↗');
    link.href = release.url;
    actions.append(link);
    for (const asset of release.assets) {
      const download = element('a', 'asset-link', asset.name.endsWith('.sha256') ? 'SHA-256 checksum' : `Download ${asset.name}`);
      download.href = asset.url;
      actions.append(download);
    }
    card.append(actions);
    container.append(card);
  }
  if (!data.releases.length) container.append(element('p', '', 'No public releases yet.'));
  const updated = document.querySelector('[data-release-updated]');
  if (updated) updated.textContent = `Release information refreshed ${new Date(data.updatedAt).toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' })}.`;
}
