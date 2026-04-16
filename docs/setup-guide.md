# Setup Guide — RKE2 auf Swiss OTC

## Voraussetzungen

- OTC Account mit Admin-Rechten (Swiss OTC, Region eu-ch2)
- OTC Access Key + Secret Key
- SSH Key Pair in OTC Console angelegt
- Lokal: `terraform >= 1.5`, `helm >= 3.14`, `kubectl`

## Schritt 1: Repository klonen & Secrets setzen

```bash
git clone https://github.com/Wolfslight-Forgehouse/rke2-sotc-cloud-manager.git
cd rke2-sotc-cloud-manager
```

GitHub Secrets setzen (Settings → Secrets → Actions):
Alle Secrets aus `docs/credentials.md` eintragen.

## Schritt 2: Terraform Variables konfigurieren

```bash
cp terraform/environments/demo/terraform.tfvars.example \
   terraform/environments/demo/terraform.tfvars

# Werte anpassen:
nano terraform/environments/demo/terraform.tfvars
```

## Schritt 3: OBS Bucket für Terraform State

```bash
# In OTC Console: Object Storage Service → Bucket erstellen
# Name: your-tfstate-bucket
# Region: eu-ch2
# Access: Private
```

## Schritt 4: Bootstrap (lokal oder via CI)

### Option A: Lokal

```bash
# Environment-Variablen setzen
source .env

# Vollständiges Bootstrap
./scripts/bootstrap-cluster.sh demo

# Kubeconfig exportieren
export KUBECONFIG=./kubeconfig-demo
kubectl get nodes
```

### Option B: GitHub Actions

1. GitHub → Actions → "Deploy - RKE2 + Cloud Manager"
2. "Run workflow" → environment: `demo`, action: `apply`
3. Warten (~10-15 Minuten)

## Schritt 5: ELB validieren

```bash
export KUBECONFIG=./kubeconfig-demo
./scripts/validate-elb.sh demo
```

Erwartete Ausgabe:
```
✅ External IP assigned: 80.158.x.x
✅ ELB is working correctly!
```

## Troubleshooting

### RKE2 startet nicht
```bash
ssh ubuntu@<MASTER_IP> 'sudo journalctl -u rke2-server -f'
```

### Cloud Manager Fehler
```bash
kubectl logs -n kube-system -l app=otc-cloud-manager -f
```

### ELB wird nicht erstellt
```bash
# Cloud Manager Logs prüfen
kubectl describe svc <your-service>
kubectl get events --sort-by='.lastTimestamp'
```

### Häufige Fehler
| Fehler | Lösung |
|--------|--------|
| `cloud.conf: permission denied` | Secret prüfen, ServiceAccount RBAC prüfen |
| `ELB subnet not found` | `OTC_ELB_SUBNET_ID` korrekt? |
| `unauthorized` | OTC Credentials prüfen, IAM-Rechte prüfen |
| Nodes im `NotReady` | Worker User-Data prüfen, Token korrekt? |
