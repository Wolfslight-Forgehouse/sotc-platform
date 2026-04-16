# Rancher Cluster Template — RKE2 + KubeOVN (Swiss OTC)

## Overview

This cluster template allows you to create fully configured RKE2 Kubernetes clusters on Swiss Open Telekom Cloud (OTC) directly from the Rancher UI. It automatically deploys:

- **KubeOVN** as the CNI (Container Network Interface) with Geneve overlay networking
- **OTC Cloud Controller Manager** for automatic ELB (Elastic Load Balancer) provisioning

Instead of manually configuring CNI and cloud integrations after cluster creation, everything is set up through a single form in Rancher.

```
┌─────────────────────────────────────────────────┐
│  Rancher UI → Create Cluster                    │
│  ┌───────────────────────────────────────────┐  │
│  │  Template: RKE2 + KubeOVN (Swiss OTC)     │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────────┐ │  │
│  │  │ Sizing  │ │ OTC     │ │ KubeOVN     │ │  │
│  │  │ S/M/L   │ │ Creds   │ │ Config      │ │  │
│  │  └────┬────┘ └────┬────┘ └──────┬──────┘ │  │
│  └───────┼───────────┼─────────────┼────────┘  │
│          ▼           ▼             ▼            │
│   ┌──────────┐ ┌──────────┐ ┌───────────────┐  │
│   │ RKE2     │ │ OTC CCM  │ │ KubeOVN       │  │
│   │ cni:none │ │ (Helm)   │ │ v1.13 (Helm)  │  │
│   └──────────┘ └──────────┘ └───────────────┘  │
└─────────────────────────────────────────────────┘
```

---

## Prerequisites

Before using this template, ensure the following are in place:

### 1. Rancher Manager (v2.8+)

A running Rancher Manager instance with admin access.

### 2. OTC Node Driver

The `docker-machine-driver-otc` must be registered in Rancher. This driver allows Rancher to create VMs on Swiss OTC.

Navigate to **Cluster Management → Drivers → Node Drivers** and verify that `opentelekomcloud` is listed and active.

### 3. OTC Infrastructure (pre-existing)

| Resource | Description | How to Get |
|----------|-------------|------------|
| **VPC ID** | Virtual Private Cloud | OTC Console → VPC → Details |
| **Subnet ID** | Network subnet (Neutron) | OTC Console → VPC → Subnets |
| **Security Group** | Must allow required ports (see below) | OTC Console → VPC → Security Groups |
| **SSH Key Pair** | Registered in OTC for node access | OTC Console → ECS → Key Pairs |

### 4. Security Group Rules

The security group **must** include these rules for KubeOVN and RKE2 to work:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 6443 | TCP | 0.0.0.0/0 | Kubernetes API server |
| 9345 | TCP | VPC CIDR | RKE2 supervisor (node join) |
| 2379-2380 | TCP | VPC CIDR | etcd cluster communication |
| 10250 | TCP | VPC CIDR | Kubelet API |
| **6081** | **UDP** | **VPC CIDR** | **KubeOVN Geneve tunnel (CRITICAL)** |
| 6641-6642 | TCP | VPC CIDR | OVN database (ovn-central) |
| 30000-32767 | TCP | 0.0.0.0/0 | NodePort services |
| 22 | TCP | Your IP | SSH access |

> **Important:** UDP port 6081 is specific to KubeOVN's Geneve overlay. Without it, cross-node pod communication will fail silently.

### 5. OTC Credentials

You need one of:
- **Rancher Cloud Credential** (recommended) — pre-created under **Cluster Management → Cloud Credentials**
- **Inline credentials** — OTC username, password, domain name, and project ID

---

## Step-by-Step: Creating a Cluster

### Step 1: Register the Template in Rancher

The template is a Helm chart located at `rancher/cluster-templates/kubeovn-rke2/` in this repository.

**Option A: Via Helm Repository**

```bash
# Package the chart
cd rancher/cluster-templates/kubeovn-rke2/
helm package .

# Push to your Helm repository (e.g., GHCR, Chartmuseum, Harbor)
helm push kubeovn-rke2-otc-0.1.0.tgz oci://ghcr.io/wolfslight-forgehouse/charts
```

Then in Rancher: **Cluster Management → Repositories → Create** and add the repository URL.

**Option B: Via Git Repository**

In Rancher: **Cluster Management → Repositories → Create**
- Name: `swiss-otc-templates`
- Target: Git repository
- URL: `https://github.com/Wolfslight-Forgehouse/swiss-otc-k8s-cloud-manager-infra`
- Git Branch: `main`
- Helm Chart Path: `rancher/cluster-templates`

### Step 2: Create a New Cluster

1. Navigate to **Cluster Management → Clusters → Create**
2. Under **RKE2/K3s**, look for **"RKE2 + KubeOVN (Swiss OTC)"**
3. Click to open the configuration form

### Step 3: Fill Out the Form

The form is organized into 6 sections:

#### Section 1: Cluster

| Field | Description | Example |
|-------|-------------|---------|
| Cluster Name | Unique identifier for your cluster | `prod-eu-ch2` |
| Kubernetes Version | RKE2 version to install | `v1.28.15+rke2r1` |

#### Section 2: Sizing

Choose a preset or go custom:

| Preset | Control Plane | Workers | Use Case |
|--------|---------------|---------|----------|
| **Small** | 1 | 2 | Development, testing |
| **Medium** | 3 | 3 | Staging, small production (HA) |
| **Large** | 3 | 5 | Production workloads (HA) |
| **Custom** | 1-5 | 1-20 | Specific requirements |

Default instance types:
- Control Plane: `s3.xlarge.4` (4 vCPU, 16 GB RAM)
- Workers: `s3.large.4` (2 vCPU, 8 GB RAM)

#### Section 3: OTC Infrastructure

Enter your pre-existing OTC resource IDs. These are found in the OTC Console.

#### Section 4: OTC Credentials

**Recommended:** Select an existing Cloud Credential from the dropdown.

If no Cloud Credential exists, fill in the inline fields:
- Auth URL: `https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3` (pre-filled)
- Domain Name: Your OTC domain (e.g., `OTC-EU-CH2-00000000...`)
- Username / Password: OTC IAM user credentials
- Project ID: Found in OTC Console → My Credentials

#### Section 5: Cloud Controller Manager

Enable (default) to get automatic LoadBalancer support:

| Field | Description |
|-------|-------------|
| ELB Subnet ID | Subnet where ELB VIPs are placed |
| ELB Network ID | VPC Network ID for backend connectivity |
| ELB Floating Network ID | `admin_external_net` ID for public IP allocation |

#### Section 6: KubeOVN

Defaults work for most deployments. Only change if you have specific requirements:

| Field | Default | When to Change |
|-------|---------|----------------|
| Pod Subnet | `10.244.0.0/16` | Conflicts with existing VPC ranges |
| Join Subnet | `100.64.0.0/16` | Conflicts with existing infrastructure |
| ovn-central CPU | `100m` | Increase for large clusters (500m+) |

### Step 4: Review and Create

1. Click **"YAML"** in the top-right to review the generated configuration
2. Verify that `cni: none` appears under `machineGlobalConfig`
3. Verify that `kube-ovn/role: master` appears in the control-plane pool labels
4. Click **Create**

### Step 5: Monitor Provisioning

The cluster provisioning follows this sequence:

```
1. VM Provisioning (2-5 min)
   └─ OTC creates ECS instances via the node driver

2. RKE2 Bootstrap (3-5 min)
   └─ RKE2 installs with cni:none — API server starts
   └─ Pods without host networking will be Pending (expected!)

3. KubeOVN Deployment (2-3 min)
   └─ Fleet deploys KubeOVN ManagedChart
   └─ ovn-central schedules on control-plane nodes
   └─ kube-ovn-cni DaemonSet rolls out on all nodes
   └─ Pending pods start getting IPs

4. OTC CCM Deployment (1-2 min)
   └─ Fleet deploys CCM after KubeOVN is ready
   └─ LoadBalancer services become available
```

**Total: ~10-15 minutes** for a small cluster.

Monitor progress in Rancher under **Cluster Management → Clusters → (your cluster) → Conditions**.

---

## Verification

Once the cluster shows **Active** in Rancher, verify the components:

### KubeOVN Status

```bash
# All kube-ovn pods should be Running
kubectl get pods -n kube-system | grep -E "ovn|kube-ovn"

# Expected output:
# kube-ovn-cni-xxxxx          1/1  Running  (one per node)
# kube-ovn-controller-xxxxx   1/1  Running
# kube-ovn-pinger-xxxxx       1/1  Running  (one per node)
# ovn-central-xxxxx           1/1  Running
# ovs-ovn-xxxxx               1/1  Running  (one per node)
```

### OTC CCM Status

```bash
kubectl get pods -n kube-system | grep otc-cloud
# otc-cloud-manager-xxxxx     1/1  Running
```

### Cross-Node Pod Connectivity

```bash
# Create two test pods on different nodes
kubectl run test-a --image=busybox --command -- sleep 3600
kubectl run test-b --image=busybox --command -- sleep 3600

# Verify they're on different nodes
kubectl get pods -o wide | grep test-

# Test connectivity
kubectl exec test-a -- ping -c 3 $(kubectl get pod test-b -o jsonpath='{.status.podIP}')

# Cleanup
kubectl delete pod test-a test-b
```

### LoadBalancer (ELB) Test

```bash
# Create a test service
kubectl expose deployment my-app --type=LoadBalancer --port=80

# Wait for external IP (ELB)
kubectl get svc my-app -w
# NAME     TYPE           EXTERNAL-IP      PORT(S)
# my-app   LoadBalancer   80.xxx.xxx.xxx   80:31234/TCP
```

---

## Troubleshooting

### Pods Stuck in Pending After Cluster Creation

**Expected during provisioning.** KubeOVN needs 2-3 minutes to deploy after RKE2 starts. Pods without host networking will be Pending until then.

If pods remain Pending after 10+ minutes:

```bash
# Check if kube-ovn-cni is running on all nodes
kubectl get ds -n kube-system kube-ovn-cni

# Check ovn-central logs
kubectl logs -n kube-system deployment/ovn-central

# Verify master label exists
kubectl get nodes --show-labels | grep kube-ovn
```

### ovn-central Pod Not Scheduling

The `kube-ovn/role=master` label should be set automatically by the template. If missing:

```bash
# Find control-plane node
MASTER=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | head -1)

# Apply label manually
kubectl label $MASTER kube-ovn/role=master --overwrite
```

### kube-ovn-cni Stuck at 0/N Ready

Usually caused by wrong RKE2 paths. Verify the ManagedChart values:

```bash
# Check the Helm release values
helm get values kube-ovn -n kube-system

# Should show:
# kubelet_conf:
#   KUBELET_DIR: /var/lib/rancher/rke2/agent/kubelet
# cni_conf:
#   CNI_CONF_DIR: /var/lib/rancher/rke2/agent/etc/cni/net.d
#   CNI_BIN_DIR: /opt/cni/bin
```

### CrashLoopBackOff After Many Restarts

Kubernetes exponential backoff can delay recovery up to 5 minutes. Force a fresh start:

```bash
kubectl delete pods -n kube-system -l app=kube-ovn-cni
kubectl delete pods -n kube-system -l app=kube-ovn-controller
```

### LoadBalancer Service Stuck in Pending

Check that the CCM has valid credentials and ELB configuration:

```bash
kubectl logs -n kube-system deployment/otc-cloud-manager | tail -20
```

Common issues:
- Missing `floatingNetworkId` → CCM cannot allocate EIPs
- Wrong `subnetId` for ELB → VIP placement fails
- Expired OTC credentials → re-create the Cloud Credential in Rancher

---

## Architecture Details

### What Happens Under the Hood

The template creates the following Kubernetes resources on the Rancher management cluster:

| Resource | Kind | Purpose |
|----------|------|---------|
| Cluster | `provisioning.cattle.io/v1` | RKE2 cluster definition with `cni: none` |
| CP MachineConfig | `OpentelekomcloudConfig` | OTC VM spec for control-plane nodes |
| Worker MachineConfig | `OpentelekomcloudConfig` | OTC VM spec for worker nodes |
| KubeOVN ClusterRepo | `catalog.cattle.io/v1` | Registers KubeOVN Helm repository |
| KubeOVN ManagedChart | `management.cattle.io/v3` | Deploys KubeOVN into the downstream cluster |
| CCM ManagedChart | `management.cattle.io/v3` | Deploys OTC CCM (after KubeOVN is ready) |

### Why `cni: none`?

RKE2 normally installs Canal as the default CNI. By setting `cni: none`, we prevent this and install KubeOVN as a separate ManagedChart instead. This gives us:

- Full control over KubeOVN version and configuration
- RKE2-specific path overrides (required for KubeOVN to work on RKE2)
- Automatic resource tuning for OTC instance sizes

### Networking: Geneve Overlay

KubeOVN uses Geneve encapsulation (UDP port 6081) to create an overlay network:

```
Node A (10.0.1.10)              Node B (10.0.1.11)
┌──────────────────┐            ┌──────────────────┐
│ Pod 10.244.0.5   │            │ Pod 10.244.1.3   │
│    │              │            │    ▲              │
│    ▼              │            │    │              │
│ kube-ovn-cni     │            │ kube-ovn-cni     │
│    │              │            │    ▲              │
│    ▼              │            │    │              │
│ OVS (Geneve)  ───┼── UDP 6081 ┼──► OVS (Geneve)  │
└──────────────────┘            └──────────────────┘
```

Pod IPs (`10.244.0.0/16`) are internal to the overlay and do not require VPC route table entries.

---

## Sizing Recommendations

| Workload | Preset | CP Flavor | Worker Flavor | Notes |
|----------|--------|-----------|---------------|-------|
| Dev/Test | Small | s3.xlarge.4 | s3.large.4 | Single CP, no HA |
| Staging | Medium | s3.xlarge.4 | s3.xlarge.4 | HA control plane |
| Production | Large | s3.2xlarge.4 | s3.xlarge.4 | HA + headroom |
| GPU/ML | Custom | s3.xlarge.4 | p2s.2xlarge.8 | GPU workers |

For clusters with 10+ nodes, increase `ovn-central` CPU request to `500m`.

---

## Updating the Template

To update the template (e.g., new KubeOVN version):

1. Edit `rancher/cluster-templates/kubeovn-rke2/values.yaml`
2. Bump version in `Chart.yaml`
3. Re-package and push to your chart repository
4. In Rancher, refresh the repository under **Cluster Management → Repositories**

Existing clusters are **not** automatically updated. To upgrade KubeOVN on a running cluster, update the ManagedChart directly in Rancher or use Fleet.
