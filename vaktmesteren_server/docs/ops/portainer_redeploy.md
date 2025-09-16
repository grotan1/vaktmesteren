# Portainer-based Redeploy Runbook

This document describes the automated remediation flow that uses the Portainer API to repair a broken service.

Overview
- Check service health via Portainer API.
- If service unhealthy: attempt a service update (rolling update / force redeploy).
- If service still unhealthy: attempt a stack deploy (redeploy the full stack/compose).
- Notify on success/failure and record logs.

Configuration
- Create `config/portainer_ci_cd.yaml` and fill in secrets. Do not commit secrets.
- Use an API key (recommended) with least privileges needed to inspect and update services/stacks.

High-level flow
1. Check service
   - Call Portainer endpoint to inspect service tasks and desired state.
   - If number of running tasks matches desired replicas and no crash loops detected: consider healthy.
2. Update service
   - Fetch current service spec via Portainer API.
   - Trigger update by changing `ForceUpdate` or image tag if desired, then POST update.
   - Poll tasks until stable or timeout.
3. Update stack (fallback)
   - Trigger stack redeploy using the stack deploy API (requires stack id and compose file or use the Portainer endpoint to redeploy existing stack).
   - Poll for stack rollout and service health.
4. Notify & escalate
   - If both steps fail, create an incident via configured `notifications.webhook` or escalate manually.

Safety & best practices
- Test scripts in staging first. Use dry-run mode where available.
- Use `service_update_attempts` and `stack_update_attempts` to avoid aggressive retries.
- Rotate API keys and store them in a secrets store (CI secrets, Vault, etc.).
- Notify on every action and retain logs for post-mortem.

Next steps
- Implement small Portainer client (provided in `lib/src/ops/portainer_client.dart`).
- Add scripts to perform `check-service`, `update-service`, and `update-stack` operations.
