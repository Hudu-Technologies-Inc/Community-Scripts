from hudu_magic.helpers.general import strip_string


class Instance:
    def __init__(self, api_key: str, instance_url: str):
        while instance_url is None:
            instance_url = input("enter the instance url for instance in order to proceed")
        while api_key is None:
            api_key = input("enter the api key for this instance in order to proceed")

        self.api_key = api_key

        normalized_url = instance_url.rstrip("/")
        if not normalized_url.startswith("https://"):
            normalized_url = f"https://{normalized_url}"
        if not normalized_url.endswith("/api/v1"):
            normalized_url += "/api/v1"

        self.instance_url = normalized_url
        self.friendly_name = strip_string(
            self.instance_url.removesuffix("/api/v1"),
            ["https", ":", "/", ".", " "]
        )

        self.get_request_headers = {
            "x-api-key": self.api_key,
            "Accept": "application/json",
        }

        self.post_request_headers = {
            "x-api-key": self.api_key,
            "Accept": "application/json",
        }