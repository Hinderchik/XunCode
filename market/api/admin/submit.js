// POST /api/admin/submit
//   body: { githubUrl, name, description, author, pluginId }
//
// Validates that the repo has plugin.json and main.js, then appends to
// data/pending.json. No auth required — moderation happens later via
// /api/admin/approve.

const fs = require('fs');
const path = require('path');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) body = await readBody(req).catch(() => ({}));
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const { githubUrl, name, description, author, pluginId, version, tags, permissions } = body || {};

  if (!githubUrl || typeof githubUrl !== 'string') {
    return res.status(400).json({ error: 'githubUrl required' });
  }
  if (!pluginId || typeof pluginId !== 'string') {
    return res.status(400).json({ error: 'pluginId required' });
  }

  const cleaned = cleanUrl(githubUrl);
  const match = /^https:\/\/github\.com\/([^/]+)\/([^/]+)$/.exec(cleaned);
  if (!match) return res.status(400).json({ error: 'githubUrl must be https://github.com/owner/repo' });
  const [, owner, repo] = match;

  // Verify plugin.json + main.js exist on either main or master.
  let manifestOk = false;
  let mainOk = false;
  for (const branch of ['main', 'master']) {
    try {
      const m = await httpHead(`https://raw.githubusercontent.com/${owner}/${repo}/${branch}/plugin.json`);
      if (m.ok) {
        manifestOk = true;
        const main = await httpHead(`https://raw.githubusercontent.com/${owner}/${repo}/${branch}/main.js`);
        mainOk = main.ok;
        break;
      }
    } catch (_) {}
  }

  if (!manifestOk) {
    return res.status(400).json({ error: 'plugin.json not reachable on main or master branch' });
  }
  if (!mainOk) {
    return res.status(400).json({ error: 'main.js not reachable' });
  }

  const pendingFile = path.join(process.cwd(), 'data', 'pending.json');
  let list = [];
  try {
    list = fs.existsSync(pendingFile) ? JSON.parse(fs.readFileSync(pendingFile, 'utf-8')) : [];
  } catch (_) { list = []; }

  list = list.filter(it => it.id !== pluginId);
  list.push({
    id: pluginId,
    name: name || pluginId,
    version: version || '1.0.0',
    description: description || '',
    author: author || owner,
    githubUrl: cleaned,
    tags: Array.isArray(tags) ? tags : [],
    permissions: Array.isArray(permissions) ? permissions : [],
    submittedAt: new Date().toISOString(),
  });

  try {
    fs.mkdirSync(path.dirname(pendingFile), { recursive: true });
    fs.writeFileSync(pendingFile, JSON.stringify(list, null, 2));
  } catch (e) {
    return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
  }

  res.status(200).json({ success: true });
};

function cleanUrl(u) {
  let s = String(u).trim();
  if (s.endsWith('.git')) s = s.slice(0, -4);
  if (s.endsWith('/')) s = s.slice(0, -1);
  return s;
}

async function httpHead(url) {
  // Use GET with Range to be compatible with raw.githubusercontent.com which
  // refuses HEAD on missing files but answers GET cleanly.
  const r = await fetch(url, { method: 'GET', headers: { 'Range': 'bytes=0-0' } });
  return { ok: r.status >= 200 && r.status < 400 };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
