# remark42 Restore

Puts one nightly folder from the `buckets.remark42` bucket back into the
running `remark42` release. Avatars and pictures go in as files, straight into
the volume. Comments go through remark42's own `restore` command, which wipes
one site and imports its export: comments, votes, blocked and verified users,
subscription e-mails and read-only posts, all under their original IDs.

Two occasions. After a loss, once `mise run charts production apply` has
installed the release empty, see Restore in `cluster/README.md`. And as a
drill against the live release: restoring the newest export reproduces the
state the site already has, and the count at the end proves it. Run the drill
after bumping the chart, and otherwise now and then.

Between the wipe and the end of the import, seconds for a few hundred
comments, the site shows none. If the import fails it stays that way until the
command is run again with the same file, so keep the terminal open.

## Before you start

`mise run kubeconfig production`, the pod `Running`, and `rclone` from
`mise install`. The R2 key comes from 1Password, the account ID from
`instance/production.env`:

```
set -a; source instance/production.env; set +a
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2_ENDPOINT="https://$TF_VAR_cloudflare_account_id.r2.cloudflarestorage.com"
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$(op read op://Develop/endurance-cloudflare-remark42_backup/username)
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$(op read op://Develop/endurance-cloudflare-remark42_backup/credential)
pod=$(kubectl -n remark42 get pod -l app.kubernetes.io/name=remark42 -o jsonpath='{.items[0].metadata.name}')
```

For the drill, note what the site has now, to compare with at the end:

```
curl -s 'https://remark42.tomy.me/api/v1/last/1000?site=blog' | jq 'length, .[0].id'
```

## 1. Pull a folder

Folders are named by the UTC time of the run. The newest is the one to
restore, unless the point is to revert to an earlier day.

```
rclone lsd r2:tomy-backup-remark42
folder=<a folder from the list>
rclone copy "r2:tomy-backup-remark42/$folder" remark42-restore/
ls remark42-restore/backup
```

One `backup-<site>-<date>.gz` per site per day, up to ten days deep. An
export starts with one line of metadata, then one line per comment, deleted
ones included, so its line count is an upper bound on what the site lists.

## 2. Avatars and pictures

Into the running pod, as its own user. The tar is made without macOS resource
forks, which would otherwise land as `._` files.

```
COPYFILE_DISABLE=1 tar -C remark42-restore -cz avatars pictures | kubectl -n remark42 exec -i "$pod" -c remark42 -- tar -C /srv/var -xz
kubectl -n remark42 exec "$pod" -c remark42 -- sh -c 'find /srv/var/avatars -type f | wc -l; find /srv/var/pictures -type f | wc -l'
fd -t f . remark42-restore/avatars | wc -l; fd -t f . remark42-restore/pictures | wc -l
```

The pod's counts are at least the local ones: files already there stay.

## 3. Comments, one site at a time

`restore` posts the file to the admin import API with `ADMIN_PASSWD`, which
the pod already has in its environment, and returns as soon as the server has
accepted it. The import itself runs in the server, so the `wait` call after it
is what blocks until it is done. Repeat the block for each site, `blog` and
`docs`.

```
site=blog
file=$(ls remark42-restore/backup | rg "^backup-$site-" | sort | tail -1)
kubectl -n remark42 cp "remark42-restore/backup/$file" "$pod:/tmp/$file" -c remark42
kubectl -n remark42 exec "$pod" -c remark42 -- /srv/remark42 restore -f "/tmp/$file" -s "$site" --url http://localhost:8080
kubectl -n remark42 exec "$pod" -c remark42 -- sh -c 'curl -s -u "admin:$ADMIN_PASSWD" "http://localhost:8080/api/v1/admin/wait?site='"$site"'"'
```

`completed, status=202` from the first, `{"status":"completed",...}` from the
second. A `409` means an import for that site is still running: wait, then
run the block again.

## 4. Check

```
curl -s 'https://remark42.tomy.me/api/v1/last/1000?site=blog' | jq 'length, .[0].id'
```

For the drill, the same count and newest ID as before. After a loss, the
count the export promised, and a blog post with comments renders them with
their avatars. Then tidy up:

```
rm -r remark42-restore
kubectl -n remark42 exec "$pod" -c remark42 -- sh -c 'rm /tmp/backup-*.gz'
```
