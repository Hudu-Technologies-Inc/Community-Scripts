from __future__ import annotations

from hudu_magic.endpoints import EndpointMeta, FieldMeta, HuduEndpoint

# consume endpoint metadata and produce human-readable descriptions for each
# explains what fields it accepts, for use in error messages and help commands
# This is not intended to be comprehensive documentation
# just enough to help users understand how to interact with the SDK when they
# encounter an error or want a quick reminder of how an endpoint works.


def describe(endpoint: HuduEndpoint) -> str:
    family = get_endpoint_family(endpoint)
    lines = [f"Family: {family_key(endpoint)}"]

    for ep in family:
        lines.append("")
        lines.extend(describe_endpoint(ep))

    return "\n".join(lines).strip()


def describe_single(endpoint: HuduEndpoint) -> str:
    return "\n".join(describe_endpoint(endpoint))


def describe_endpoint(endpoint: HuduEndpoint) -> list[str]:
    meta = endpoint.meta
    lines = [f"- {meta.tag} ({endpoint.path})"]

    methods = supported_methods(meta)
    lines.append(f"  Methods: {', '.join(methods) if methods else 'None'}")

    lines.extend(format_fields_block("Path params", meta.path_params, indent="  "))
    lines.extend(format_fields_block("Query params", meta.query_params, indent="  "))
    lines.extend(format_fields_block("Create fields", meta.create_fields, indent="  "))
    lines.extend(format_fields_block("Update fields", meta.update_fields, indent="  "))

    return lines


def family_key(endpoint: HuduEndpoint) -> str:
    return endpoint.path.split("/", 1)[0]


def get_endpoint_family(endpoint: HuduEndpoint) -> list[HuduEndpoint]:
    key = family_key(endpoint)
    related = [ep for ep in HuduEndpoint if family_key(ep) == key]
    return sorted(related, key=endpoint_sort_key)


def endpoint_sort_key(endpoint: HuduEndpoint) -> tuple[int, int, str]:
    path = endpoint.path
    depth = path.count("/")

    if "{" not in path:
        kind = 0
    elif path.endswith("}"):
        kind = 1
    else:
        kind = 2

    return (kind, depth, path)


def supported_methods(meta: EndpointMeta) -> list[str]:
    if getattr(meta, "methods", None):
        return list(meta.methods)

    methods: list[str] = []
    if meta.supports_get or meta.supports_list:
        methods.append("GET")
    if meta.supports_create:
        methods.append("POST")
    if meta.supports_update:
        methods.append("PUT")
    if meta.supports_delete:
        methods.append("DELETE")
    return methods


def format_fields_block(
    title: str,
    fields: dict[str, FieldMeta] | None,
    indent: str = "",
) -> list[str]:
    if not fields:
        return []

    lines = [f"{indent}{title}:"]
    for name, field in fields.items():
        req = "required" if field.required else "optional"
        field_type = field.type or "any"
        lines.append(f"{indent}  - {name}: {field_type} ({req})")
        if field.description:
            lines.append(f"{indent}      {field.description}")
    return lines