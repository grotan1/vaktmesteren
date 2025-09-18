# Vaktmesteren Server

## Oversikt

Vaktmesteren Server er en Serverpod-basert Dart-server som brukes til overvåking og varsling. Serveren integreres med Icinga2 for å håndtere alarmer og varsler, og tilbyr webgrensesnitt for å vise logger og alert-historikk. Den støtter også integrasjoner med Microsoft Teams for varsler og Portainer for container-operasjoner.

Prosjektet inkluderer:
- Serverpod-server for backend-logikk
- Flutter-klient for frontend
- Docker-konfigurasjon for enkel distribusjon
- Terraform-konfigurasjoner for AWS og GCP-deployering

## Funksjoner

- **Icinga2-integrasjon**: Overvåker tjenester og sender varsler basert på alarmer
- **Webgrensesnitt**: Logger-visning, alert-historikk og Portainer-operasjoner
- **Teams-varsler**: Sender adaptive kort til Microsoft Teams-kanaler
- **Portainer-ops**: Sjekker og administrerer Docker-tjenester via Portainer API
- **Database-støtte**: Bruker PostgreSQL for persistent lagring
- **Redis-støtte**: For caching og sesjonshåndtering

## Installasjon

### Forutsetninger

- Dart SDK >= 3.5.0
- Docker og Docker Compose (for database og Redis)
- PostgreSQL (valgfritt, hvis ikke bruker Docker)
- Redis (valgfritt, hvis ikke bruker Docker)

### Oppsett

1. Klon repositoriet:
   ```bash
   git clone https://github.com/grotan1/vaktmesteren.git
   cd vaktmesteren_server
   ```

2. Installer avhengigheter:
   ```bash
   dart pub get
   ```

3. Start database og Redis med Docker:
   ```bash
   docker compose up --build --detach
   ```

4. Kjør serveren:
   ```bash
   dart bin/main.dart
   ```

Serveren vil starte på port 8080 (web), 8081 (HTTP) og 8082 (WebSocket).

## Bruk

### Webgrensesnitt

- **Hovedside**: `http://localhost:8080/`
- **Logger**: `http://localhost:8080/logs`
- **Alert-historikk**: `http://localhost:8080/alerts/history`

### API-endepunkter

Serveren tilbyr følgende interne endepunkter:

- `/logs/ws`: WebSocket for sanntidslogger
- `/logs/poll`: Polling for logger
- `/_internal/ops/portainer/check-service`: Sjekk Portainer-tjeneste

### Konfigurasjon

Konfigurasjonsfiler finnes i `config/`-mappen:

- `development.yaml`: Utviklingsmiljø
- `production.yaml`: Produksjonsmiljø
- `icinga2.yaml`: Icinga2-konfigurasjon
- `teams_notifications.yaml`: Teams-varsler
- `portainer_ci_cd.yaml`: Portainer-ops

Eksempel på Icinga2-konfigurasjon:
```yaml
host: icinga2.example.com
port: 5665
username: apiuser
password: apipassword
```

## Distribusjon

### Docker

Bygg og kjør med Docker:
```bash
docker build -t vaktmesteren-server .
docker run -p 8080:8080 vaktmesteren-server
```

### AWS

Bruk Terraform-konfigurasjon i `deploy/aws/terraform/`:
```bash
cd deploy/aws/terraform
terraform init
terraform apply
```

### GCP

Bruk Terraform-konfigurasjon i `deploy/gcp/terraform_gce/` eller Cloud Run-skript i `deploy/gcp/console_gcr/`.

## Utvikling

### Generer kode

Serverpod krever kodegenerering:
```bash
serverpod generate
```

### Kjør tester

```bash
dart test
```

### Opprett migrasjoner

```bash
serverpod create-migration
dart bin/main.dart --apply-migrations --role=maintenance
```

## Bidra

1. Fork repositoriet
2. Opprett en feature-branch
3. Gjør endringer og test
4. Send pull request

## Lisens

Dette prosjektet er lisensiert under [MIT License](LICENSE).

## Kontakt

For spørsmål eller støtte, kontakt utviklingsteamet.