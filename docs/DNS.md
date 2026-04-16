# OTC Private DNS — Interne Namensauflösung

## Übersicht
OTC Designate (DNS as a Service) stellt eine private DNS Zone bereit,
die nur innerhalb des VPC auflösbar ist. Kein öffentlicher DNS-Eintrag nötig.

## Zone: `sotc.internal`

| Record | Typ | Ziel |
|---|---|---|
| `traefik.sotc.internal` | A | Traefik ELB IP |
| `*.sotc.internal` | A | Traefik ELB IP (Wildcard) |
| `argocd.sotc.internal` | CNAME | traefik.sotc.internal |
| `grafana.sotc.internal` | CNAME | traefik.sotc.internal |
| `prometheus.sotc.internal` | CNAME | traefik.sotc.internal |

## Terraform

```hcl
module "dns" {
  source = "../../modules/dns"
  dns_zone       = "sotc.internal"
  vpc_id         = module.networking.vpc_id
  traefik_elb_ip = "185.x.x.x"  # Nach Apply aus output holen
}
```

## Zweistufiger Rollout

### Schritt 1: Cluster aufbauen (ohne traefik_elb_ip)
```bash
# Erster Apply → ELB IP aus Output lesen
terraform output traefik_elb_ip
```

### Schritt 2: DNS Records befüllen
```bash
# In GitHub Secrets: TF_VAR_traefik_elb_ip = "185.x.x.x"
# Oder: terraform.tfvars anpassen + nochmal Apply
```

## Interne TLS via Cert-Manager

Für `*.sotc.internal` verwenden wir eine selbst-signierte interne CA:

```yaml
# Ingress mit interner TLS
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "sotc-internal-ca-issuer"
spec:
  tls:
  - hosts: [meine-app.sotc.internal]
    secretName: meine-app-tls
```

## Warum Private DNS?

- **Kein öffentlicher DNS** nötig für interne Services
- **Wildcard** `*.sotc.internal` → alle Services über Traefik
- **DNS-01 ACME** Challenge (optional für öffentliche Zertifikate)
- **ExternalDNS** Integration möglich (automatische Record-Erstellung)

## ExternalDNS (optional, nächster Schritt)

ExternalDNS kann automatisch DNS-Records aus Ingress/Service-Annotationen erstellen:

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: meine-app.sotc.internal
```

Ticket: SDE-283
