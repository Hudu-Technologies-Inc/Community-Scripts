from __future__ import annotations

import ipaddress
from pathlib import Path
from typing import Any

from .constants import (
    ALLOWED_PHOTO_EXTS,
    ALLOWED_PHOTOABLE_TYPES,
    ALLOWED_PUBLIC_PHOTOABLE_TYPES,
    ALLOWED_PUBPHOTO_EXTS,
    ALLOWED_UPLOADABLE_TYPES,
    FALSY_VALUES,
    FROMABLE_TOABLE_TYPES,
    LABELABLE_TYPES,
    TRUTHY_VALUES,
    VLAN_ID_RANGES_PATTERN,
)
from .endpoints import FieldMeta, HuduEndpoint
from .help import format_fields_block, supported_methods


class HuduError(Exception):
    """Base exception for hudu_magic."""


class HuduConfigurationError(HuduError):
    """Raised when client or instance configuration is invalid."""


class HuduAPIError(HuduError):
    """Raised when the Hudu API returns an error response."""

    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        super().__init__(f"Hudu API error ({status_code}): {message}")


class HuduValidationError(ValueError):
    """Raised when a request payload fails local SDK validation."""


class HuduNotImplementedError(NotImplementedError):
    """Raised when a requested operation is not implemented."""


def validate_relatables(fromable_endpoint: str, toable_endpoint: str) -> None:
    if fromable_endpoint not in FROMABLE_TOABLE_TYPES:
        raise HuduValidationError(
            f"Objects of type {fromable_endpoint} cannot be related to any other objects")

    if toable_endpoint not in FROMABLE_TOABLE_TYPES:
        raise HuduValidationError(
            f"Objects of type {toable_endpoint} cannot be related to any other objects")


def coerce_value(value: Any, meta: FieldMeta) -> Any:
    if value is None:
        return None

    if meta.enum and value not in meta.enum:
        raise ValueError(
            f"Invalid value for '{meta.name}': {value!r}. "
            f"Allowed: {meta.enum}"
        )

    if meta.type == "integer":
        return int(value)
    if meta.type == "boolean":
        if isinstance(value, bool):
            return to_bool(value)
    if meta.type == "number":
        return float(value)
    if meta.type == "array":
        if isinstance(value, list):
            return value
        return [value]
    if meta.type == "string":
        return str(value)

    return value


def coerce_and_validate_params(
    provided: dict[str, Any],
    field_map: dict[str, FieldMeta],
    *,
    context: str = "",
    required_fields: tuple[str, ...] = (),
    allow_unknown: bool = False,
) -> dict[str, Any]:
    result: dict[str, Any] = {}

    for name in required_fields:
        if name not in provided or provided[name] is None:
            raise ValueError(f"{context}: missing required field '{name}'")

    for key, value in provided.items():
        meta = field_map.get(key)
        if meta is None:
            if allow_unknown:
                result[key] = value
                continue
            raise ValueError(f"{context}: unknown field '{key}'")

        result[key] = coerce_value(value, meta)

    return result


def describe_payload(endpoint: HuduEndpoint, operation: str) -> str:
    meta = endpoint.meta
    lines = [f"{meta.tag} ({endpoint.path})"]

    if operation == "create":
        lines.extend(format_fields_block("Create fields", meta.create_fields))
    elif operation == "update":
        lines.extend(format_fields_block("Update fields", meta.update_fields))

    return "\n".join(lines)


def validate_payload(
    endpoint: HuduEndpoint,
    payload: dict[str, Any],
    operation: str,
    *,
    allow_unknown_fields: bool = False,
) -> None:
    if not isinstance(payload, dict):
        raise HuduValidationError("payload must be a dict")

    meta = endpoint.meta
    methods = ", ".join(supported_methods(meta))

    if operation == "create":
        if not meta.supports_create:
            raise HuduValidationError(
                f"{endpoint.name} does not support create. Supported methods:\n"
                f"{methods}"
            )
        required_fields = set(meta.create_required_fields or ())
        allowed_fields = set((meta.create_fields or {}).keys())

    elif operation == "update":
        if not meta.supports_update:
            raise HuduValidationError(
                f"{endpoint.name} does not support update. Supported methods:\n"
                f"{methods}"
            )
        required_fields = set(meta.update_required_fields or ())
        allowed_fields = set((meta.update_fields or {}).keys())

    else:
        raise HuduValidationError(f"Unsupported operation: {operation}")

    if allowed_fields and not allow_unknown_fields:
        unknown_fields = sorted(set(payload.keys()) - allowed_fields)
        if unknown_fields:
            raise HuduValidationError(
                f"Unknown field(s) for {endpoint.name} {operation}:\n"
                f"{', '.join(unknown_fields)}"
            )

    missing_required = sorted(
        field_name
        for field_name in required_fields
        if payload.get(field_name) in (None, "")
    )
    if missing_required:
        raise HuduValidationError(
            f"Missing required field(s) for {endpoint.name} {operation}:\n"
            f"{', '.join(missing_required)}"
        )


def validate_required_string(value: str, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(
            f"{field_name} is required and must be a non-empty string")
    return value


def validate_required_int(value: int, field_name: str) -> int:
    if not isinstance(value, int):
        raise ValueError(f"{field_name} is required and must be an integer")
    return value


def validate_int_range(value: int, field_name: str, minimum: int, maximum: int) -> int:
    validate_required_int(value, field_name)
    if not (minimum <= value <= maximum):
        raise ValueError(
            f"{field_name} must be between {minimum} and {maximum}")
    return value


def validate_choice(value: str, field_name: str, allowed: set[str]) -> str:
    if value not in allowed:
        raise ValueError(
            f"{field_name} must be one of: {', '.join(sorted(allowed))}")
    return value


def validate_vlan_id(value: int) -> int:
    return validate_int_range(value, "vlan_id", 4, 4094)


def validate_vlan_id_ranges(value: str) -> str:
    validate_required_string(value, "vlan_id_ranges")
    if not VLAN_ID_RANGES_PATTERN.fullmatch(value):
        raise ValueError(
            "vlan_id_ranges must look like '1-4' or '200-300,400-450'"
        )
    return value


def validate_network_address(value: str) -> str:
    validate_required_string(value, "address")
    try:
        ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        raise ValueError(
            f"address must be a valid CIDR network: {value}") from exc
    return value


def validate_ip_address(value: str) -> str:
    validate_required_string(value, "address")
    try:
        ipaddress.ip_address(value)
    except ValueError as exc:
        raise ValueError(
            f"address must be a valid IP address: {value}") from exc
    return value


def to_bool(value: object, default: bool = False) -> bool:
    try:
        if isinstance(value, bool):
            return value
        s = str(value).strip().lower()
        if s in TRUTHY_VALUES:
            return True
        if s in FALSY_VALUES:
            return False
    except Exception:
        pass

    return default


def validate_uploadable_type(value: str) -> bool:
    uploadable = value in ALLOWED_UPLOADABLE_TYPES
    return uploadable


def validate_photo_file(file_path: str | Path) -> Path:
    file_path = Path(file_path)

    if not file_path.is_file():
        raise FileNotFoundError(file_path)

    if Path(file_path).suffix.lower() not in ALLOWED_PHOTO_EXTS:
        raise ValueError("Photo file must be a supported image format")

    return file_path


def validate_pubphoto_file(file_path: str | Path) -> Path:
    file_path = Path(file_path)

    if not file_path.is_file():
        raise FileNotFoundError(file_path)

    if Path(file_path).suffix.lower() not in ALLOWED_PUBPHOTO_EXTS:
        raise ValueError("Public photo file must be a supported image format")

    return file_path


def validate_photoable_type(value: str) -> bool:
    photoable = value in ALLOWED_PHOTOABLE_TYPES
    return photoable


def validate_pubphotoable_type(value: str) -> bool:
    pubphotoable = value in ALLOWED_PUBLIC_PHOTOABLE_TYPES
    return pubphotoable


def validate_labelable_type(value: str) -> str:
    validate_required_string(value, "labelable_type")
    if value not in LABELABLE_TYPES:
        raise HuduValidationError(
            f"Invalid labelable_type {value!r}. "
            f"Allowed: {', '.join(LABELABLE_TYPES)}"
        )
    return value


def resolve_label_type_id(label_type: int | str | Any) -> int | str:
    if isinstance(label_type, (int, str)):
        return label_type

    label_type_id = getattr(label_type, "id", None)
    if label_type_id is None:
        raise ValueError("label_type must be an int, str, or object with an id")
    return label_type_id
