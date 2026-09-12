#!/usr/bin/env python3
"""Generate a Postman v2.1 collection for the Flowexa mobile app API.

Source of truth: `php artisan route:list --json` from ../../backend.
Scope: a top "★ Mobile App" folder with the exact endpoints the Flutter app
(unichat_mobile_app) calls, plus the full grouped v1 API below it for reference.

Usage:
    python3 generate.py                       # runs artisan, writes the collection here
    python3 generate.py routes.json out.json  # explicit files
"""
import json
import os
import re
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))

if len(sys.argv) >= 3:
    ROUTES = json.load(open(sys.argv[1]))
    OUT = sys.argv[2]
else:
    backend = os.path.normpath(os.path.join(_HERE, "..", "..", "backend"))
    raw = subprocess.check_output(["php", "artisan", "route:list", "--json"], cwd=backend)
    ROUTES = json.loads(raw)
    OUT = os.path.join(_HERE, "Flowexa-Mobile-API.postman_collection.json")

BASE = "{{baseUrl}}"

# ── Which route groups belong in the mobile collection ───────────────────────
# key = first path segment after api/v1/ ; value = (folder name, order)
GROUPS = {
    "auth":            ("Auth",                 1),
    "device-auth":     ("Auth · Device Login",  2),
    "devices":         ("Auth · Devices",       3),
    "push":            ("Push Notifications",   4),
    "analytics":       ("Dashboard · Analytics",5),
    "conversations":   ("Chats",               10),
    "contacts":        ("Contacts",            11),
    "labels":          ("Contacts · Labels",   12),
    "leads":           ("Leads",               13),
    "lead-categories": ("Leads · Categories",  14),
    "lead-assignments":("Leads · Assignments", 15),
    "campaigns":       ("Campaigns",           20),
    "message-sender":  ("Message Sender",      21),
    "message-logs":    ("Message Logs",        22),
    "templates":       ("WA Cloud · Templates",30),
    "wa-cloud":        ("WA Cloud",            31),
    "phone-numbers":   ("WA Cloud · Numbers",  32),
    "wa-chat-templates":("WA Chat · Templates",40),
    "waha":            ("WA Chat · Sessions & Groups", 41),
    "wa-agent":        ("AI Agent",            50),
    "flow-builders":   ("Flow Builder",        51),
    "meta-ads":        ("Meta Ads",            60),
    "meta-ai":         ("Meta AI",             61),
    "instagram":       ("Instagram",           62),
    "listings":        ("Listings / Catalog",  63),
    "media-library":   ("Media Library",       64),
    "widgets":         ("Website Widget",      65),
    "survey-forms":    ("Survey Forms",        66),
    "staff":           ("Team · Staff",        70),
    "roles":           ("Team · Roles",        71),
    "company-roles":   ("Team · Company Roles",72),
    "hr":              ("HR",                  73),
    "working-hours":   ("Working Hours",       74),
    "wallet":          ("Wallet",              80),
    "plans":           ("Plans",               81),
    "addons":          ("Add-ons",             82),
    "settings":        ("Settings",            90),
    "company":         ("Company",             91),
    "google":          ("Integrations · Google", 92),
    "blacklist":       ("Blacklist",           93),
    "otp-service":     ("OTP Service",         94),
    "otp":             ("OTP",                 95),
    "wa-export":       ("Exports",             96),
    "crm":             ("CRM (Deals/Tasks)",   97),
    "superadmin":      ("Superadmin",         120),
}

# Endpoints to skip entirely (webhooks, public browser-only, payment callbacks)
SKIP_SUBSTR = [
    "/webhook", "/callback", "razorpay", "/public/", "dummy-whatsapp",
    "{waChatToken}", "/mcp",
]

# ── Known request bodies (from the mobile app + obvious shapes) ──────────────
BODIES = {
    "POST api/v1/auth/login": {"email": "you@example.com", "password": "secret"},
    "POST api/v1/auth/register": {"name": "", "email": "", "password": "", "company_name": ""},
    "POST api/v1/auth/change-password": {"current_password": "", "password": "", "password_confirmation": ""},
    "POST api/v1/auth/forgot-password": {"email": ""},
    "POST api/v1/auth/reset-password": {"token": "", "email": "", "password": "", "password_confirmation": ""},
    "PUT api/v1/auth/profile": {"name": "", "phone": ""},
    "POST api/v1/device-auth/check": {"pin": "123456"},
    "POST api/v1/device-auth/claim": {
        "pin": "123456", "device_uid": "{{deviceUid}}", "device_name": "iPhone",
        "platform": "ios", "app_version": "1.0.0", "push_token": ""},
    "POST api/v1/device-auth/remove-device": {"device_id": 1, "pin": "123456"},
    "POST api/v1/device-auth/heartbeat": {"app_version": "1.0.0", "push_token": ""},
    "POST api/v1/push/register-token": {"token": "", "platform": "ios"},
    "DELETE api/v1/push/unregister-token": {"token": ""},
    "POST api/v1/conversations/:id/messages": {"message": "Hello from Postman", "type": "text"},
    "POST api/v1/contacts": {"name": "", "phone": "", "email": "", "label_ids": []},
    "PUT api/v1/contacts/:contact": {"name": "", "phone": "", "email": ""},
    "POST api/v1/contacts/:contact/labels": {"label_ids": [1]},
    "POST api/v1/contacts/by-labels": {"label_ids": [1]},
    "POST api/v1/labels": {"name": "", "color": "#0F766E"},
    "POST api/v1/leads": {"contact_id": 1, "priority": "medium", "category": "", "assigned_to": None, "notes": ""},
    "PUT api/v1/leads/:lead": {"status": "", "priority": "medium", "category": "", "value": 0},
    "POST api/v1/leads/:lead/notes": {"note": ""},
    "POST api/v1/leads/:lead/assign": {"assigned_to": 1},
    "POST api/v1/leads/bulk-assign": {"lead_ids": [1, 2], "assigned_to": 1},
    "POST api/v1/campaigns": {"name": "", "template_id": 1, "contact_ids": [], "scheduled_at": None},
    "POST api/v1/message-sender": {"name": "", "message": "", "contact_ids": []},
    "POST api/v1/templates/sync-from-meta": {},
    "POST api/v1/staff": {"name": "", "email": "", "password": "", "role": "agent"},
    "POST api/v1/hr/attendance/clock-in": {},
    "POST api/v1/hr/attendance/clock-out": {},
    "POST api/v1/hr/leave": {"leave_type_id": 1, "from": "2026-01-01", "to": "2026-01-02", "reason": ""},
    "POST api/v1/hr/leave/:id/review": {"status": "approved", "note": ""},
    "POST api/v1/settings/api-keys": {"provider": "openai", "key": "", "label": ""},
    "POST api/v1/wa-agent/knowledge-base": {"title": "", "content": "", "type": "text"},
    "POST api/v1/instagram/conversations/:id/reply": {"message": ""},
    "PATCH api/v1/instagram/conversations/:id": {"status": "read"},
    "POST api/v1/waha/sessions": {"name": "default", "phone": ""},
    "POST api/v1/phone-numbers": {"phone_number_id": "", "display_number": "", "label": ""},
    "POST api/v1/wa-cloud/automations": {"name": "", "trigger": "", "enabled": True},
    "POST api/v1/listings": {"title": "", "price": 0, "description": "", "images": []},
    "POST api/v1/wa-export/chats": {"chat_ids": []},
    "PATCH api/v1/meta-ads/campaigns/:id/status": {"status": "PAUSED"},
    "PATCH api/v1/meta-ads/ads/:id/status": {"status": "PAUSED"},
    "PATCH api/v1/meta-ads/adsets/:id/status": {"status": "PAUSED"},
    "PATCH api/v1/wa-cloud/automations/:id": {"enabled": False},
    "PATCH api/v1/wa-agent/playbook/:id": {"enabled": False},
    "PATCH api/v1/wa-agent/automations/:id": {"enabled": False},
    "PATCH api/v1/instagram/conversations/:id": {"status": "closed"},
    "PATCH api/v1/staff/:staff/reset-password": {"password": "", "password_confirmation": ""},
    "PATCH api/v1/settings/api-keys/:id/set-active": {},
    "POST api/v1/leads/:lead/notes": {"note": ""},
    "PUT api/v1/leads/:lead": {"status": "new", "priority": "medium", "category": "", "value": 0},
    "POST api/v1/instagram/automations": {"name": "", "trigger_keyword": "", "reply": "", "account_id": 1},
    "PUT api/v1/instagram/automations/:id": {"name": "", "trigger_keyword": "", "reply": ""},
    "POST api/v1/widgets": {"name": "", "greeting": "", "color": "#0F766E"},
    "PUT api/v1/widgets/:id": {"name": "", "greeting": "", "color": "#0F766E"},
    "PUT api/v1/phone-numbers/:id": {"display_number": "", "label": ""},
    "POST api/v1/wa-agent/playbook": {"title": "", "instruction": "", "enabled": True},
    "PUT api/v1/listings/:id": {"title": "", "price": 0, "description": ""},
    "POST api/v1/media-library/folders": {"name": "", "parent_id": None},
    "POST api/v1/hr/leave/:id/cancel": {},
    "POST api/v1/wa-export/contacts": {},
    "POST api/v1/wa-export/groups": {},
    "POST api/v1/otp-service/test-send": {"to": "", "template": ""},
}

LIST_QUERY = {  # groups whose GET-collection endpoints get pagination params
    "contacts", "leads", "conversations", "campaigns", "message-logs",
    "staff", "listings", "media-library", "wa-agent", "meta-ads", "instagram",
}


# ── Exact endpoints the Flutter app (unichat_mobile_app) calls today ────────
# "METHOD api/v1/<path with :params>"  →  optional note
MOBILE = {
    "POST api/v1/auth/login": "",
    "GET api/v1/auth/me": "",
    "POST api/v1/auth/logout": "",
    "POST api/v1/device-auth/check": "",
    "POST api/v1/device-auth/claim": "",
    "POST api/v1/device-auth/remove-device": "",
    "GET api/v1/device-auth/status": "called on every cold start",
    "POST api/v1/device-auth/heartbeat": "every 5 min + on resume",
    "POST api/v1/device-auth/logout": "",
    "GET api/v1/analytics/overview": "Home stats strip",
    "GET api/v1/analytics/leads": "",
    "GET api/v1/analytics/wallet": "",
    "GET api/v1/conversations": "?per_page=100",
    "GET api/v1/conversations/:id/messages": "",
    "POST api/v1/conversations/:id/messages": "{message,type}",
    "GET api/v1/contacts": "?per_page / search",
    "POST api/v1/contacts": "",
    "GET api/v1/contacts/:contact": "",
    "PUT api/v1/contacts/:contact": "",
    "DELETE api/v1/contacts/:contact": "",
    "POST api/v1/contacts/:contact/labels": "{label_ids}",
    "GET api/v1/labels": "",
    "GET api/v1/leads": "?status / search / per_page",
    "POST api/v1/leads": "",
    "GET api/v1/leads/:lead": "",
    "PUT api/v1/leads/:lead": "",
    "DELETE api/v1/leads/:lead": "",
    "GET api/v1/leads/:lead/notes": "",
    "POST api/v1/leads/:lead/notes": "",
    "GET api/v1/leads/:lead/events": "",
    "POST api/v1/leads/:lead/assign": "{assigned_to}",
    "GET api/v1/campaigns": "",
    "GET api/v1/notifications": "app: NotificationsPage — likely should be GET /push/history",
    "GET api/v1/staff": "",
    "POST api/v1/staff": "",
    "PUT api/v1/staff/:staff": "",
    "PATCH api/v1/staff/:staff/reset-password": "",
    "PATCH api/v1/staff/:staff/toggle-active": "",
    "DELETE api/v1/staff/:staff": "",
    "GET api/v1/roles": "",
    "GET api/v1/devices": "",
    "DELETE api/v1/devices/:id": "",
    "GET api/v1/meta-ads/accounts": "",
    "POST api/v1/meta-ads/accounts/:id/set-default": "",
    "GET api/v1/meta-ads/campaigns": "",
    "PATCH api/v1/meta-ads/campaigns/:id/status": "{status}",
    "POST api/v1/meta-ads/campaigns/:id/duplicate": "",
    "DELETE api/v1/meta-ads/campaigns/:id": "",
    "GET api/v1/meta-ads/insights/overview": "",
    "GET api/v1/meta-ads/audience-sets": "",
    "POST api/v1/meta-ads/audience-sets/:id/duplicate": "",
    "DELETE api/v1/meta-ads/audience-sets/:id": "",
    "GET api/v1/meta-ads/lead-forms": "",
    "GET api/v1/instagram/accounts": "",
    "POST api/v1/instagram/accounts/:id/sync": "",
    "POST api/v1/instagram/accounts/:id/import-listings": "",
    "GET api/v1/instagram/conversations": "",
    "PATCH api/v1/instagram/conversations/:id": "{status}",
    "POST api/v1/instagram/conversations/:id/reply": "{message}",
    "GET api/v1/instagram/automations": "",
    "POST api/v1/instagram/automations": "",
    "PUT api/v1/instagram/automations/:id": "",
    "DELETE api/v1/instagram/automations/:id": "",
    "POST api/v1/instagram/automations/:id/toggle": "",
    "GET api/v1/wa-agent/stats": "",
    "GET api/v1/wa-agent/sessions": "",
    "POST api/v1/wa-agent/sessions/:id/close": "",
    "POST api/v1/wa-agent/sessions/:id/transfer": "",
    "GET api/v1/wa-agent/playbook": "",
    "POST api/v1/wa-agent/playbook": "",
    "PATCH api/v1/wa-agent/playbook/:id": "",
    "DELETE api/v1/wa-agent/playbook/:id": "",
    "POST api/v1/wa-agent/playbook/:id/toggle": "",
    "GET api/v1/wa-agent/automations": "",
    "GET api/v1/wa-agent/knowledge-base": "",
    "POST api/v1/wa-agent/knowledge-base": "",
    "DELETE api/v1/wa-agent/knowledge-base/:id": "",
    "GET api/v1/widgets": "",
    "POST api/v1/widgets": "",
    "PUT api/v1/widgets/:id": "",
    "DELETE api/v1/widgets/:id": "",
    "GET api/v1/templates": "",
    "POST api/v1/templates/sync-from-meta": "",
    "POST api/v1/templates/:id/submit": "",
    "POST api/v1/templates/:id/sync": "",
    "GET api/v1/wa-chat-templates": "",
    "GET api/v1/phone-numbers": "",
    "POST api/v1/phone-numbers": "",
    "PUT api/v1/phone-numbers/:id": "",
    "DELETE api/v1/phone-numbers/:id": "",
    "POST api/v1/phone-numbers/:id/set-default": "",
    "POST api/v1/phone-numbers/:id/verify": "",
    "GET api/v1/waha/sessions": "",
    "POST api/v1/waha/sessions": "",
    "GET api/v1/waha/sessions/:id": "",
    "POST api/v1/waha/sessions/:id/start": "",
    "POST api/v1/waha/sessions/:id/stop": "",
    "POST api/v1/waha/sessions/:id/logout": "",
    "DELETE api/v1/waha/sessions/:id": "",
    "GET api/v1/flow-builders": "",
    "DELETE api/v1/flow-builders/:id": "",
    "GET api/v1/wa-cloud/inbox-analytics": "",
    "GET api/v1/wa-cloud/automations": "",
    "POST api/v1/wa-cloud/automations": "",
    "PATCH api/v1/wa-cloud/automations/:id": "",
    "DELETE api/v1/wa-cloud/automations/:id": "",
    "POST api/v1/wa-cloud/automations/:id/toggle": "",
    "GET api/v1/survey-forms": "",
    "PUT api/v1/survey-forms/:id": "",
    "DELETE api/v1/survey-forms/:id": "",
    "GET api/v1/survey-forms/:id/responses": "",
    "GET api/v1/settings/api-keys": "",
    "POST api/v1/settings/api-keys": "",
    "POST api/v1/settings/api-keys/:id/set-active": "",
    "DELETE api/v1/settings/api-keys/:id": "",
    "GET api/v1/google/status": "",
    "GET api/v1/google/connect": "returns OAuth URL",
    "DELETE api/v1/google/disconnect": "",
    "GET api/v1/hr/attendance/me": "",
    "POST api/v1/hr/attendance/clock-in": "",
    "POST api/v1/hr/attendance/clock-out": "",
    "GET api/v1/hr/leave": "",
    "POST api/v1/hr/leave": "",
    "POST api/v1/hr/leave/:id/cancel": "",
    "GET api/v1/wallet": "",
    "GET api/v1/wallet/transactions": "",
    "GET api/v1/plans/current": "",
    "GET api/v1/otp-service": "",
    "GET api/v1/otp-service/logs": "",
    "POST api/v1/otp-service/reset-token": "",
    "POST api/v1/otp-service/test-send": "",
    "GET api/v1/wa-export": "",
    "POST api/v1/wa-export/chats": "",
    "POST api/v1/wa-export/contacts": "",
    "POST api/v1/wa-export/groups": "",
    "DELETE api/v1/wa-export/:id": "",
    "GET api/v1/wa-export/:id/download": "",
    "GET api/v1/listings": "",
    "POST api/v1/listings": "",
    "PUT api/v1/listings/:id": "",
    "DELETE api/v1/listings/:id": "",
    "GET api/v1/media-library": "",
    "GET api/v1/media-library/folders": "",
    "POST api/v1/media-library/folders": "",
    "DELETE api/v1/media-library/folders/:id": "",
    "DELETE api/v1/media-library/:id": "",
    "GET api/v1/superadmin/dashboard": "",
    "GET api/v1/superadmin/companies": "",
    "PATCH api/v1/superadmin/companies/:company/status": "",
}


def route_key(route):
    method = route["method"].split("|")[0]
    psegs = [re.sub(r"\{(\w+)\??\}", r":\1", s) for s in route["uri"].split("/")]
    return f"{method} " + "/".join(psegs)


def to_postman_path(uri):
    # api/v1/contacts/{contact} -> ["contacts", ":contact"]
    segs = uri.split("/")[2:]
    return ["/".join([""])[:0] or s for s in segs], [re.sub(r"\{(\w+)\??\}", r":\1", s) for s in segs]


def path_vars(segs):
    out = []
    for s in segs:
        if s.startswith(":"):
            out.append({"key": s[1:], "value": "1"})
    return out


def build_request(route):
    method = route["method"].split("|")[0]
    uri = route["uri"]
    _, psegs = to_postman_path(uri)
    group = uri.split("/")[2]

    url = {
        "raw": BASE + "/" + "/".join(psegs),
        "host": [BASE],
        "path": psegs,
    }
    pv = path_vars(psegs)
    if pv:
        url["variable"] = pv

    is_collection_get = method == "GET" and len(psegs) == 1
    if group in LIST_QUERY and is_collection_get:
        url["query"] = [
            {"key": "page", "value": "1"},
            {"key": "per_page", "value": "25"},
            {"key": "search", "value": "", "disabled": True},
        ]
        url["raw"] += "?page=1&per_page=25"

    req = {
        "method": method,
        "header": [],
        "url": url,
    }

    if method in ("POST", "PUT", "PATCH", "DELETE"):
        key = f"{method} {uri.replace(chr(123),'{').replace(chr(125),'}')}"
        # normalise {param} to :param for body lookup
        norm = f"{method} " + "api/v1/" + "/".join(psegs)
        body = BODIES.get(norm, BODIES.get(key))
        if body is None and method in ("POST", "PUT", "PATCH"):
            body = {}
        if body is not None:
            req["header"].append({"key": "Content-Type", "value": "application/json"})
            req["body"] = {
                "mode": "raw",
                "raw": json.dumps(body, indent=2),
                "options": {"raw": {"language": "json"}},
            }
    return req


def nice_name(route):
    method = route["method"].split("|")[0]
    segs = route["uri"].split("/")[3:]  # drop api/v1/<group>
    tail = "/".join(segs) if segs else "(list)"
    tail = re.sub(r"\{(\w+)\??\}", r"{\1}", tail)
    verb = {"GET": "Get", "POST": "Create/Do", "PUT": "Update", "PATCH": "Patch", "DELETE": "Delete"}.get(method, method)
    if not segs:
        return f"{verb} {method}"
    return f"{method} {tail}"


def synth_route(mkey):
    method, uri = mkey.split(" ", 1)
    return {"method": method, "uri": uri.replace(":", "{").replace("{", "{") , "_synth": True,
            "method_raw": method, "uri_raw": uri}


def build_mobile_folder(route_index):
    """Top-level folder: exactly the endpoints unichat_mobile_app calls."""
    kids = []
    for mkey, note in MOBILE.items():
        method, uri = mkey.split(" ", 1)
        psegs = uri.split("/")[2:]
        real = route_index.get(mkey)
        missing = real is None
        fake = {"method": method, "uri": "api/v1/" + "/".join(psegs)}
        req = build_request(fake)
        desc = []
        if note:
            desc.append(note)
        if missing:
            desc.append("⚠️  This path is **not** registered in `routes/api.php` "
                        "(`php artisan route:list`). The mobile app calls it but the server "
                        "will 404 — needs a backend route or an app fix.")
        item = {"name": f"{method} /" + "/".join(psegs), "request": req, "response": []}
        if desc:
            item["request"]["description"] = "\n\n".join(desc)
        kids.append(item)
    kids.sort(key=lambda x: x["name"])
    return {
        "name": "★ Mobile App — Endpoints In Use",
        "description": (
            f"The {len(MOBILE)} endpoints the Flutter app (`unichat_mobile_app`) calls today, "
            "extracted from its Dio/repository code. Two are flagged ⚠️ as missing on "
            "the server. Everything below this folder is the full grouped API for reference."
        ),
        "item": kids,
    }


def main():
    route_index = {route_key(r): r for r in ROUTES if r["uri"].startswith("api/v1/")}
    folders = {}
    for r in ROUTES:
        uri = r["uri"]
        if not uri.startswith("api/v1/"):
            continue
        if any(s in uri for s in SKIP_SUBSTR):
            continue
        group = uri.split("/")[2]
        if group not in GROUPS:
            continue
        fname, order = GROUPS[group]
        folders.setdefault((order, fname), [])
        folders[(order, fname)].append({
            "name": nice_name(r),
            "request": build_request(r),
            "response": [],
        })

    items = [build_mobile_folder(route_index)]
    for (order, fname) in sorted(folders):
        kids = sorted(folders[(order, fname)], key=lambda x: (x["request"]["method"] != "GET", x["name"]))
        items.append({"name": fname, "item": kids})

    collection = {
        "info": {
            "name": "Flowexa Mobile API",
            "description": (
                "REST API for the Flowexa mobile app (`unichat_mobile_app`).\n\n"
                "Base URL: `https://flowexa-api.univexa.in/api/v1`\n\n"
                "## Auth\n"
                "1. Run **Auth · Device Login → POST device-auth/check** with a PIN or QR "
                "`token` from the web app (Settings → Devices → Link a device).\n"
                "2. Run **POST device-auth/claim** — its test script saves `{{token}}` automatically.\n"
                "3. Or use **Auth → POST auth/login** with email + password.\n\n"
                "All other requests send `Authorization: Bearer {{token}}` via collection auth.\n\n"
                "Generated from `php artisan route:list` — methods/paths are exact; "
                "request bodies for unlisted fields are placeholders, check the FormRequest."
            ),
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
        },
        "auth": {
            "type": "bearer",
            "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}],
        },
        "event": [
            {
                "listen": "prerequest",
                "script": {"type": "text/javascript", "exec": [""]},
            }
        ],
        "variable": [
            {"key": "baseUrl", "value": "https://flowexa-api.univexa.in/api/v1"},
            {"key": "token", "value": ""},
            {"key": "deviceUid", "value": "postman-" + "test-device"},
        ],
        "item": items,
    }

    # attach token-capture test script to every login / claim request
    capture = {
        "listen": "test",
        "script": {"type": "text/javascript", "exec": [
            "const j = pm.response.json();",
            "const tok = j.access_token || (j.data && j.data.access_token);",
            "if (tok) { pm.collectionVariables.set('token', tok); console.log('token saved'); }",
        ]},
    }

    def walk(node):
        for it in node.get("item", []):
            if "item" in it:
                walk(it)
            else:
                p = "/".join(it["request"]["url"]["path"])
                if p.endswith("auth/login") or p.endswith("device-auth/claim"):
                    it.setdefault("event", []).append(json.loads(json.dumps(capture)))

    walk(collection)

    json.dump(collection, open(OUT, "w"), indent=2)
    n = sum(len(f["item"]) for f in items)
    print(f"wrote {OUT}: {len(items)} folders, {n} requests")


main()
