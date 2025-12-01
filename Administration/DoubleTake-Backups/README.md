# HuduSoftware - Doubletake
### v 1.20.0

## [Link to Dockerhub Page](https://hub.docker.com/r/hudusoftware/doubletake)

Simplest way to back up and restore a postgres db (and your config files) to/from s3 bucket

## About

#### *This will do two simple things, when you want them done-*
1. Dump and validate/encrypt/compress postgres database with cron schedule
2. Download and decompress/decrypt/validate, then restore dumpfile to postgres.

## Requirements
1. Docker installed
2. S3 Storage with corresponding Access Key and Access Key ID, available storage space
3. Postgresql database (versions 12.2-17.2 tested and working)

### NOTES:
- Postgres Alpine branch is preferred for versions 16+
- DB_PASSWORD and DB_BACKUP_RETENTION are now deprecated parameters (for now)


### Configuration
These items need to be set with docker -e flag, with docker-compose environment like below, or with env-file.
At present, these are designed to be used with a database that has auth-mode of trust. However DB_PASSWORD can be used otherwise. This can be registered as described above or as a docker secret.



```
environment:
    - S3_HOST_BASE=s3.amazonaws.com
    - S3_REGION=us-east-2
    - S3_BUCKET=yourbucketname
    - S3_FOLDER=subfoldername
    - S3_ACCESS_KEY_ID=youraccesskey
    - S3_SECRET_ACCESS_KEY=yoursecretkey
    - CRON_SCHEDULE='0 */6 * * *' # Optional, default is 0 */6 * * * or every 6 hours
    - DB_BACKUP_VERIFY=1 # Optional, default is 1
    - DB_BACKUP_COMPRESS=0 # Optional, default is 0
    - DB_BACKUP_COMPRESS_LEVEL= # Optional, default is 4
    - DB_USER=postgres
    - DB_NAME=hudu_production
    - DB_HOST=db # localhost, unix socket, tcp socket, remote host, etc
    - DB_BACKUP_ENCRYPT_KEY=dddddddddddeeeeeeeeeaaaaaaaaddddddddbbbbbbbbeeeeeeeeeeffffffffff optional, required for encryption, to generate, run openssl rand -hex 32
    - DB_BACKUP_ENCRYPT_IV=dddddeeeeeaaaaadddddbbbbeeeeffff # optional, required for encryption, to generate, run openssl rand -hex 16
    - NO_ENCRYPT=0 (Optional, allows for decrypting existing remote files/dumps, but new dumps will not be encrypted)
    - S3_REQUEST_HEADERS="x-amz-object-lock-retain-until-date:2027-12-31T00:00:00Z\x-amz-object-lock-mode:GOVERNANCE" # Optional, default is blank/none
    - S3_MD5_REQUIRED= # Optional, default is 0, skips MD5 check if set to 1
    - PG_DUMP_USER_ARGS= # Optional, default is none/nil, for special cases, add a string of args to be evaluated
    - AUTO_LIFECYCLE_POLICY_TAGS=0 # Optional, default is 0, supported only if S3 provider allows X-AMZ tags

```

>note on bucketname
Make sure it only contains lowercase letters, numbers, hyphens, and periods

#### Additional Information: CRON_SCHEDULE:
if in the environment section of your docker-compose file, make sure to encapsulate with single quotes `'`. If in  .env file, encapsulate with single quotes `'` or no quotes, as in
`CRON_SCHEDULE=0 */6 * * *`
*or*
`CRON_SCHEDULE='0 */6 * * *'`

#### Additional Information: S3_REQUEST_HEADERS:
Whether in environment section of docker-compose or env_file, make sure to encapsulate with double-quotes `"`.
specify as many headers as you'd like, delimited, or seperated by
`\\`
*(2x backslash)*

leave out *any spaces*, and just specify in this format:
`S3_REQUEST_HEADERS="key:value\\key:value\\key:value"`

Leave blank to exclude user-specified custom headers.

#### Additional Information: AUTO_LIFECYCLE_POLICY_TAGS
If this is set to 1 (for on, default 0), then the X-AMZ-TAG of daily, weekly, monthly will be added when uploading dumpfiles or auxillary backups.
NOTE: If you would like to use this feature, ensure that your S3 Provider allows for X-AMZ-TAGs to be used!
This can be used directly with lifecycle policy on AWS or programmatically for tinkerers that want their own custom lifecycle policy solution

#### Additional Information: S3_MD5_REQUIRED:

This item defaults to 0, but is required for any s3 buckets that have versioning capabilities enabled (aws s3, as example)

If file-locking is enabled for your bucket, this is a must!
While internally, this container uses *blake2 algorithm* for file verification, this option allows for us to provide file versioning (and verification) information to our s3 provider.

IF FILE LOCKING IS ENABLED, BE SURE TO SET THIS TO `1`

#### Additional Information: DB_BACKUP_VERIFY:
This parameter is optional **(defaulting to null for 'off')**
It uses blake2 algorithm (superior to sha256 or md5) to verify file integrity before restore


#### Additional Environment Information: DB_BACKUP_ENCRYPT_KEY and DB_BACKUP_ENCRYPT_IV:
This parameter is optional **(defaulting to blank for 'off')**

This configuration parameter dictates whether or not we perform hashing calculation on file to determine complete file integrity.

>How is file integrity checked, exactly?
>>File integrity is ensured by, first, during upload, calculating the BLAKE2 sequence of your dumpfile.
A file with BLAKE2 hash and bytes size is generated during backup/upload. This file is downloaded during restore/download and checked to ensure the file hasn't changed since it was originally calculated.

#### Additional Environment Information: S3_HOST_BASE:
This allows this to work in a provider-agnostic manner.
See below for common params per-provider-

- AWS
```
      - S3_HOST_BASE=s3.amazonaws.com
```

- Wasabi
```
      - S3_HOST_BASE=s3.wasabisys.com
```

- DigitalOcean
```
      - S3_HOST_BASE=nyc3.digitaloceanspaces.com
```
---

## Auto Lifecycle Taging
**(AUTO_LIFECYCLE_POLICY_TAGS, default 0, off)**
```
Assumptions:
backup A is the current backup
backup B is the most recent backup EXCLUDING A
backup C is the second most recent backup EXCLUDING A
```
#### **3 backup cases (in order of precedence/importance): monthly, weekly, hourly**
### The Rules of Entagment:
---
###### While some of these rules may not work for every case, they are generally useful to apply, since it all comes down to the lifecycle policy being applied. What's important to remember here is the order of precedence, and you can construct your own policies around giving precedence to the latest backups.
---
```
default tags (in chronological order): monthly, hourly, hourly.
with the order of precedence and backup strategy in mind, the current backup will ALWAYS be tagged as monthly. this satisfies the rolling
backup strategy of making sure the most recent backup is always of the highest precedence. as stated previously, the number of backups needing to be re-tagged is 2 (# of backup cases - 1). due to the tag defaults, both of these backups
needing to be re-tagged will be tagged as hourly and therefore we only need to consider 2 overrides: monthly and weekly.

Overrides
----

Monthly overrides occur if the backup we are checking is not in the same month as the month for next backup (more explained below).

weekly overrides occur if the backup we are checking is not in the same week as the week for the next backup.
So, to account for these 2 possible override values, we simply need to check if either condition is satisfied in order of
their precedence (monthly first and then weekly) for each backup
e.g. if backup B was taken in a different month than backup A, override with monthly.

if backup B was taken in a different week than backup A, override as monthly. do nothing if both are unsatisfied and leave as hourly. then,if backup C was taken in a different month than backup B, override with monthly, if backup C was taken in a different week than backup B, override with weekly the only other override needed is then no backups found, which simply have no tags
```

##### Possible **S3 bucket** configuration param combinations are tested for each -release, see possible combinations, below:
-file locking ON, file versioning ON
-file locking OFF, file versioning ON
-file locking OFF, versioning OFF

*NOT RECCOMENDED TO BE RAN WITH-* (not likely supported by your preferred s3 provider):
-file locking ON, versioning OFF

---

##### Possible **DUMPFILE** configuration param combinations are tested for each -release, see possible combinations, below:
-with-user-pg-args,interactive, encrypted, validated, compressed
-with-user-pg-args,interactive, encrypted, validated, not-compressed
-with-user-pg-args,interactive, unencrypted, validated, compressed
-with-user-pg-args,interactive, unencrypted, validated, not-compressed
-with-user-pg-args,interactive, encrypted, not-validated, compressed
-with-user-pg-args,interactive, encrypted, not-validated, not-compressed
-with-user-pg-args,interactive, unencrypted, not-validated, compressed
-with-user-pg-args,interactive, unencrypted, not-validated, not-compressed
-with-user-pg-args,non-interactive, encrypted, validated, compressed
-with-user-pg-args,non-interactive, encrypted, validated, not-compressed
-with-user-pg-args,non-interactive, unencrypted, validated, compressed
-with-user-pg-args,non-interactive, unencrypted, validated, not-compressed
-with-user-pg-args,non-interactive, encrypted, not-validated, compressed
-with-user-pg-args,non-interactive, encrypted, not-validated, not-compressed
-with-user-pg-args,non-interactive, unencrypted, not-validated, compressed
-with-user-pg-args,non-interactive, unencrypted, not-validated, not-compressed
-no-user-pg-args,interactive, encrypted, validated, compressed
-no-user-pg-args,interactive, encrypted, validated, not-compressed
-no-user-pg-args,interactive, unencrypted, validated, compressed
-no-user-pg-args,interactive, unencrypted, validated, not-compressed
-no-user-pg-args,interactive, encrypted, not-validated, compressed
-no-user-pg-args,interactive, encrypted, not-validated, not-compressed
-no-user-pg-args,interactive, unencrypted, not-validated, compressed
-no-user-pg-args,interactive, unencrypted, not-validated, not-compressed
-no-user-pg-args,non-interactive, encrypted, validated, compressed
-no-user-pg-args,non-interactive, encrypted, validated, not-compressed
-no-user-pg-args,non-interactive, unencrypted, validated, compressed
-no-user-pg-args,non-interactive, unencrypted, validated, not-compressed
-no-user-pg-args,non-interactive, encrypted, not-validated, compressed
-no-user-pg-args,non-interactive, encrypted, not-validated, not-compressed
-no-user-pg-args,non-interactive, unencrypted, not-validated, compressed
-no-user-pg-args,non-interactive, unencrypted, not-validated, not-compressed

##### Possible **S3CMD** configuration param combinations are tested for each -release, see possible combinations, below:
-Auto-Lifecycle-Policy-Tagging,MD5-Enforced-In-transit,with-user-specified-X-AMZ-headers
-Auto-Lifecycle-Policy-Tagging,MD5-Enforced-In-transit,without-user-specified-X-AMZ-headers
-Auto-Lifecycle-Policy-Tagging,MD5-NOT-Enforced-In-transit,with-user-specified-X-AMZ-headers
-Auto-Lifecycle-Policy-Tagging,MD5-NOT-Enforced-In-transit,without-user-specified-X-AMZ-headers
-SANS-Auto-Lifecycle-Policy-Tagging,MD5-Enforced-In-transit,with-user-specified-X-AMZ-headers
-SANS-Auto-Lifecycle-Policy-Tagging,MD5-Enforced-In-transit,without-user-specified-X-AMZ-headers
-SANS-Auto-Lifecycle-Policy-Tagging,MD5-NOT-Enforced-In-transit,with-user-specified-X-AMZ-headers
-SANS-Auto-Lifecycle-Policy-Tagging,MD5-NOT-Enforced-In-transit,without-user-specified-X-AMZ-headers

---

## Manual Actions - Backup
##### *(change 'backups' for the actual name of your container.)*
---

##### With Docker Compose:
```
$ docker-compose exec -T backups /bin/bash -c "/backup.sh"
```

##### With Docker:
```
$ docker exec -it {container_id}  /bin/bash -c "/backup.sh"
```
---
expected stdout:
```
appending folder s3://examplepgbackups/yourfolder
s3://examplepgbackups/yourfolder/backup.sql
s3://examplepgbackups/yourfolder/backup.meta
upload: '/dump/backup.meta' -> 's3://examplepgbackups/yourfolder/backup.meta' (147 bytes in 0.4 seconds, 338.52 B/s) [1 of 1]
calculated metadata uploaded to s3://examplepgbackups/yourfolder/backup.meta
compressed backup file to /dump/backup.sql.xz
upload: '/dump/backup.sql.xz' -> 's3://examplepgbackups/yourfolder/backup.sql.xz' (58552 bytes in 0.7 seconds, 84.10 KB/s) [1 of 1]
compressed backup uploaded to s3://examplepgbackups/yourfolder/backup.sql.xz
Upload successful.

```

## Manual Actions - Restore
##### *(change 'backups' for the actual name of your container.)*
---

##### With Docker Compose:
```
$ docker-compose exec -T backups /bin/bash -c "/restore.sh"
```

##### With Docker:
```
$ docker exec -it {container_id}  /bin/bash -c "/restore.sh"
```
---
expected stdout:
```
appending folder s3://examplepgbackups/yourfolder
s3://examplepgbackups/yourfolder/backup.sql
s3://examplepgbackups/yourfolder/backup.meta
attempting download of s3://examplepgbackups/yourfolder/backup.sql.xz to /dump/restore.sql.xz...
download: 's3://examplepgbackups/yourfolder/backup.sql.xz' -> '/dump/restore.sql.xz' (58552 bytes in 0.2 seconds, 265.58 KB/s)
decompressing /dump/restore.sql.xz
decompressed backup file to /dump/restore.sql
download: 's3://examplepgbackups/yourfolder/backup.meta' -> '/dump/backup.meta' (147 bytes in 0.1 seconds, 1224.40 B/s)
metadata downloaded to /dump/backup.meta
Metadata is the same.
Metadata is identical.
Download successful.
(postgres restore jargon)
```
---
## Manual Actions - View Contents of Logfile
##### *(change 'backups' for the actual name of your container.)*
---

##### With Docker Compose:
```
$ docker-compose exec -T backups /bin/sh -c "cat /doubletake.log"
```

##### With Docker:
```
$ docker exec -it {container_id} /bin/sh -c "cat /doubletake.log"
```
---

## Manual Actions - Download / Upload

Outside of restoring and backing up, if a particular backup needs to be retrieved for a particular purpose (using sed to rename a column before restoring, for example), you can volume mount /dump/backup.sql.gz, which will allow your container host to easily modify the file. Similarly, you can reupload an existing dump or download an existing dump (in case of S3 service interruption).

##### With Docker-Compose

```
$ docker-compose exec -T backups /bin/bash -c "/download.sh"
```

```
$ docker-compose exec -T backups  /bin/bash -c "/upload.sh"
```

---

##### With Docker

```
$ docker exec -it {container_id}  /bin/bash -c "/download.sh"
```

```
$ docker exec -it {container_id}  /bin/bash -c "/upload.sh"
```
## Note for cloud providers and service providers

When using with many instances, you can (and should) configure per-folder access policies. This would prevent someone with access to one folder from gaining access to any other folders.

This can be programmatically achieved by making a policy using AWS cli (or equivelent with other s3 providers) or respective API each time you will need to create / grant access to a new folder.

Conversely, it would be wise to keep track of policies, so that they can be revoked in the case of teardown.