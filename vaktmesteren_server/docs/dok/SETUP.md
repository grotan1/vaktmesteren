# Oppsett og Installasjon

Denne guiden beskriver hvordan du setter opp Vaktmesteren Server for utvikling og produksjon.

## Hurtigstart

For rask oppsett:

```bash
git clone https://github.com/grotan1/vaktmesteren.git
cd vaktmesteren_server
dart pub get
docker compose up --build --detach
dart bin/main.dart
```

Serveren er nå tilgjengelig på `http://localhost:8080`.

## Detaljert Oppsett

### 1. Systemkrav

- **Dart SDK**: Versjon 3.5.0 eller nyere
- **Docker**: For database og Redis (anbefalt)
- **PostgreSQL**: Versjon 13+ (hvis ikke bruker Docker)
- **Redis**: Versjon 6+ (hvis ikke bruker Docker)
- **Git**: For versjonskontroll

### 2. Kloning og Avhengigheter

```bash
git clone https://github.com/grotan1/vaktmesteren.git
cd vaktmesteren_server
dart pub get
```

### 3. Database og Redis

#### Med Docker (Anbefalt)

```bash
docker compose up --build --detach
```

Dette starter:
- PostgreSQL på port 5432
- Redis på port 6379
- PgAdmin på port 8083 (valgfritt)

#### Uten Docker

Installer PostgreSQL og Redis manuelt, og oppdater konfigurasjonen i `config/`-filene.

### 4. Konfigurasjon

Kopier eksempelkonfigurasjoner:

```bash
cp config/development.yaml config/local.yaml
```

Rediger `config/local.yaml` med dine innstillinger:

```yaml
database:
  host: localhost
  port: 5432
  name: vaktmesteren
  user: postgres
  password: your_password

redis:
  host: localhost
  port: 6379

server:
  port: 8080
  publicHost: localhost
  publicPort: 8080
  publicScheme: http
```

### 5. Kjør Serveren

```bash
dart bin/main.dart
```

For produksjon:
```bash
dart bin/main.dart --mode production
```

### 6. Verifiser Oppsett

Åpne nettleseren og gå til:
- `http://localhost:8080/` - Hovedsiden
- `http://localhost:8080/logs` - Loggvisning

## Feilsøking

### Vanlige Problemer

#### Database-tilkobling feiler
- Sjekk at PostgreSQL kjører
- Verifiser database-legitimasjon i konfigurasjon
- Sørg for at databasen eksisterer

#### Port-konflikter
- Endre porter i `config/local.yaml`
- Sjekk at ingen andre tjenester bruker portene 8080-8082

#### Avhengigheter feiler
```bash
dart pub cache repair
dart pub get
```

### Logger

Serverlogger finnes i `logs/`-mappen. For mer detaljerte logger:

```bash
dart bin/main.dart --logging all
```

## Produksjonsoppsett

For produksjon:

1. Bruk `config/production.yaml`
2. Sett miljøvariabler for sensitive data
3. Konfigurer reverse proxy (nginx/Apache)
4. Aktiver SSL/TLS
5. Sett opp monitoring og logging

### Miljøvariabler

```bash
export DATABASE_PASSWORD=your_secure_password
export REDIS_PASSWORD=your_redis_password
export SERVERPOD_SESSION_SECRET=your_session_secret
```

## Neste Steg

Etter oppsett, se:
- [Brukerveiledning](BRUK.md)
- [API-dokumentasjon](API.md)
- [Konfigurasjonsguide](CONFIG.md)