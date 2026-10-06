export const validDomain = domain => typeof domain === 'string' && domain.length <= 253 &&
  /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(domain);

export function effectiveRules(policy, now = Date.now() / 1000) {
  if (policy?.schemaVersion !== 1 || !Number.isFinite(policy.generatedAt) || !Number.isFinite(policy.heartbeatExpiresAt) ||
      policy.generatedAt > now + 5 || policy.heartbeatExpiresAt <= now || policy.heartbeatExpiresAt > policy.generatedAt + 30 || !Array.isArray(policy.rules)) return [];
  return policy.rules.filter(rule => validDomain(rule.domain) && Number.isFinite(rule.expiresAt) && rule.expiresAt > now);
}

export function matchingRule(url, rules) {
  try {
    const parsed = new URL(url);
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    const host = parsed.hostname.toLowerCase().replace(/\.$/, '');
    return rules.filter(rule => host === rule.domain || host.endsWith('.' + rule.domain))
      .sort((a, b) => b.expiresAt - a.expiresAt)[0] ?? null;
  } catch { return null; }
}

export function networkRules(rules, extensionURL) {
  const domains = [...new Set(rules.map(rule => rule.domain))].sort();
  if (!domains.length) return [];
  return [
    { id: 1, priority: 2, action: { type: 'redirect', redirect: { regexSubstitution: extensionURL + 'blocked.html#redirect=\\0' } },
      condition: { requestDomains: domains, regexFilter: '^https?://.*', resourceTypes: ['main_frame'] } },
    { id: 2, priority: 1, action: { type: 'block' },
      condition: { requestDomains: domains, excludedResourceTypes: ['main_frame'] } },
  ];
}

export function originalURL(hash) {
  try {
    const raw = hash.startsWith('#url=') ? decodeURIComponent(hash.slice(5)) : hash.startsWith('#redirect=') ? hash.slice(10) : '';
    const url = new URL(raw);
    // Block pages are publicly navigable: never turn their return button into a script launcher.
    return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

const siteNames = { 'mail.google.com':'Gmail', 'gmail.com':'Gmail', 'linkedin.com':'LinkedIn', 'slack.com':'Slack' };
export const siteName = domain => siteNames[domain] || domain;

export function siteGroups(rules) {
  const groups = new Map();
  for (const rule of rules) {
    const name = siteName(rule.domain);
    const key = name + ':' + rule.expiresAt;
    if (!groups.has(key)) groups.set(key, { name, expiresAt:rule.expiresAt });
  }
  return [...groups.values()].sort((a,b) => a.name.localeCompare(b.name));
}
export function connectionMessage(error) {
  if (/forbidden|not allowed|permission/i.test(error || '')) return 'Turn on the Ortus extension for this browser profile, then reconnect.';
  return 'Open Ortus, go to Settings → Website blocking, then reconnect.';
}
