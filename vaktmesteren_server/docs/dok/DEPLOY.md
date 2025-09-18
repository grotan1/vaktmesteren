# Distribusjonsguide

Denne guiden beskriver hvordan du distribuerer Vaktmesteren Server til forskjellige plattformer.

## Docker Distribusjon

### Bygg og Kjør Lokalt

```bash
# Bygg Docker-image
docker build -t vaktmesteren-server .

# Kjør container
docker run -p 8080:8080 -p 8081:8081 -p 8082:8082 \
  -e DATABASE_HOST=host.docker.internal \
  -e REDIS_HOST=host.docker.internal \
  vaktmesteren-server
```

### Docker Compose

Bruk inkludert `docker-compose.yaml`:

```bash
# For utvikling
docker compose up --build

# For produksjon
docker compose -f docker-compose.prod.yaml up --build -d
```

### Multi-stage Build

Dockerfile bruker multi-stage build for optimalisering:

```dockerfile
# Build stage
FROM dart:3.5.0 AS build
WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/main.dart -o bin/server

# Runtime stage
FROM alpine:latest
COPY --from=build /app/bin/server /app/server
COPY --from=build /app/config/ /app/config/
COPY --from=build /app/web/ /app/web/
EXPOSE 8080 8081 8082
CMD ["/app/server"]
```

## AWS Distribusjon

### Terraform Oppsett

Naviger til AWS Terraform-mappen:

```bash
cd deploy/aws/terraform
```

### Konfigurasjon

Rediger `config.auto.tfvars`:

```hcl
project_name = "vaktmesteren"
aws_region = "us-west-2"
instance_type = "t3.micro"
database_instance_class = "db.t3.micro"
redis_node_type = "cache.t3.micro"
```

### Distribuer

```bash
# Initialiser Terraform
terraform init

# Planlegg endringer
terraform plan

# Distribuer
terraform apply
```

### AWS Ressurser

Terraform oppretter:
- EC2-instans for serveren
- RDS PostgreSQL-database
- ElastiCache Redis
- Load Balancer
- Security Groups
- CloudFront distribusjon (valgfritt)

### Blue-Green Deployment

Bruk CodeDeploy for zero-downtime:

```bash
# Bygg og last opp
aws deploy create-deployment \
  --application-name vaktmesteren-server \
  --deployment-group-name production \
  --s3-location bucket=vaktmesteren-deploy,key=app.zip
```

## GCP Distribusjon

### Cloud Run (Anbefalt)

```bash
cd deploy/gcp/console_gcr

# Bygg og last opp
gcloud builds submit --tag gcr.io/PROJECT-ID/vaktmesteren-server

# Distribuer til Cloud Run
gcloud run deploy vaktmesteren-server \
  --image gcr.io/PROJECT-ID/vaktmesteren-server \
  --platform managed \
  --port 8080 \
  --allow-unauthenticated \
  --set-env-vars DATABASE_HOST=... \
  --set-secrets REDIS_PASSWORD=redis-password:latest
```

### GCE med Terraform

```bash
cd deploy/gcp/terraform_gce

terraform init
terraform plan
terraform apply
```

## Lokal Distribusjon

### Systemd Service

Opprett `/etc/systemd/system/vaktmesteren.service`:

```ini
[Unit]
Description=Vaktmesteren Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=vaktmesteren
WorkingDirectory=/opt/vaktmesteren
ExecStart=/usr/local/bin/dart /opt/vaktmesteren/bin/main.dart
Restart=always
RestartSec=5
Environment=DATABASE_HOST=localhost
Environment=REDIS_HOST=localhost

[Install]
WantedBy=multi-user.target
```

Aktiver og start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable vaktmesteren
sudo systemctl start vaktmesteren
```

### Nginx Reverse Proxy

Konfigurer Nginx for SSL-terminering:

```nginx
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/ssl/certs/api.example.com.crt;
    ssl_certificate_key /etc/ssl/private/api.example.com.key;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://localhost:8082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## Kubernetes Distribusjon

### Helm Chart

Opprett `k8s/Chart.yaml`:

```yaml
apiVersion: v2
name: vaktmesteren
description: Vaktmesteren Server Helm Chart
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### Deployment Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vaktmesteren-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: vaktmesteren-server
  template:
    metadata:
      labels:
        app: vaktmesteren-server
    spec:
      containers:
      - name: server
        image: vaktmesteren-server:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_HOST
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: host
        - name: REDIS_HOST
          value: redis-service
---
apiVersion: v1
kind: Service
metadata:
  name: vaktmesteren-service
spec:
  selector:
    app: vaktmesteren-server
  ports:
    - port: 80
      targetPort: 8080
  type: LoadBalancer
```

Installer med Helm:

```bash
helm install vaktmesteren ./k8s
```

## Overvåking og Logging

### Health Checks

Serveren tilbyr health check endepunkt:

```bash
curl http://localhost:8080/health
```

### Logging

- Applikasjonslogger: `/var/log/vaktmesteren/`
- Systemlogger: Journald/systemd
- Cloud logging: CloudWatch/Cloud Logging

### Metrics

Integrer med Prometheus:

```yaml
scrape_configs:
  - job_name: 'vaktmesteren'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
```

## Sikkerhet

### SSL/TLS

Alltid bruk HTTPS i produksjon:

```yaml
server:
  ssl:
    enabled: true
    certificate: /path/to/cert.pem
    privateKey: /path/to/key.pem
```

### Secrets Management

- AWS: Systems Manager Parameter Store
- GCP: Secret Manager
- Kubernetes: Secrets

### Network Security

- Bruk security groups/network policies
- Begrens tilgang til nødvendige porter
- Aktiver WAF (Web Application Firewall)

## Backup og Recovery

### Database Backup

```bash
# Automatisk backup
pg_dump vaktmesteren > backup_$(date +%Y%m%d).sql

# Restore
psql vaktmesteren < backup_20230918.sql
```

### Application Backup

```bash
# Backup config og data
tar -czf backup.tar.gz config/ migrations/ web/
```

## Skalering

### Horisontal Skalering

- Bruk load balancer
- Kjør flere instanser
- Bruk Redis for sesjonsdeling

### Vertikal Skalering

- Øk CPU/minne på instanser
- Optimaliser database
- Bruk caching strategier

## Feilsøking

### Vanlige Distribusjonsproblemer

#### Container Exit Codes
- Kode 1: Konfigurasjonsfeil
- Kode 137: Out of memory
- Kode 139: Segmentation fault

#### Database Connection Issues
- Sjekk security groups
- Verifiser VPC peering
- Test med telnet

#### SSL Certificate Errors
- Sjekk certificate expiry
- Verifiser certificate chain
- Test med openssl

### Debug Mode

Kjør med debug-flagg:

```bash
dart bin/main.dart --logging all --debug
```

### Logs

Sjekk logger:

```bash
# Docker
docker logs vaktmesteren-server

# Systemd
journalctl -u vaktmesteren -f

# AWS
aws logs tail /aws/lambda/vaktmesteren --follow
```