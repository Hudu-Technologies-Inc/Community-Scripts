# hudu-magic

[![Publish to PyPI](https://github.com/Hudu-Technologies-Inc/hudu-magic/actions/workflows/publish-pypi.yml/badge.svg?branch=main)](https://github.com/Hudu-Technologies-Inc/hudu-magic/actions/workflows/publish-pypi.yml)

A **tiny, enum-driven, class-based Python API client** for Hudu.

- Minimal dependencies (requests)
- Generated from OpenAPI  
- Low Maintenance
- Designed for clarity and maintainability

---

[PyWheels link](https://www.piwheels.org/project/hudu-magic/)

[PyPi link](https://pypi.org/project/hudu-magic/)

---

# Quick Start

```python
from hudu_magic import HuduClient

client = HuduClient(
    api_key="your_api_key",
    instance_url="https://yourinstance.huducloud.com"
)

company = client.companies.create(name="Test Company")

# Use a real asset_layout_id from your Hudu instance (e.g. from client.asset_layouts.list()).
asset = client.assets.create(
    company_id=company.id,
    name="Router",
    asset_layout_id=1,
)

asset.name = "Updated Router"
asset.save()

asset.delete()
```

---

# Installation

## Install package

```bash
pip install hudu-magic
```
---

# Usage Info and Guide

There are several examples in the examples folder that might be helpful if you're just starting out

# Core Concepts

## Client
Handles auth, requests, pagination, wrapping.

```python
client.assets.list()
```

## Collections
Collection-level operations:
- list()
- get()
- create()
- delete()
- archive()
- unarchive()

```python
assetsforcompany.save()
assetsforcompany.delete()
assetsforcompany.archive()
```

## Models (HuduObject)
Instance-level operations:
- save()
- delete()
- refresh()
- relate_to()
- list_photos()
- list_uploads()
- relate_to()
- upload_to()

```python
asset.save()
asset.delete()
```

## Special Model Methods

### Companies

```python
mycompany.list_assets()
mycompany.list_articles()
mycompany.list_passwords()
mycompany.list_procedures()
mycompany.list_websites()
mycompany.create_website()
```


---

# Creating Objects

The create base method for all objects is simple. you can specify properties in either the payload object (standard dictionary) or as kwargs (just propertyname=value)

This means you can use either:

### kwargs (recommended)
```python
client.assets.create(name="Router", company_id=1, asset_layout_id=10)
```

### dict payload
```python
client.assets.create(payload={"name": "Router", "company_id": 1, "asset_layout_id": 10})
```

---

# Updating Objects

```python
asset.name = "New Name"
asset.save()
```

or

```python
asset.update(name="New Name")
```

---

# Relations

```python
asset.relate_to(website)
```

or

```python
client.relations.create(from_obj=asset, to_obj=website)
```

---

# Uploads

```python
asset.upload_to("file.zip")

uploads = asset.list_uploads()
```

# Photos

```python
asset.add_photo("image.png")

photos = asset.list_photos()
```

---

## Generating builds for new Hudu versions or previous versions

1. Place openapi spec file https://yoururl.huducloud.com/api-docs.json in project directory as hudu-openapiv1.json

2. run `python generate_endpoints.py` after sourcing virtual environment (that has dev dependencies installed)

3. run `./build.sh`

***todo: `.\build.ps1`***

this is designed to be super simple so that subsequent releases can eventually just be automatically generated, tested, validated, and pushed to pypi.

#### Note on building and tests

- Run tests with `./build.sh --test` (or `pytest` from a dev environment with `pip install -e ".[dev]"`).
- Integration tests are skipped unless you set `HUDU_RUN_INTEGRATION=1`. With that set, copy `testenv.example` to `testenv` and fill in `HUDU_TEST_API_KEY` and `HUDU_TEST_INSTANCE`.

---

# Error Handling, Additional Info / Help


If more information is needed, you can call this method on class members to get all associated info from hudu's API spec-

`huduobject.help()`

For resources such as `client.assets`, you can call:

`client.assets.describe()`

or for more verbose info:

`client.assets.help()`

if an object type or resource doesnt support a method call or payload param, you'll be notified of which one(s), if any, are invalid.

# Special Class Methods



## Advanced Use Possibilities

### Multi-Client

You can instantiate two or more client objects, like above, to transfer data from, say, your dev instance to production. This hasn't been extensively tested expecially for objects dependent on companies (assets, passwordfolders)

```python
client2.assets.create(
    **client1.assets.get(6).to_dict()
)
```

# Philosophy

- Simple > clever  
- Explicit > implicit  
- Thin wrapper over Hudu API  

---

# License

MIT


