"""
Typical patterns using the resource-oriented API.

Environment:
  HUDU_API_KEY          — required
  HUDU_INSTANCE_URL     — required (e.g. https://your-instance.hudu.app)

Optional:
  HUDU_COMPANY_ID       — if set, loads that company and lists its articles/assets
"""

from __future__ import annotations

import os
import sys

from hudu_magic import HuduClient


def main() -> None:
    key = os.environ.get("HUDU_API_KEY")
    url = os.environ.get("HUDU_INSTANCE_URL")
    if not key or not url:
        print("Set HUDU_API_KEY and HUDU_INSTANCE_URL.", file=sys.stderr)
        sys.exit(1)

    client = HuduClient(api_key=key, instance_url=url)

    print("API version:", client.check_version())

    users = client.users.list()
    print(f"Users: {len(users)}")

    layouts = client.asset_layouts.list()
    print(f"Asset layouts: {len(layouts)}")
    if layouts:
        sample = layouts[0]
        print(f"  example layout id={sample.id!r} name={getattr(sample, 'name', None)!r}")

    company_id = os.environ.get("HUDU_COMPANY_ID")
    if not company_id:
        print("Set HUDU_COMPANY_ID to see company-scoped list examples.")
        return

    cid = int(company_id)
    company = client.companies.get(cid)
    print(f"Company: id={company.id} name={company.name!r}")

    articles = company.list_articles()
    print(f"Articles for company {cid}: {len(articles)}")

    assets = client.assets.list_for_company(cid)
    print(f"Assets for company {cid}: {len(assets)}")


if __name__ == "__main__":
    main()
