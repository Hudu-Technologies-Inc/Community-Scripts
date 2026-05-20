# halosync

Sync Hudu websites into Halo PSA (assets or services).

## Setup

### 1. construct environment

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### 2. fill out environment variables

***vim/nano/emacs/notepad etc***

```
cp .env.example .env
```

## Run

```bash
source .env
python Sync-Websites.py --dry-run   # preview
python Sync-Websites.py             # sync
```

## Notes format

Halo stores notes as **plain text** (HTML links are not rendered). The sync builds a consistent layout:

- **Overview** — Hudu ID, company, domain, live website URL, Hudu record URL
- **Notes from Hudu** — original website notes (if any)
- **Monitoring (Hudu)** — DNS/SSL/WHOIS flags and timestamps from Hudu
- **Live DNS lookup** — optional (`SYNC_LIVE_DNS=1`), SPF/DMARC/TXT/MX from Cloudflare DoH
- **Expirations** — matched Hudu expirations (domain, SSL, etc.)

The formatter is `build_hudu_website_sync_notes()` in `Sync-Websites.py` and can be applied to objects other than Assets in Halo if desired

## Idempotency

Assets are matched by inventory tag: `hudu-website-ID-{hudu_website_id}` (exact lookup; Halo’s inventory filter is prefix-based).
