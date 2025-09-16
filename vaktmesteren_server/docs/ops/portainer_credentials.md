Portainer CI/CD credentials
=================================

This document describes how to store Portainer credentials locally for automated scripts.

1) Create a local config file:

```bash
# Create config/portainer_ci_cd.yaml and set the real token value. Do not commit this file.
```

2) Create the file securely without exposing the password in shell history:

```bash
read -s -p "Portainer token: " TOKEN
echo
cat > config/portainer_ci_cd.yaml <<EOF
portainer:
  url: "https://portainer.example.com"
  endpoint_id: 1
  token: "$TOKEN"
EOF
chmod 600 config/portainer_ci_cd.yaml
```

3) Ensure the file is ignored by git (the repo already lists `config/portainer_ci_cd.yaml` in `.gitignore`).

4) Use environment variable overrides if you need to keep secrets out of files in some environments.
