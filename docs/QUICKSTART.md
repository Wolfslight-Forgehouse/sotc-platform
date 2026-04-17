# Quick Start — RKE2 auf Swiss OTC aufbauen

## Voraussetzungen

- Swiss OTC Account mit `eu-ch2` Zugriff
- IAM User mit AK/SK Credentials und folgenden Permissions:
  - `ELB FullAccess`, `VPC FullAccess`, `ECS FullAccess`
  - `OBS OperateAccess` (für Terraform State)
  - `EVS FullAccess` (für Block Storage)
- GitHub Account mit Zugriff auf dieses Repo
- GitHub Actions aktiviert

## Schritt 1: GitHub Secrets setzen

Unter `Settings → Secrets → Actions → New repository secret`:

```
OTC_ACCESS_KEY       → AK aus OTC IAM
OTC_SECRET_KEY       → SK aus OTC IAM
OTC_PROJECT_ID       → Project ID (eu-ch2_...)
OTC_USERNAME         → IAM Username
OTC_PASSWORD         → IAM Password
OTC_DOMAIN_NAME      → OTC Domain (OTC000000000010000...)
RKE2_TOKEN           → beliebiger sicherer String (z.B. openssl rand -hex 32)
SSH_PRIVATE_KEY      → Ed25519 Private Key
SSH_PUBLIC_KEY       → Ed25519 Public Key
GHCR_PULL_TOKEN      → GitHub Classic PAT (read:packages)
GH_PAT               → GitHub Classic PAT (repo + workflow + write:packages)
```

Und unter `Settings → Environments → production` dieselben Secrets auch als **Environment Secrets** setzen.

## Schritt 2: OBS Bucket für Terraform State

Im OTC Console unter Storage → OBS → Bucket erstellen:
- Name: `your-tfstate-bucket`
- Region: `eu-ch2`
- Versioning: aktiviert

## Schritt 3: CCM Image bauen

```
GitHub Actions → ccm-build.yml → Run workflow
```

Das baut und pushed `ghcr.io/<org>/swiss-otc-cloud-controller-manager:vX.Y.Z` (+ optional `latest` als Floating-Tag). Seit v0.1.0 ist das Image als **Multi-Arch Manifest List** (amd64+arm64) published — siehe [VERSIONS.md](../VERSIONS.md).

## Schritt 4: Cluster aufbauen

```
GitHub Actions → infra-apply.yml → Run workflow → confirm: APPLY
```

Die Pipeline:
1. Terraform erstellt: VPC, Subnets, Security Groups, Bastion, Master, Worker
2. Wartet bis RKE2 bereit ist
3. Deployed OTC CCM (Helm)
4. Deployed Cinder CSI (Helm)
5. Deployed Demo App (kubectl)
6. Wartet auf ELB External-IP
7. HTTP Smoke Test

**Dauer**: ca. 8-12 Minuten.

## Schritt 5: Cluster verifizieren

```bash
# SSH-Tunnel aufbauen
ssh -L 16443:<MASTER_IP>:6443 ubuntu@<BASTION_IP> -N &

# kubeconfig holen
ssh -J ubuntu@<BASTION_IP> ubuntu@<MASTER_IP> \
  "sudo cat /etc/rancher/rke2/rke2.yaml" > rke2.yaml
sed -i 's|https://127.0.0.1:6443|https://localhost:16443|g' rke2.yaml

# Nodes prüfen
kubectl --kubeconfig rke2.yaml --insecure-skip-tls-verify get nodes

# StorageClasses prüfen
kubectl --kubeconfig rke2.yaml --insecure-skip-tls-verify get sc

# Demo App
curl http://<ELB_IP>
```

## Schritt 6: Cluster abbauen

```
GitHub Actions → infra-destroy-v2.yml → Run workflow → confirm: DESTROY
```

Räumt automatisch ELBs auf bevor Terraform destroy läuft.

---

## Typische Fehler & Lösungen

### CCM: `ImagePullBackOff`
```
GHCR_PULL_TOKEN Secret fehlt oder hat falschen Scope.
→ Classic PAT mit read:packages erstellen und als Secret setzen.
```

### CCM: `yaml unmarshal errors`
```
cloud.conf hat falsches Format.
→ Helm --set für availabilityZones entfernen (default aus values.yaml reicht).
```

### Cinder CSI: `You must provide a password`
```
AK/SK funktioniert nicht für openstack-cinder-csi.
→ OTC_USERNAME / OTC_PASSWORD verwenden (Keystone Auth).
```

### Terraform Destroy: `subnet still in use`
```
ELB blockiert Subnet-Deletion.
→ infra-destroy führt Pre-Destroy aus (kubectl delete svc).
→ Falls manuell: OTC Console → ELB löschen, dann destroy.
```
