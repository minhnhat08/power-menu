#!/usr/bin/env node
'use strict';
const { install, uninstall } = require('../lib/install');
const { version } = require('../package.json');

async function main() {
  const cmd = process.argv[2] || 'install';
  try {
    if (cmd === 'install') {
      await install(version);
    } else if (cmd === 'uninstall') {
      uninstall();
    } else {
      console.error(
        `Unknown command: ${cmd}\nUsage: power-menu [install|uninstall]`
      );
      process.exit(1);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

main();
