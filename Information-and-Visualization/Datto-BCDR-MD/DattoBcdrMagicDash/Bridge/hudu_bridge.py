"""Isolated newline-delimited JSON bridge for the bundled hudu-magic client."""

from __future__ import annotations

import json
import re
import socket
import sys
from importlib import metadata
from pathlib import Path
from typing import Any


MAX_FRAME_BYTES = 16 * 1024 * 1024
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_ERROR_CHARS = 2_000

# stdout is the protocol. Redirect every ordinary print from dependencies to stderr,
# then write protocol frames only through the saved binary stream.
_protocol_stdout = sys.stdout.buffer
sys.stdout = sys.stderr
sys.dont_write_bytecode = True

_project_root = Path(__file__).resolve().parents[2]
_site_dir = _project_root / "Runtime" / "site"
if not _site_dir.is_dir():
    raise RuntimeError("The verified bundled Python site directory is missing.")
sys.path.insert(0, str(_site_dir))

import truststore  # noqa: E402

truststore.inject_into_ssl()

import requests  # noqa: E402
from hudu_magic import HuduClient  # noqa: E402
from hudu_magic.endpoints import HuduEndpoint  # noqa: E402
from hudu_magic.models import HuduCollection, HuduObject  # noqa: E402
from hudu_magic.validation import HuduAPIError, HuduValidationError  # noqa: E402


class _HuduSession(requests.Session):
    """Keep the Hudu API key on same-origin redirects only."""

    def rebuild_auth(
        self,
        prepared_request: requests.PreparedRequest,
        response: requests.Response,
    ) -> None:
        original_url = response.request.url
        redirected_url = prepared_request.url
        super().rebuild_auth(prepared_request, response)
        if (
            original_url
            and redirected_url
            and self.should_strip_auth(original_url, redirected_url)
        ):
            prepared_request.headers.pop("x-api-key", None)


class BridgeProtocolError(ValueError):
    """Raised when a protocol frame violates the bridge contract."""


class BridgeState:
    def __init__(self) -> None:
        self.client: HuduClient | None = None
        self.api_key = ""

    def close(self) -> None:
        if self.client is not None:
            self.client.session.close()
        self.client = None
        self.api_key = ""


STATE = BridgeState()


def _positive_int(value: Any, name: str) -> int:
    if isinstance(value, bool):
        raise HuduValidationError(f"{name} must be a positive integer.")
    if isinstance(value, int):
        converted = value
    elif isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*", value):
        converted = int(value)
    else:
        raise HuduValidationError(f"{name} must be a positive integer.")
    if converted < 1:
        raise HuduValidationError(f"{name} must be a positive integer.")
    return converted


def _required_text(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise HuduValidationError(f"{name} must be a non-empty string.")
    return value.strip()


def _required_client() -> HuduClient:
    if STATE.client is None:
        raise BridgeProtocolError("The bridge has not been initialized.")
    return STATE.client


def _to_wire(value: Any) -> Any:
    if isinstance(value, HuduObject):
        return _to_wire(value.to_dict())
    if isinstance(value, HuduCollection):
        return [_to_wire(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _to_wire(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_wire(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    raise TypeError(f"Unsupported response type: {type(value).__name__}")


def _model_dict(value: Any, description: str) -> dict[str, Any]:
    wire = _to_wire(value)
    if not isinstance(wire, dict):
        raise HuduValidationError(f"Hudu returned an invalid {description} response.")
    return wire


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    wire = _to_wire(value)
    if isinstance(wire, list):
        return wire
    return [wire]


def _init(args: dict[str, Any]) -> dict[str, Any]:
    api_key = _required_text(args.get("api_key"), "api_key")
    instance_url = _required_text(args.get("instance_url"), "instance_url")
    if not instance_url.lower().startswith("https://"):
        raise HuduValidationError("instance_url must use HTTPS.")

    STATE.close()
    STATE.api_key = api_key
    client = HuduClient(
        api_key=api_key,
        instance_url=instance_url,
        timeout=30,
        max_retries=1,
        retry_on_rate_limit=True,
        retry_on_error=False,
    )
    safe_session = _HuduSession()
    safe_session.headers.update(client.session.headers)
    client.session.close()
    client.session = safe_session
    STATE.client = client
    return {"initialized": True}


def _magic_dash_list(args: dict[str, Any]) -> list[dict[str, Any]]:
    client = _required_client()
    company_id = _positive_int(args.get("company_id"), "company_id")
    title = _required_text(args.get("title"), "title")
    result = client.magic_dashes.list(
        company_id=company_id,
        title=title,
        page_size=1000,
    )
    verified: list[dict[str, Any]] = []
    for index, item in enumerate(_as_list(result)):
        record = _model_dict(item, f"Magic Dash item {index + 1}")
        _positive_int(record.get("id"), f"Magic Dash item {index + 1} id")
        returned_company_id = _positive_int(
            record.get("company_id"),
            f"Magic Dash item {index + 1} company_id",
        )
        returned_title = _required_text(
            record.get("title"),
            f"Magic Dash item {index + 1} title",
        )
        if returned_company_id != company_id or returned_title.casefold() != title.casefold():
            raise HuduValidationError(
                "Hudu returned a Magic Dash outside the requested company and title scope."
            )
        verified.append(record)
    return verified


def _company_for_name_write(args: dict[str, Any]) -> dict[str, Any]:
    client = _required_client()
    company_id = _positive_int(args.get("company_id"), "company_id")
    target = _model_dict(
        client.companies.get(company_id),
        f"Company {company_id}",
    )
    returned_id = _positive_int(target.get("id"), f"Company {company_id} id")
    if returned_id != company_id:
        raise HuduValidationError(
            "Hudu returned a company outside the requested ID scope."
        )
    company_name = _required_text(target.get("name"), f"Company {company_id} name")

    # Magic Dash upsert identifies its company by name, so refresh the target by ID
    # and prove that its current name is still unique without re-reading the complete
    # company inventory for every matched Datto client.
    exact_matches: list[dict[str, Any]] = []
    result = client.companies.list(name=company_name, page_size=1000)
    for index, item in enumerate(_as_list(result)):
        record = _model_dict(item, f"Company name result {index + 1}")
        _positive_int(record.get("id"), f"Company name result {index + 1} id")
        returned_name = _required_text(
            record.get("name"),
            f"Company name result {index + 1} name",
        )
        if returned_name.casefold() == company_name.casefold():
            exact_matches.append(record)
    if len(exact_matches) != 1 or _positive_int(
        exact_matches[0].get("id"),
        "Exact-name company id",
    ) != company_id:
        raise HuduValidationError(
            f"{len(exact_matches)} Hudu companies now share the name '{company_name}'."
        )
    return target


def _magic_dash_create(payload: Any) -> Any:
    client = _required_client()
    if not isinstance(payload, dict):
        raise HuduValidationError("payload must be an object.")
    allowed = {
        "message",
        "company_name",
        "title",
        "icon",
        "image_url",
        "content_link",
        "content",
        "shade",
    }
    clean = {
        key: value
        for key, value in payload.items()
        if key in allowed and value not in (None, "")
    }
    # Hudu's tile supports either an image or an icon. When switching an existing
    # managed tile to an icon, preserve the explicit empty image value so the POST
    # clears stale artwork instead of silently omitting the field.
    if clean.get("icon") and payload.get("image_url") == "":
        clean["image_url"] = ""
    _required_text(clean.get("company_name"), "company_name")
    _required_text(clean.get("title"), "title")
    return client.magic_dashes.create(clean)


def _magic_dash_upsert_for_company(
    args: dict[str, Any],
    *,
    compact_response: bool = True,
) -> Any:
    client = _required_client()
    company_id = _positive_int(args.get("company_id"), "company_id")
    expected_name = _required_text(
        args.get("expected_company_name"),
        "expected_company_name",
    )
    ownership_marker_value = args.get("ownership_marker")
    ownership_marker = (
        None
        if ownership_marker_value is None
        else _required_text(ownership_marker_value, "ownership_marker")
    )
    target = _company_for_name_write({"company_id": company_id})
    current_name = _required_text(target.get("name"), f"Company {company_id} name")
    if current_name.casefold() != expected_name.casefold():
        raise HuduValidationError(
            f"Company {company_id} changed names before the Magic Dash write."
        )

    payload = args.get("payload")
    if not isinstance(payload, dict):
        raise HuduValidationError("payload must be an object.")
    title = _required_text(payload.get("title"), "title")
    collisions = _magic_dash_list({"company_id": company_id, "title": title})
    preexisting_ids = {
        _positive_int(dash.get("id"), "Existing Magic Dash id")
        for dash in collisions
    }
    if ownership_marker is not None:
        unowned = [
            dash
            for dash in collisions
            if ownership_marker not in str(dash.get("content") or "")
        ]
        if unowned:
            raise HuduValidationError(
                f"Company {company_id} has an unowned Magic Dash with the requested title."
            )
        if len(collisions) > 1:
            raise HuduValidationError(
                f"Company {company_id} has multiple owned Magic Dashes with the requested title."
            )

    scoped_payload = dict(payload)
    scoped_payload["company_name"] = current_name
    result = _magic_dash_create(scoped_payload)
    written = _model_dict(result, "Written Magic Dash")
    dash_id = _positive_int(written.get("id"), "Written Magic Dash id")
    try:
        verified_writes = _magic_dash_list(
            {"company_id": company_id, "title": title}
        )
        if len(verified_writes) != 1:
            raise HuduValidationError(
                "Post-write verification did not find exactly one Magic Dash under the requested company."
            )
        verified_write = verified_writes[0]
        verified_id = _positive_int(
            verified_write.get("id"), "Verified Magic Dash id"
        )
        if verified_id != dash_id:
            raise HuduValidationError(
                "The written Magic Dash was not returned under the requested company."
            )
        if ownership_marker is not None and ownership_marker not in str(
            verified_write.get("content") or ""
        ):
            raise HuduValidationError(
                "The written Magic Dash no longer contains its ownership marker."
            )
    except Exception as verification_exc:
        if dash_id in preexisting_ids:
            raise HuduValidationError(
                "Post-write Magic Dash verification failed; the pre-existing Magic Dash "
                "was left in place because its final state could not be confirmed."
            ) from verification_exc
        try:
            client.magic_dashes.delete(dash_id)
        except Exception as cleanup_exc:
            raise HuduValidationError(
                "Post-write Magic Dash verification failed, and automatic cleanup failed."
            ) from cleanup_exc
        raise HuduValidationError(
            "Post-write Magic Dash verification failed; the unverified write was removed."
        ) from verification_exc
    if compact_response:
        return {"id": dash_id, "company_id": company_id, "verified": True}
    return result


def _magic_dash_upsert_by_unique_name(args: dict[str, Any]) -> Any:
    client = _required_client()
    payload = args.get("payload")
    if not isinstance(payload, dict):
        raise HuduValidationError("payload must be an object.")
    company_name = _required_text(payload.get("company_name"), "company_name")
    exact_matches: list[dict[str, Any]] = []
    for index, item in enumerate(
        _as_list(client.companies.list(name=company_name, page_size=1000))
    ):
        record = _model_dict(item, f"Company name result {index + 1}")
        returned_name = _required_text(
            record.get("name"),
            f"Company name result {index + 1} name",
        )
        if returned_name.casefold() == company_name.casefold():
            exact_matches.append(record)
    if len(exact_matches) != 1:
        raise HuduValidationError(
            f"{len(exact_matches)} Hudu companies now share the name '{company_name}'."
        )
    company_id = _positive_int(
        exact_matches[0].get("id"),
        "Exact-name company id",
    )
    scoped_payload = dict(payload)
    scoped_payload.pop("company_name", None)
    return _magic_dash_upsert_for_company(
        {
            "company_id": company_id,
            "expected_company_name": company_name,
            "payload": scoped_payload,
        },
        compact_response=False,
    )


def _require_payload(args: dict[str, Any]) -> dict[str, Any]:
    payload = args.get("payload")
    if not isinstance(payload, dict):
        raise HuduValidationError("payload must be an object.")
    return payload


def _asset_layouts_list(_args: dict[str, Any]) -> list[Any]:
    return _as_list(_required_client().asset_layouts.list())


def _asset_layouts_get(args: dict[str, Any]) -> dict[str, Any]:
    layout_id = _positive_int(args.get("id"), "id")
    result = _required_client().asset_layouts.get(layout_id)
    wire = _to_wire(result)
    if wire is None or wire == []:
        raise HuduValidationError(f"Hudu asset layout ID {layout_id} was not found.")
    if isinstance(wire, dict):
        for wrapper in ("asset_layout", "data"):
            nested = wire.get(wrapper)
            if isinstance(nested, dict):
                wire = nested
                break
    if isinstance(wire, list):
        matches = []
        for item in wire:
            if not isinstance(item, dict):
                continue
            try:
                returned_id = _positive_int(item.get("id"), "returned asset layout id")
            except HuduValidationError:
                continue
            if returned_id == layout_id:
                matches.append(item)
        if not matches:
            raise HuduValidationError(f"Hudu asset layout ID {layout_id} was not found.")
        if len(matches) != 1:
            raise HuduValidationError(
                f"Hudu returned multiple asset layouts with ID {layout_id}."
            )
        wire = matches[0]
    model = _model_dict(wire, "asset layout")
    returned_id = _positive_int(model.get("id"), "returned asset layout id")
    if returned_id != layout_id:
        raise HuduValidationError(
            f"Hudu returned the wrong asset layout for requested ID {layout_id}."
        )
    return model


def _asset_layouts_create(args: dict[str, Any]) -> Any:
    payload = dict(_require_payload(args))
    if "active" in payload or "slug" in payload:
        raise HuduValidationError("asset_layouts.create must not send active or slug.")
    _required_text(payload.get("name"), "name")
    return _to_wire(_required_client().asset_layouts.create(payload=payload))


def _asset_layouts_update(args: dict[str, Any]) -> Any:
    layout_id = _positive_int(args.get("id"), "id")
    payload = dict(_require_payload(args))
    allowed_keys = {
        "active",
        "name",
        "icon",
        "color",
        "icon_color",
        "include_passwords",
        "include_photos",
        "include_comments",
        "include_files",
        "password_types",
        "fields",
    }
    if "slug" in payload:
        raise HuduValidationError("asset_layouts.update must not send slug.")
    unexpected = sorted(set(payload.keys()) - allowed_keys)
    if unexpected:
        raise HuduValidationError(
            "asset_layouts.update contains unsupported keys: " + ", ".join(unexpected)
        )
    if payload.get("active") is not True:
        raise HuduValidationError("asset_layouts.update requires active true.")
    if "fields" not in payload:
        raise HuduValidationError(
            "asset_layouts.update requires existing fields with positive ids."
        )
    fields = payload["fields"]
    if not isinstance(fields, list) or not fields:
        raise HuduValidationError(
            "asset_layouts.update fields must contain existing fields with positive ids."
        )
    for index, field in enumerate(fields):
        if not isinstance(field, dict):
            raise HuduValidationError(
                f"asset_layouts.update fields[{index}] must be an object."
            )
        _positive_int(field.get("id"), f"fields[{index}].id")
    # POST /asset_layouts does not support update. Activate with PUT /asset_layouts/{id}.
    return _to_wire(
        _required_client().update(
            HuduEndpoint.ASSET_LAYOUTS_ID,
            layout_id,
            payload,
        )
    )


def _asset_layouts_connect_existing(args: dict[str, Any]) -> Any:
    """Safely activate a selected customer layout and add only our missing field."""
    layout_id = _positive_int(args.get("id"), "id")
    payload = dict(_require_payload(args))
    allowed_keys = {
        "active",
        "name",
        "icon",
        "color",
        "icon_color",
        "include_passwords",
        "include_photos",
        "include_comments",
        "include_files",
        "password_types",
        "fields",
    }
    if "slug" in payload:
        raise HuduValidationError("asset_layouts.connect_existing must not send slug.")
    unexpected = sorted(set(payload.keys()) - allowed_keys)
    if unexpected:
        raise HuduValidationError(
            "asset_layouts.connect_existing contains unsupported keys: "
            + ", ".join(unexpected)
        )
    if payload.get("active") is not True:
        raise HuduValidationError("asset_layouts.connect_existing requires active true.")
    fields = payload.get("fields")
    if not isinstance(fields, list) or not fields:
        raise HuduValidationError("asset_layouts.connect_existing requires fields.")

    new_fields = []
    compatible_details = 0
    for index, field in enumerate(fields):
        if not isinstance(field, dict):
            raise HuduValidationError(
                f"asset_layouts.connect_existing fields[{index}] must be an object."
            )
        field_id = field.get("id")
        label = field.get("label")
        field_type = field.get("field_type")
        if field_id is None:
            new_fields.append(field)
        else:
            _positive_int(field_id, f"fields[{index}].id")
        if isinstance(label, str) and label.casefold() == "asset details".casefold():
            if not isinstance(field_type, str) or field_type.casefold() != "richtext":
                raise HuduValidationError(
                    "Asset Details already exists with an incompatible field type."
                )
            compatible_details += 1

    if compatible_details != 1:
        raise HuduValidationError(
            "asset_layouts.connect_existing requires exactly one RichText Asset Details field."
        )
    if len(new_fields) > 1:
        raise HuduValidationError(
            "asset_layouts.connect_existing may create only one missing field."
        )
    if new_fields:
        new_field = new_fields[0]
        if (
            new_field.get("label") != "Asset Details"
            or new_field.get("field_type") != "RichText"
            or new_field.get("required") is not False
            or new_field.get("show_in_list") is not False
        ):
            raise HuduValidationError(
                "asset_layouts.connect_existing may create only the optional RichText Asset Details field."
            )
    return _to_wire(
        _required_client().update(
            HuduEndpoint.ASSET_LAYOUTS_ID,
            layout_id,
            payload,
        )
    )


def _assets_list(args: dict[str, Any]) -> list[Any]:
    company_id = _positive_int(args.get("company_id"), "company_id")
    layout_id = _positive_int(args.get("asset_layout_id"), "asset_layout_id")
    result = _required_client().assets.list(
        company_id=company_id,
        asset_layout_id=layout_id,
        page_size=1000,
    )
    return _as_list(result)


def _assets_create(args: dict[str, Any]) -> Any:
    company_id = _positive_int(args.get("company_id"), "company_id")
    payload = _require_payload(args)
    return _to_wire(
        _required_client().assets.create(company_id=company_id, payload=payload)
    )


def _assets_update(args: dict[str, Any]) -> Any:
    item_id = _positive_int(args.get("id"), "id")
    company_id = _positive_int(args.get("company_id"), "company_id")
    payload = _require_payload(args)
    return _to_wire(
        _required_client().assets.update(
            item_id,
            company_id,
            payload=payload,
        )
    )


def _assets_archive(args: dict[str, Any]) -> Any:
    item_id = _positive_int(args.get("id"), "id")
    company_id = _positive_int(args.get("company_id"), "company_id")
    return _to_wire(_required_client().assets.archive(item_id, company_id))


def _dispatch(op: str, args: dict[str, Any]) -> Any:
    if op == "init":
        return _init(args)
    if op == "heartbeat":
        return {"ready": STATE.client is not None}
    if op == "shutdown":
        STATE.close()
        return {"shutdown": True}

    client = _required_client()
    if op == "app_info":
        return client.get("api_info")
    if op == "companies.list":
        return client.companies.list(page_size=1000)
    if op == "companies.resolve_for_name_write":
        return _company_for_name_write(args)
    if op == "magic_dash.list":
        return _magic_dash_list(args)
    if op == "magic_dash.upsert":
        return _magic_dash_upsert_by_unique_name(args)
    if op == "magic_dash.upsert_for_company":
        return _magic_dash_upsert_for_company(args)
    if op == "magic_dash.delete":
        return client.magic_dashes.delete(_positive_int(args.get("id"), "id"))
    if op == "asset_layouts.list":
        return _asset_layouts_list(args)
    if op == "asset_layouts.get":
        return _asset_layouts_get(args)
    if op == "asset_layouts.create":
        return _asset_layouts_create(args)
    if op == "asset_layouts.update":
        return _asset_layouts_update(args)
    if op == "asset_layouts.connect_existing":
        return _asset_layouts_connect_existing(args)
    if op == "assets.list":
        return _assets_list(args)
    if op == "assets.create":
        return _assets_create(args)
    if op == "assets.update":
        return _assets_update(args)
    if op == "assets.archive":
        return _assets_archive(args)
    raise BridgeProtocolError(f"Unsupported operation: {op}")


def _redact(message: str) -> str:
    sanitized = message
    if STATE.api_key:
        sanitized = sanitized.replace(STATE.api_key, "[REDACTED]")
    # hudu-magic appends the request method, URL, and body to API errors. The body
    # can contain credentials or customer content and must never cross the bridge.
    for marker in ("\nMETHOD=", "\r\nMETHOD=", "\nURL=", "\nBODY="):
        if marker in sanitized:
            sanitized = sanitized.split(marker, 1)[0]
    sanitized = re.sub(r"^Hudu API error \(\d+\):\s*", "", sanitized)
    sanitized = " ".join(sanitized.replace("\x00", "").split())
    return sanitized[:MAX_ERROR_CHARS] or "The Hudu request failed."


def _is_dns_error(exc: BaseException) -> bool:
    current: BaseException | None = exc
    for _ in range(8):
        if current is None:
            break
        if isinstance(current, socket.gaierror):
            return True
        text = str(current).lower()
        if any(token in text for token in ("nameresolutionerror", "getaddrinfo", "failed to resolve")):
            return True
        current = current.__cause__ or current.__context__
    return False


def _error_payload(exc: BaseException) -> dict[str, Any]:
    status: int | None = None
    if isinstance(exc, requests.exceptions.Timeout):
        kind, message = "Timeout", "The Hudu API request timed out."
    elif isinstance(exc, requests.exceptions.SSLError):
        kind, message = "TlsError", "TLS certificate validation failed while connecting to Hudu."
    elif isinstance(exc, requests.exceptions.ConnectionError):
        if _is_dns_error(exc):
            kind, message = "DnsError", "DNS resolution failed while connecting to Hudu."
        else:
            kind, message = "ConnectionError", "Could not connect to the Hudu API."
    elif isinstance(exc, HuduAPIError):
        kind = "HuduAPIError"
        status = int(exc.status_code)
        message = _redact(str(exc))
    elif isinstance(exc, BridgeProtocolError):
        kind, message = "ProtocolError", _redact(str(exc))
    elif isinstance(exc, (HuduValidationError, ValueError)):
        kind, message = "ValidationError", _redact(str(exc))
    else:
        kind = "InternalError"
        message = f"The Hudu bridge failed unexpectedly ({type(exc).__name__})."
    return {"kind": kind, "status": status, "message": message}


def _write_frame(frame: dict[str, Any]) -> None:
    encoded = json.dumps(frame, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(encoded) > MAX_RESPONSE_BYTES:
        encoded = json.dumps(
            {
                "id": frame.get("id"),
                "ok": False,
                "error": {
                    "kind": "ProtocolError",
                    "status": None,
                    "message": "The Hudu bridge response exceeds the maximum size.",
                },
            },
            separators=(",", ":"),
        ).encode("utf-8") + b"\n"
    _protocol_stdout.write(encoded)
    _protocol_stdout.flush()


def _read_frame() -> tuple[Any, dict[str, Any]] | None:
    raw = sys.stdin.buffer.readline(MAX_FRAME_BYTES + 1)
    if not raw:
        return None
    if len(raw) > MAX_FRAME_BYTES:
        while raw and not raw.endswith(b"\n"):
            raw = sys.stdin.buffer.readline(MAX_FRAME_BYTES + 1)
        raise BridgeProtocolError("The request frame exceeds the maximum size.")
    try:
        frame = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BridgeProtocolError("The request frame is not valid UTF-8 JSON.") from exc
    if not isinstance(frame, dict):
        raise BridgeProtocolError("The request frame must be a JSON object.")
    request_id = frame.get("id")
    if isinstance(request_id, bool) or not isinstance(request_id, int) or request_id < 0:
        raise BridgeProtocolError("The request id must be a non-negative integer.")
    op = frame.get("op")
    if not isinstance(op, str) or not op:
        raise BridgeProtocolError("The operation name must be a non-empty string.")
    args = frame.get("args", {})
    if not isinstance(args, dict):
        raise BridgeProtocolError("The operation arguments must be a JSON object.")
    return request_id, {"op": op, "args": args}


def _run() -> int:
    if "--self-test" in sys.argv[1:]:
        _write_frame(
            {
                "id": 0,
                "ok": True,
                "data": {
                    "python": sys.version.split()[0],
                    "hudu_magic": metadata.version("hudu-magic"),
                    "truststore": metadata.version("truststore"),
                    "isolated": bool(sys.flags.isolated),
                    "no_site": bool(sys.flags.no_site),
                    "ignore_environment": bool(sys.flags.ignore_environment),
                },
            }
        )
        return 0

    while True:
        request_id: Any = None
        try:
            parsed = _read_frame()
            if parsed is None:
                break
            request_id, request = parsed
            data = _to_wire(_dispatch(request["op"], request["args"]))
            _write_frame({"id": request_id, "ok": True, "data": data})
            if request["op"] == "shutdown":
                break
        except BaseException as exc:  # Every frame receives a structured failure.
            _write_frame({"id": request_id, "ok": False, "error": _error_payload(exc)})
    STATE.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(_run())
