# CloudNativePG — PostgreSQL Operator

## Übersicht
CloudNativePG (CNPG) managed PostgreSQL Cluster als Kubernetes-native Resource.

## Demo Cluster

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-demo
spec:
  instances: 1
  storage:
    storageClass: csi-cinder-sc-delete
    size: 10Gi
```

## Verbindung

```bash
# Service-Name: <cluster-name>-rw (read-write) / <cluster-name>-ro (read-only)
kubectl get svc | grep postgres

# Password holen
kubectl get secret postgres-demo-app -o jsonpath='{.data.password}' | base64 -d

# Verbinden
kubectl run psql --rm -it --image=postgres:16 -- \
  psql postgresql://app:<password>@postgres-demo-rw/app
```

## Production Cluster (HA)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-prod
spec:
  instances: 3  # Primary + 2 Standby
  storage:
    storageClass: csi-evs-ssd
    size: 50Gi
  backup:
    barmanObjectStore:
      destinationPath: s3://my-postgres-backups
      s3Credentials:
        accessKeyId:
          name: s3-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: s3-creds
          key: SECRET_ACCESS_KEY
```

## Jira Integration
Ticket: SDE-280
