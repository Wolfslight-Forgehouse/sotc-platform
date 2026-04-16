# ADR-001: Repository Architecture & Deployment Cases

**Status:** Proposed  
**Date:** 2026-04-16  
**Context:** Swiss OTC Kubernetes Platform  

---

## Decision

Split the current monorepo `swiss-otc-k8s-cloud-manager-infra` into **three repositories** with clear boundaries, and support **three deployment cases** through shared Terraform modules with case-specific entrypoints.

## Problem

The current monorepo mixes three concerns with different release cycles:

| Concern | Change Frequency | Trigger |
|---------|------------------|---------|
| Cloud Controller Manager (Go) | On bug/feature | Code change |
| Infrastructure (Terraform) | On infra change | New AZ, flavor, SG |
| Platform (Rancher, ArgoCD, Policies) | On platform evolution | New template, policy |

A CCM bugfix currently requires reviewing Terraform and ArgoCD changes in the same PR. Terraform state risk is coupled to application code changes.

## Three Deployment Cases

The platform must support three ways to deploy RKE2 clusters on Swiss OTC:

```
┌─────────────────────────────────────────────────────────────┐
│                   Swiss OTC (eu-ch2)                        │
│                                                             │
│  Case 1: Full Terraform          Case 2: Join Existing      │
│  ┌─────────────────────┐        ┌─────────────────────┐    │
│  │ terraform apply      │        │ Pre-deployed VMs     │    │
│  │  → VPC + SGs         │        │  → cloud-init only   │    │
│  │  → ECS instances     │        │  → RKE2 join token   │    │
│  │  → RKE2 bootstrap    │        │  → RKE2 agent start  │    │
│  │  → CNI + CCM (Helm)  │        │  → CNI + CCM (Helm)  │    │
│  └─────────────────────┘        └─────────────────────┘    │
│                                                             │
│  Case 3: Rancher-Managed                                    │
│  ┌─────────────────────────────────────────────┐           │
│  │ Rancher UI → Cluster Template                │           │
│  │  → Rancher creates VMs via Node Driver       │           │
│  │  → RKE2 with cni:none                        │           │
│  │  → KubeOVN + CCM via ManagedChart            │           │
│  └─────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### When to Use Which

| Case | When | Who Runs It | Automation Level |
|------|------|-------------|------------------|
| **Full Terraform** | Greenfield deployment, CI/CD pipeline | Platform Team via GitHub Actions | Fully automated |
| **Join Existing** | VMs already provisioned (by another team, manual, or different IaC) | Platform Team via CLI/pipeline | Semi-automated |
| **Rancher-Managed** | Self-service cluster creation, multi-cluster management | Platform Team via Rancher UI | Fully automated (UI-driven) |

---

## Repository Structure

### Repo 1: `sotc-cloud-manager`

**Purpose:** OTC Cloud Controller Manager — the Go application that bridges Kubernetes and OTC APIs.

```
sotc-cloud-manager/
├── cmd/cloud-controller-manager/
│   └── main.go
├── pkg/opentelekomcloud/
│   ├── config/
│   ├── instances/
│   └── loadbalancer/
├── helm/otc-cloud-manager/         # CCM Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── Dockerfile
├── Makefile
├── go.mod
├── go.sum
├── .github/workflows/
│   ├── ci.yml                      # Go test + lint
│   ├── build.yml                   # Docker build + push to GHCR
│   └── release.yml                 # Semantic versioning + Helm chart publish
├── DEVELOPMENT.md
└── README.md
```

**Release artifact:** Container image + Helm chart on GHCR  
**CI trigger:** Changes to `cmd/`, `pkg/`, `helm/`, `Dockerfile`, `go.*`  
**Consumers:** `sotc-infra` (Helm install), `sotc-platform` (ManagedChart reference)

### Repo 2: `sotc-infra`

**Purpose:** Infrastructure provisioning for all deployment cases. Shared Terraform modules with case-specific entrypoints.

```
sotc-infra/
├── modules/
│   ├── compute/                    # ECS instances (shared)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── networking/                 # VPC, subnets, SGs, EIPs (shared)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rke2-config/                # cloud-init template generation (shared)
│   │   ├── main.tf                 # Renders cloud-init from templates
│   │   ├── variables.tf            # master_ip, token, cni, cloud-provider
│   │   └── outputs.tf              # Rendered cloud-init YAML
│   ├── dns/                        # OTC DNS zones + records
│   └── shared-elb/                 # Pre-provisioned ELB (optional)
│
├── cloud-init/
│   ├── rke2-server.yaml.tpl       # RKE2 server (control-plane) cloud-init
│   ├── rke2-agent.yaml.tpl        # RKE2 agent (worker) cloud-init
│   └── common.yaml.tpl            # Shared setup (packages, kernel params)
│
├── environments/
│   ├── full-terraform/             # Case 1: Full automated deployment
│   │   ├── main.tf                 # Uses: compute + networking + rke2-config
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars.example
│   │
│   ├── join-existing/              # Case 2: Pre-deployed VMs
│   │   ├── main.tf                 # Uses: rke2-config only
│   │   ├── variables.tf            # Inputs: existing IPs, SSH keys
│   │   ├── outputs.tf
│   │   └── README.md               # How to use with pre-deployed VMs
│   │
│   └── rancher-managed/            # Case 3: Networking only (Rancher does VMs)
│       ├── main.tf                 # Uses: networking only
│       ├── variables.tf            # VPC config for Rancher node driver
│       ├── outputs.tf              # vpc_id, subnet_id, sg_id for Rancher
│       └── README.md
│
├── scripts/
│   ├── bootstrap-cluster.sh
│   ├── validate-elb.sh
│   └── post-apply.sh
│
├── .github/workflows/
│   ├── infra-plan.yml
│   ├── infra-apply.yml
│   └── infra-destroy.yml
└── README.md
```

**Key design: Shared modules, case-specific entrypoints.**

```
                    ┌─────────────┐
                    │ modules/    │
                    │  compute    │──── Case 1 (full-terraform)
                    │  networking │──── Case 1 + Case 3 (rancher-managed)
                    │  rke2-config│──── Case 1 + Case 2 (join-existing)
                    └─────────────┘
```

| Environment | compute | networking | rke2-config |
|-------------|---------|------------|-------------|
| full-terraform | YES | YES | YES |
| join-existing | no | no | YES |
| rancher-managed | no | YES | no |

### Repo 3: `sotc-platform`

**Purpose:** Kubernetes platform layer — everything that runs on top of the cluster.

```
sotc-platform/
├── rancher/
│   └── cluster-templates/
│       └── kubeovn-rke2/           # Rancher Cluster Template (Case 3)
│           ├── Chart.yaml
│           ├── values.yaml
│           ├── questions.yaml
│           └── templates/
│
├── argocd/
│   ├── apps/                       # ArgoCD Application manifests
│   │   ├── cert-manager.yaml
│   │   ├── monitoring.yaml
│   │   ├── traefik.yaml
│   │   └── kyverno.yaml
│   ├── appsets/
│   └── projects/
│
├── charts/                         # Platform Helm charts (not CCM)
│   ├── external-dns/
│   └── kyverno/
│
├── policies/
│   ├── baseline/
│   ├── best-practices/
│   ├── custom/
│   └── restricted/
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── RANCHER-CLUSTER-TEMPLATE.md
│   ├── KUBE-OVN.md
│   ├── NETWORKING.md
│   ├── STORAGE.md
│   ├── POST-INSTALL.md
│   ├── TEAM-ONBOARDING.md
│   └── ADR/
│       └── 001-repo-architecture.md
│
├── .github/workflows/
│   ├── lint-charts.yml
│   ├── validate-policies.yml
│   └── sync-argocd.yml
└── README.md
```

---

## Cross-Repo Dependencies

```
sotc-cloud-manager                sotc-infra                  sotc-platform
 │                                 │                           │
 │  publishes:                     │  consumes:                │  consumes:
 │  ├─ GHCR container image        │  ├─ CCM image tag         │  ├─ CCM Helm chart
 │  └─ Helm chart (OCI)            │  │   (in post-apply.sh)   │  │   (ManagedChart ref)
 │                                 │  └─ cloud-init templates  │  └─ KubeOVN Helm repo
 │                                 │      (in rke2-config/)    │
 │                                 │                           │
 │  version contract:              │  provides to platform:    │  provides to teams:
 │  └─ Semantic versioning         │  └─ vpc_id, subnet_id,    │  └─ Cluster templates
 │     (v1.0.0, v1.1.0, ...)      │     sg_id (TF outputs)    │     ArgoCD apps
 │                                 │                           │     Kyverno policies
```

### Versioning Strategy

| Repo | Versioning | Trigger |
|------|-----------|---------|
| `sotc-cloud-manager` | Semantic (v1.0.0) | Go/Helm changes |
| `sotc-infra` | Commit-based | Terraform changes |
| `sotc-platform` | Helm chart versions | Template/chart changes |

Pinning strategy:
- `sotc-infra` pins CCM image to a specific tag (e.g., `v1.2.0`) — not `latest`
- `sotc-platform` ManagedChart references CCM Helm chart by version
- KubeOVN version pinned in `values.yaml` of the cluster template

---

## Migration Plan

### Phase 1: Create New Repos (Week 1)

The existing monorepo (`swiss-otc-k8s-cloud-manager-infra`) remains as-is for reference. Three new repos are created and code is copied (not moved) from the monorepo.

1. Create `sotc-cloud-manager` in `Wolfslight-Forgehouse`
   - Copy: `cmd/`, `pkg/`, `helm/otc-cloud-manager/`, `Dockerfile`, `Makefile`, `go.*`
   - Copy: `.github/workflows/ccm-build.yml`, `ci-go.yaml`, `codeql.yaml`
   - Set up GHCR publishing pipeline

2. Create `sotc-platform` in `Wolfslight-Forgehouse`
   - Copy: `rancher/`, `argocd/`, `charts/`, `policies/`, `docs/`
   - Copy: `.github/workflows/kyverno-ci.yaml`, `validate-cni.yml`
   - Set up Helm lint + ArgoCD sync pipelines

3. Create `sotc-infra` in `Wolfslight-Forgehouse`
   - Copy: `terraform/`, `scripts/`, `.github/workflows/infra-*.yml`
   - Add: `cloud-init/` templates (extract from compute module inline scripts)
   - Add: `environments/join-existing/` and `environments/rancher-managed/`

### Phase 2: Wire Cross-Repo Dependencies (Week 2)

1. Update `sotc-infra` to pull CCM image from `sotc-cloud-manager` GHCR
2. Update `sotc-platform` ManagedChart to reference CCM Helm chart from GHCR OCI
3. Update `sotc-infra/environments/rancher-managed/` outputs to match what `sotc-platform` cluster template expects as inputs
4. Test all three deployment cases end-to-end

### Phase 3: Build Join-Existing Case (Week 2-3)

1. Create `sotc-infra/environments/join-existing/`
   - Input: list of existing VM IPs, SSH key, master designation
   - Action: Generate cloud-init, SSH into VMs, apply RKE2 config, start services
   - Alternative: Ansible playbook instead of Terraform for this case
2. Document the flow in `sotc-platform/docs/`

### Phase 4: Cleanup & Handover (Week 3)

1. Add deprecation notice to old monorepo README (do not archive yet — keep as reference)
2. Update all team documentation links
3. Team walkthrough of new structure

---

## Alternatives Considered

### Monorepo with Better Structure

Rejected because:
- CI/CD pipelines would still run Go tests on Terraform changes
- Terraform state management is coupled to unrelated code
- No independent release versioning

### 2-Repo Split (CCM + Everything Else)

Rejected because:
- Terraform and Platform still coupled
- Infrastructure blast radius affects Rancher templates and policies

### Separate Repo Per Deployment Case

Rejected because:
- Would duplicate shared Terraform modules across repos
- One Platform Team managing 5+ repos is overhead without benefit

---

## Consequences

### Positive
- Independent release cycles for CCM, infrastructure, and platform
- Faster CI/CD (Go tests don't run on Terraform PRs)
- Reduced blast radius (TF destroy can't touch ArgoCD apps)
- Clear ownership boundaries even within one team
- Each repo has focused, relevant documentation

### Negative
- Cross-repo version management requires discipline (pin versions, not `latest`)
- Three repos to clone for full local development
- Need to coordinate breaking changes across repos (rare, but happens)

### Mitigations
- Dependabot/Renovate for automated version bumps across repos
- Shared GitHub Actions workflows via a `.github` repo or reusable workflows
- Integration test pipeline that tests all three repos together (weekly)
