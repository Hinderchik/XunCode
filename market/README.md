# VScode Mobile Plugin Marketplace

Vercel-hosted backend for the in-app marketplace.

## Endpoints

| Method | Path                       | Purpose                                         |
|--------|----------------------------|-------------------------------------------------|
| GET    | `/api/plugins/list`        | All approved plugins, sorted by rating          |
| GET    | `/api/plugins/info?id=…`   | Single plugin detail                            |
| GET    | `/api/plugins/reviews?id=…`| Reviews for a plugin (legacy alias)             |
| GET    | `/api/plugins/review?id=…` | Reviews for a plugin                            |
| POST   | `/api/plugins/review`      | Add or update a review                          |
| POST   | `/api/admin/submit`        | Submit a GitHub repo for moderation             |
| POST   | `/api/admin/approve`       | Approve a pending submission (admin key)        |

## Local development

```sh
cd market
npx vercel dev
```

`vercel dev` mounts `data/` writable, so submit/review/approve can persist
locally. The `public/index.html` UI is served at `/`.

## Production storage

Vercel functions have a read-only filesystem on production deployments,
so writes from `submit` / `review` / `approve` would be lost. The simplest
durable backend: commit changes back to the repo through the GitHub API.

Set the following env vars on the Vercel project:

| Var               | What                                           |
|-------------------|------------------------------------------------|
| `ADMIN_API_KEY`   | Required by `approve.js`                       |
| `GH_TOKEN`        | (Optional) Personal access token w/ `repo`     |
| `GH_REPO`         | (Optional) `owner/repo` to commit data back to |

If `GH_TOKEN` and `GH_REPO` are present, you can extend the write path in
`review.js` / `submit.js` / `approve.js` to call `PUT /repos/.../contents/...`
instead of `fs.writeFileSync`.

## Data layout

```
data/
├── plugins.json        # Approved plugins (array)
├── pending.json        # Submissions awaiting review (array)
└── reviews/
    └── <pluginId>.json # Reviews for a single plugin
```

Each entry in `plugins.json` looks like:

```json
{
  "id": "com.author.plugin",
  "name": "Pretty Name",
  "version": "1.0.0",
  "author": "author",
  "description": "What it does",
  "githubUrl": "https://github.com/author/repo",
  "rating": 4.5,
  "reviewsCount": 12,
  "downloads": 342,
  "icon": "https://…",
  "tags": ["git", "linter"]
}
```

## Admin web UI

`public/index.html` ships with three tabs:

- **Browse** — public list of approved plugins (rendered with stars).
- **Submit** — anyone can paste a GitHub URL; the form posts to
  `/api/admin/submit`, which validates that `plugin.json` and `main.js`
  exist on the `main` or `master` branch.
- **Admin** — paste your `ADMIN_API_KEY`, get the list of pending
  submissions, hit Approve.

## Links

- GitHub: <https://github.com/Hinderchik>
- Telegram Dev: <https://t.me/XunKal1Dev>
- Telegram: <https://t.me/GodPassTGK>
