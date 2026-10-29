from __future__ import annotations

import time
from pathlib import Path
from typing import Any, ClassVar, Iterable

from hudu_magic.constants import LABEL_COLLECTION_BATCH_MIN
from hudu_magic.help import describe_single, supported_methods
from hudu_magic.helpers.general import is_version_greater_or_equal
from hudu_magic.helpers.labels import (
    convert_to_hudu_label_color,
    filter_labels_for_label_type_ids,
    filter_labels_for_targets,
    group_labelable_targets,
    normalize_labelable_id,
)

from .endpoints import HuduEndpoint
from .models import (
    Asset,
    Exports,
    HuduCollection,
    HuduObject,
    Photo,
    PublicPhoto,
    Upload,
    _flatten_label_results,
    _wrap_hudu_object_results,
    ordered_procedure_tasks,
)
from .validation import (
    HuduAPIError,
    HuduNotImplementedError,
    HuduValidationError,
    resolve_label_type_id,
    to_bool,
    validate_ip_address,
    validate_labelable_type,
    validate_network_address,
    validate_pubphoto_file,
    validate_uploadable_type,
    validate_vlan_id,
    validate_vlan_id_ranges,
)

# Passed through to ``HuduClient.create`` / ``update``, not merged into JSON body.
_CLIENT_HTTP_KWARGS = frozenset({"validate", "allow_unknown_fields"})

# ``POST /exports`` include flags default to True in :meth:`ExportsResource.start` when omitted.
_EXPORT_START_DEFAULT_TRUE_INCLUDES = (
    "include_passwords",
    "include_websites",
    "include_articles",
    "include_archived_articles",
    "include_archived_passwords",
    "include_archived_websites",
    "include_archived_assets",
)


class BaseResource:
    endpoint: HuduEndpoint
    
    def _resolve_action_path(
        self,
        item_id: int | str | None = None,
        action: str | None = None,
    ) -> str:
        if item_id is None:
            if action is not None:
                raise ValueError(f"Cannot use action '{action}' without an id")
            return self.client.resolve_path(self.endpoint)

        path = self.client.resolve_path(self.endpoint, item_id)

        if action:
            path = f"{path}/{action}"

        return path    

    def __init__(self, client):
        self.client = client

    def _merge_payload(self, payload: dict | None, kwargs: dict) -> dict:
        if payload and kwargs:
            return {**payload, **kwargs}
        if payload:
            return payload
        return kwargs

    def _require_support(self, operation: str) -> None:
        attr_name = f"supports_{operation}"
        if not getattr(self.endpoint.meta, attr_name, False):
            raise HuduNotImplementedError(
                f"{self.endpoint.name} does not support {operation}"
                f"supported methods are: {supported_methods}"
            )

    def _reraise_with_description(self, exc: HuduValidationError) -> None:
        raise HuduValidationError(
            f"{exc}\n\n{describe_single(self.endpoint)}"
        ) from None

    def get(self, item_id=None, **params):
        if item_id is None and "id" in params:
            item_id = params.pop("id")

        if item_id is not None:
            if not self.endpoint.meta.supports_get:
                raise ValueError(f"{self.endpoint.name} does not support get")

            path = self.client.resolve_path(self.endpoint, item_id)
            raw = self.client._get_nonpaginated(path)

            item_endpoint = getattr(HuduEndpoint, f"{self.endpoint.name}_ID", self.endpoint)
            result = self.client._wrap_result(item_endpoint, raw)
            if isinstance(result, HuduCollection):
                if not result:
                    return None
                if len(result) == 1 or item_id is not None:
                    return result.first() or None

            if isinstance(result, list):
                if not result:
                    return None
                if len(result) == 1 or item_id is not None:
                    return result[0] or None

            return result

        return self.list(**params)

    def create(self, payload: dict[str, Any] | None = None, **kwargs) -> Any:
        try:
            client_kw = {k: v for k, v in kwargs.items() if k in _CLIENT_HTTP_KWARGS}
            body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
            merged = self._merge_payload(payload, body_kw)
            return self.client.create(self.endpoint, merged, **client_kw)
        except HuduValidationError as e:
            self._reraise_with_description(e)

    def update(self, item_id: int | str, payload: dict[str, Any] | None = None, **kwargs) -> Any:
        try:
            client_kw = {k: v for k, v in kwargs.items() if k in _CLIENT_HTTP_KWARGS}
            body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
            merged = self._merge_payload(payload, body_kw)
            return self.client.update(self.endpoint, item_id, merged, **client_kw)
        except HuduValidationError as e:
            self._reraise_with_description(e)

    def delete(self, item_id: int | str) -> Any:
        try:
            self._require_support("delete")
            path = self.client.resolve_path(self.endpoint, item_id)
            return self.client.delete(path)
        except HuduValidationError as e:
            raise HuduValidationError(
                f"{e}\n\n{describe_single(self.endpoint)}"
            ) from None

    def archive(self, item_id: int | str) -> Any:
        try:
            self._require_support("archive")
            path = self.client.resolve_path(
                self.endpoint, item_id) + "/archive"
            if item_id is None:
                raise ValueError("Cannot archive object without an id")
            return self.client.put(path)
        except HuduValidationError as e:
            raise HuduValidationError(
                f"{e}\n\n{describe_single(self.endpoint)}"
            ) from None

    def unarchive(self, item_id: int | str) -> Any:
        try:
            self._require_support("unarchive")
            path = self.client.resolve_path(
                self.endpoint, item_id) + "/unarchive"
            if item_id is None:
                raise ValueError("Cannot unarchive object without an id")
            return self.client.put(path)
        except HuduValidationError as e:
            raise HuduValidationError(
                f"{e}\n\n{describe_single(self.endpoint)}"
            ) from None

    # aliased methods for convenience and readability
    def list(self, **params) -> Any:
        self._require_support("list")
        return self.client.get(self.endpoint, params=params or None)

    def get_all(self, **params):
        return self.get(None, **params)

    def new(self, payload: dict, **kwargs):
        return self.create(payload, **kwargs)

    # resource-level help-get
    def describe(self) -> str:
        return describe_single(self.endpoint)
    
    def help(self) -> str:
        return self.describe()

    # For resources that support file uploads and relations, we can provide helper methods to list related items
    def list_photos(self, to_object: HuduObject, **params):
        return self.client.photos.list(
            photoable_type=to_object.to_photo_ref(),
            photoable_id=str(to_object.id),
            **params,
        )

    def list_relations(self, to_object: HuduObject, **params):
        return self.client.relations.list_relations(to_object, **params)

    def list_uploads(self, to_object: HuduObject):
        uploadable_type = to_object.to_upload_ref()
        object_id = str(to_object.id)

        return [
            u
            for u in self.client.uploads.list()
            if u.uploadable_type == uploadable_type
            and str(u.uploadable_id) == object_id
        ]

    def add_label(
        self,
        to_object: HuduObject | HuduCollection,
        label_type: int | str | HuduObject,
        user_id: int | None = None,
        **kwargs,
    ) -> Any:
        return self.client.labels.assign(
            to_object,
            label_type,
            user_id=user_id,
            **kwargs,
        )

    def list_labels(
        self,
        to_object: HuduObject | HuduCollection,
        label_type: int | str | HuduObject | None = None,
        **params,
    ) -> Any:
        label_type_id = None
        if label_type is not None:
            label_type_id = resolve_label_type_id(label_type)
        return self.client.labels.list_for(
            to_object,
            label_type_id=label_type_id,
            **params,
        )

    def strip_labels(
        self,
        to_object: HuduObject | HuduCollection,
        label_type: int | str | HuduObject | None = None,
    ) -> list[Any]:
        return self.client.labels.strip(to_object, label_type=label_type)


class BaseFileResource(BaseResource):
    endpoint: ClassVar[HuduEndpoint]
    model_cls: ClassVar[type]
    file_form_field: ClassVar[str] = "file"

    def _validate_file_path(self, file_path: str | Path) -> Path:
        file_path = Path(file_path)
        if not file_path.is_file():
            raise FileNotFoundError(f"File not found: {file_path}")
        return file_path

    def _safe_filename(self, filename: str | None, fallback: str) -> str:
        filename = filename or fallback
        return "".join("_" if c in '<>:"/\\|?*' else c for c in filename)

    def _wrap_model(self, result: Any) -> Any:
        if isinstance(result, dict):
            result = self.client._extract_primary_object(result)
            return self.model_cls(self.client, self.endpoint, result)
        return result

    def _post_file(
        self,
        file_path: str | Path,
        *,
        data: dict[str, str],
    ) -> Any:
        file_path = self._validate_file_path(file_path)

        with file_path.open("rb") as fh:
            result = self.client.post(
                self.endpoint,
                files={self.file_form_field: (file_path.name, fh)},
                data=data,
            )

        return self._wrap_model(result)

    def _download_file(
        self,
        object_or_id,
        out_dir: str | Path = ".",
        *,
        download_path_template: str,
        fallback_prefix: str,
    ) -> Path:
        if hasattr(object_or_id, "id"):
            obj = object_or_id
            object_id = obj.id
        else:
            object_id = object_or_id
            obj = self.get(object_id)

        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        filename = (
            getattr(obj, "name", None)
            or getattr(obj, "file_name", None)
            or str(object_id)
        )

        safe_name = self._safe_filename(
            filename, f"{fallback_prefix}-{object_id}")
        destination = out_dir / safe_name

        url = self.client.build_url(
            download_path_template.format(id=object_id))
        response = self.client.get_url(url, timeout=self.client.timeout)
        response.raise_for_status()

        destination.write_bytes(response.content)

        return destination


class CompaniesResource(BaseResource):
    endpoint = HuduEndpoint.COMPANIES


class PhotosResource(BaseFileResource):
    endpoint = HuduEndpoint.PHOTOS
    model_cls = Photo
    file_form_field = "file"

    def create(
        self,
        file_path: str | Path,
        to_object: HuduObject,
        caption: str | None = None,
    ) -> Any:
        validate_pubphoto_file(file_path)

        photoable_type = to_object.to_photo_ref()

        if not caption or not str(caption).strip():
            caption = f"uploaded photo to {photoable_type} with id {to_object.id} without caption"

        return self._post_file(
            file_path,
            data={
                "caption": caption,
                "photoable_id": str(to_object.id),
                "photoable_type": photoable_type,
            },
        )

    def download(self, photo_or_id, out_dir: str | Path = ".") -> Path:
        return self._download_file(
            photo_or_id,
            out_dir=out_dir,
            download_path_template="photos/{id}?download=true",
            fallback_prefix="photo",
        )


class PublicPhotosResource(BaseFileResource):
    endpoint = HuduEndpoint.PUBLIC_PHOTOS
    model_cls = PublicPhoto
    file_form_field = "photo"

    def create(
        self,
        file_path: str | Path,
        to_object: HuduObject,
    ) -> Any:
        validate_pubphoto_file(file_path)

        photoable_type = to_object.to_pubphoto_ref()

        return self._post_file(
            file_path,
            data={
                "record_id": str(to_object.id),
                "record_type": photoable_type,
            },
        )

    def download(self, photo_or_id, out_dir: str | Path = ".") -> Path:
        raise NotImplementedError(
            "Hudu API does not currently support downloading public photos"
        )


class UploadsResource(BaseFileResource):
    endpoint = HuduEndpoint.UPLOADS
    model_cls = Upload

    def list(self, **params) -> Any:
        if is_version_greater_or_equal(str(self.client.check_version()), "2.41.3"):
            return self.client.get(self.endpoint, params=params or None, paginate=True)
        return self.client.get(self.endpoint, params=params or None, paginate=False)

    def create(
        self,
        file_path: str | Path,
        to_object: HuduObject,
    ) -> Any:
        uploadable_type = to_object.to_upload_ref()
        if not uploadable_type or validate_uploadable_type(uploadable_type) is False:
            raise ValueError(
                f"object is not of uploadable type {uploadable_type}")

        return self._post_file(
            file_path,
            data={
                "upload[uploadable_id]": str(to_object.id),
                "upload[uploadable_type]": uploadable_type,
            },
        )

    def download(self, upload_or_id, out_dir: str | Path = ".") -> Path:
        return self._download_file(
            upload_or_id,
            out_dir=out_dir,
            download_path_template="uploads/{id}?download=true",
            fallback_prefix="upload",
        )


class ArticlesResource(BaseResource):
    endpoint = HuduEndpoint.ARTICLES

    def get(self, item_id=None, **params):
        if item_id is None and "id" in params:
            item_id = params.pop("id")

        if item_id is None:
            return self.list(**params)

        raw = self.client._get_nonpaginated(self._resolve_action_path(item_id))
        return self.client._wrap_result(HuduEndpoint.ARTICLES_ID, raw)

    def create(self, payload: dict[str, Any] | None = None, **kwargs) -> Any:
        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._merge_payload(payload, body_kw)
        result = self.client.post(self._resolve_action_path(), json={"article": merged})
        return self.client._wrap_result(HuduEndpoint.ARTICLES, result)

    def update(self, item_id: int | str, payload: dict[str, Any] | None = None, **kwargs) -> Any:
        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._merge_payload(payload, body_kw)
        result = self.client.put(
            self._resolve_action_path(item_id),
            json={"article": merged},
        )
        return self.client._wrap_result(HuduEndpoint.ARTICLES_ID, result)

    def delete(self, item_id: int | str) -> Any:
        return self.client.delete(self._resolve_action_path(item_id))

    def archive(self, item_id: int | str) -> Any:
        return self.client.put(self._resolve_action_path(item_id, "archive"))

    def unarchive(self, item_id: int | str) -> Any:
        return self.client.put(self._resolve_action_path(item_id, "unarchive"))


class FoldersResource(BaseResource):
    endpoint = HuduEndpoint.FOLDERS


class RackStoragesResource(BaseResource):
    endpoint = HuduEndpoint.RACK_STORAGES


class AssetPasswordsResource(BaseResource):
    endpoint = HuduEndpoint.ASSET_PASSWORDS


class WebsitesResource(BaseResource):
    endpoint = HuduEndpoint.WEBSITES


class Asset_LayoutsResource(BaseResource):
    endpoint = HuduEndpoint.ASSET_LAYOUTS


class PasswordFoldersResource(BaseResource):
    endpoint = HuduEndpoint.PASSWORD_FOLDERS

    def save(self, item_id: int | str, payload: dict[str, Any], **kwargs) -> Any:
        company_id = payload.get("company_id")
        if company_id is None:
            raise ValueError(
                "company_id is required in payload to update a password folder"
            )

        if payload.get("security") is None:
            payload["security"] = "all_users"

        path = f"companies/{company_id}/password_folders/{item_id}"
        result = self.client.put(path, json={"password_folder": payload})
        return self.client._wrap_result(self.endpoint, result)


class AssetsResource(BaseResource):
    endpoint = HuduEndpoint.ASSETS

    def _list_company_assets(self, company_id: int | str, params: dict | None) -> Any:
        """GET companies/{company_id}/assets — path is not an endpoint enum, so paginate and wrap here."""
        path = f"companies/{company_id}/assets"
        page = 1
        all_items: list[dict] = []
        p = dict(params or {})
        seen_signatures: set[tuple] = set()
        while True:
            page_params = {**p, "page": page}
            result = self.client._get_nonpaginated(path, page_params)
            if isinstance(result, dict):
                items = (
                    result.get("companies_assets")
                    or result.get("assets")
                    or result.get("items")
                    or result.get("data")
                    or []
                )
            elif isinstance(result, list):
                items = result
            else:
                items = []
            if not items:
                break
            signature = tuple(
                item.get("id") for item in items if isinstance(item, dict)
            )
            if signature in seen_signatures:
                break
            seen_signatures.add(signature)
            all_items.extend(items)
            page += 1
        return self.client._wrap_result(HuduEndpoint.ASSETS, all_items)

    def list(self, company_id=None, **params):
        if company_id is None and "company_id" in params:
            company_id = params.pop("company_id")

        if company_id is not None:
            return self._list_company_assets(company_id, params)

        return self.client.get(self.endpoint, params=params or None, paginate=True)

    def get(self, item_id=None, company_id=None, **params):
        if item_id is None and "id" in params:
            item_id = params.pop("id")

        if company_id is None and "company_id" in params:
            company_id = params.pop("company_id")

        if item_id is not None:
            if company_id is not None:
                path = f"companies/{company_id}/assets/{item_id}"
                raw = self.client._get_nonpaginated(path)
                return self.client._wrap_result(HuduEndpoint.ASSETS, raw)

            result = self.client.get(
                self.endpoint,
                params={"id": item_id, **params},
                paginate=False,
            )

            if isinstance(result, HuduCollection):
                if not result:
                    return None
                if len(result) == 1:
                    return result[0]

            if isinstance(result, list):
                if not result:
                    return None
                if len(result) == 1:
                    return result[0]
                
            if isinstance(result, dict):
                result = self.client._extract_primary_object(result)

            return result

        return self.list(company_id=company_id, **params)
    def create(
        self,
        company_id: int | str,
        payload: dict[str, Any] | None = None,
        **kwargs,
    ) -> Any:
        if company_id is None:
            raise ValueError("Asset create() requires company_id")

        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._merge_payload(payload, body_kw)
        wrapped = {"asset": merged}
        result = self.client.post(f"companies/{company_id}/assets", json=wrapped)

        if isinstance(result, dict):
            result = self.client._extract_primary_object(result)
            return Asset(self.client, HuduEndpoint.ASSETS, result)

        return result

    def update(
        self,
        item_id: int | str,
        company_id: int | str,
        payload: dict[str, Any] | None = None,
        **kwargs,
    ) -> Any:
        if item_id is None:
            raise ValueError("Cannot update asset without an id")
        if company_id is None:
            raise ValueError("Asset update() requires company_id")

        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._merge_payload(payload, body_kw)
        path = f"companies/{company_id}/assets/{item_id}"
        result = self.client.put(path, json={"asset": merged})
        return self.client._wrap_result(HuduEndpoint.ASSETS, result)

    def delete(self, item_id: int | str, company_id: int | str) -> Any:
        if item_id is None:
            raise ValueError("Cannot delete object without an id")
        if company_id is None:
            raise ValueError("Asset delete() requires company_id")

        return self.client.delete(f"companies/{company_id}/assets/{item_id}")

    def archive(self, item_id: int | str, company_id: int | str) -> Any:
        if item_id is None:
            raise ValueError("Cannot archive object without an id")
        if company_id is None:
            raise ValueError("Asset archive() requires company_id")

        path = f"companies/{company_id}/assets/{item_id}/archive"
        return self.client.put(path)

    def unarchive(self, item_id: int | str, company_id: int | str) -> Any:
        if item_id is None:
            raise ValueError("Cannot unarchive object without an id")
        if company_id is None:
            raise ValueError("Asset unarchive() requires company_id")

        path = f"companies/{company_id}/assets/{item_id}/unarchive"
        return self.client.put(path)

    def list_for_company(self, company_id: int | str | HuduObject, **params) -> Any:
        if isinstance(company_id, HuduObject):
            company_id = company_id.id

        if company_id is None:
            raise ValueError("Cannot list assets without a company id")

        return self.list(company_id=company_id, **params)

class NetworksResource(BaseResource):
    endpoint = HuduEndpoint.NETWORKS

    def create(self, payload: dict, **kwargs):
        validate_network_address(str(payload.get("address", None)))

        return self.client.create(self.endpoint, payload, **kwargs)


class LabelsResource(BaseResource):
    endpoint = HuduEndpoint.LABELS

    def delete(self, item_id: int | str) -> Any:
        try:
            path = self.client.resolve_path(HuduEndpoint.LABELS_ID, item_id)
            return self.client.delete(path)
        except HuduValidationError as e:
            raise HuduValidationError(
                f"{e}\n\n{describe_single(HuduEndpoint.LABELS_ID)}"
            ) from None

    def _assign_one(
        self,
        to_object: HuduObject,
        label_type: int | str | HuduObject,
        user_id: int | None = None,
        **kwargs,
    ) -> Any:
        ref = to_object.to_labelable_ref()
        payload: dict[str, Any] = {
            "label_type_id": resolve_label_type_id(label_type),
            "labelable_type": ref["type"],
            "labelable_id": ref["id"],
        }
        if user_id is not None:
            payload["user_id"] = user_id
        return self.create(payload, **kwargs)

    def assign(
        self,
        to_object: HuduObject | HuduCollection,
        label_type: int | str | HuduObject,
        user_id: int | None = None,
        **kwargs,
    ) -> Any:
        if isinstance(to_object, HuduCollection):
            if not to_object:
                return HuduCollection([])
            results = [
                self._assign_one(obj, label_type, user_id=user_id, **kwargs)
                for obj in to_object
            ]
            return _wrap_hudu_object_results(results)

        return self._assign_one(
            to_object,
            label_type,
            user_id=user_id,
            **kwargs,
        )

    add_label = assign

    def list_for(
        self,
        to_object: HuduObject,
        label_type_id: int | str | None = None,
        **params,
    ) -> Any:
        ref = to_object.to_labelable_ref()
        query = {
            **params,
            "labelable_type": ref["type"],
            "labelable_id": ref["id"],
        }
        if label_type_id is not None:
            query["label_type_id"] = label_type_id
        return self.list(**query)

    def list_for_collection(
        self,
        to_objects: HuduCollection,
        label_type_id: int | str | None = None,
        **params,
    ) -> Any:
        """
        List labels for many labelable records with one API list per distinct
        ``labelable_type`` (then filter locally by record id), instead of one
        request per object.
        """
        if not to_objects:
            return HuduCollection([])

        if len(to_objects) < LABEL_COLLECTION_BATCH_MIN:
            results: list[Any] = []
            for obj in to_objects:
                results.extend(
                    _flatten_label_results(
                        self.list_for(obj, label_type_id=label_type_id, **params)
                    )
                )
            return _wrap_hudu_object_results(results)

        targets = group_labelable_targets(to_objects)
        results = []
        for labelable_type, id_set in targets.items():
            query = {**params, "labelable_type": labelable_type}
            if label_type_id is not None:
                query["label_type_id"] = label_type_id
            batch = filter_labels_for_targets(
                _flatten_label_results(self.list(**query)),
                {labelable_type: id_set},
                label_type_id=label_type_id,
            )
            results.extend(batch)
        return _wrap_hudu_object_results(results)

    def _strip_matched_labels(self, labels: Iterable[Any]) -> list[Any]:
        removed: list[Any] = []
        for label in labels:
            label_id = label.id if hasattr(label, "id") else label.get("id")
            if label_id is None:
                continue
            removed.append(self.delete(label_id))
        return removed

    def _strip_one(
        self,
        to_object: HuduObject,
        label_type_id: int | str | None = None,
    ) -> list[Any]:
        return self._strip_matched_labels(
            _flatten_label_results(
                self.list_for(to_object, label_type_id=label_type_id)
            )
        )

    def _strip_collection(
        self,
        to_objects: HuduCollection,
        label_type_id: int | str | None = None,
    ) -> list[Any]:
        labels = self.list_for_collection(to_objects, label_type_id=label_type_id)
        return self._strip_matched_labels(_flatten_label_results(labels))

    def strip_label_types_from(
        self,
        to_object: HuduObject,
        label_types: Iterable[Any],
    ) -> list[Any]:
        """Remove labels on ``to_object`` for many label types (one list, then delete)."""
        type_ids = {
            normalize_labelable_id(resolve_label_type_id(label_type))
            for label_type in label_types
        }
        if not type_ids:
            return []

        matched = filter_labels_for_label_type_ids(
            _flatten_label_results(self.list_for(to_object)),
            type_ids,
        )
        return self._strip_matched_labels(matched)

    def strip(
        self,
        to_object: HuduObject | HuduCollection,
        label_type: int | str | HuduObject | None = None,
    ) -> list[Any]:
        label_type_id = None
        if label_type is not None:
            label_type_id = resolve_label_type_id(label_type)

        if isinstance(to_object, HuduCollection):
            if not to_object:
                return []

            if len(to_object) >= LABEL_COLLECTION_BATCH_MIN:
                return self._strip_collection(to_object, label_type_id=label_type_id)

            removed: list[Any] = []
            for obj in to_object:
                removed.extend(self._strip_one(obj, label_type_id=label_type_id))
            return removed

        return self._strip_one(to_object, label_type_id=label_type_id)

    strip_labels = strip


class LabelTypesResource(BaseResource):
    endpoint = HuduEndpoint.LABEL_TYPES

    def _prepare_payload(self, merged: dict[str, Any]) -> dict[str, Any]:
        payload = dict(merged)

        if "color" in payload and payload["color"] is not None:
            payload["color"] = convert_to_hudu_label_color(str(payload["color"]))

        record_types = payload.get("applicable_record_types")
        if record_types is not None:
            payload["applicable_record_types"] = [
                validate_labelable_type(str(record_type))
                for record_type in record_types
            ]

        return payload

    def create(self, payload: dict[str, Any] | None = None, **kwargs) -> Any:
        client_kw = {k: v for k, v in kwargs.items() if k in _CLIENT_HTTP_KWARGS}
        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._prepare_payload(self._merge_payload(payload, body_kw))

        try:
            return self.client.create(self.endpoint, merged, **client_kw)
        except HuduValidationError as e:
            self._reraise_with_description(e)

    def update(
        self,
        item_id: int | str,
        payload: dict[str, Any] | None = None,
        **kwargs,
    ) -> Any:
        client_kw = {k: v for k, v in kwargs.items() if k in _CLIENT_HTTP_KWARGS}
        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._prepare_payload(self._merge_payload(payload, body_kw))

        try:
            return self.client.update(
                HuduEndpoint.LABEL_TYPES_ID,
                item_id,
                merged,
                **client_kw,
            )
        except HuduValidationError as e:
            self._reraise_with_description(e)

class IPAddressesResource(BaseResource):
    endpoint = HuduEndpoint.IP_ADDRESSES

    def create(self, payload: dict, **kwargs):
        validate_ip_address(str(payload.get("address", None)))

        return self.client.create(self.endpoint, payload, **kwargs)


class VlansResource(BaseResource):
    endpoint = HuduEndpoint.VLANS

    def create(self, payload: dict, **kwargs):
        try:
            vlanid = int(str(payload.get("vlan_id")))
        except ValueError:
            raise ValueError("vlan_id must be an integer")
        validate_vlan_id(vlanid)

        payload["archived"] = to_bool(
            str(payload.get("archived")), default=False)
        return self.client.create(self.endpoint, payload, **kwargs)


class VLANZonesResource(BaseResource):
    endpoint = HuduEndpoint.VLAN_ZONES

    def create(self, payload: dict, **kwargs):
        validate_vlan_id_ranges(str(payload.get("vlan_id_ranges")))

        payload["archived"] = to_bool(
            str(payload.get("archived")), default=False)
        return self.client.create(self.endpoint, payload, **kwargs)


class RelationsResource(BaseResource):
    endpoint = HuduEndpoint.RELATIONS

    def create(
        self,
        from_obj: HuduObject,
        to_obj: HuduObject,
        description: str | None = None,
        is_inverse: bool = False,
        **kwargs,
    ):
        from_ref = from_obj.to_relation_ref()
        to_ref = to_obj.to_relation_ref()

        payload = {
            "fromable_id": from_ref["id"],
            "fromable_type": from_ref["type"],
            "toable_id": to_ref["id"],
            "toable_type": to_ref["type"],
            "is_inverse": is_inverse,
        }

        if description is not None:
            payload["description"] = description

        return self.client.create(self.endpoint, payload, **kwargs)

    def list_relations(self, to_object: HuduObject, **params) -> list[Any]:
        """
        List relations involving ``to_object`` using server-side filters.

        Issues two ``GET /relations`` queries (as FROM and as TO), then dedupes by
        relation id. Falls back to a local filter pass so unexpected rows are still
        excluded if the API ignores unknown params on older instances.
        """
        relation_ref = to_object.to_relation_ref()
        relation_type = str(relation_ref["type"])
        object_id = relation_ref["id"]
        object_id_str = str(object_id)

        as_from = self.list(
            fromable_type=relation_type,
            fromable_id=object_id,
            **params,
        )
        as_to = self.list(
            toable_type=relation_type,
            toable_id=object_id,
            **params,
        )

        seen: set[str] = set()
        results: list[Any] = []

        for relation in list(as_from or []) + list(as_to or []):
            relation_id = getattr(relation, "id", None)
            if relation_id is None and isinstance(relation, dict):
                relation_id = relation.get("id")
            key = str(relation_id) if relation_id is not None else repr(relation)
            if key in seen:
                continue

            from_type = str(
                getattr(relation, "fromable_type", None)
                or (relation.get("fromable_type") if isinstance(relation, dict) else "")
                or ""
            ).strip().lower()
            from_id = str(
                getattr(relation, "fromable_id", None)
                or (relation.get("fromable_id") if isinstance(relation, dict) else "")
                or ""
            )
            to_type = str(
                getattr(relation, "toable_type", None)
                or (relation.get("toable_type") if isinstance(relation, dict) else "")
                or ""
            ).strip().lower()
            to_id = str(
                getattr(relation, "toable_id", None)
                or (relation.get("toable_id") if isinstance(relation, dict) else "")
                or ""
            )

            matches = (
                from_type == relation_type.lower() and from_id == object_id_str
            ) or (
                to_type == relation_type.lower() and to_id == object_id_str
            )
            if not matches:
                continue

            seen.add(key)
            results.append(relation)

        return results


class RackStorageResource(BaseResource):
    endpoint = HuduEndpoint.RACK_STORAGES


class RackStorageItemResource(BaseResource):
    endpoint = HuduEndpoint.RACK_STORAGE_ITEMS


class UsersResource(BaseResource):
    endpoint = HuduEndpoint.USERS

    def assign_task(self, task_id: int | str, user_id: int | str):
        if task_id is None:
            raise ValueError("task_id is required to assign a user to a procedure task")
        taskItem = self.client.procedure_tasks.get(task_id)
        procedure = taskItem.procedure

        if not procedure.is_run:
            template_tasks = ordered_procedure_tasks(self.client, procedure.id)
            try:
                tid = int(task_id)
                idx = next(
                    i
                    for i, t in enumerate(template_tasks)
                    if int(t.id) == tid
                )
            except (StopIteration, TypeError, ValueError) as exc:
                raise ValueError(
                    f"Task {task_id!r} is not listed for procedure {procedure.id!r}"
                ) from exc

            run = procedure.kick_off()
            run_tasks = ordered_procedure_tasks(self.client, run.id)
            if idx >= len(run_tasks):
                raise ValueError(
                    "kick_off succeeded but run task list length does not match template"
                )
            taskItem = run_tasks[idx]

        assignedusers = list(taskItem.assigned_users or [])
        if user_id in assignedusers:
            raise ValueError(
                f"User {user_id} is already assigned to task {taskItem.id}"
            )
        assignedusers.append(user_id)
        return taskItem.update({"assigned_users": assignedusers})
class GroupsResource(BaseResource):
    endpoint = HuduEndpoint.GROUPS


class ProceduresResource(BaseResource):
    endpoint = HuduEndpoint.PROCEDURES


class ProcedureTasksResource(BaseResource):
    endpoint = HuduEndpoint.PROCEDURE_TASKS


class CardsResource(BaseResource):
    endpoint = HuduEndpoint.CARDS_LOOKUP


class FlagsResource(BaseResource):
    endpoint = HuduEndpoint.FLAGS


class FlagTypesResource(BaseResource):
    endpoint = HuduEndpoint.FLAG_TYPES


class MagicDashesResource(BaseResource):
    endpoint = HuduEndpoint.MAGIC_DASH


class ActivityLogsResource(BaseResource):
    endpoint = HuduEndpoint.ACTIVITY_LOGS


class ExpirationsResource(BaseResource):
    endpoint = HuduEndpoint.EXPIRATIONS


class ExportsResource(BaseFileResource):
    endpoint = HuduEndpoint.EXPORTS
    model_cls = Exports

    @staticmethod
    def _export_asset_layout_id(item: Any) -> int | None:
        if item is None:
            return None
        if isinstance(item, dict):
            inner = item.get("asset_layout") or item
            if isinstance(inner, dict):
                raw = inner.get("id")
            else:
                raw = None
        else:
            raw = getattr(item, "id", None)
        if raw is None:
            return None
        try:
            return int(raw)
        except (TypeError, ValueError):
            return None

    def _normalize_export_start_body(self, body: dict[str, Any]) -> dict[str, Any]:
        for key in _EXPORT_START_DEFAULT_TRUE_INCLUDES:
            if key not in body:
                body[key] = True

        raw_ids = body.get("asset_layout_ids")
        needs_layouts = raw_ids is None or (
            isinstance(raw_ids, (list, tuple)) and len(raw_ids) == 0
        )
        if needs_layouts:
            layouts = self.client.asset_layouts.list()
            ids: list[int] = []
            for layout in layouts or []:
                lid = self._export_asset_layout_id(layout)
                if lid is not None:
                    ids.append(lid)
            if ids:
                body["asset_layout_ids"] = ids

        return body

    def start(
        self,
        payload: dict[str, Any] | None = None,
        **kwargs: Any,
    ) -> Any:
        """Queue a company data export (``POST /exports``).

        Omitted ``include_*`` booleans default to ``True``. When ``asset_layout_ids`` is
        omitted or empty, all layout IDs from :meth:`HuduClient.asset_layouts.list` are
        sent (matches Hudu behavior of exporting every layout type).
        """
        client_kw = {k: v for k, v in kwargs.items() if k in _CLIENT_HTTP_KWARGS}
        body_kw = {k: v for k, v in kwargs.items() if k not in _CLIENT_HTTP_KWARGS}
        merged = self._merge_payload(payload, body_kw)
        normalized = self._normalize_export_start_body(dict(merged))
        return self.create(normalized, **client_kw)

    def new(self, payload: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        """Same as :meth:`start` (export queue helper)."""
        return self.start(payload, **kwargs)

    def get(self, item_id=None, **params):
        if item_id is None and "id" in params:
            item_id = params.pop("id")

        if item_id is None:
            return super().get(None, **params)

        if not self.endpoint.meta.supports_get:
            raise ValueError(f"{self.endpoint.name} does not support get")

        # Plain GET /exports/{id} returns JSON metadata while the job runs. A
        # ``download=false`` query hits file semantics and can 404 with "Export file
        # not available" until the export completes (see Get-HuduExports in HuduAPI).
        path = self.client.resolve_path(self.endpoint, item_id)
        raw = self.client._get_nonpaginated(path)
        item_endpoint = HuduEndpoint.EXPORTS_ID
        result = self.client._wrap_result(item_endpoint, raw)
        if isinstance(result, HuduCollection):
            if not result:
                return None
            if len(result) == 1 or item_id is not None:
                return result.first() or None

        if isinstance(result, list):
            if not result:
                return None
            if len(result) == 1 or item_id is not None:
                return result[0] or None

            return result

        return result

    def wait_until_downloadable(
        self,
        export_or_id,
        *,
        interval: float = 2.0,
        timeout: float | None = 1800.0,
    ) -> Exports:
        """Poll until ``download_url`` is set (same readiness signal as ``Save-HuduExports``).

        Relying on ``status == \"completed\"`` is brittle across Hudu versions; the API
        exposes a ``download_url`` when the file can be fetched.
        """
        if hasattr(export_or_id, "id"):
            export_id = export_or_id.id
        else:
            export_id = export_or_id

        deadline = None if timeout is None else time.monotonic() + timeout
        terminal_fail = frozenset({"failed", "error", "cancelled", "canceled"})

        while True:
            try:
                current = self.get(export_id)
            except HuduAPIError as exc:
                if exc.status_code != 404 or "not available" not in str(exc).lower():
                    raise
                if deadline is not None and time.monotonic() >= deadline:
                    raise TimeoutError(
                        f"Timed out after {timeout}s waiting for export {export_id!r} "
                        f"(export still unavailable)"
                    ) from exc
                time.sleep(interval)
                continue

            if current is None:
                raise ValueError(f"Export {export_id!r} not found while polling")

            data = current.to_dict()
            status = str(data.get("status") or "").strip().lower()
            if status in terminal_fail:
                raise RuntimeError(
                    f"Export {export_id} ended with status={data.get('status')!r}"
                )

            if str(data.get("download_url") or "").strip():
                return current

            if deadline is not None and time.monotonic() >= deadline:
                raise TimeoutError(
                    f"Timed out after {timeout}s waiting for export {export_id} "
                    f"(last status={data.get('status')!r})"
                )

            time.sleep(interval)

    def download(self, export_or_id, out_dir: str | Path = ".") -> Path:
        """Save export bytes to ``out_dir`` (uses ``download_url`` when set, else API download)."""
        if hasattr(export_or_id, "id"):
            obj = export_or_id
            object_id = obj.id
            if not str(obj.get("download_url") or "").strip():
                obj = self.get(object_id)
        else:
            object_id = export_or_id
            obj = self.get(object_id)

        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        file_name = obj.get("file_name")
        is_pdf = obj.get("is_pdf")
        ext = ".pdf" if is_pdf else ".csv"
        safe_name = self._safe_filename(file_name, f"export-{object_id}{ext}")
        destination = out_dir / safe_name

        download_url = obj.get("download_url")
        if download_url and str(download_url).strip():
            url = str(download_url).strip()
        else:
            url = self.client.build_url(f"exports/{object_id}?download=true")

        response = self.client.get_url(
            url,
            timeout=self.client.timeout,
            allow_redirects=True,
        )
        response.raise_for_status()
        destination.write_bytes(response.content)
        return destination


class S3ExportsResource(BaseResource):
    endpoint = HuduEndpoint.S3_EXPORTS

    def start(
        self,
        payload: dict[str, Any] | None = None,
        **kwargs: Any,
    ) -> Any:
        """Begin an S3-side export (``POST /s3_exports``); same as :meth:`create`."""
        return self.create(payload, **kwargs)


class ListResourceListResource(BaseResource):
    endpoint = HuduEndpoint.LISTS
