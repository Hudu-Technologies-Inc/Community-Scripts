"""
Inspect generated OpenAPI metadata (no network calls).

Default: compact table of every HuduEndpoint.

  python endpoint_catalog.py
  python endpoint_catalog.py --detail COMPANIES
  python endpoint_catalog.py --detail ARTICLES
"""

from __future__ import annotations

import argparse

from hudu_magic.endpoints import HuduEndpoint
from hudu_magic.help import describe_single


def _ops(meta) -> str:
    parts = []
    if meta.supports_list:
        parts.append("list")
    if meta.supports_get:
        parts.append("get")
    if meta.supports_create:
        parts.append("create")
    if meta.supports_update:
        parts.append("update")
    if meta.supports_delete:
        parts.append("delete")
    if meta.supports_archive:
        parts.append("archive")
    if meta.supports_unarchive:
        parts.append("unarchive")
    return ",".join(parts) or "—"


def main() -> None:
    parser = argparse.ArgumentParser(description="Browse HuduEndpoint metadata.")
    parser.add_argument(
        "--detail",
        metavar="NAME",
        help="Enum member name, e.g. COMPANIES or ASSETS (see table first column).",
    )
    args = parser.parse_args()

    if args.detail:
        try:
            ep = HuduEndpoint[args.detail]
        except KeyError:
            print(f"Unknown endpoint {args.detail!r}. Use a name from the first column below.")
            args.detail = None
        else:
            print(describe_single(ep))
            return

    rows = sorted(HuduEndpoint, key=lambda e: (e.meta.tag or "", e.endpoint))
    tag_w = max(len(e.meta.tag or "") for e in rows)
    name_w = max(len(e.name) for e in rows)
    path_w = max(len(e.endpoint) for e in rows)

    print(
        f"{'NAME':<{name_w}}  {'PATH':<{path_w}}  {'TAG':<{tag_w}}  "
        f"PATH_TEMPLATE  OPERATIONS"
    )
    print("-" * (name_w + path_w + tag_w + 40))

    for ep in rows:
        m = ep.meta
        templated = "yes" if "{" in m.path else "no"
        print(
            f"{ep.name:<{name_w}}  {ep.endpoint:<{path_w}}  "
            f"{(m.tag or ''):<{tag_w}}  {templated:<13}  {_ops(m)}"
        )

    print(
        "\nPass --detail NAME for path/query/create field help "
        "(NAME is the first column, e.g. COMPANIES)."
    )


if __name__ == "__main__":
    main()
