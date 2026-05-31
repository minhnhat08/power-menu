'use strict';
const https = require('https');
const crypto = require('crypto');

// GET a URL into a Buffer, following GitHub's redirects to release storage.
function fetch(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'power-menu-cli' } }, (res) => {
        const { statusCode, headers } = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          resolve(fetch(headers.location));
          return;
        }
        if (statusCode !== 200) {
          res.resume();
          reject(new Error(`Request to ${url} failed: HTTP ${statusCode}`));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      })
      .on('error', reject);
  });
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

module.exports = { fetch, sha256 };
