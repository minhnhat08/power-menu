'use strict';
const https = require('https');
const crypto = require('crypto');

// GET a URL into a Buffer, following GitHub's redirects to release storage.
function fetch(url, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    if (redirectsLeft === 0) {
      reject(new Error(`Too many redirects for ${url}`));
      return;
    }
    https
      .get(url, { headers: { 'User-Agent': 'power-menu-cli' } }, (res) => {
        const { statusCode, headers } = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          resolve(fetch(headers.location, redirectsLeft - 1));
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
