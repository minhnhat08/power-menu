'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { paths, assetUrl } = require('./config');
const { fetch, sha256 } = require('./download');
const { renderPlist } = require('./launchagent');

const ZIP = 'PowerMenu.app.zip';

function assertMacOS() {
  if (process.platform !== 'darwin') {
    throw new Error('PowerMenu is macOS only.');
  }
}

function bootoutAgent(p) {
  const domain = `gui/${process.getuid()}`;
  try {
    execFileSync('/bin/launchctl', ['bootout', domain, p.plistPath], {
      stdio: 'ignore',
    });
  } catch {
    // not loaded — fine
  }
}

async function install(version) {
  assertMacOS();
  const p = paths();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'power-menu-'));
  try {
    console.log(`Downloading PowerMenu v${version}...`);
    const zip = await fetch(assetUrl(version, ZIP));
    const sumText = (await fetch(assetUrl(version, `${ZIP}.sha256`))).toString(
      'utf8'
    );
    const expected = sumText.trim().split(/\s+/)[0];
    const actual = sha256(zip);
    if (expected !== actual) {
      throw new Error(`Checksum mismatch: expected ${expected}, got ${actual}`);
    }

    const zipPath = path.join(tmp, ZIP);
    fs.writeFileSync(zipPath, zip);

    bootoutAgent(p);
    fs.rmSync(p.appDest, { recursive: true, force: true });
    fs.mkdirSync(p.appDir, { recursive: true });

    execFileSync('/usr/bin/ditto', ['-x', '-k', zipPath, tmp]);
    fs.renameSync(path.join(tmp, 'PowerMenu.app'), p.appDest);
    execFileSync('/usr/bin/xattr', [
      '-dr',
      'com.apple.quarantine',
      p.appDest,
    ]);

    fs.mkdirSync(path.dirname(p.plistPath), { recursive: true });
    fs.writeFileSync(p.plistPath, renderPlist(p.execPath));
    execFileSync('/bin/launchctl', [
      'bootstrap',
      `gui/${process.getuid()}`,
      p.plistPath,
    ]);

    execFileSync('/usr/bin/open', [p.appDest]);
    console.log(`Installed to ${p.appDest}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function uninstall() {
  assertMacOS();
  const p = paths();
  bootoutAgent(p);
  fs.rmSync(p.plistPath, { force: true });
  fs.rmSync(p.appDest, { recursive: true, force: true });
  console.log('PowerMenu removed.');
}

module.exports = { install, uninstall, assertMacOS };
