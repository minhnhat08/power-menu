'use strict';
const os = require('os');
const path = require('path');

const REPO = 'minhnhat08/power-menu';
const LABEL = 'com.minhnhat.powermenu';
const APP_NAME = 'PowerMenu.app';

function paths(home = os.homedir()) {
  const appDir = path.join(home, 'Applications');
  const appDest = path.join(appDir, APP_NAME);
  return {
    appDir,
    appDest,
    execPath: path.join(appDest, 'Contents', 'MacOS', 'PowerMenu'),
    plistPath: path.join(home, 'Library', 'LaunchAgents', `${LABEL}.plist`),
  };
}

function assetUrl(version, asset) {
  return `https://github.com/${REPO}/releases/download/v${version}/${asset}`;
}

module.exports = { REPO, LABEL, APP_NAME, paths, assetUrl };
