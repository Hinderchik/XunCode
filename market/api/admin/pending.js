// GET /api/admin/pending
//   query/header: adminKey or x-admin-key
//
// Returns the list of submissions awaiting review. Required because Vercel
// only serves files under /public, so the admin UI cannot read data/pending.json
// directly.

const fs = require('fs');
const path = require('path');

module.exports = (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const expected = process.env.ADMIN_API_KEY;
  if (!expected) return res.status(500).json({ error: 'ADMIN_API_KEY not configured' });

  const provided =
    (req.query && req.query.adminKey) ||
    req.headers['x-admin-key'] ||
    '';
  if (provided !== expected) return res.status(401).json({ error: 'invalid adminKey' });

  try {
    const file = path.join(process.cwd(), 'data', 'pending.json');
    const raw = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '[]';
    const list = JSON.parse(raw);
    res.status(200).json(Array.isArray(list) ? list : []);
  } catch (e) {
    res.status(500).json({ error: String(e && e.message || e) });
  }
};
