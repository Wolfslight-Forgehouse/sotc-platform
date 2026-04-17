# OTC Cloud Controller Manager — Configuration Guide

> **TL;DR:** OTC has two overlapping "subnet" concepts with confusing naming. The CCM
> `cloud.conf` fields `subnet_id` and `network_id` are **semantically inverted** relative
> to the Terraform provider's output attribute names. Getting this wrong produces a cryptic
> `ELB.8904: subnet not found` from the OTC ELB v3 API.
>
> This page exists because we burned ~2 hours on this during the CCM E2E test (2026-04-17).
> See [SDE-361](https://madcluster.atlassian.net/browse/SDE-361) for the tracking ticket.

## The Naming Conflict

### What Terraform calls them

The OTC Terraform provider's `opentelekomcloud_vpc_subnet_v1` resource exposes three IDs:

| Attribute | OTC semantics | Example |
|-----------|---------------|---------|
| `.id` | **VPC Subnet UUID** — the high-level OTC-proprietary handle | `f2d6ecf7-...` |
| `.subnet_id` | **Neutron Network ID** — the underlying OpenStack network | `ed8272e0-...` |
| `.network_id` | Neutron Network ID (same as `.subnet_id` in practice) | `ed8272e0-...` |

### What ELB v3 API wants

The ELB v3 `POST /v3/{project_id}/elb/loadbalancers` call accepts:

| API field | What OTC's docs say | What OTC actually expects |
|-----------|---------------------|---------------------------|
| `vip_subnet_cidr_id` | "ID of the subnet where the load balancer's VIP resides" | **Neutron Network ID** (NOT VPC Subnet UUID!) |
| `elb_virsubnet_ids` | "IDs of subnets on the downlink plane" | VPC Subnet UUID works |

The word "subnet" appears in both OTC attribute names **and** API field names, but they
reference different concepts. Nobody renames anything because changing the names would
break every external integration.

### What our CCM struct calls them

To make things worse, the CCM's [`NetworkConfig`](https://github.com/Wolfslight-Forgehouse/sotc-cloud-manager/blob/main/pkg/opentelekomcloud/config/config.go)
struct chose field names that match what you'd naively **expect**, not what OTC **accepts**:

```go
type NetworkConfig struct {
    VpcID     string `yaml:"vpc_id"`
    SubnetID  string `yaml:"subnet_id"`   // → vip_subnet_cidr_id → expects NEUTRON NETWORK ID
    NetworkID string `yaml:"network_id"`  // → elb_virsubnet_ids  → expects VPC Subnet UUID
}
```

So you have a three-way naming mismatch:

```
Terraform name    →    CCM struct field   →    OTC ELB v3 API field
────────────────       ────────────────        ────────────────────
.subnet_id        →    SubnetID (as YAML)  →   vip_subnet_cidr_id  ← CORRECT
.id               →    NetworkID            →   elb_virsubnet_ids   ← CORRECT

If you instead do the "obvious" thing:
.id               →    SubnetID             →   vip_subnet_cidr_id  ← ELB.8904 ERROR
```

## The Right Mapping

When you run `terraform output` and want to plug IDs into `cloud.conf`, use **this table**:

| Terraform output | `cloud.conf` field | Goes to OTC ELB API as |
|------------------|--------------------|-----------------------|
| `vpc_id` | `network.vpc_id` | VPC reference |
| `vpc_subnet_v1.subnet_id` | `network.subnet_id` | `vip_subnet_cidr_id` |
| `vpc_subnet_v1.id` | `network.network_id` | `elb_virsubnet_ids` |

## Worked Example

Assume your Terraform state has:

```hcl
# module.networking.opentelekomcloud_vpc_subnet_v1.rke2:
resource "opentelekomcloud_vpc_subnet_v1" "rke2" {
  id         = "f2d6ecf7-7649-4507-86bc-1e61ef3d1d43"  # VPC Subnet UUID
  subnet_id  = "ed8272e0-698a-4d14-a644-e41189acc168"  # Neutron Network ID
  network_id = "ed8272e0-698a-4d14-a644-e41189acc168"  # Neutron Network ID (same)
  vpc_id     = "118ed983-cfa3-4554-a0f8-1a955cf065f2"
}
```

Then your `cloud.conf` (the Kubernetes Secret mounted into the CCM pod) must be:

```yaml
auth:
  auth_url: "https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3"
  access_key: "<AK>"
  secret_key: "<SK>"
  project_id: "<project-uuid>"
region: "eu-ch2"

network:
  vpc_id: "118ed983-cfa3-4554-a0f8-1a955cf065f2"    # From .vpc_id
  subnet_id: "ed8272e0-698a-4d14-a644-e41189acc168" # From Terraform .subnet_id (Neutron)
  network_id: "f2d6ecf7-7649-4507-86bc-1e61ef3d1d43" # From Terraform .id (VPC Subnet)

loadbalancer:
  availability_zones:
    - "eu-ch2a"
```

Note the **swap**: Terraform's `.id` goes to `network.network_id`, and Terraform's
`.subnet_id` goes to `network.subnet_id`. Naively the same-named field (`subnet_id` in
Terraform and `subnet_id` in CCM) feels like the mapping, but that's exactly the trap.

## How to Verify

After deploying the CCM with this cloud-config, create a test `Service type:LoadBalancer`.

**Note on images**: We use [`traefik/whoami`](https://hub.docker.com/r/traefik/whoami) for demo
pods throughout this platform — it's a ~5 MB container that echoes request metadata on port 80,
perfect for LB testing. The platform has standardized on Traefik (see
[ADR / team preference](ARCHITECTURE.md)): `ingress-nginx` is disabled by default in the
cloud-init (`disabled_components` in the compute module), so don't use `nginx`-based examples.

```bash
kubectl create deployment whoami --image=traefik/whoami --replicas=2
kubectl expose deployment whoami --type=LoadBalancer --port=80
```

Within ~15 seconds you should see an `EXTERNAL-IP` assigned:

```
$ kubectl get svc whoami
NAME     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
whoami   LoadBalancer   10.43.171.55   10.0.1.169    80:31684/TCP   10s
```

The CCM logs will show the happy path:

```
Creating new LoadBalancer name="k8s-kubernetes-default-whoami"
Pool created id="..." name="k8s-kubernetes-default-whoami-pool-80"
Member added ip="10.0.1.87" port=31684
Listener created name="k8s-kubernetes-default-whoami-listener-80" port=80
EnsuredLoadBalancer Ensured load balancer
```

### Failure Signature

If the IDs are swapped, CCM logs cycle with:

```
Creating load balancer name="k8s-kubernetes-default-nginx-demo" eipBandwidth=0
Unhandled Error err="...failed to create load balancer: status 404, body: 
  {"error_msg":"subnet f2d6ecf7-... could not be found.",
   "error_code":"ELB.8904",...}"
```

The subnet ID echoed back is the one from `vip_subnet_cidr_id` — if that's the VPC
Subnet UUID (`.id`), ELB v3 rejects it. Swap to the Neutron Network ID (`.subnet_id`).

## Why We Don't "Just Fix" The CCM Struct Names

The temptation is to rename `SubnetID` → `NeutronNetworkID` (or similar) in the Go struct.
We explicitly chose **not** to:

1. **Back-compat**: Existing deployments (including our own production infra tests) use
   the current field names. Renaming is a breaking change for every consumer's cloud.conf.
2. **Upstream alignment**: The upstream `openstack-cloud-controller-manager` uses identical
   names — keeping parity makes it easier to port patches.
3. **Documentation is cheaper than churn**: A prominent comment + this page solves the
   confusion for 99% of readers without breaking anyone.

Instead we added **inline Godoc warnings** at the struct definition and at both getter
functions in `loadbalancer.go`, plus the Helm `values.yaml` has the mapping table.

## See Also

- [SDE-361 — Subnet-ID Naming Mismatch](https://madcluster.atlassian.net/browse/SDE-361)
- [sotc-cloud-manager: pkg/opentelekomcloud/config/config.go](https://github.com/Wolfslight-Forgehouse/sotc-cloud-manager/blob/main/pkg/opentelekomcloud/config/config.go) — inline Godoc warning
- [sotc-cloud-manager: helm/otc-cloud-manager/values.yaml](https://github.com/Wolfslight-Forgehouse/sotc-cloud-manager/blob/main/helm/otc-cloud-manager/values.yaml) — mapping table in comments
- [docs/ARCHITECTURE.md § OTC-Gotchas](ARCHITECTURE.md) — Gotcha #2 and #8 for the full picture
