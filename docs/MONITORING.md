# kube-prometheus-stack — Monitoring & Alerting

## Komponenten
- **Prometheus** — Metriken-Sammlung + Alerting
- **Grafana** — Dashboards (admin/admin)
- **Alertmanager** — Alert-Routing
- **node-exporter** — Node-Metriken
- **kube-state-metrics** — Kubernetes-Objekt-Metriken

## Zugang
- **Grafana:** http://grafana.local (via Ingress)
- **Credentials:** admin / admin (bitte ändern!)

## Default Dashboards
- Kubernetes Cluster Overview
- Node Exporter Full
- Kubernetes Pods

## Custom Alert-Regel

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-alerts
  namespace: monitoring
spec:
  groups:
  - name: my-rules
    rules:
    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} crasht"
```

## Retention
7 Tage (konfigurierbar via `prometheus.prometheusSpec.retention`)

## Jira Integration
Ticket: SDE-281
