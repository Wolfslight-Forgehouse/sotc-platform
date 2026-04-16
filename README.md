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
| `deploy/` | Kubernetes manifests and Helm values (storage, ingress, security) |
| `docs/` | Architecture docs, team onboarding, guides |

## Related Repositories

| Repository | Purpose |
|-----------|---------|
| [sotc-cloud-manager](https://github.com/Wolfslight-Forgehouse/sotc-cloud-manager) | OTC Cloud Controller Manager |
| [sotc-infra](https://github.com/Wolfslight-Forgehouse/sotc-infra) | Terraform infrastructure provisioning |

## Architecture

See [docs/ADR-001-REPO-ARCHITECTURE.md](docs/ADR-001-REPO-ARCHITECTURE.md) for the repository split rationale.

---

## How-To: Create a Cluster with Rancher + KubeOVN

### Prerequisites

| Requirement | Description |
|-------------|-------------|
| Rancher Manager | v2.8+ with admin access |
| OTC Node Driver | `docker-machine-driver-otc` registered and active in Rancher |
| OTC VPC + Subnet | Pre-existing (created via [sotc-infra](https://github.com/Wolfslight-Forgehouse/sotc-infra)) |
| Security Group | Must allow UDP 6081 (Geneve), TCP 6443, TCP 9345 |

### Step 1: Register This Repo as a Rancher Catalog

**Option A: Git Repository**

In Rancher: **Cluster Management → Repositories → Create**
- Name: `sotc-platform`
- Target: **Git repository**
- Git Repo URL: `https://github.com/Wolfslight-Forgehouse/sotc-platform`
- Git Branch: `main`

**Option B: Helm Package**

```bash
cd rancher/cluster-templates/kubeovn-rke2/
helm package .
# Push to your chart registry (GHCR, Harbor, Chartmuseum)
helm push kubeovn-rke2-otc-0.1.0.tgz oci://ghcr.io/wolfslight-forgehouse/charts
```

Then add the OCI registry as a Rancher repository.

### Step 2: Create a Cluster from the Template

1. Go to **Cluster Management → Clusters → Create**
2. Under **RKE2/K3s**, select **"RKE2 + KubeOVN (Swiss OTC)"**
3. Fill out the 6-section form:

| Section | Key Fields |
|---------|-----------|
| **Cluster** | Name, Kubernetes version |
| **Sizing** | Small (1+2) / Medium (3+3) / Large (3+5) / Custom |
| **OTC Infrastructure** | VPC ID, Subnet ID, Security Groups |
| **OTC Credentials** | Cloud Credential or inline (auth URL, domain, user/pass, project) |
| **Cloud Controller Manager** | ELB Subnet, Network, Floating Network IDs |
| **KubeOVN** | Pod Subnet (default: 10.244.0.0/16) |

4. Click **Create**

### Step 3: Wait for Provisioning (~10-15 min)

```
1. VM Provisioning      (2-5 min)  → OTC creates ECS instances
2. RKE2 Bootstrap       (3-5 min)  → RKE2 starts with cni:none
3. KubeOVN Deployment   (2-3 min)  → Fleet installs KubeOVN
4. OTC CCM Deployment   (1-2 min)  → Fleet installs CCM after KubeOVN
```

### Step 4: Verify

```bash
# KubeOVN pods
kubectl get pods -n kube-system | grep -E "ovn|kube-ovn"

# OTC CCM
kubectl get pods -n kube-system | grep otc-cloud

# Cross-node connectivity
kubectl run test-a --image=busybox -- sleep 3600
kubectl run test-b --image=busybox -- sleep 3600
kubectl exec test-a -- ping -c 3 $(kubectl get pod test-b -o jsonpath='{.status.podIP}')
kubectl delete pod test-a test-b

# LoadBalancer test
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx -w  # Wait for EXTERNAL-IP
```

For the full guide, see [docs/RANCHER-CLUSTER-TEMPLATE.md](docs/RANCHER-CLUSTER-TEMPLATE.md).

---

## How-To: Set Up ArgoCD GitOps

### Step 1: Deploy ArgoCD on the Cluster

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 7.7.0 \
  --set server.insecure=true \
  --wait --timeout 8m
```

### Step 2: Bootstrap App-of-Apps

```bash
# Create projects
kubectl apply -f argocd/projects/infrastructure.yaml
kubectl apply -f argocd/projects/workloads.yaml

# Bootstrap root app (syncs all other apps)
kubectl apply -f argocd/apps/root.yaml

# Bootstrap workload AppSet
kubectl apply -f argocd/appsets/workloads-appset.yaml
```

### Step 3: Verify

```bash
# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# List synced apps
kubectl get applications -n argocd
```

ArgoCD will auto-sync: cert-manager, monitoring (Prometheus + Grafana), Traefik, Kyverno, CloudNativePG, ExternalDNS, and kube-bench.

---

## How-To: Apply Kyverno Policies

Policies are organized by CIS Benchmark levels:

```bash
# Baseline (required for all clusters)
kubectl apply -f policies/baseline/

# Best practices (recommended)
kubectl apply -f policies/best-practices/

# Restricted (for security-sensitive workloads)
kubectl apply -f policies/restricted/

# Custom OTC policies
kubectl apply -f policies/custom/

# Verify
kubectl get clusterpolicies
```

All policies run in **audit mode** by default — they report violations but don't block deployments.

---

## Credentials Setup

### OTC Credentials for Rancher

**Option A: Rancher Cloud Credential (Recommended)**

1. In Rancher: **Cluster Management → Cloud Credentials → Create**
2. Select your node driver (opentelekomcloud)
3. Enter:
   - Auth URL: `https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3`
   - Domain Name: `OTC-EU-CH2-...`
   - Username / Password
   - Project ID

**Option B: Inline Credentials**

Fill in the credential fields directly in the cluster template form. Less secure — credentials are stored as Helm release secrets.

### Finding OTC Resource IDs

After provisioning networking with [sotc-infra](https://github.com/Wolfslight-Forgehouse/sotc-infra):

```bash
cd sotc-infra/terraform/environments/demo
terraform output

# Output includes:
# vpc_id           = "vpc-xxxxx"
# subnet_id        = "subnet-xxxxx"
# security_group_id = "sg-xxxxx"
# subnet_network_id = "network-xxxxx"  (for ELB)
```

Or find them in the OTC Console:
- **VPC ID**: VPC → Virtual Private Cloud → Details
- **Subnet ID**: VPC → Subnets → Details
- **Security Group**: VPC → Security Groups
- **Floating Network ID**: `admin_external_net` (use `openstack network list --external`)

### OTC IAM Endpoint

For Swiss OTC (eu-ch2):
```
https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3
```

> **Important:** Swiss OTC uses `iam-pub` (not `iam`) and the `.sc.` infix in the domain.
