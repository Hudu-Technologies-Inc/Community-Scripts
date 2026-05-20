#!/usr/bin/env python3
"""
Sync Hudu websites/domains into Halo PSA assets (idempotent).

Matching key: inventory_number = hudu-website-{hudu_website_id}
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib.parse import urlparse

import httpx
from hudu_magic import HuduClient

HUDU_WEBSITE_INVENTORY_PREFIX = "hudu-website-ID-"
NOTES_SECTION_RULE = "─" * 44
NOTES_SYNC_FOOTER = "Synced by halosync from Hudu"

# Hudu expiration_type values that apply to monitored websites/domains.
WEBSITE_EXPIRATION_TYPES = frozenset(
    {"domain", "ssl_certificate", "undeclared", "warranty"}
)


def load_env_file(path: str = ".env") -> None:
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:]
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def parse_client_map(raw: str | None) -> dict[int, int]:
    if not raw:
        return {}
    data = json.loads(raw)
    return {int(k): int(v) for k, v in data.items()}


def env_flag(name: str, *, default: bool = False) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def format_metadata_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, (dict, list)):
        return json.dumps(value, indent=2, default=str)
    return str(value).strip()


def extract_hudu_dns_metadata(data: dict[str, Any]) -> list[tuple[str, str]]:
    """Build labeled rows from Hudu website monitoring / DNS-related fields."""
    rows: list[tuple[str, str]] = []

    def add(label: str, key: str, *, invert_bool: bool = False) -> None:
        if key not in data:
            return
        value = data[key]
        if value is None or value == "":
            return
        if invert_bool and isinstance(value, bool):
            value = not value
        rows.append((label, format_metadata_value(value)))

    add("DNS monitoring enabled", "disable_dns", invert_bool=True)
    add("SSL monitoring enabled", "disable_ssl", invert_bool=True)
    add("WHOIS monitoring enabled", "disable_whois", invert_bool=True)
    add("Website monitoring paused", "paused")
    add("SPF tracking enabled", "enable_spf_tracking")
    add("DKIM tracking enabled", "enable_dkim_tracking")
    add("DMARC tracking enabled", "enable_dmarc_tracking")
    add("Last refreshed (Hudu)", "refreshed_at")
    add("Last monitored (Hudu)", "monitored_at")
    add("Monitoring status", "monitoring_status")
    add("Website status", "status")
    add("Monitor type", "monitor_type")
    add("Potentially proxied (CDN)", "potentially_proxied")
    add("Cloudflare details", "cloudflare_details")
    add("HTTP headers (last check)", "headers")
    add("Monitor code", "code")
    add("Monitor message", "message")
    add("Monitor keyword", "keyword")
    add("Archived", "archived")
    add("Discarded at", "discarded_at")

    if not data.get("enable_spf_tracking") and not data.get("enable_dkim_tracking"):
        rows.append(
            (
                "Note",
                "Hudu API does not expose SPF/DKIM/DMARC record text; "
                "only tracking flags and timestamps are available from Hudu API directly.",
            )
        )
    return rows


def lookup_live_dns(domain: str) -> list[tuple[str, str]]:
    """Optional live DNS via Cloudflare DNS-over-HTTPS (no extra dependencies)."""
    rows: list[tuple[str, str]] = []
    if not domain:
        return rows

    def query(name: str, rtype: str) -> list[str]:
        try:
            r = httpx.get(
                "https://cloudflare-dns.com/dns-query",
                params={"name": name, "type": rtype},
                headers={"accept": "application/dns-json"},
                timeout=15,
            )
            r.raise_for_status()
            answers = r.json().get("Answer") or []
            values: list[str] = []
            for ans in answers:
                data = ans.get("data", "")
                if rtype == "TXT":
                    data = data.strip('"')
                values.append(data)
            return values
        except httpx.HTTPError:
            return []

    for rtype in ("A", "AAAA", "MX", "NS", "CNAME"):
        answers = query(domain, rtype)
        if answers:
            rows.append((f"Live {rtype}", "\n".join(answers)))

    txt_records = query(domain, "TXT")
    if txt_records:
        rows.append(("Live TXT", "\n".join(txt_records)))
        spf = [t for t in txt_records if "v=spf1" in t.lower()]
        if spf:
            rows.append(("Live SPF", "\n".join(spf)))
        dkim = [t for t in txt_records if "v=dkim1" in t.lower()]
        if dkim:
            rows.append(("Live DKIM (on apex TXT)", "\n".join(dkim)))

    dmarc_name = f"_dmarc.{domain}"
    dmarc_txt = query(dmarc_name, "TXT")
    if dmarc_txt:
        rows.append((f"Live DMARC ({dmarc_name})", "\n".join(dmarc_txt)))

    common_dkim_selectors = ("default", "selector1", "selector2", "google", "k1", "s1", "dkim")
    for selector in common_dkim_selectors:
        dkim_host = f"{selector}._domainkey.{domain}"
        dkim_txt = query(dkim_host, "TXT")
        dkim_records = [t for t in dkim_txt if "v=dkim1" in t.lower()]
        if dkim_records:
            rows.append((f"Live DKIM ({dkim_host})", "\n".join(dkim_records)))

    if not rows:
        rows.append(("Live DNS", f"No answers returned for {domain}"))
    return rows


def format_notes_section(title: str, rows: list[tuple[str, str]]) -> str:
    """Plaintext section: shared by Halo assets and services notes fields."""
    if not rows:
        return ""
    lines = [NOTES_SECTION_RULE, title, NOTES_SECTION_RULE, ""]
    for label, value in rows:
        if "\n" in value:
            lines.append(f"  {label}")
            lines.extend(f"    {part}" for part in value.splitlines())
        else:
            lines.append(f"  {label}: {value}")
    return "\n".join(lines)


def split_hudu_and_live_dns_rows(
    rows: list[tuple[str, str]],
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    live_prefixes = ("Live ",)
    hudu_rows: list[tuple[str, str]] = []
    live_rows: list[tuple[str, str]] = []
    for label, value in rows:
        if label.startswith(live_prefixes):
            live_rows.append((label, value))
        else:
            hudu_rows.append((label, value))
    return hudu_rows, live_rows


def expiration_to_dict(expiration: Any) -> dict[str, Any]:
    if hasattr(expiration, "to_dict"):
        return expiration.to_dict()
    return dict(expiration)


def list_all_hudu_expirations(hudu: HuduClient) -> list[dict[str, Any]]:
    return [expiration_to_dict(exp) for exp in hudu.expirations.list()]


class ExpirationIndex:
    """In-memory indexes for matching Hudu expirations to websites."""

    def __init__(self, expirations: list[dict[str, Any]]):
        self.by_website_id: dict[int, list[dict[str, Any]]] = {}
        self.by_asset_field_id: dict[int, list[dict[str, Any]]] = {}
        self.by_company_id: dict[int, list[dict[str, Any]]] = {}

        for exp in expirations:
            if exp.get("archived_at"):
                continue

            company_id = exp.get("company_id")
            if company_id is not None:
                self.by_company_id.setdefault(int(company_id), []).append(exp)

            asset_field_id = exp.get("asset_field_id")
            if asset_field_id is not None:
                self.by_asset_field_id.setdefault(int(asset_field_id), []).append(exp)

            if exp.get("expirationable_type") == "Website":
                website_id = exp.get("expirationable_id")
                if website_id is not None:
                    self.by_website_id.setdefault(int(website_id), []).append(exp)

    def match_for_website(
        self,
        website: dict[str, Any],
        *,
        hudu: HuduClient | None = None,
    ) -> list[dict[str, Any]]:
        website_id = website.get("id")
        company_id = website.get("company_id")
        asset_field_id = website.get("asset_field_id")

        if website_id is None:
            return []

        seen: set[int] = set()
        matched: list[dict[str, Any]] = []

        def add(exp: dict[str, Any]) -> None:
            exp_id = exp.get("id")
            if exp_id is None or exp_id in seen:
                return
            seen.add(int(exp_id))
            matched.append(exp)

        for exp in self.by_website_id.get(int(website_id), []):
            add(exp)

        if asset_field_id is not None:
            for exp in self.by_asset_field_id.get(int(asset_field_id), []):
                add(exp)

        if company_id is not None:
            for exp in self.by_company_id.get(int(company_id), []):
                exp_type = (exp.get("expiration_type") or "").lower()
                obj_type = exp.get("expirationable_type")
                obj_id = exp.get("expirationable_id")

                if obj_type == "Website" and obj_id == website_id:
                    add(exp)
                elif exp_type in WEBSITE_EXPIRATION_TYPES and obj_type == "Website":
                    if obj_id is None or obj_id == website_id:
                        add(exp)

        if hudu is not None and not matched:
            for exp in hudu.expirations.list(
                resource_type="Website",
                resource_id=int(website_id),
                archived=False,
            ):
                add(expiration_to_dict(exp))

        matched.sort(
            key=lambda row: (
                row.get("date") or "9999-99-99",
                row.get("expiration_type") or "",
                row.get("id") or 0,
            )
        )
        return matched


def format_expiration_label(exp: dict[str, Any]) -> str:
    exp_type = exp.get("expiration_type") or "unknown"
    labels = {
        "domain": "Domain registration",
        "ssl_certificate": "SSL certificate",
        "undeclared": "Website expiration",
        "warranty": "Warranty",
        "asset_field": "Custom field",
        "article_expiration": "Article",
    }
    return labels.get(exp_type, exp_type.replace("_", " ").title())


def extract_expiration_metadata(
    expirations: list[dict[str, Any]],
) -> tuple[list[tuple[str, str]], str | None]:
    rows: list[tuple[str, str]] = []
    warranty_candidates: list[str] = []

    for exp in expirations:
        label = format_expiration_label(exp)
        date = exp.get("date") or "unknown"
        exp_id = exp.get("id")
        obj_type = exp.get("expirationable_type") or ""
        obj_id = exp.get("expirationable_id")
        detail = date
        if exp_id is not None:
            ref = f"Hudu expiration #{exp_id}"
            if obj_type and obj_id is not None:
                ref += f" · {obj_type} #{obj_id}"
            elif obj_type:
                ref += f" · {obj_type}"
            detail = f"{date} ({ref})"
        rows.append((label, detail))

        exp_type = (exp.get("expiration_type") or "").lower()
        if exp_type in {"domain", "ssl_certificate", "undeclared"} and exp.get("date"):
            warranty_candidates.append(str(exp["date"]))

    warranty_end = min(warranty_candidates) if warranty_candidates else None
    return rows, warranty_end


def build_hudu_website_sync_notes(
    data: dict[str, Any],
    *,
    hudu_id: Any,
    company_name: str,
    name: str,
    hudu_instance_url: str,
    live_dns: bool,
    expirations: list[dict[str, Any]] | None = None,
) -> str:
    """
    Plaintext notes layout for Halo records (assets today; services use the same body).

    Halo does not render HTML in notes — URLs are listed explicitly so they stay copyable.
    """
    user_notes = (data.get("notes") or "").strip()
    domain = normalize_website_name(name) or name
    site_url = normalize_external_url(name)
    hudu_url = build_hudu_record_url(hudu_instance_url, data)

    overview: list[tuple[str, str]] = [
        ("Hudu website ID", str(hudu_id)),
    ]
    if company_name:
        overview.append(("Company", company_name))
    if domain:
        overview.append(("Domain", domain))
    if site_url:
        overview.append(("Live website", site_url))
    if hudu_url:
        overview.append(("Hudu record", hudu_url))
    if data.get("refreshed_at"):
        overview.append(("Last refreshed in Hudu", str(data["refreshed_at"])))

    sections: list[str] = [
        "HUDU WEBSITE",
        format_notes_section("Overview", overview),
    ]

    if user_notes:
        sections.append(format_notes_section("Notes from Hudu", [("Notes", user_notes)]))

    all_monitoring_rows = list(extract_hudu_dns_metadata(data))
    if live_dns:
        if data.get("disable_dns"):
            all_monitoring_rows.append(
                (
                    "Hudu DNS monitoring",
                    "Paused in Hudu; live lookup below is independent of Hudu checks",
                )
            )
        all_monitoring_rows.extend(lookup_live_dns(domain))

    monitoring_rows, live_dns_rows = split_hudu_and_live_dns_rows(all_monitoring_rows)
    monitoring_block = format_notes_section("Monitoring (Hudu)", monitoring_rows)
    if monitoring_block:
        sections.append(monitoring_block)
    live_block = format_notes_section("Live DNS lookup", live_dns_rows)
    if live_block:
        sections.append(live_block)

    if expirations:
        exp_rows, _ = extract_expiration_metadata(expirations)
        exp_block = format_notes_section("Expirations", exp_rows)
        if exp_block:
            sections.append(exp_block)

    sections.append(f"{NOTES_SYNC_FOOTER} · website #{hudu_id}")
    return "\n\n".join(part for part in sections if part)


def build_asset_notes(
    data: dict[str, Any],
    *,
    hudu_id: Any,
    company_name: str,
    name: str,
    hudu_instance_url: str,
    live_dns: bool,
    expirations: list[dict[str, Any]] | None = None,
) -> str:
    return build_hudu_website_sync_notes(
        data,
        hudu_id=hudu_id,
        company_name=company_name,
        name=name,
        hudu_instance_url=hudu_instance_url,
        live_dns=live_dns,
        expirations=expirations,
    )


def website_inventory_number(hudu_website_id: int | str) -> str:
    return f"{HUDU_WEBSITE_INVENTORY_PREFIX}{hudu_website_id}"


def normalize_website_name(name: str | None) -> str:
    if not name:
        return ""
    name = name.strip()
    if "://" not in name:
        name = f"https://{name}"
    parsed = urlparse(name)
    host = parsed.netloc or parsed.path
    return host.strip("/") or name


def normalize_external_url(url: str | None) -> str:
    """Ensure a browsable URL (used for website name / live site link)."""
    if not url:
        return ""
    url = url.strip()
    if "://" not in url:
        url = f"https://{url}"
    return url


def build_hudu_record_url(instance_url: str, data: dict[str, Any]) -> str:
    """Hudu website path from API (e.g. /websites/{slug}) joined to instance base."""
    path = (data.get("url") or data.get("full_url") or "").strip()
    if not path:
        return ""
    if path.startswith("http://") or path.startswith("https://"):
        return path
    base = instance_url.rstrip("/")
    if not path.startswith("/"):
        path = f"/{path}"
    return f"{base}{path}"


class HaloClient:
    def __init__(self, base_url: str, client_id: str, client_secret: str, tenant: str):
        self.base_url = base_url.rstrip("/")
        self.client_id = client_id
        self.client_secret = client_secret
        self.tenant = tenant
        self._token: str | None = None
        self.http = httpx.Client(timeout=60)

    def token(self) -> str:
        if self._token:
            return self._token

        r = self.http.post(
            f"{self.base_url}/auth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "scope": "all",
                "tenant": self.tenant,
            },
        )
        r.raise_for_status()
        self._token = r.json()["access_token"]
        return self._token

    def request(self, method: str, path: str, **kwargs) -> Any:
        r = self.http.request(
            method,
            f"{self.base_url}/api/{path.lstrip('/')}",
            headers={"Authorization": f"Bearer {self.token()}"},
            **kwargs,
        )
        r.raise_for_status()
        return r.json() if r.content else None

    def list_clients(self) -> list[dict]:
        data = self.request("GET", "Client", params={"pageinate": False})
        return data.get("clients") or []

    def list_sites(self, client_id: int) -> list[dict]:
        data = self.request("GET", "Site", params={"client_id": client_id, "pageinate": False})
        return data.get("sites") or []

    def list_assets(self, *, assettype_id: int | None = None) -> list[dict]:
        """Load all matching assets (Halo caps unpaginated responses at 50)."""
        page_size = 100
        page_no = 1
        all_assets: list[dict] = []

        while True:
            params: dict[str, Any] = {
                "pageinate": True,
                "page_no": page_no,
                "page_size": page_size,
            }
            if assettype_id is not None:
                params["assettype_id"] = assettype_id

            data = self.request("GET", "Asset", params=params)
            batch = data.get("assets") or []
            all_assets.extend(batch)

            record_count = int(data.get("record_count") or 0)
            if not batch or len(all_assets) >= record_count:
                break
            page_no += 1

        return all_assets

    def find_asset_by_inventory_exact(
        self,
        inventory: str,
        *,
        assettype_id: int | None = None,
    ) -> dict | None:
        """
        Halo's inventory_number filter is prefix-based (e.g. ID-2 matches ID-20).
        Always confirm an exact inventory_number match in results.
        """
        params: dict[str, Any] = {
            "inventory_number": inventory,
            "search_inventory_number_only": True,
            "pageinate": False,
        }
        if assettype_id is not None:
            params["assettype_id"] = assettype_id

        data = self.request("GET", "Asset", params=params)
        for asset in data.get("assets") or []:
            if (asset.get("inventory_number") or "") == inventory:
                return asset
        return None

    def list_asset_types(self) -> list[dict]:
        data = self.request("GET", "AssetType", params={"pageinate": False})
        return data if isinstance(data, list) else data.get("assettypes") or []

    def get_asset_type(self, assettype_id: int) -> dict:
        return self.request("GET", f"AssetType/{assettype_id}")

    def upsert_asset(self, payload: dict) -> dict:
        result = self.request("POST", "Asset", json=[payload])
        if isinstance(result, list):
            return result[0]
        return result


def resolve_asset_type_id(halo: HaloClient, type_name: str) -> int:
    needle = type_name.strip().lower()
    if not needle:
        raise SystemExit("HALO_ASSET_TYPE_NAME must not be empty")

    types = halo.list_asset_types()
    matches = [
        t for t in types if (t.get("name") or "").strip().lower() == needle
    ]
    if len(matches) == 1:
        return int(matches[0]["id"])

    if len(matches) > 1:
        ids = ", ".join(str(t["id"]) for t in matches)
        raise SystemExit(
            f"Multiple Halo asset types named {type_name!r} (ids: {ids}). "
            "Rename duplicates in Halo or use a unique name."
        )

    available = sorted({t.get("name") for t in types if t.get("name")})
    raise SystemExit(
        f"No Halo asset type named {type_name!r}. "
        f"Available types: {', '.join(available)}"
    )


def build_halo_asset_fields(
    asset_type: dict,
    metadata: dict[str, str],
    field_map: dict[str, str],
    existing_asset: dict | None,
) -> list[dict]:
    """
    Map Hudu metadata keys to Halo asset-type field names (case-insensitive).

    field_map: Halo field label -> Hudu metadata key (e.g. {"Last DNS check": "refreshed_at"})
    """
    type_fields = asset_type.get("fields") or []
    if not type_fields or not field_map:
        return []

    existing_values = {
        (f.get("name") or "").strip().lower(): f
        for f in (existing_asset or {}).get("fields") or []
    }
    payload_fields: list[dict] = []

    for field_def in type_fields:
        label = (field_def.get("field_name") or field_def.get("name") or "").strip()
        if not label:
            continue
        hudu_key = field_map.get(label) or field_map.get(label.lower())
        if not hudu_key or hudu_key not in metadata:
            continue

        entry = {
            "id": int(field_def.get("field_id") or field_def.get("id")),
            "name": label,
            "value": format_metadata_value(metadata[hudu_key]),
        }
        existing = existing_values.get(label.lower())
        if existing and existing.get("typeinfo_id"):
            entry["typeinfo_id"] = existing["typeinfo_id"]
        payload_fields.append(entry)

    return payload_fields


class CompanyResolver:
    def __init__(
        self,
        halo_clients: list[dict],
        *,
        client_map: dict[int, int],
        default_client_id: int | None,
    ):
        self.client_map = client_map
        self.default_client_id = default_client_id
        self.by_hudu_company_id = client_map
        self.by_name: dict[str, int] = {}
        for client in halo_clients:
            name = (client.get("name") or "").strip().lower()
            if name:
                self.by_name[name] = int(client["id"])

    def resolve(self, hudu_company_id: int | None, company_name: str | None) -> int | None:
        if hudu_company_id is not None and hudu_company_id in self.by_hudu_company_id:
            return self.by_hudu_company_id[hudu_company_id]
        if company_name:
            mapped = self.by_name.get(company_name.strip().lower())
            if mapped is not None:
                return mapped
        return self.default_client_id


class SiteResolver:
    def __init__(self, halo: HaloClient):
        self.halo = halo
        self._cache: dict[int, int] = {}

    def resolve(self, client_id: int) -> int | None:
        if client_id in self._cache:
            return self._cache[client_id]

        sites = self.halo.list_sites(client_id)
        if not sites:
            return None

        primary = next(
            (s for s in sites if s.get("isprimary") or s.get("is_primary")),
            None,
        )
        chosen = primary or sites[0]
        site_id = int(chosen["id"])
        self._cache[client_id] = site_id
        return site_id


def build_halo_payload(
    website: Any,
    *,
    assettype_id: int,
    asset_type: dict,
    client_id: int,
    site_id: int,
    existing: dict | None,
    live_dns: bool,
    halo_field_map: dict[str, str],
    expirations: list[dict[str, Any]] | None = None,
) -> dict:
    data = website.to_dict() if hasattr(website, "to_dict") else dict(website)
    hudu_id = data.get("id")
    name = data.get("name") or ""
    company_name = data.get("company_name") or ""

    metadata: dict[str, Any] = dict(data)
    for label, value in extract_hudu_dns_metadata(data):
        metadata[label] = value
    expirations = expirations or []
    sync_notes = build_asset_notes(
        data,
        hudu_id=hudu_id,
        company_name=company_name,
        name=name,
        hudu_instance_url=require_env("HUDU_INSTANCE_URL"),
        live_dns=live_dns,
        expirations=expirations,
    )
    _, warranty_end = extract_expiration_metadata(expirations)

    payload: dict[str, Any] = {
        "inventory_number": website_inventory_number(hudu_id),
        "key_field": normalize_website_name(name) or name,
        "client_id": client_id,
        "site_id": site_id,
        "assettype_id": assettype_id,
        "notes": sync_notes,
        "inactive": False,
    }
    if warranty_end:
        payload["warranty_end"] = warranty_end
        payload["warranty_note"] = "Nearest domain/SSL expiry from Hudu expirations"

    asset_fields = build_halo_asset_fields(
        asset_type, metadata, halo_field_map, existing
    )
    if asset_fields:
        payload["fields"] = asset_fields

    if existing:
        payload["id"] = existing["id"]
    return payload


def index_hudu_website_assets(assets: list[dict]) -> dict[str, dict]:
    indexed: dict[str, dict] = {}
    for asset in assets:
        inv = asset.get("inventory_number") or ""
        if not inv.startswith(HUDU_WEBSITE_INVENTORY_PREFIX):
            continue
        # Keep the first exact match only (index is keyed by full inventory string).
        indexed.setdefault(inv, asset)
    return indexed


def resolve_existing_halo_asset(
    halo: HaloClient,
    inventory: str,
    *,
    assettype_id: int,
    cache: dict[str, dict],
) -> dict | None:
    if inventory in cache:
        return cache[inventory]
    found = halo.find_asset_by_inventory_exact(inventory, assettype_id=assettype_id)
    if found:
        cache[inventory] = found
    return found


def sync_websites(*, dry_run: bool = False) -> int:
    load_env_file()

    hudu = HuduClient(
        api_key=require_env("HUDU_API_KEY"),
        instance_url=require_env("HUDU_INSTANCE_URL"),
    )
    halo = HaloClient(
        base_url=require_env("HALO_BASE_URL"),
        client_id=require_env("HALO_CLIENT_ID"),
        client_secret=require_env("HALO_CLIENT_SECRET"),
        tenant=require_env("HALO_TENANT"),
    )

    asset_type_name = require_env("HALO_ASSET_TYPE_NAME")
    assettype_id = resolve_asset_type_id(halo, asset_type_name)
    asset_type = halo.get_asset_type(assettype_id)
    print(f"Using Halo asset type {asset_type_name!r} (id={assettype_id})")

    live_dns = env_flag("SYNC_LIVE_DNS")
    if live_dns:
        print("Live DNS lookups enabled (Cloudflare DoH)")

    halo_field_map: dict[str, str] = {}
    raw_field_map = os.getenv("HALO_WEBSITE_FIELD_MAP")
    if raw_field_map:
        try:
            halo_field_map = json.loads(raw_field_map)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid HALO_WEBSITE_FIELD_MAP JSON: {exc}") from exc

    default_client_id_raw = os.getenv("HALO_DEFAULT_CLIENT_ID")
    default_client_id = int(default_client_id_raw) if default_client_id_raw else None
    client_map = parse_client_map(os.getenv("HUDU_HALO_CLIENT_MAP"))

    company_resolver = CompanyResolver(
        halo.list_clients(),
        client_map=client_map,
        default_client_id=default_client_id,
    )
    site_resolver = SiteResolver(halo)
    halo_assets = halo.list_assets(assettype_id=assettype_id)
    existing_by_inventory = index_hudu_website_assets(halo_assets)
    print(
        f"Indexed {len(existing_by_inventory)} existing website assets "
        f"(from {len(halo_assets)} {asset_type_name!r} assets in Halo)"
    )

    all_expirations = list_all_hudu_expirations(hudu)
    expiration_index = ExpirationIndex(all_expirations)
    website_linked = sum(len(v) for v in expiration_index.by_website_id.values())
    print(
        f"Loaded {len(all_expirations)} Hudu expirations "
        f"({website_linked} linked to websites by ID)"
    )

    websites = hudu.websites.list()
    stats = {"created": 0, "updated": 0, "unchanged": 0, "skipped": 0}

    for website in websites:
        data = website.to_dict() if hasattr(website, "to_dict") else dict(website)
        hudu_id = data.get("id")
        company_id = data.get("company_id")
        company_name = data.get("company_name")
        name = data.get("name") or f"website-{hudu_id}"

        if hudu_id is None:
            stats["skipped"] += 1
            print(f"SKIP  missing id for {name!r}")
            continue

        halo_client_id = company_resolver.resolve(company_id, company_name)
        if halo_client_id is None:
            stats["skipped"] += 1
            print(
                f"SKIP  {name} (hudu company {company_id} / {company_name!r}) — "
                "no Halo client match (set HUDU_HALO_CLIENT_MAP or HALO_DEFAULT_CLIENT_ID)"
            )
            continue

        halo_site_id = site_resolver.resolve(halo_client_id)
        if halo_site_id is None:
            stats["skipped"] += 1
            print(f"SKIP  {name} — Halo client {halo_client_id} has no sites")
            continue

        inventory = website_inventory_number(hudu_id)
        existing = resolve_existing_halo_asset(
            halo,
            inventory,
            assettype_id=assettype_id,
            cache=existing_by_inventory,
        )

        # Refresh single record so monitoring timestamps/headers are current.
        try:
            website = hudu.websites.get(hudu_id)
        except Exception:
            pass

        website_data = (
            website.to_dict() if hasattr(website, "to_dict") else dict(website)
        )
        matched_expirations = expiration_index.match_for_website(
            website_data, hudu=hudu
        )

        payload = build_halo_payload(
            website,
            assettype_id=assettype_id,
            asset_type=asset_type,
            client_id=halo_client_id,
            site_id=halo_site_id,
            existing=existing,
            live_dns=live_dns,
            halo_field_map=halo_field_map,
            expirations=matched_expirations,
        )

        if existing:
            same = (
                (existing.get("key_field") or "") == payload["key_field"]
                and int(existing.get("client_id") or 0) == halo_client_id
                and int(existing.get("site_id") or 0) == halo_site_id
                and int(existing.get("assettype_id") or 0) == assettype_id
                and (existing.get("notes") or "") == payload["notes"]
                and (existing.get("fields") or []) == (payload.get("fields") or [])
                and str(existing.get("warranty_end") or "")[:10]
                == str(payload.get("warranty_end") or "")[:10]
            )
            if same:
                stats["unchanged"] += 1
                print(f"OK    {inventory} unchanged ({payload['key_field']})")
                continue
            action = "UPDATE"
            stats["updated"] += 1
        else:
            action = "CREATE"
            stats["created"] += 1

        exp_count = len(matched_expirations)
        exp_suffix = f", {exp_count} expiration(s)" if exp_count else ""
        print(
            f"{action} {inventory} -> client {halo_client_id}, "
            f"site {halo_site_id}, key {payload['key_field']!r}{exp_suffix}"
        )
        if dry_run:
            continue

        saved = halo.upsert_asset(payload)
        existing_by_inventory[inventory] = saved

    print(
        "\nDone. "
        f"created={stats['created']} updated={stats['updated']} "
        f"unchanged={stats['unchanged']} skipped={stats['skipped']} "
        f"(dry_run={dry_run})"
    )
    return 0 if stats["skipped"] == 0 else 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync Hudu websites into Halo PSA assets")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned creates/updates without calling Halo write APIs",
    )
    args = parser.parse_args()
    try:
        sync_websites(dry_run=args.dry_run)
    except httpx.HTTPStatusError as exc:
        print(f"Halo API error: {exc.response.status_code} {exc.response.text[:500]}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
