# sotc-platform

Kubernetes platform layer for RKE2 clusters on Swiss Open Telekom Cloud (OTC).

Rancher cluster templates, ArgoCD GitOps apps, Kyverno security policies, and team documentation.

## Components

| Directory | Purpose |
|-----------|---------|
| `rancher/cluster-templates/` | Rancher Cluster Templates (KubeOVN + OTC CCM) |
| `argocd/` | ArgoCD Application manifests and AppSets |
| `charts/` | Platform Helm charts (ExternalDNS, Kyverno) |
| `policies/` | Kyverno policies (baseline, best-practices, restricted) |
| `deploy/` | Kubernetes manifests (storage, ingress, security) |
| `docs/` | Architecture docs, team onboarding, guides |

## Related Repositories

| Repository | Purpose |
|-----------|---------|
| [sotc-cloud-manager](https://github.com/Wolfslight-Forgehouse/sotc-cloud-manager) | OTC Cloud Controller Manager |
| [sotc-infra](https://github.com/Wolfslight-Forgehouse/sotc-infra) | Terraform infrastructure provisioning |

## Cluster Templates

Create RKE2 clusters with KubeOVN CNI directly from the Rancher UI:

```bash
cd rancher/cluster-templates/kubeovn-rke2/
helm lint .
helm package .
```

See [docs/RANCHER-CLUSTER-TEMPLATE.md](docs/RANCHER-CLUSTER-TEMPLATE.md) for the full guide.

## Architecture

See [docs/ADR-001-REPO-ARCHITECTURE.md](docs/ADR-001-REPO-ARCHITECTURE.md) for the repository split rationale.
