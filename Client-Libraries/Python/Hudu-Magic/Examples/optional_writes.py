"""
Opt-in create / update / delete examples (same patterns as integration tests).

Set HUDU_ALLOW_WRITES=1 or this script exits without calling the API.

Requires:
  HUDU_API_KEY, HUDU_INSTANCE_URL
  HUDU_COMPANY_ID       — company to attach the temporary article to
  HUDU_ASSET_LAYOUT_ID  — valid layout id for that instance (see asset_layouts.list())

Creates one article, updates content, then deletes it.
"""

from __future__ import annotations

import os
import sys
import uuid

from hudu_magic import HuduClient


def main() -> None:
    if os.environ.get("HUDU_ALLOW_WRITES") != "1":
        print(
            "Skipping mutations. Set HUDU_ALLOW_WRITES=1 plus "
            "HUDU_COMPANY_ID and HUDU_ASSET_LAYOUT_ID to run.",
            file=sys.stderr,
        )
        sys.exit(0)

    key = os.environ.get("HUDU_API_KEY")
    url = os.environ.get("HUDU_INSTANCE_URL")
    company_raw = os.environ.get("HUDU_COMPANY_ID")
    layout_raw = os.environ.get("HUDU_ASSET_LAYOUT_ID")
    if not key or not url or not company_raw or not layout_raw:
        print(
            "Need HUDU_API_KEY, HUDU_INSTANCE_URL, HUDU_COMPANY_ID, HUDU_ASSET_LAYOUT_ID.",
            file=sys.stderr,
        )
        sys.exit(1)

    company_id = int(company_raw)
    layout_id = int(layout_raw)
    client = HuduClient(api_key=key, instance_url=url)

    suffix = uuid.uuid4().hex[:8]
    article = client.articles.create(
        payload={
            "name": f"hudu-magic example {suffix}",
            "content": "created by examples/optional_writes.py",
            "company_id": company_id,
        },
    )
    print("created article", article.id, article.name)

    article.content = "updated content"
    article.save()
    print("updated article content")

    # Asset under a company (layout id must exist in your Hudu instance)
    asset = client.assets.create(
        company_id=company_id,
        payload={"name": f"example asset {suffix}", "asset_layout_id": layout_id},
    )
    print("created asset", asset.id, asset.name)

    asset.archive()
    print("archived asset")
    asset.unarchive()
    print("unarchived asset")

    asset.delete()
    print("deleted asset")

    article.delete()
    print("deleted article")


if __name__ == "__main__":
    main()
