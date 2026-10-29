from urllib.parse import urlparse


def strip_string(value: str, remove: list[str]) -> str:
    for item in remove:
        value = value.replace(item, "")
    return value


def ensure_https(value: str) -> str:
    """
    Ensure a string is a valid HTTP/HTTPS URL by prepending https:// if missing.
    Used primarily for Hudu Website objects where the 'name' field must be a URL.
    """
    if not value:
        raise ValueError("URL value cannot be empty")

    parsed = urlparse(value)

    if parsed.scheme in ("http", "https"):
        return value

    return f"https://{value}"


def parse_version(v):
    return tuple(map(int, v.split(".")))


def is_version_greater_or_equal(v1, v2):
    return parse_version(v1) >= parse_version(v2)


def is_zero_percent(value):
    return float(value.rstrip('%').strip()) == 0
