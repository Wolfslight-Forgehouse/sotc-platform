# Version Matrix — Swiss OTC Kubernetes Platform

> **Stand**: 2026-04-18
>
> Diese Datei ist die **Single-Source-of-Truth** für alle Versionen von Platform-Komponenten,
> die in `sotc-platform` deployed werden. Wenn du einen Tag in deploy/**/*.yaml änderst,
> aktualisiere auch diese Datei im selben Commit.

## Platform Release

Die Platform wird als Gesamtsystem versioniert. Die aktuelle Release-Reihe:

| Component | Release |
|-----------|---------|
| **sotc-platform** | `v0.1.0` |
| **sotc-cloud-manager** (CCM) | `v0.1.0` |
| **sotc-infra** (Terraform) | `v0.1.0` |

Die drei Repos werden synchron getagged — ein `v0.1.0` Tag bedeutet: diese drei Commits wurden zusammen E2E-validiert.

## Container Images

### Unsere eigenen Images (ghcr.io/wolfslight-forgehouse/)

Packages sind **private** — Cluster brauchen `imagePullSecret: ghcr-pull`.

| Image | Tag | Platform | Where Pinned |
|-------|-----|----------|--------------|
| `swiss-otc-cloud-controller-manager` | `v0.1.0` | amd64 + arm64 (Multi-Arch Manifest List) | `deploy/helm/swiss-otc-ccm/values.yaml`, `rancher/cluster-templates/kubeovn-rke2/values.yaml` |
| `csi-s3-driver` | `v0.43.4` | amd64 (single-arch) | `deploy/helm/csi-s3/values.yaml`, `docs/STORAGE.md`, `docs/GITOPS.md` |

### Upstream Images

| Image | Tag | Purpose | Where Pinned |
|-------|-----|---------|--------------|
| `busybox` | `1.36` | Demo-Pods, CI Connectivity Tests | `deploy/k8s/storage/demo-*.yaml`, `.github/workflows/validate-cni.yml` |
| `aquasec/kube-bench` | `v0.15.0` | CIS Benchmark Jobs | `deploy/k8s/security/kube-bench-*.yaml` |
| `halverneus/static-file-server` | `v1.8.12` | Demo-App HTTP-Server (nginx replacement) | `deploy/apps/demo-app/deployment.yaml` |
| `traefik/whoami` | `latest`* | E2E Test Target | Ad-hoc (nicht in Repo committed) |
| `traefik/traefik` (Helm Chart) | `>= 26.0.0` | Ingress Controller (public + internal) | `deploy/k8s/ingress/traefik-values.yaml` |

\* `traefik/whoami:latest` wird **nicht committed** sondern nur in Ad-hoc E2E Tests genutzt.
 Kyverno Policy `disallow-latest-tag` ist daher **nicht verletzt**.

## CNI + External Charts

| Chart | Version | Upstream | Purpose |
|-------|---------|----------|---------|
| `kube-ovn` | `v1.13.0` | https://kubeovn.github.io/kube-ovn | Alternative CNI (Geneve Overlay) |
| `cilium` | built-in RKE2 | — | Primary CNI (kubeProxyReplacement) |
| `openstack-cinder-csi` | `2.35.0` | https://kubernetes.github.io/cloud-provider-openstack | EVS Block Storage |
| `csi-s3` (Helm chart) | `0.43.4` | https://yandex-cloud.github.io/k8s-csi-s3/charts | OBS Object Storage |

## Kubernetes + RKE2

| Component | Version | Notes |
|-----------|---------|-------|
| **RKE2** | `v1.34.6+rke2r3` | Getestet in SDE-295 bis SDE-393 |
| **Kubernetes** | `v1.34.6` | RKE2-embedded |
| **OTC Ubuntu Image** | `Standard_Ubuntu_22.04_latest` | via Terraform `data "opentelekomcloud_images_image_v2"` |

## OTC-Specific Versions

| API | Endpoint | Version |
|-----|----------|---------|
| **IAM** | `iam-pub.eu-ch2.sc.otc.t-systems.com` | v3 |
| **ELB** | `elb.eu-ch2.sc.otc.t-systems.com` | **v3** (Dedicated Load Balancer) |
| **VPC** | `vpc.eu-ch2.sc.otc.t-systems.com` | v1 |
| **ECS** | `ecs.eu-ch2.sc.otc.t-systems.com` | v1.1 |
| **NAT** | `nat.eu-ch2.sc.otc.t-systems.com` | v2 |

## Version-Update Workflow

Wenn du ein Image-Tag änderst:

1. **Edit** die entsprechende YAML-Datei in `deploy/`
2. **Update** diese VERSIONS.md Tabelle
3. **Commit** beides im gleichen Commit: `chore(deps): bump <component> <old> → <new>`
4. **Tag** einen neuen Platform-Release wenn alle 3 Repos zusammen stabil sind

## Why Pin :latest?

Unsere Kyverno Policy `policies/best-practices/disallow-latest-tag.yaml` verbietet
`image: *:latest` in allen User-Namespaces (aktuell als `Audit`, nächste Iteration als `Enforce`).

`:latest` ist problematisch weil:
- **Reproducibility**: Gleicher Commit-SHA kann in 2 Wochen unterschiedliche Images ziehen
- **Rollback**: Nach einem Fehler kann man nicht zu "dem Image das gestern lief" zurück
- **Multi-Node Drift**: Pod A auf Node 1 hat cached `latest` vom Montag, Pod B auf Node 2 hat `latest` vom Donnerstag → inkonsistentes Behaviour

Lösung: Konkrete Tags überall. Floating Tags (`latest`, `stable`) nur für Dev/Quickstart.

## References

- [Confluence: Swiss OTC Platform Guide](https://madcluster.atlassian.net/wiki/spaces/SkyNetLabs/pages/580321282)
- [SDE-328 Epic: Terraform+Ansible Bootstrap](https://madcluster.atlassian.net/browse/SDE-328)
- [SDE-391 Epic: Rancher-Native Platform](https://madcluster.atlassian.net/browse/SDE-391)
- [SDE-352: Multi-Arch CCM Release](https://madcluster.atlassian.net/browse/SDE-352)
