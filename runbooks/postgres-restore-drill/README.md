# Postgres Restore Drill

Proves the shared Postgres cluster `main` can be rebuilt from R2. It restores
a throwaway cluster, `drill`, from the latest base backup plus the archived
WAL, and checks that a row written after that backup came back. Nothing in
`main` or in R2 changes, apart from one marker table that the last step drops.

Run it after changing anything in `cluster/platform/charts/postgres`, after
bumping the operator or the barman-cloud plugin, and otherwise now and then.
The real procedure, for when `main` is gone, is under Restore in
`cluster/README.md`.

## Before you start

`mise run kubeconfig production`, then check that `main` is healthy and WAL
archiving works:

```
kubectl cnpg status main -n postgres
```

`Working WAL archiving` must read `OK`, and `Last Successful Backup` must be
set.

## 1. Write a marker

Each command is its own transaction. The switch must run after the insert has
committed: in one `psql -c` they share a transaction, the commit lands in the
next WAL segment, and the drill restores everything but the row.

```
kubectl cnpg psql main -n postgres -- -d app -c "create table if not exists drill (at timestamptz default now())"
kubectl cnpg psql main -n postgres -- -d app -c "insert into drill default values returning at"
kubectl cnpg psql main -n postgres -- -d app -c "select pg_walfile_name(pg_switch_wal())"
```

Note the `at` value and the WAL file name. Wait until the archiver has
uploaded that file, which usually takes seconds:

```
kubectl cnpg psql main -n postgres -- -c "select last_archived_wal, last_failed_wal from pg_stat_archiver"
```

`last_archived_wal` must be the file the switch printed, or a later one.

## 2. Restore into a throwaway cluster

`drill` recovers from the `main` folder in R2 through the same `r2`
ObjectStore. It has no WAL archiver, so it writes nothing to R2, and its
volume uses the Delete storage class, so removing it leaves nothing behind.

```
kubectl apply -f runbooks/postgres-restore-drill/cluster.yaml
```

Wait for `Cluster in healthy state`, about 90 seconds, longer if the
autoscaler has to add a node:

```
kubectl -n postgres get cluster drill -w
```

## 3. Check the marker

```
kubectl cnpg psql drill -n postgres -- -d app -c "select * from drill order by at"
```

Pass: the `at` from step 1 is in the list.

Fail: if the table or the row is missing, find where replay stopped:

```
kubectl -n postgres exec drill-1 -- sh -c 'tail -n 1 /var/lib/postgresql/data/pgdata/pg_wal/*.history'
```

The LSN in the newest history file is where recovery ended. If it comes before the WAL file
from step 1, that file was not in R2 yet when the drill restored. Rerun from
step 2.

## 4. Clean up

```
kubectl delete -f runbooks/postgres-restore-drill/cluster.yaml
kubectl cnpg psql main -n postgres -- -d app -c "drop table drill"
```

Check that the drill's volume went with it:

```
kubectl -n postgres get pvc
```

Only `main-1` should be left.
