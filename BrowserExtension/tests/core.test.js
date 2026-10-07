import { test } from 'node:test';
import assert from 'node:assert/strict';
import { effectiveRules, matchingRule, networkRules, originalURL, validDomain, siteGroups, connectionMessage } from '../core.js';
import { glyph } from '../glyphs.js';

const policy = { schemaVersion: 1, generatedAt: 100, heartbeatExpiresAt: 120, rules: [{ domain: 'linkedin.com', expiresAt: 150 }] };
test('rules expire on either the session deadline or the app heartbeat', () => {
  assert.equal(effectiveRules(policy, 119).length, 1);
  assert.equal(effectiveRules(policy, 120).length, 0);
  assert.equal(effectiveRules({ ...policy, heartbeatExpiresAt: 180 }, 110).length, 0);
  assert.equal(effectiveRules({ ...policy, rules: [{ domain: 'linkedin.com', expiresAt: 105 }] }, 106).length, 0);
  for (const bad of [null, {}, { ...policy, schemaVersion: 2 }, { ...policy, generatedAt: Infinity }, { ...policy, rules: [{}] }]) {
    assert.deepEqual(effectiveRules(bad, 110), []);
  }
});
test('host boundaries block subdomains without blocking lookalike or unrelated sites', () => {
  const rules = effectiveRules(policy, 110);
  for (const url of ['https://linkedin.com/feed', 'https://www.linkedin.com/feed', 'https://uk.linkedin.com/']) assert.ok(matchingRule(url, rules));
  for (const url of ['https://notlinkedin.com/', 'https://linkedin.com.evil.test/', 'https://google.com/', 'file:///linkedin.com', 'garbage']) assert.equal(matchingRule(url, rules), null);
  assert.equal(matchingRule('https://docs.google.com', [{domain:'mail.google.com',expiresAt:150}]), null);
});
test('network rules redirect pages and block background requests with deduplicated domains', () => {
  const rules = networkRules([...policy.rules, ...policy.rules], 'chrome-extension://example/');
  assert.equal(rules.length, 2);
  assert.deepEqual(rules[0].condition.requestDomains, ['linkedin.com']);
  assert.deepEqual(rules[0].condition.resourceTypes, ['main_frame']);
  assert.equal(rules[0].action.redirect.regexSubstitution, 'chrome-extension://example/blocked.html#redirect=\\0');
  assert.equal(rules[1].action.type, 'block');
  assert.deepEqual(networkRules([], 'chrome-extension://example/'), []);
});
test('blocked page return URLs cannot execute scripts or navigate to privileged protocols', () => {
  const url = 'https://mail.google.com/mail/u/0/#inbox';
  assert.equal(originalURL('#url=' + encodeURIComponent(url)), url);
  assert.equal(originalURL('#redirect=' + url), url);
  for (const input of ['#url=javascript%3Aalert(1)', '#redirect=file:///etc/passwd', '#redirect=https://user:password@example.com', '#url=%invalid']) assert.equal(originalURL(input), null);
});
test('domain validator rejects rule injection and malformed names', () => {
  for (const input of ['*.com', '-a.com', 'a..com', 'foo.com/path', 'google.com|.*', null, 'foo.com\n']) assert.equal(validDomain(input), false);
  assert.equal(validDomain('xn--bcher-kva.de'), true);
});

test('site summaries group service aliases while preserving different deadlines', () => {
  assert.deepEqual(siteGroups([{domain:'gmail.com',expiresAt:120},{domain:'mail.google.com',expiresAt:120}]), [{name:'Gmail',expiresAt:120}]);
  assert.equal(siteGroups([{domain:'gmail.com',expiresAt:120},{domain:'mail.google.com',expiresAt:150}]).length,2);
});
test('transport errors become actionable recovery instructions', () => {
  const message = connectionMessage('Specified native messaging host not found.');
  assert.ok(message.includes('Website blocking'));
  assert.ok(!message.includes('native messaging'));
  assert.ok(connectionMessage('Access forbidden').includes('profile'));
});

test('custom website glyphs recognize services, subdomains and aliases without lookalike matches', () => {
  for (const [name, domain] of [['YouTube','youtube.com'], ['Twitch','twitch.tv'], ['Netflix','netflix.com'],
    ['Spotify','spotify.com'], ['Discord','discord.com'], ['Telegram','telegram.org']]) {
    assert.ok(glyph(name).startsWith('<svg'));
    assert.equal(glyph('www.' + domain), glyph(name));
    assert.equal(glyph(domain.toUpperCase() + '.'), glyph(name));
    assert.equal(glyph('not' + domain), '');
    assert.equal(glyph(domain + '.example.com'), '');
  }
  assert.equal(glyph('youtu.be'), glyph('YouTube'));
  assert.equal(glyph('discord.gg'), glyph('Discord'));
  assert.equal(glyph('t.me'), glyph('Telegram'));
  for (const unknown of ['example.com', 'constructor', '__proto__', null]) assert.equal(glyph(unknown), '');
});
