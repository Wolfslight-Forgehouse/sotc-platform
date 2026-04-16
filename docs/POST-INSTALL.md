# Post-Installation Guide — CCM, CSI, OBS, Annotations

> Nach dem Cluster-Setup: Wie man Cloud-native Features nutzt.

---

## Cloud Controller Manager (CCM)

### Wie der CCM funktioniert

Wenn du einen Kubernetes Service mit `type: LoadBalancer` erstellst, macht der CCM automatisch:

1. OTC ELB v3 Dedicated erstellen
2. Listener für den Port anlegen
3. Pool mit Health Monitor erstellen
4. Alle Node-IPs als Members registrieren
5. Optional: EIP binden (wenn annotiert)
6. Service `EXTERNAL-IP` setzen

### LoadBalancer Service — Basis

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mein-service
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: meine-app
  ports:
    - port: 80
      targetPort: 8080
```

→ CCM erstellt automatisch ELB **ohne** EIP (VPC-intern).

---

### CCM Annotations — Vollständige Referenz

#### Netzwerk
```yaml
# Subnet für ELB VIP (PFLICHT wenn mehrere Subnets)
otc.io/elb-virsubnet-id: "<neutron-subnet-id>"

# Bestehenden shared ELB nutzen statt neuen erstellen
kubernetes.io/elb.id: "<elb-id>"
```

#### EIP (öffentliche IP)
```yaml
# EIP automatisch erstellen und binden
otc.io/elb-eip-type: "5_bgp"                    # IP-Typ (5_bgp = Standard)
otc.io/elb-eip-bandwidth-name: "mein-service-bw"
otc.io/elb-eip-bandwidth-size: "10"              # Mbps
otc.io/elb-eip-charge-mode: "traffic"            # traffic | bandwidth
```

#### Health Check
```yaml
otc.io/elb-health-check-flag: "on"
otc.io/elb-health-check-option: '{"protocol":"TCP","interval":5,"timeout":3,"unhealthy_threshold":3}'
```

#### Vollständiges Beispiel (public Service mit EIP)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp-public
  annotations:
    otc.io/elb-virsubnet-id: "8d1936fa-6a47-4435-8d4d-c691cdf24eb7"
    otc.io/elb-eip-type: "5_bgp"
    otc.io/elb-eip-bandwidth-name: "webapp-bw"
    otc.io/elb-eip-bandwidth-size: "10"
    otc.io/elb-eip-charge-mode: "traffic"
spec:
  type: LoadBalancer
  selector:
    app: webapp
  ports:
    - port: 443
      targetPort: 8443
```

---

## Shared ELB (pre-deployed via Terraform)

Wenn `enable_shared_elb = true` in Terraform — ein ELB für mehrere Services:

```bash
# ELB ID aus Terraform Output holen
SHARED_ELB_ID=$(cd terraform/environments/dev && terraform output -raw shared_elb_id)
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: service-a
  annotations:
    kubernetes.io/elb.id: "<SHARED_ELB_ID>"       # ← shared ELB nutzen
    otc.io/elb-virsubnet-id: "<subnet-id>"
    kubernetes.io/elb.protocol: TCP
    kubernetes.io/elb.port: "80"                   # Port am shared ELB
spec:
  type: LoadBalancer
  selector:
    app: service-a
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: service-b
  annotations:
    kubernetes.io/elb.id: "<SHARED_ELB_ID>"       # gleicher ELB!
    otc.io/elb-virsubnet-id: "<subnet-id>"
    kubernetes.io/elb.port: "8080"                 # anderer Port!
spec:
  type: LoadBalancer
  selector:
    app: service-b
  ports:
    - port: 8080
      targetPort: 9000
```

---

## EVS Block Storage (Cinder CSI)

### StorageClasses

```bash
kubectl get storageclass
# csi-cinder-sc-delete    (default, Delete Policy)
# csi-cinder-sc-retain    (Retain Policy)
```

### PVC erstellen

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mein-evs-pvc
spec:
  accessModes:
    - ReadWriteOnce          # EVS = RWO only
  storageClassName: csi-cinder-sc-delete
  resources:
    requests:
      storage: 10Gi
```

### Pod mit EVS PVC

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: evs-demo
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: mein-evs-pvc
```

---

## OBS Object Storage (CSI-S3 / GeeseFS)

### StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-obs
provisioner: ru.yandex.s3.csi
parameters:
  mounter: geesefs
  options: "--memory-limit 1000 --dir-mode 0777 --file-mode 0666"
  csi.storage.k8s.io/provisioner-secret-name: csi-s3-secret
  csi.storage.k8s.io/provisioner-secret-namespace: kube-system
  csi.storage.k8s.io/controller-publish-secret-name: csi-s3-secret
  csi.storage.k8s.io/controller-publish-secret-namespace: kube-system
  csi.storage.k8s.io/node-stage-secret-name: csi-s3-secret
  csi.storage.k8s.io/node-stage-secret-namespace: kube-system
  csi.storage.k8s.io/node-publish-secret-name: csi-s3-secret
  csi.storage.k8s.io/node-publish-secret-namespace: kube-system
reclaimPolicy: Delete
```

### PVC (ReadWriteMany — mehrere Pods gleichzeitig!)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mein-obs-pvc
spec:
  accessModes:
    - ReadWriteMany          # OBS = RWX! Mehrere Pods gleichzeitig
  storageClassName: csi-obs
  resources:
    requests:
      storage: 10Gi          # Nur ein Label — OBS hat kein echtes Quota
```

### Multi-Tenant OBS (eigene Credentials pro Team)

```yaml
# Secret pro Team
apiVersion: v1
kind: Secret
metadata:
  name: csi-obs-team-backend
  namespace: kube-system
stringData:
  accessKeyID: "TEAM_AK"
  secretAccessKey: "TEAM_SK"
  endpoint: "https://obs.eu-ch2.sc.otc.t-systems.com"
  region: "eu-ch2"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-obs-team-backend
provisioner: ru.yandex.s3.csi
parameters:
  mounter: geesefs
  csi.storage.k8s.io/provisioner-secret-name: csi-obs-team-backend
  csi.storage.k8s.io/provisioner-secret-namespace: kube-system
  # ... (alle secret refs auf das Team-Secret)
reclaimPolicy: Retain        # Retain für produktive Daten!
```

---

## Ingress (nginx-internal / nginx-public)

### IngressClass wählen

```bash
kubectl get ingressclass
# nginx-internal   k8s.io/ingress-nginx-internal   (VPC-intern)
# nginx-public     k8s.io/ingress-nginx-public      (Internet, nur wenn ccm_elb_eip=true)
```

### Ingress Manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: meine-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx-public    # oder nginx-internal
  rules:
    - host: meine-app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mein-service
                port:
                  number: 80
```

---

## ConfigMaps — CCM Konfiguration

Der CCM wird via Helm values konfiguriert, nicht via ConfigMap. Konfiguration prüfen:

```bash
kubectl get helmchart swiss-otc-ccm -n kube-system -o yaml
kubectl get secret swiss-otc-ccm-cloud-config -n kube-system -o jsonpath='{.data.cloud\.conf}' | base64 -d
```

Typische cloud.conf Werte:
```ini
[Global]
access-key = <AK>
secret-key  = <SK>
project-id  = <PROJECT_ID>
domain-name = <DOMAIN>
region      = eu-ch2
auth-url    = https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3

[LoadBalancer]
subnet-id   = <neutron-subnet-id>
```

---

## Debugging

```bash
# CCM Logs
kubectl logs -n kube-system -l app=swiss-otc-cloud-controller-manager -f

# Cinder CSI Logs
kubectl logs -n kube-system -l app=openstack-cinder-csi -c cinder-csi-plugin -f

# CSI-S3 Logs
kubectl logs -n kube-system -l app=csi-s3 -f

# PVC Events
kubectl describe pvc mein-obs-pvc

# Service Events (ELB Provisioning)
kubectl describe svc mein-service

# geesefs auf Node prüfen
kubectl get nodes -o wide  # Node IP holen
ssh ubuntu@BASTION_IP "ssh ubuntu@NODE_IP 'which geesefs && geesefs --version'"
```
