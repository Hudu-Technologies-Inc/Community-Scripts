fromable_toable_types = {
    "RackStorage": "rack_storages",
    "Password": "asset_passwords",
    "Asset": "assets",
    "IpAddress": "ip_addresses",
    "Network": "networks",
}

toable_fromable_types = {v: k for k, v in fromable_toable_types.items()}

match_found_options = [
    "always ask me if matching",
    "always skip import if matching (keep dest data)",
    "always overwrite destination if matching (keep source data)",
    "auto-select more-recent last updated date (keep most-recent)",
    "auto-select earlier created-on date (keep)",
    "ask me after each type of item.",
]
