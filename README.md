# a2 controlled content service

This service gives the a2 owner a review gate between web/AI research and phones.
AI output is always a draft. Only the admin console can publish or withdraw it.

## Run locally

Requires Node 20 or newer.

```bash
cp .env.example .env
# Set ADMIN_TOKEN and, for AI research, OPENAI_API_KEY.
node --env-file=.env src/server.mjs
```

Open `http://localhost:8787/admin`, enter `ADMIN_TOKEN`, and connect. The public
device feed is `GET /api/v1/content?deviceId=...&userId=...&groups=...`.

Generate a strong admin token on Linux with:

```bash
openssl rand -hex 32
```

Create an OpenAI project API key in the OpenAI Platform, place it only in the
server `.env`, and never put it in Flutter, source control, or the browser.

## aa-cloud-wp30 deployment

1. Copy `server/` to `/opt/a2-content`.
2. Create `/etc/a2-content.env` from `.env.example`, owned by root and mode 600.
3. Copy `deploy/a2-content.service` to `/etc/systemd/system/`.
4. Run `sudo systemctl daemon-reload && sudo systemctl enable --now a2-content`.
5. Put the nginx configuration behind a real hostname and TLS certificate.
6. In a2, open **You → Data → Server** and enter the HTTPS origin only.

The current private deployment uses Docker at `/srv/apps/a2`, listens only on
`127.0.0.1:8787`, and is exposed to the owner's tailnet with:

```bash
sudo tailscale serve --bg --yes 8787
```

Its private console is `https://aa-cloud-wp30.tail52a6fb.ts.net/admin/`. To add
or rotate the OpenAI key without putting it in shell history, connect by SSH,
run `nano /srv/apps/a2/.env`, fill `OPENAI_API_KEY`, save, then run:

```bash
cd /srv/apps/a2
docker compose up -d --force-recreate
```

Retrieve the generated admin token directly in your own SSH terminal with:

```bash
sed -n 's/^ADMIN_TOKEN=//p' /srv/apps/a2/.env
```

The JSON file is suitable for initial private testing. Before broad public use,
move releases, users and device enrolments to PostgreSQL, add backups, rate
limits, audit-log retention and real user/device authentication. Target IDs in
this first version control rollout visibility; they must not protect sensitive
or paid content.

## Safety model

- Research uses the OpenAI Responses API with web search and structured output.
- `store: false` is set for draft requests.
- Drafts retain sources and an evidence note for human review.
- Publishing and withdrawal require the server-side admin bearer token.
- Phones receive versioned published releases and cache the last valid response.
- Withdrawing stops a release appearing on the next device check.
- Do not use remote content to silently change medical calculations. Changes to
  calorie equations or safety floors should require an app release and testing.
