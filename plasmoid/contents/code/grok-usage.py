#!/usr/bin/env python3
"""Fetch the same SuperGrok /usage quota the Grok Build TUI shows."""
from __future__ import print_function

import fcntl
import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

BILLING_URL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
SETTINGS_URL = "https://cli-chat-proxy.grok.com/v1/settings"
TOKEN_URL = "https://auth.x.ai/oauth2/token"
USER_AGENT = "grok-usage-plasmoid/0.1"
TOKEN_SKEW = timedelta(minutes=2)
PRODUCT_LABELS = {
    "GrokBuild": "Grok Build",
    "GrokChat": "Grok Chat",
    "GrokVoice": "Grok Voice",
}
PERIOD_LABELS = {
    "USAGE_PERIOD_TYPE_WEEKLY": "hebdomadaire",
    "USAGE_PERIOD_TYPE_MONTHLY": "mensuel",
    "WEEKLY": "hebdomadaire",
    "MONTHLY": "mensuel",
}


def grok_home():
    return os.path.expanduser(os.environ.get("GROK_HOME") or "~/.grok")


def auth_path():
    return os.path.join(grok_home(), "auth.json")


def lock_path():
    return os.path.join(grok_home(), "auth.json.lock")


def emit(payload, code=0):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.exit(code)


def fail(error, message, code=1):
    emit({"ok": False, "error": error, "message": message}, code)


def parse_iso(value):
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    if "." in text:
        head, rest = text.split(".", 1)
        digits = []
        tz = rest
        for i, ch in enumerate(rest):
            if ch.isdigit():
                digits.append(ch)
            else:
                tz = rest[i:]
                break
        else:
            tz = ""
        frac = ("".join(digits) + "000000")[:6]
        text = head + "." + frac + tz
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def iso_z(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def load_auth():
    path = auth_path()
    if not os.path.isfile(path):
        return None
    with open(path, "r") as handle:
        return json.load(handle)


def pick_credential(store):
    if not isinstance(store, dict):
        return None, None
    for key, cred in store.items():
        if isinstance(cred, dict) and cred.get("key"):
            return key, cred
    return None, None


def token_still_good(cred, now):
    expires = parse_iso(cred.get("expires_at"))
    if expires is None:
        return bool(cred.get("key"))
    return expires - TOKEN_SKEW > now


def http_json(url, headers, data=None, timeout=15):
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            if not body:
                return {}, response.status
            return json.loads(body.decode("utf-8")), response.status
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except Exception:
            parsed = {"raw": raw[:200].decode("utf-8", "replace")}
        raise HttpError(exc.code, parsed)
    except urllib.error.URLError as exc:
        raise HttpError(0, {"message": str(exc.reason)})


class HttpError(Exception):
    def __init__(self, status, payload):
        Exception.__init__(self, "HTTP %s" % status)
        self.status = status
        self.payload = payload


def refresh_token(cred):
    refresh = cred.get("refresh_token")
    client_id = cred.get("oidc_client_id")
    if not refresh or not client_id:
        return None
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": client_id,
    }).encode("utf-8")
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": USER_AGENT,
    }
    payload, _status = http_json(TOKEN_URL, headers, data=body)
    access = payload.get("access_token")
    if not access:
        return None
    now = datetime.now(timezone.utc)
    expires_in = payload.get("expires_in") or 21600
    try:
        expires_in = int(expires_in)
    except (TypeError, ValueError):
        expires_in = 21600
    cred = dict(cred)
    cred["key"] = access
    if payload.get("refresh_token"):
        cred["refresh_token"] = payload["refresh_token"]
    cred["expires_at"] = iso_z(now + timedelta(seconds=expires_in))
    return cred


def atomic_write_auth(store):
    path = auth_path()
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix="auth.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(store, handle, indent=2)
            handle.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def locked_access_token():
    now = datetime.now(timezone.utc)
    lock_file = lock_path()
    try:
        lock_fd = os.open(lock_file, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError:
        lock_fd = None
    try:
        if lock_fd is not None:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        store = load_auth()
        if store is None:
            return None, "not_logged_in", "Aucune session Grok. Lance `grok login`."
        slot, cred = pick_credential(store)
        if cred is None:
            return None, "not_logged_in", "Aucune session Grok. Lance `grok login`."
        if token_still_good(cred, now):
            return cred["key"], None, None
        try:
            updated = refresh_token(cred)
        except HttpError as exc:
            if exc.status in (400, 401, 403):
                return None, "relogin", "Session expirée. Relance `grok login`."
            return None, "network", "Impossible de renouveler la session Grok."
        if updated is None:
            return None, "relogin", "Session expirée. Relance `grok login`."
        store[slot] = updated
        try:
            atomic_write_auth(store)
        except OSError:
            pass
        return updated["key"], None, None
    finally:
        if lock_fd is not None:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except OSError:
                pass
            os.close(lock_fd)


def auth_headers(token):
    return {
        "Authorization": "Bearer %s" % token,
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
        "x-xai-token-auth": "xai-grok-cli",
    }


def unwrap_val(node):
    if isinstance(node, dict) and "val" in node:
        return node.get("val")
    return node


def as_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def product_rows(config):
    rows = []
    for item in config.get("productUsage") or []:
        if not isinstance(item, dict):
            continue
        product_id = item.get("product") or ""
        percent = as_float(item.get("usagePercent"))
        rows.append({
            "id": product_id,
            "label": PRODUCT_LABELS.get(product_id, product_id or "Autre"),
            "percent": percent,
        })
    return rows


def build_percent(products):
    for item in products:
        if item.get("id") == "GrokBuild":
            return item.get("percent")
    return None


def format_reset(iso_value):
    dt = parse_iso(iso_value)
    if dt is None:
        return None, None
    local = dt.astimezone()
    months = (
        "janv.", "févr.", "mars", "avr.", "mai", "juin",
        "juil.", "août", "sept.", "oct.", "nov.", "déc.",
    )
    days = ("lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim.")
    human = "%s %s %s à %02dh%02d" % (
        days[local.weekday()], local.day, months[local.month - 1],
        local.hour, local.minute,
    )
    return dt.isoformat(), human


def summarize(config, plan):
    percent = as_float(config.get("creditUsagePercent"))
    if percent is None:
        used = as_float(unwrap_val(config.get("onDemandUsed")))
        cap = as_float(unwrap_val(config.get("onDemandCap")))
        if used is not None and cap:
            percent = used / cap * 100.0
        elif config.get("currentPeriod"):
            percent = 0.0
    products = product_rows(config)
    period = config.get("currentPeriod") or {}
    period_type = period.get("type") or ""
    reset_iso = period.get("end") or config.get("billingPeriodEnd")
    reset_at, reset_human = format_reset(reset_iso)
    return {
        "ok": True,
        "percent": percent,
        "build_percent": build_percent(products),
        "products": products,
        "period": PERIOD_LABELS.get(period_type, period_type or None),
        "reset_at": reset_at,
        "reset_human": reset_human,
        "plan": plan,
        "unified": bool(config.get("isUnifiedBillingUser")),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }


def fetch_plan(token):
    try:
        payload, _status = http_json(SETTINGS_URL, auth_headers(token), timeout=5)
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    return payload.get("subscription_tier_display")


def main():
    token, error, message = locked_access_token()
    if token is None:
        fail(error, message, 2)
    try:
        payload, _status = http_json(BILLING_URL, auth_headers(token))
    except HttpError as exc:
        if exc.status in (401, 403):
            fail("relogin", "Session refusée. Relance `grok login`.", 2)
        fail("network", "Impossible de lire le quota Grok.")
    except Exception:
        fail("network", "Impossible de lire le quota Grok.")
    config = payload.get("config") if isinstance(payload, dict) else None
    if not isinstance(config, dict):
        fail("parse", "Reponse quota inattendue.")
    result = summarize(config, fetch_plan(token))
    emit(result)


if __name__ == "__main__":
    main()
