const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
  '../layout/Library/Application Support/BHT/BHTwitter.bundle/BHTSessionTransaction.js'), 'utf8');

function client(exports, withModule = true) {
  const calls = [];
  const requireModule = () => exports(calls);
  // Synthetic web-client runtime. No browser, network, cookies, or real X
  // credentials are present in these fixtures.
  requireModule.m = withModule ? { fixture: function () {
    return ['x-client-transaction-id', 'rweb_client_transaction_id_enabled'];
  } } : {};
  const chunks = [];
  chunks.push = item => item[2](requireModule);
  const window = { webpackChunk_twitter_responsive_web: chunks };
  vm.runInNewContext(source, {
    window, atob: value => Buffer.from(value, 'base64').toString('binary'),
    setTimeout: (callback, delay) => { const timer = setTimeout(callback, delay); timer.unref(); return timer; },
  });
  return { window, calls };
}

(async () => {
  const token = Buffer.from('synthetic transaction fixture').toString('base64');
  const fixture = client(calls => ({
    unrelatedExport: () => { throw new Error('not the generator'); },
    generate: async (host, path, method) => { calls.push({ host, path, method }); return token; },
  }));
  assert.equal(await fixture.window.__bhtTransactionId('/i/api/graphql/q/CreateTweet', 'POST'), token);
  assert.deepEqual(fixture.calls[0], { host: 'https://x.com', path: '/i/api/graphql/q/CreateTweet', method: 'POST' });
  assert.equal(await fixture.window.__bhtTransactionId('/i/api/graphql/other/FavoriteTweet', 'POST'), token);
  assert.equal(fixture.calls[1].path, '/i/api/graphql/other/FavoriteTweet');
  const failed = client(() => ({ generate: () => Buffer.from('e:fixture failed').toString('base64') }));
  assert.match(await failed.window.__bhtTransactionId('/test', 'POST'), /^ERR:/);
  const missing = client(() => ({}), false);
  assert.match(await missing.window.__bhtTransactionId('/test', 'POST'), /^ERR:/);
  process.stdout.write('PASS: web-client transaction discovery, method/path binding, cached generator, and failure handling\n');
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
