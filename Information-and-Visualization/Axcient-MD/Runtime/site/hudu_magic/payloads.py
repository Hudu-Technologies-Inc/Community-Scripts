import math

from hudu_magic.constants import (
    COMPANY_PROPERTIES_TO_POP_ON_SAVE,
    FOLDER_PROPERTIES_TO_POP_ON_SAVE,
    IPAM_PROPERTIES_TO_POP_ON_SAVE,
    PASSWORD_PROPERTIES_TO_POP_ON_SAVE,
    PROPERTIES_TO_POP_ON_SAVE,
    WEBSITE_PROPERTIES_TO_POP_ON_SAVE,
)
from hudu_magic.endpoints import HuduEndpoint

RESOURCE_WRAPPERS = {
    "asset_layouts": "asset_layout",
    "companies": "company",
    "articles": "article",
    "exports": "export",
    "folders": "folder",
    "websites": "website",
    "asset_passwords": "asset_password",
    "password_folders": "password_folder",
    "networks": "network",
    "vlans": "vlan",
    "vlan_zones": "vlan_zone",
    "rack_storages": "rack_storage",
    "photos": "photo",
    "uploads": "upload",
    "lists": "list",
    "flags": "flag",
    "flag_types": "flag_type",
    "procedure_tasks": "procedure_task",
    "relations": "relation",
    "assets": "asset",
    "asset_layouts_move_layout": "asset",
}


def maybe_wrap_payload(endpoint: HuduEndpoint | str, payload: dict) -> dict:
    if not isinstance(endpoint, HuduEndpoint):
        return payload

    endpoint_key = endpoint.endpoint.replace("/{id}", "")
    wrapper = RESOURCE_WRAPPERS.get(endpoint_key)

    if not wrapper:
        return payload

    if wrapper in payload:
        return payload

    return {wrapper: payload}


def normalize_asset_website_field_value(value):
    """
    Coerce a **Website** custom-field value for Hudu save: strip whitespace,
    require ``https://`` (upgrade ``http://``), and prepend ``https://`` when
    the scheme is missing.

    Non-strings and ``None`` are returned unchanged. Empty after strip returns
    ``""`` so callers can clear a field.
    """
    if value is None or not isinstance(value, str):
        return value
    stripped = value.strip()
    if not stripped:
        return stripped
    lower = stripped.lower()
    if lower.startswith("https://"):
        return stripped
    if lower.startswith("http://"):
        return f"https://{stripped[7:]}"
    return f"https://{stripped}"


def normalize_asset_number_field_value(value):
    """
    Coerce a **Number** custom-field value to a JSON integer for Hudu (no ``.0``
    floats). Whole floats and numeric strings become ``int``; fractional values
    use ``round`` before converting.

    ``None`` is unchanged. ``bool`` is unchanged (avoids ``bool`` being treated
    as ``0``/``1``). Unparseable strings and non-numeric types are returned as-is.
    """
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            return value
        return int(round(value))
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return value
        try:
            d = float(s)
        except ValueError:
            return value
        if not math.isfinite(d):
            return value
        return int(round(d))
    return value


def transform_asset_fields_for_save(fields):
    """
    Convert GET-style **asset** custom field rows (per-asset ``fields``) for save.

    This is **not** for asset **layout** definition fields; use
    :func:`hudu_magic.helpers.asset_layouts.layout_fields_for_create` for layout
    templates.

    **Website** fields (``field_type`` ``Website``): ``value`` is normalized with
    :func:`normalize_asset_website_field_value` so bare hosts and ``http://``
    become ``https://``, matching typical Hudu validation.

    **Number** fields (``field_type`` ``Number``): ``value`` is normalized with
    :func:`normalize_asset_number_field_value` so floats like ``1.0`` and strings
    like ``"42"`` become integers.

    **ListSelect** (``field_type`` ``ListSelect``): GET responses often expose
    selected options as IDs or structured JSON, while create/update bodies expect
    the **list item label** (or labels for multi-select). This function does **not**
    call the Lists API; resolve IDs to names in your integration (for example via
    ``client.lists``) before save, or pass values already in write shape.
    """
    transformed = []

    for field in fields:
        if isinstance(field, dict):
            # GET-style field object
            if "label" in field:
                key = field["label"].replace(" ", "_").lower()
                value = field.get("value")
                ft = (field.get("field_type") or "").strip().lower()
                if ft == "website":
                    value = normalize_asset_website_field_value(value)
                elif ft == "number":
                    value = normalize_asset_number_field_value(value)
                transformed.append({key: value})
                continue

            # already in write-shape
            if len(field) == 1:
                transformed.append(field)
                continue

        transformed.append(field)

    return transformed


def transform_custom_fields_for_save(fields):
    """
    Convert Hudu GET-style custom fields:
        [{"label": "Installed At", "value": None}, ...]
    into Hudu PUT/POST-style custom fields:
        [{"Installed At": None}, ...]
    """
    if not isinstance(fields, list):
        return fields

    transformed = []

    for field in fields:
        if isinstance(field, dict):
            # already in write-shape like {"Installed At": None}
            if "label" not in field and "value" not in field and len(field) == 1:
                transformed.append(field)
                continue

            label = field.get("label")
            value = field.get("value")

            if label is not None:
                transformed.append({label: value})
                continue

        transformed.append(field)
    return transformed


def clean_payload(payload: dict) -> dict:
    return {
        k: v
        for k, v in payload.items()
        if k not in PROPERTIES_TO_POP_ON_SAVE and v is not None
    }


def normalize_asset_payload_for_save(data: dict) -> dict:
    allowed = {
        "name",
        "asset_layout_id",
        "company_id",
        "slug",
        "primary_serial",
        "primary_model",
        "primary_mail",
        "primary_manufacturer",
        "custom_fields",
    }

    payload = {k: v for k, v in data.items() if k in allowed and v is not None}

    if "fields" in data and "custom_fields" not in payload:
        payload["custom_fields"] = transform_asset_fields_for_save(
            data["fields"]
        )
    return payload


def normalize_company_payload_for_save(data: dict) -> dict:
    return {k: v for k, v in data.items()
            if k not in COMPANY_PROPERTIES_TO_POP_ON_SAVE and v is not None}


def normalize_password_payload_for_save(data: dict) -> dict:
    return {k: v for k, v in data.items()
            if k not in PASSWORD_PROPERTIES_TO_POP_ON_SAVE and v is not None}


def normalize_website_payload_for_save(data: dict) -> dict:
    return {k: v for k, v in data.items()
            if k not in WEBSITE_PROPERTIES_TO_POP_ON_SAVE and v is not None}


def normalize_folder_payload_for_save(data: dict) -> dict:
    return {k: v for k, v in data.items()
            if k not in FOLDER_PROPERTIES_TO_POP_ON_SAVE and v is not None}


def normalize_ipam_payload_for_save(data: dict) -> dict:
    return {k: v for k, v in data.items()
            if k not in IPAM_PROPERTIES_TO_POP_ON_SAVE and v is not None}


def normalize_procedure_payload_for_save(data: dict) -> dict:
    """Fields allowed on ``PUT /procedures/{id}`` per OpenAPI (e.g. Hudu 2.41.0)."""
    allowed = frozenset({"name", "description", "archived"})
    return {k: v for k, v in data.items() if k in allowed and v is not None}


def strip_run_only_fields_from_payload(data: dict) -> dict:
    from hudu_magic.constants import PROCEDURE_TASK_RUN_ONLY_FIELDS
    return {k: v for k, v in data.items() 
            if k not in PROCEDURE_TASK_RUN_ONLY_FIELDS and v is not None}
