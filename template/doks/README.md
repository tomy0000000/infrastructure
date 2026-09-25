# DOKS

Terraform owns the cluster. This module has one sharp edge worth knowing before
you touch `kubernetes.node.size` in an environment's `config.yaml`: the node
size cannot be changed in place.

## Why a size change destroys the cluster

`node_size` reaches the `node_pool` block inside
`digitalocean_kubernetes_cluster`, which is the cluster's default node pool
rather than a resource of its own. The provider marks `size` as `ForceNew`, and
a `ForceNew` field nested inside a block replaces the resource that holds it.
So `terraform apply` on a changed size destroys the cluster and builds a new
one.

The cause sits in the DigitalOcean API, which has no operation that changes a
pool's size. Replacing a pool always means create-new then delete-old, and the
provider cannot do that to a pool living inside the cluster resource.

A rebuild costs the cluster ID, the kubeconfig, every PersistentVolume, and the
load balancer IP the shared Gateway answers on. This module does not set
`destroy_all_associated_resources`, so the old load balancer outlives the
destroy and keeps billing until someone deletes it by hand.

Read the plan before applying any size change. `# forces replacement` on
`module.doks.digitalocean_kubernetes_cluster.this` means the whole cluster, not
the pool.

## The default node pool is whichever pool carries the tag

The provider does not track the default pool by ID or by name. On every read it
walks the cluster's pools and adopts the one tagged
`terraform:default-node-pool`. Move that tag to a different pool and the next
refresh adopts that pool instead, with no state surgery and no import. That is
what makes the resize below possible.

## Resize without recreating the cluster

`mise run resize <env>` swaps the default pool for one at the size in
`config.yaml`. The cluster keeps its ID, its load balancer, and its volumes
throughout.

1. Set `kubernetes.node.size` in `<env>/config.yaml` and do not push it yet.
   A push to `main` triggers the apply, which would replace the cluster.
2. `mise run kubeconfig <env>`, since the task drains nodes through kubectl.
3. `mise run resize <env>`.
4. `terraform -chdir=<env> plan` must report `No changes`. Anything proposing
   to replace the cluster means the tag did not land, so fix the tag rather
   than applying.
5. Commit and push the size change.

The task renames the old pool to `<name>-old` and creates the new pool under
the freed name. Once the new nodes are Ready, it cordons and drains the old
nodes, moves `terraform:default-node-pool` to the new pool, and deletes the
old one. It finds both pools by name and size, so a rerun after a failure
resumes where the last run stopped.

Two details matter if you ever do this by hand. doctl replaces the whole tag
set on `node-pool update`, so every call repeats the full list. Nodes are
selected by the `doks.digitalocean.com/node-pool-id` label, because the rename
leaves the pool name label stale on nodes already running.

The Gateway keeps its address across all of this. Worth confirming it never
moved:

```
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

## Rebuilding instead

When the cluster holds no PersistentVolumeClaims, a rebuild is fewer steps than
the swap above and the only thing it really costs is the Gateway's load balancer
IP. Delete the cluster, set the new size, and follow `Restore` in
`cluster/README.md`.

That stops being true as soon as an app stores data. Once a PVC exists, a
rebuild is a restore, and the swap above is the cheaper path.
