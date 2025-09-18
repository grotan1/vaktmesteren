# Konfigurasjonsguide

Denne guiden forklarer hvordan du konfigurerer Vaktmesteren Server for forskjellige miljøer og integrasjoner.

## Konfigurasjonsfiler

Konfigurasjonsfiler ligger i `config/`-mappen og bruker YAML-format.

### Hovedkonfigurasjon

#### development.yaml / production.yaml
Hovedkonfigurasjon for serveren.

```yaml
# Database konfigurasjon
database:
  host: localhost
  port: 5432
  name: vaktmesteren
  user: postgres
  password: your_password

# Redis konfigurasjon
redis:
  host: localhost
  port: 6379
  password: null  # Sett hvis Redis krever passord

# Server konfigurasjon
server:
  port: 8080
  publicHost: localhost
  publicPort: 8080
  publicScheme: http

# Logging
logging: normal  # normal, debug, all

# Serverpod spesifikke innstillinger
serverpod:
  session:
    secret: your_session_secret
  insights:
    enabled: true
```

### Icinga2 Konfigurasjon

#### icinga2.yaml
Konfigurasjon for Icinga2-integrasjon.

```yaml
# Icinga2 API tilkobling
host: icinga2.example.com
port: 5665
username: apiuser
password: api_password

# SSL/TLS innstillinger
ssl:
  enabled: true
  verifyPeer: true
  caCertificate: /path/to/ca.crt

# Alert filtre
filters:
  hostGroups: ['linux-servers', 'windows-servers']
  serviceGroups: ['web-services', 'database-services']

# Polling intervall (sekunder)
pollInterval: 60

# Retry innstillinger
retry:
  maxAttempts: 3
  delaySeconds: 30
```

### Teams Varsler

#### teams_notifications.yaml
Konfigurasjon for Microsoft Teams-integrasjon.

```yaml
# Aktiver Teams varsler
enabled: true

# Webhook URL for Teams kanal
webhookUrl: https://outlook.office.com/webhook/...

# Avanserte innstillinger
advanced:
  timeout: 30  # sekunder
  retryCount: 3
  rateLimit:
    requestsPerMinute: 30

# Varslingsregler
rules:
  - name: critical_alerts
    conditions:
      - state: CRITICAL
      - hostGroup: production
    template: critical_template
    channels: ['production-alerts']

  - name: warning_alerts
    conditions:
      - state: WARNING
      - serviceGroup: web
    template: warning_template
    channels: ['dev-alerts']

# Meldingsmaler
templates:
  critical_template:
    title: "🚨 KRITISK ALERT"
    color: "d63384"
    includeDetails: true
    includeHostInfo: true

  warning_template:
    title: "⚠️ WARNING ALERT"
    color: "fd7e14"
    includeDetails: true
    includeHostInfo: false
```

### Portainer Operasjoner

#### portainer_ci_cd.yaml
Konfigurasjon for Portainer-integrasjon.

```yaml
# Portainer API tilkobling
api:
  url: https://portainer.example.com/api
  username: admin
  password: portainer_password

# Standard endepunkt
defaultEndpoint: 1

# Tjeneste kartlegging
services:
  web-app:
    name: "web-app"
    endpointId: 1
    stack: "production-stack"

  api-server:
    name: "api-server"
    endpointId: 1
    stack: "backend-stack"

# Sikkerhetsinnstillinger
security:
  allowedNetworks: ['192.168.1.0/24', '10.0.0.0/8']
  rateLimit:
    requestsPerMinute: 60
```

## Miljøvariabler

Du kan overstyre konfigurasjon med miljøvariabler:

```bash
# Database
export DATABASE_HOST=prod-db.example.com
export DATABASE_PASSWORD=secure_password

# Server
export SERVERPOD_PORT=8080
export SERVERPOD_PUBLIC_HOST=api.example.com

# Secrets
export ICINGA2_PASSWORD=icinga_secret
export TEAMS_WEBHOOK_URL=https://hooks.example.com/...
```

## Miljøspesifikke Konfigurasjoner

### Utvikling
- Bruk `development.yaml`
- Aktiver debug-logging
- Tillat CORS for localhost
- Bruk lokale databaser

### Staging
- Bruk staging-spesifikke verdier
- Aktiver ekstra logging
- Konfigurer test-varsler

### Produksjon
- Bruk `production.yaml`
- Aktiver SSL/TLS
- Konfigurer produksjonsdatabaser
- Sett opp monitoring

## Validering

For å validere konfigurasjonen:

```bash
dart bin/main.dart --validate-config
```

Dette vil:
- Sjekke syntaks
- Validere tilkoblinger
- Teste API-endepunkter
- Rapportere konfigurasjonsfeil

## Sikkerhet

### Passord og Secrets
- Aldri lagre passord i konfigurasjonsfiler
- Bruk miljøvariabler eller secret management
- Roter passord regelmessig

### Nettverkssikkerhet
- Begrens API-tilgang til nødvendige IP-adresser
- Bruk VPN for interne endepunkter
- Aktiver rate limiting

### SSL/TLS
```yaml
server:
  ssl:
    enabled: true
    certificate: /path/to/cert.pem
    privateKey: /path/to/key.pem
    caCertificate: /path/to/ca.pem
```

## Feilsøking

### Vanlige Konfigurasjonsfeil

#### Database Connection Failed
- Sjekk host, port og legitimasjon
- Verifiser at databasen eksisterer
- Sjekk nettverkstilgang

#### Icinga2 Authentication Failed
- Verifiser API-bruker og passord
- Sjekk SSL-sertifikater
- Test API-tilkobling manuelt

#### Teams Webhook Not Working
- Verifiser webhook URL
- Sjekk kanal-tillatelser
- Test webhook med curl

### Debug-konfigurasjon

For debugging, legg til:

```yaml
logging: all
debug:
  database: true
  icinga2: true
  teams: true
```

## Eksempler

### Full Produksjonskonfigurasjon

```yaml
database:
  host: prod-db.cluster.example.com
  port: 5432
  name: vaktmesteren_prod
  user: vaktmesteren_user
  password: ${DATABASE_PASSWORD}

redis:
  host: redis-cluster.example.com
  port: 6379
  password: ${REDIS_PASSWORD}

server:
  port: 8080
  publicHost: api.vaktmesteren.no
  publicPort: 443
  publicScheme: https
  ssl:
    enabled: true
    certificate: /etc/ssl/certs/vaktmesteren.crt
    privateKey: /etc/ssl/private/vaktmesteren.key

icinga2:
  host: icinga2.internal.example.com
  port: 5665
  username: vaktmesteren
  password: ${ICINGA2_PASSWORD}

teams:
  enabled: true
  webhookUrl: ${TEAMS_WEBHOOK_URL}

portainer:
  api:
    url: https://portainer.internal.example.com/api
    username: vaktmesteren
    password: ${PORTAINER_PASSWORD}
```