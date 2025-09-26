# Configuration Templates

This directory contains example/template versions of external service configuration files.

## Usage

Copy these template files to `../external/` and customize them for your environment:

```bash
# Copy all templates to external directory
cp config/external_templates/*.example config/external/

# Remove .example extensions
cd config/external/
mv icinga2.yaml.example icinga2.yaml
mv ssh_restart.yaml.example ssh_restart.yaml
mv teams_notifications.yaml.example teams_notifications.yaml
mv portainer_ci_cd.yaml.example portainer_ci_cd.yaml
```

## Template Files

- `icinga2.yaml.example` - Template for Icinga2 monitoring server configuration
- `ssh_restart.yaml.example` - Template for SSH restart service configuration  
- `teams_notifications.yaml.example` - Template for Microsoft Teams notifications
- `portainer_ci_cd.yaml.example` - Template for Portainer CI/CD deployment configuration

## Customization

After copying the templates:

1. Update connection details (hostnames, ports, credentials)
2. Configure service-specific settings
3. Test the configuration before deploying to production
4. Consider using environment variables for sensitive values

## Version Control

- Keep template files in version control
- **DO NOT** commit actual configuration files with real credentials to version control
- Add `config/external/*.yaml` to your `.gitignore` if it contains sensitive data