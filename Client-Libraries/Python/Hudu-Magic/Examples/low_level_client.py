"""
Using HuduClient.get() with enum members that have a concrete path (no {placeholders}).

Looping client.get() over every HuduEndpoint is unsafe: templated paths like
companies/{company_id}/assets would be requested literally and fail.

This script only calls a few list-friendly endpoints. Prefer client.users.list(),
client.companies.get(id), etc. for day-to-day use.

Environment:
  HUDU_API_KEY, HUDU_INSTANCE_URL — required
"""

from __future__ import annotations

import os
import sys

from hudu_magic import HuduClient, HuduEndpoint


def main() -> None:
    key = os.environ.get("HUDU_API_KEY")
    url = os.environ.get("HUDU_INSTANCE_URL")
    if not key or not url:
        print("Set HUDU_API_KEY and HUDU_INSTANCE_URL.", file=sys.stderr)
        sys.exit(1)

    client = HuduClient(api_key=key, instance_url=url)

    # String paths work for simple GETs
    info = client.get("api_info")
    print("api_info:", info if isinstance(info, dict) else type(info))

    # Enum members with no path template are safe for list-style GETs
    safe_for_global_list = (
        HuduEndpoint.USERS,
        HuduEndpoint.GROUPS,
        HuduEndpoint.COMPANIES,
        HuduEndpoint.ASSET_LAYOUTS,
    )

    for ep in safe_for_global_list:
        data = client.get(ep)
        n = len(data) if hasattr(data, "__len__") else "?"
        print(f"{ep.name}: {n} items (wrapped models or raw list)")


if __name__ == "__main__":
    main()
