---
paths:
  - "template/**"
  - "staging/**"
  - "production/**"
  - "scripts/import-resources.sh"
---

# Terraform

- State is throwaway. Every run starts empty and `scripts/import-resources.sh`
  adopts what exists by looking it up in the provider's API by name. A new
  resource kind needs an import function there, or the next run tries to
  create a duplicate. Cluster and instance lookups fail hard on a failed
  import for that reason.
- Nothing that lives inside the cluster goes in Terraform. `helm_release`
  cannot survive throwaway state, and Helm already keeps release state in
  the cluster.
- `config.yaml` per environment is the single source of truth. `main.tf`
  reads it into locals, helmfile reads it as environment values. Add settings
  there, not as variables.
- Load balancers and volumes are created through the Kubernetes API, so
  Terraform does not know they exist. `destroy_all_associated_resources` on
  the DOKS module is still unset: a cluster delete leaves them behind and
  billing. Fix it before relying on cluster recreation as a routine.
- Some cluster settings are one-way doors fixed at creation: `ha`, and
  whether the cluster is VPC-native. Decide them before the first apply, and
  say so when a change would need a recreate.
- Recreating a cluster is the DR rehearsal: delete it out of band, then run
  the normal apply. Everything on it comes back from `cluster/`.
