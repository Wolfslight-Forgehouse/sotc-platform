# Cert-Manager — Automatische TLS Zertifikate

## Übersicht
Cert-Manager automatisiert das Ausstellen und Erneuern von TLS-Zertifikaten via Let's Encrypt.

## Installation
Wird automatisch in der `infra-apply` Pipeline deployed (SDE-279).

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.16.0 \
  --set installCRDs=true
```

## ClusterIssuers

| Name | Umgebung | ACME Server |
|---|---|---|
| `letsencrypt-staging` | Test | staging.api.letsencrypt.org |
| `letsencrypt-prod` | Production | acme-v02.api.letsencrypt.org |

## TLS für Ingress aktivieren

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: meine-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - meine-app.example.com
    secretName: meine-app-tls
  rules:
  - host: meine-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: meine-app
            port:
              number: 80
```

## Troubleshooting

```bash
# Certificate Status
kubectl get certificate -A
kubectl describe certificate <name>

# ACME Challenge prüfen
kubectl get challenge -A
kubectl describe challenge <name>
```
