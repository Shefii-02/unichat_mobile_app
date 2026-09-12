# Flowexa Mobile — Postman

API collection for the Flowexa mobile app (`unichat_mobile_app`). The app talks
to **one** backend — the Laravel API at `https://flowexa-api.univexa.in/api/v1`.
(`nodeBase` / `socketUrl` are declared in `ApiConstants` but nothing in `lib/`
uses them yet.)

## Files

| File | What it is |
|---|---|
| `Flowexa-Mobile-API.postman_collection.json` | The collection. Import into Postman. |
| `Flowexa-Prod.postman_environment.json` | Environment → `https://flowexa-api.univexa.in/api/v1` |
| `Flowexa-Local.postman_environment.json` | Environment → `http://127.0.0.1:8000/api/v1` |
| `generate.py` | Regenerates the collection from `php artisan route:list`. |

## Import

1. Postman → **Import** → drop all three JSON files.
2. Pick the **Flowexa · Prod** environment (top-right).
3. Authenticate (see below). `{{token}}` is filled automatically.
4. Every request inherits `Authorization: Bearer {{token}}` from the collection.

## Auth

Two ways, mirroring the app:

**Device login (what the mobile app does)**
1. On the web app: **Settings → Devices → Link a device** — note the 6-digit PIN
   (or the 40-char QR `token`).
2. `★ Mobile App` → `POST /device-auth/check` — body `{"pin": "123456"}`.
3. `POST /device-auth/claim` — same credential + device info. Its **test script
   saves `{{token}}`** for you.

**Email + password**
- `Auth → POST /auth/login` — `{"email","password"}`. Also auto-saves `{{token}}`.

## Layout

- **★ Mobile App — Endpoints In Use** — the ~149 requests the Flutter app actually
  makes, pulled from its Dio/repository code. Start here for "does the mobile app
  work" testing.
- Everything below — the full `api/v1` surface, grouped by module, for reference.

## Known mismatch

- `GET /notifications` (app: `NotificationsPage`) is **not a registered route**.
  It 404s; the app swallows the error and shows an empty list. The intended
  endpoint is almost certainly `GET /push/history`. Fix in the app or add the
  backend route.

## Regenerating

```bash
cd postman
python3 generate.py          # needs php + ../../backend
```

Methods and paths come straight from `route:list`, so they're exact. Request
**bodies** for fields the app doesn't set are placeholders — check the
controller's FormRequest for the authoritative shape.
