# CIS Benchmark — kube-bench für RKE2

## Übersicht
[kube-bench](https://github.com/aquasecurity/kube-bench) prüft den Cluster gegen
den CIS Kubernetes Benchmark (Profil: `rke2-cis-1.7`).

## Deployment

### Einmalig (bei Pipeline Apply)
```bash
kubectl apply -f deploy/k8s/security/kube-bench-job.yaml         # Master
kubectl apply -f deploy/k8s/security/kube-bench-workers-job.yaml # Worker Nodes
```

### Täglich automatisch (CronJob 02:00 Uhr)
```bash
kubectl apply -f deploy/k8s/security/kube-bench-cronjob.yaml
```

### Via ArgoCD (GitOps)
`argocd/apps/kube-bench.yaml` — managed automatisch alle Security-Manifeste.

## Ergebnisse lesen

```bash
# Letzten Job-Pod finden
POD=$(kubectl get pods -n kube-system -l app=kube-bench \
  --field-selector=status.phase=Succeeded \
  -o jsonpath='{.items[-1].metadata.name}')

# Vollständiger Report
kubectl logs $POD -n kube-system

# Nur FAILs anzeigen
kubectl logs $POD -n kube-system | grep "^\[FAIL\]"

# Summary
kubectl logs $POD -n kube-system | grep "total:"
```

## CIS Checks (RKE2-Profil)

| Section | Beschreibung |
|---|---|
| 1.x | Control Plane Components |
| 2.x | etcd |
| 3.x | Control Plane Configuration |
| 4.x | Worker Nodes |
| 5.x | Kubernetes Policies |

## Typische WARN/FAIL bei RKE2

| Check | Status | Grund |
|---|---|---|
| 1.2.6 AlwaysPullImages | WARN | Optional, Performance-Abwägung |
| 4.2.6 protectKernelDefaults | FAIL | Kernel-Parameter nicht gesetzt |
| 5.1.x RBAC | WARN | Default ServiceAccounts |

## Häufige Fixes

```bash
# Kernel Parameter für CIS 4.2.6
echo "kernel.dmesg_restrict=1" >> /etc/sysctl.d/99-cis.conf
sysctl --system
```

## Compliance-Ziel
Ziel: **PASS ≥ 85%** der CIS-Checks für RKE2-CIS-1.7.

Ticket: SDE-284
