# GitHub Secrets — Required Credentials

## Pflicht-Secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret Name | Beschreibung | Woher |
|---|---|---|
| `OTC_ACCESS_KEY_ID` | OTC Access Key | OTC Console → IAM → Users → Security Credentials |
| `OTC_SECRET_ACCESS_KEY` | OTC Secret Key | Beim Key-Erstellen einmalig sichtbar |
| `OTC_DOMAIN_NAME` | Tenant/Domain Name | OTC Console → Account-Einstellungen |
| `OTC_PROJECT_ID` | Projekt-ID | OTC Console → Projekte |
| `OTC_AUTH_URL` | IAM Endpoint | `https://iam.eu-ch2.otc.t-systems.com/v3` |
| `OTC_USERNAME` | IAM Username | OTC Console → IAM |
| `OTC_PASSWORD` | IAM Passwort | OTC IAM |
| `OTC_TENANT_NAME` | Tenant/Projekt Name | OTC Console |
| `OTC_ELB_SUBNET_ID` | Subnet für ELB | OTC Console → VPC → Subnets |
| `OTC_FLOATING_NETWORK_ID` | Externe Netzwerk-ID | OTC Console → Network → Floating IPs |
| `OTC_NETWORK_ID` | VPC Network ID | OTC Console → VPC |
| `KUBECONFIG_BASE64` | base64 kubeconfig | Nach Cluster-Init: `base64 -w0 kubeconfig` |

## OTC Console Pfade

### Access Keys erstellen
1. OTC Console → rechts oben → Username → My Credentials
2. Access Keys → Create Access Key
3. Download sofort! (Secret wird nur einmal angezeigt)

### Projekt-ID finden
1. OTC Console → oben links → Projekt-Dropdown
2. "Manage Projects" → Projekt-ID in der Liste

### Subnet- und Netzwerk-IDs
Nach dem ersten Terraform-Apply:
```bash
cd terraform/environments/demo
terraform output
```

### Floating Network ID
```bash
# Mit OpenStack CLI:
openstack network list --external
# → admin_external_net ID
```

## Für lokale Entwicklung (.env)

```bash
# .env (nie committen!)
export OTC_ACCESS_KEY_ID=AK...
export OTC_SECRET_ACCESS_KEY=SK...
export OTC_DOMAIN_NAME=OTC-EU-DE-...
export OTC_PROJECT_ID=...
export OTC_AUTH_URL=https://iam.eu-ch2.otc.t-systems.com/v3
export OTC_USERNAME=...
export OTC_PASSWORD=...
export OTC_TENANT_NAME=...
```
