# API-dokumentasjon

Denne dokumentasjonen beskriver API-endepunktene tilgjengelig i Vaktmesteren Server.

## Web-endepunkter

### Offentlige Endepunkter

#### GET /
Hovedsiden med Serverpod-informasjon.

#### GET /logs
Loggvisningsgrensesnitt.
- **Parametere**: Ingen
- **Respons**: HTML-side med loggvisning

#### GET /logs/ws
WebSocket for sanntidslogger.
- **Protokoll**: WebSocket
- **Data**: JSON-meldinger med loggoppføringer

#### GET /logs/poll
Polling-endepunkt for logger.
- **Parametere**:
  - `since` (valgfritt): Timestamp for siste logg
- **Respons**: JSON-array med nye loggoppføringer

#### GET /alerts/history
Alert-historikk visning.
- **Parametere**:
  - `days` (valgfritt): Antall dager å vise (standard: 30)
- **Respons**: HTML-side med alert-tabell

#### GET /alerts/history/json
Alert-historikk som JSON.
- **Parametere**:
  - `days` (valgfritt): Antall dager å vise (standard: 30)
  - `state` (valgfritt): Filtrer på tilstand (0=OK, 1=WARNING, 2=CRITICAL)
- **Respons**: JSON-array med alert-data

### Interne Endepunkter

#### POST /_internal/ops/portainer/check-service
Sjekker om en tjeneste eksisterer i Portainer.
- **Tilgang**: Kun interne nettverk (private IP-adresser)
- **Parametere**:
  - `serviceName`: Navn på tjenesten
  - `endpointId` (valgfritt): Portainer-endepunkt ID
- **Respons**:
  ```json
  {
    "exists": true,
    "serviceId": 123,
    "status": "running"
  }
  ```

## Serverpod Endepunkter

Serveren bruker Serverpod's endpoint-system. Tilgjengelige endepunkter:

### AlertHistory
Håndterer alert-historikk i databasen.

#### getRecentAlerts
Henter nylige alarmer.
- **Parametere**:
  - `days`: Antall dager tilbake
  - `limit`: Maks antall resultater
- **Respons**: Liste med AlertHistory-objekter

#### createAlert
Oppretter en ny alert.
- **Parametere**:
  - `host`:Vertsnavn
  - `service`: Tjenestenavn
  - `state`: Tilstand (0=OK, 1=WARNING, 2=CRITICAL)
  - `message`: Alert-melding
- **Respons**: Opprettet AlertHistory-objekt

### PortainerOps
Operasjoner mot Portainer API.

#### checkService
Sjekker tjenestestatus.
- **Parametere**:
  - `serviceName`: Tjenestenavn
- **Respons**: Tjenesteinformasjon

## WebSocket Streams

### Logg Stream
- **Endepunkt**: `/logs/ws`
- **Meldingstyper**:
  - `log_entry`: Ny loggoppføring
  - `error`: Feilmelding
  - `status`: Tilkoblingsstatus

Eksempel melding:
```json
{
  "type": "log_entry",
  "data": {
    "timestamp": "2025-09-18T10:30:00Z",
    "level": "info",
    "message": "Alert service started",
    "sessionId": "abc123"
  }
}
```

## Feilhåndtering

API-et returnerer standard HTTP-statuskoder:

- `200`: Suksess
- `400`: Ugyldig forespørsel
- `401`: Uautorisert
- `403`: Forbudt
- `404`: Ikke funnet
- `500`: Intern serverfeil

Feilrespons format:
```json
{
  "error": "Beskrivelse av feil",
  "code": "ERROR_CODE",
  "details": {}
}
```

## Autentisering

De fleste endepunkter krever ikke autentisering. Interne endepunkter er begrenset til private IP-adresser.

For fremtidig autentisering, planlegges JWT-tokens.

## Rate Limiting

API-et har rate limiting for å forhindre misbruk:
- Web-endepunkter: 100 forespørsler per minutt per IP
- API-endepunkter: 1000 forespørsler per minutt per IP

## Eksempler

### Hent Alert-historikk med cURL

```bash
curl -X GET "http://localhost:8080/alerts/history/json?days=7&state=2"
```

### Koble til WebSocket

```javascript
const ws = new WebSocket('ws://localhost:8080/logs/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Ny logg:', data);
};
```

### Sjekk Portainer-tjeneste

```bash
curl -X POST "http://localhost:8080/_internal/ops/portainer/check-service" \
  -H "Content-Type: application/json" \
  -d '{"serviceName": "my-service"}'
```