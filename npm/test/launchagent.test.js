'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { renderPlist } = require('../lib/launchagent');

test('renderPlist embeds the label, executable path, and RunAtLoad', () => {
  const xml = renderPlist(
    '/Users/test/Applications/PowerMenu.app/Contents/MacOS/PowerMenu'
  );
  assert.match(xml, /<string>com\.minhnhat\.powermenu<\/string>/);
  assert.match(
    xml,
    /<string>\/Users\/test\/Applications\/PowerMenu\.app\/Contents\/MacOS\/PowerMenu<\/string>/
  );
  assert.match(xml, /<key>RunAtLoad<\/key><true\/>/);
});
