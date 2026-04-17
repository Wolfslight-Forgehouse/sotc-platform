# Quickstart — RKE2 auf Swiss OTC via CLI (ohne GitHub Repo/Actions)

> Dieser Guide zeigt wie man den Stack komplett lokal deployed — kein GitHub Actions, kein Repo-Klon nötig.

## Voraussetzungen

```bash
# Tools installieren
brew install terraform helm kubectl git
# oder auf Linux:
apt install -y terraform kubectl git
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 1. OTC Credentials vorbereiten

```bash
export OTC_ACCESS_KEY="YOUR_OTC_ACCESS_KEY"
export OTC_SECRET_KEY="YOUR_OTC_SECRET_KEY"
export OTC_PROJECT_ID="YOUR_PROJECT_ID"
export OTC_DOMAIN_NAME="YOUR_DOMAIN_NAME"
export OTC_USERNAME="YOUR_IAM_USERNAME"
export OTC_PASSWORD="your-password"
export OTC_TENANT_NAME="eu-ch2_yourproject"
```

## 2. OBS Bucket für Terraform State (einmalig)

```bash
# Mit awscli (OBS-kompatibel)
aws configure set aws_access_key_id $OTC_ACCESS_KEY
aws configure set aws_secret_access_key $OTC_SECRET_KEY

aws s3 mb s3://your-tfstate-bucket \
  --endpoint-url https://obs.eu-ch2.sc.otc.t-systems.com \
  --region eu-ch2
```

## 3. SSH Key erzeugen

```bash
ssh-keygen -t ed25519 -f ~/.ssh/rke2-otc -C "rke2-otc-deploy" -N ""
export SSH_PUBLIC_KEY=$(cat ~/.ssh/rke2-otc.pub)
export SSH_PRIVATE_KEY=$(cat ~/.ssh/rke2-otc)
```

## 4. RKE2 Token generieren

```bash
export RKE2_TOKEN=$(openssl rand -hex 32)
echo "Token: $RKE2_TOKEN"  # Speichern!
```

## 5. Terraform Deploy

```bash
# Repo klonen (nur für Terraform Modules)
git clone https://github.com/Wolfslight-Forgehouse/rke2-sotc-cloud-manager.git
cd rke2-sotc-cloud-manager/terraform/environments/dev

# Backend initialisieren
terraform init \
  -backend-config="access_key=$OTC_ACCESS_KEY" \
  -backend-config="secret_key=$OTC_SECRET_KEY"

# Variablen setzen
cat > terraform.tfvars << TFVARS
access_key    = "$OTC_ACCESS_KEY"
secret_key    = "$OTC_SECRET_KEY"
project_id    = "$OTC_PROJECT_ID"
domain_name   = "$OTC_DOMAIN_NAME"
project_name  = "$OTC_TENANT_NAME"
cluster_name  = "rke2-dev"
ssh_public_key  = "$SSH_PUBLIC_KEY"
ssh_private_key = "$SSH_PRIVATE_KEY"
rke2_token    = "$RKE2_TOKEN"

# ELB + Ingress Konfiguration
enable_shared_elb    = true   # Pre-deployed shared ELB
shared_elb_eip       = false  # Kein EIP (VPC-intern)
ccm_elb_eip          = true   # CCM ELBs public
# Ingress wird separat mit Traefik deployed (siehe § 8 unten), nicht über Terraform.
TFVARS

terraform plan
terraform apply -auto-approve
```

## 6. kubeconfig holen

```bash
# IPs aus Terraform Output
BASTION_IP=$(terraform output -raw bastion_ip)
MASTER_IP=$(terraform output -raw master_ip)

# kubeconfig via SSH Tunnel
ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke2-otc ubuntu@$BASTION_IP \
  "ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke2-otc ubuntu@$MASTER_IP \
  'sudo cat /etc/rancher/rke2/rke2.yaml'" 2>/dev/null | \
  sed "s/127.0.0.1/$MASTER_IP/g" > ~/.kube/rke2-otc.yaml

export KUBECONFIG=~/.kube/rke2-otc.yaml

# SSH Tunnel öffnen (im Hintergrund)
ssh -f -N -L 6443:$MASTER_IP:6443 \
  -o StrictHostKeyChecking=no \
  -i ~/.ssh/rke2-otc ubuntu@$BASTION_IP

kubectl --insecure-skip-tls-verify get nodes
```

## 7. CCM, Cinder CSI, CSI-S3 installieren

> Wenn nicht über Pipeline deployed, hier die manuellen Helm-Befehle:

```bash
SUBNET_ID=$(terraform output -raw subnet_network_id)

# CCM
helm repo add swiss-otc https://wolfslight-forgehouse.github.io/rke2-sotc-cloud-manager
helm upgrade --install swiss-otc-ccm swiss-otc/swiss-otc-cloud-controller-manager \
  -n kube-system \
  --set cloudConfig.auth.accessKey=$OTC_ACCESS_KEY \
  --set cloudConfig.auth.secretKey=$OTC_SECRET_KEY \
  --set cloudConfig.auth.projectId=$OTC_PROJECT_ID \
  --set cloudConfig.auth.domainName=$OTC_DOMAIN_NAME \
  --set cloudConfig.region=eu-ch2 \
  --set cloudConfig.network.subnetId=$SUBNET_ID

# Cinder CSI (EVS Block Storage)
helm repo add cpo https://kubernetes.github.io/cloud-provider-openstack
kubectl create secret generic cinder-csi-cloud-config -n kube-system \
  --from-literal=cloud.conf="[Global]
username=$OTC_USERNAME
password=$OTC_PASSWORD
auth-url=https://iam-pub.eu-ch2.sc.otc.t-systems.com/v3
tenant-id=$OTC_PROJECT_ID
domain-name=$OTC_DOMAIN_NAME
region=eu-ch2"

helm upgrade --install cinder-csi cpo/openstack-cinder-csi \
  -n kube-system \
  --set storageClass.enabled=true \
  --set secret.enabled=false

# CSI-S3 (OBS Object Storage)
kubectl create secret generic csi-s3-secret -n kube-system \
  --from-literal=accessKeyID=$OTC_ACCESS_KEY \
  --from-literal=secretAccessKey=$OTC_SECRET_KEY \
  --from-literal=endpoint=https://obs.eu-ch2.sc.otc.t-systems.com \
  --from-literal=region=eu-ch2

helm repo add csi-s3 https://yandex-cloud.github.io/k8s-csi-s3/charts
helm upgrade --install csi-s3 csi-s3/csi-s3 \
  -n kube-system \
  --version 0.43.4 \
  --set storageClass.singleBucket=rke2-obs-storage \
  --set image.repository=ghcr.io/wolfslight-forgehouse/csi-s3-driver \
  --set image.tag=latest \
  --set secret.create=false \
  --set secret.name=csi-s3-secret

# geesefs auf allen Nodes installieren
for NODE_IP in $MASTER_IP $(terraform output -json worker_ips | jq -r '.[]'); do
  scp -o ProxyJump=ubuntu@$BASTION_IP -i ~/.ssh/rke2-otc \
    /path/to/geesefs-linux-amd64-v0.42.4 ubuntu@$NODE_IP:/tmp/geesefs
  ssh -J ubuntu@$BASTION_IP -i ~/.ssh/rke2-otc ubuntu@$NODE_IP \
    "sudo install -m755 /tmp/geesefs /usr/local/bin/geesefs && \
     echo user_allow_other | sudo tee -a /etc/fuse.conf"
done
```

## 8. Traefik Ingress (optional)

Platform-Standard ist Traefik (ingress-nginx wird nicht mehr verwendet, siehe Gotcha #8
in der [Confluence Platform Page](https://madcluster.atlassian.net/wiki/spaces/SkyNetLabs/pages/580321282)).

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik

# Intern (VPC-only) — für Services die nur vom VPC aus erreichbar sein sollen
helm upgrade --install traefik-internal traefik/traefik \
  -n traefik-internal --create-namespace \
  --set ingressClass.enabled=true \
  --set ingressClass.name=traefik-internal \
  --set service.type=LoadBalancer \
  --set service.annotations."otc\.io/elb-virsubnet-id"=$SUBNET_ID

# Public (mit EIP) — für Services im Internet, erstellt automatisch einen OTC EIP
helm upgrade --install traefik-public traefik/traefik \
  -n traefik-public --create-namespace \
  --set ingressClass.enabled=true \
  --set ingressClass.name=traefik-public \
  --set service.type=LoadBalancer \
  --set service.annotations."otc\.io/elb-virsubnet-id"=$SUBNET_ID \
  --set service.annotations."otc\.io/elb-eip-type"=5_bgp \
  --set service.annotations."otc\.io/elb-eip-bandwidth-size"=10 \
  --set service.annotations."otc\.io/elb-eip-charge-mode"=traffic
```

**Ingress-Ressource mit Traefik** (k8s-native `networking.k8s.io/v1` Ingress):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mein-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik-public   # oder traefik-internal
  rules:
    - host: mein-app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mein-service
                port: { number: 80 }
```

Für erweiterte Routing-Features (Middleware, TLS, Weighted Services) siehe Traefik's
`IngressRoute` CRD — [Traefik Docs](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/).
