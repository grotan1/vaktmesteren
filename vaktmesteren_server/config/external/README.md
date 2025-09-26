# External Configuration Files

This directory contains configuration files for external services that can be easily mounted as Docker volumes for runtime configuration without rebuilding the container.

## Files in this directory:

- `icinga2.yaml` - Icinga2 monitoring server connection configuration
- `ssh_restart.yaml` - SSH restart service configuration for automated service recovery
- `teams_notifications.yaml` - Microsoft Teams webhook notification configuration
- `portainer_ci_cd.yaml` - Portainer CI/CD deployment credentials and configuration

## Docker Volume Mounting

To mount these configurations in Docker, use:

```yaml
services:
  vaktmesteren:
    # ... other configuration
    volumes:
      - ./config/external:/app/config/external:ro
```

Or with docker run:
```bash
docker run -v $(pwd)/config/external:/app/config/external:ro your-image
```

## Template Files

Example/template versions of these files are available in `../external_templates/` with `.example` extensions. Copy these to get started:

```bash
cp config/external_templates/icinga2.yaml.example config/external/icinga2.yaml
cp config/external_templates/ssh_restart.yaml.example config/external/ssh_restart.yaml  
cp config/external_templates/teams_notifications.yaml.example config/external/teams_notifications.yaml
cp config/external_templates/portainer_ci_cd.yaml.example config/external/portainer_ci_cd.yaml
```

## Security Notes

- Mount these volumes as read-only (`:ro`) when possible
- Keep sensitive credentials in separate password files or environment variables
- Ensure proper file permissions (600 or 644) on the host system