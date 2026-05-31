'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { paths, assetUrl } = require('../lib/config');

test('paths derives app and plist locations from a home dir', () => {
  const p = paths('/Users/test');
  assert.strictEqual(p.appDir, '/Users/test/Applications');
  assert.strictEqual(p.appDest, '/Users/test/Applications/PowerMenu.app');
  assert.strictEqual(
    p.execPath,
    '/Users/test/Applications/PowerMenu.app/Contents/MacOS/PowerMenu'
  );
  assert.strictEqual(
    p.plistPath,
    '/Users/test/Library/LaunchAgents/com.minhnhat.powermenu.plist'
  );
});

test('assetUrl builds a version-pinned release download URL', () => {
  assert.strictEqual(
    assetUrl('1.2.3', 'PowerMenu.app.zip'),
    'https://github.com/minhnhat08/power-menu/releases/download/v1.2.3/PowerMenu.app.zip'
  );
});
