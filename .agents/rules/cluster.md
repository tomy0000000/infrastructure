---
paths:
  - "cluster/**"
---

# Cluster releases

- One helmfile. `needs:` is the only ordering, file position is for readers.
  A release that renders a kind another release installs (a `Certificate`, an
  `HTTPRoute`, an `ExternalSecret`) sets `disableValidationOnInstall: true`,
  because `helmfile apply` diffs everything before it syncs anything and
  helm-diff validates against the API server.
- Adding a foreign kind to a release that is already installed is a two-apply
  change, the provider first, since that setting only covers first install.
- CRDs a chart does not upgrade itself come from a `presync` hook script under
  `cluster/scripts/`, server-side applied, taking the version from
  `{{ .Release.Version }}` so the chart version stays the one pin. Envoy
  Gateway's CRDs chart cannot be a Helm release: its release Secret exceeds
  1 MB. origin-ca-issuer's chart ships no CRDs at all.
- Never delete the six Gateway API CRDs DOKS pre-installs expecting them
  back. DOKS installs them once at provisioning and never reconciles them.
  The hook takes them over with `--force-conflicts` and marks them
  `install-policy: external`.
- No `--take-ownership`, no `--args` on the command line. Everything a first
  install needs is declared next to its release.
- Every workload Secret is an `ExternalSecret` against the `onepassword`
  ClusterSecretStore, declared next to its consumer, or in `cluster-config`
  when the consuming chart has no `extraObjects`. Never `kubectl create
  secret`, never an `op://` placeholder in a README. `refreshInterval: 1h`,
  the account is on the Family plan with 1,000 reads a day.
- 1Password items are `<cluster>-<vendor>-<purpose>`, dashes between parts,
  underscores as spaces within one, API Credential type, token in
  `credential`. The cluster segment comes from `kubernetes.name` in
  `config.yaml`. Document each new item in `cluster/secrets.md`.
- An app is two releases reading one values file: the chart, and
  `<app>-route` from `apps/charts/route`, which reads the `httpRoute:` block
  the app chart ignores. Separate releases so one app failing cannot block
  another's route. The route release needs only its own app.
- One shared Gateway. Each Gateway is a DigitalOcean load balancer.
- Stateful apps use `do-block-storage-retain`, so an uninstall keeps the
  volume, and `strategy: Recreate`, because a block volume mounts on one pod
  and a rolling update deadlocks. Retain protects against an uninstall, not a
  lost cluster: name the backup gap when adding state.
- Set small resource requests on every release. The pool floor is one
  `s-1vcpu-2gb` node and the Gateway's proxy alone holds 512Mi.
- Pin chart versions. Bumping one means reading the diff of what it renders.
