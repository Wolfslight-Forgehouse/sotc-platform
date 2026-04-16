# GitOps Integration Guide

> Wie man den Stack ohne GitHub Actions betreibt — mit Fleet, FluxCD, ArgoCD oder direkt via Helm.

---

## Option A: SUSE Rancher Fleet

Fleet arbeitet mit Git-Repos und deployt Helm Charts + Manifeste automatisch.

### 1. Fleet installieren (in bestehendem Rancher)

```bash
# Fleet ist in Rancher eingebaut — oder standalone:
helm repo add fleet https://rancher.github.io/fleet-helm-charts
helm install fleet fleet/fleet -n cattle-fleet-system --create-namespace
```

### 2. GitRepo Resource anlegen

```yaml
# fleet-gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: rke2-otc-stack
  namespace: fleet-local
spec:
  repo: https://github.com/Wolfslight-Forgehouse/rke2-sotc-cloud-manager
  branch: main
  paths:
    - deploy/fleet/ccm        # CCM
    - deploy/fleet/csi        # Cinder CSI + CSI-S3
    - deploy/fleet/ingress    # ingress-nginx
  targets:
    - name: production
      clusterSelector:
        matchLabels:
          env: production
```

### 3. Fleet Bundle für CCM

```yaml
# deploy/fleet/ccm/fleet.yaml
defaultNamespace: kube-system
helm:
  repo: https://wolfslight-forgehouse.github.io/rke2-sotc-cloud-manager
  chart: swiss-otc-cloud-controller-manager
  releaseName: swiss-otc-ccm
  values:
    cloudConfig:
      auth:
        accessKey: "${OTC_ACCESS_KEY}"   # aus Fleet Secret
        secretKey: "${OTC_SECRET_KEY}"
        projectId: "${OTC_PROJECT_ID}"
      region: eu-ch2
```

---

## Option B: GitLab + FluxCD

### 1. FluxCD Bootstrap mit GitLab

```bash
flux bootstrap gitlab \
  --owner=your-gitlab-group \
  --repository=rke2-k8s-config \
  --branch=main \
  --path=clusters/production \
  --token-auth
```

### 2. HelmRepository + HelmRelease für CCM

```yaml
# clusters/production/ccm/helmrepo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: swiss-otc-ccm
  namespace: kube-system
spec:
  interval: 1h
  url: https://wolfslight-forgehouse.github.io/rke2-sotc-cloud-controller-manager
---
# clusters/production/ccm/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: swiss-otc-ccm
  namespace: kube-system
spec:
  interval: 5m
  chart:
    spec:
      chart: swiss-otc-cloud-controller-manager
      sourceRef:
        kind: HelmRepository
        name: swiss-otc-ccm
  valuesFrom:
    - kind: Secret
      name: otc-credentials     # kubectl create secret mit AK/SK
      valuesKey: values.yaml
```

### 3. CSI-S3 HelmRelease

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: csi-s3
  namespace: kube-system
spec:
  url: https://yandex-cloud.github.io/k8s-csi-s3/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: csi-s3
  namespace: kube-system
spec:
  chart:
    spec:
      chart: csi-s3
      version: "0.43.4"    # FIXIERT — nicht auto-update!
      sourceRef:
        kind: HelmRepository
        name: csi-s3
  values:
    storageClass:
      singleBucket: rke2-obs-storage
    image:
      repository: ghcr.io/wolfslight-forgehouse/csi-s3-driver
      tag: latest
    secret:
      create: false
      name: csi-s3-secret
```

### 4. GitLab CI für Terraform (statt GitHub Actions)

```yaml
# .gitlab-ci.yml
stages:
  - plan
  - apply
  - destroy

variables:
  TF_ROOT: terraform/environments/dev

terraform:plan:
  stage: plan
  image: hashicorp/terraform:1.7
  script:
    - cd $TF_ROOT
    - terraform init -backend-config="access_key=$OTC_ACCESS_KEY" -backend-config="secret_key=$OTC_SECRET_KEY"
    - terraform plan -out=tfplan
  artifacts:
    paths: [terraform/environments/dev/tfplan]

terraform:apply:
  stage: apply
  image: hashicorp/terraform:1.7
  when: manual
  script:
    - cd $TF_ROOT
    - terraform apply tfplan
  environment: production
```

---

## Option C: ArgoCD

### 1. ArgoCD Application für CCM

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: swiss-otc-ccm
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://wolfslight-forgehouse.github.io/rke2-sotc-cloud-controller-manager
    chart: swiss-otc-cloud-controller-manager
    targetRevision: "latest"
    helm:
      values: |
        cloudConfig:
          auth:
            accessKey: "$OTC_ACCESS_KEY"
          region: eu-ch2
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 2. App of Apps Pattern für ganzen Stack

```yaml
# apps/otc-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: otc-stack
spec:
  source:
    repoURL: https://github.com/Wolfslight-Forgehouse/rke2-sotc-cloud-manager
    path: deploy/argocd/apps
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
```

---

## Option D: Direkt via Helm (ohne GitOps)

### Alles in einem Schritt

```bash
SUBNET_ID=$(kubectl get nodes -o jsonpath='{.items[0].metadata.annotations.otc\.io/subnet-id}' 2>/dev/null || echo "DEIN-SUBNET-ID")

# 1. CCM
helm upgrade --install swiss-otc-ccm \
  oci://ghcr.io/wolfslight-forgehouse/charts/swiss-otc-cloud-controller-manager \
  -n kube-system \
  --set cloudConfig.auth.accessKey=$OTC_ACCESS_KEY \
  --set cloudConfig.auth.secretKey=$OTC_SECRET_KEY \
  --set cloudConfig.auth.projectId=$OTC_PROJECT_ID \
  --set cloudConfig.auth.domainName=$OTC_DOMAIN_NAME \
  --set cloudConfig.region=eu-ch2 \
  --set cloudConfig.network.subnetId=$SUBNET_ID \
  --wait

# 2. Cinder CSI
kubectl create secret generic cinder-csi-cloud-config -n kube-system \
  --from-literal=cloud.conf="[Global]
username=$OTC_USERNAME
password=$OTC_PASSWORD
auth-url=https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3
tenant-id=$OTC_PROJECT_ID
domain-name=$OTC_DOMAIN_NAME
region=eu-ch2" --dry-run=client -o yaml | kubectl apply -f -

helm repo add cpo https://kubernetes.github.io/cloud-provider-openstack
helm upgrade --install cinder-csi cpo/openstack-cinder-csi \
  -n kube-system --version 2.35.0 \
  --set secret.enabled=false \
  --wait

# 3. CSI-S3
kubectl create secret generic csi-s3-secret -n kube-system \
  --from-literal=accessKeyID=$OTC_ACCESS_KEY \
  --from-literal=secretAccessKey=$OTC_SECRET_KEY \
  --from-literal=endpoint=https://obs.eu-ch2.sc.otc.t-systems.com \
  --from-literal=region=eu-ch2 \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add csi-s3 https://yandex-cloud.github.io/k8s-csi-s3/charts
helm upgrade --install csi-s3 csi-s3/csi-s3 \
  -n kube-system --version 0.43.4 \
  --set image.repository=ghcr.io/wolfslight-forgehouse/csi-s3-driver \
  --set image.tag=latest \
  --set secret.create=false \
  --set secret.name=csi-s3-secret

# 4. ingress-nginx (internal + public)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm upgrade --install nginx-internal ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.ingressClassResource.name=nginx-internal \
  --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-internal \
  --set "controller.service.annotations.otc\.io/elb-virsubnet-id=$SUBNET_ID"

helm upgrade --install nginx-public ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.ingressClassResource.name=nginx-public \
  --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-public \
  --set "controller.service.annotations.otc\.io/elb-virsubnet-id=$SUBNET_ID" \
  --set "controller.service.annotations.otc\.io/elb-eip-type=5_bgp" \
  --set "controller.service.annotations.otc\.io/elb-eip-bandwidth-size=10" \
  --set "controller.service.annotations.otc\.io/elb-eip-charge-mode=traffic"
```

---

## Subnet ID herausfinden

```bash
# Aus Terraform Output
cd terraform/environments/dev && terraform output subnet_network_id

# Aus laufendem Cluster (Node Annotation)
kubectl get node -o json | jq -r '.items[0].metadata.annotations | to_entries[] | select(.key | contains("subnet")) | .value'

# Via OTC API
TOKEN=$(curl -sf -X POST https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d "{...}" -i | grep -i x-subject-token | awk '{print $2}')
curl -sf -H "X-Auth-Token: $TOKEN" \
  "https://vpc.eu-ch2.sc.otc.t-systems.com/v2.0/subnets" | jq '.subnets[] | {id, name, cidr}'
```
