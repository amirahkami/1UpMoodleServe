# Reproducibility Checklist

A fresh VPS deployment is valid when this works:

```bash
bash scripts/bootstrap.sh
```

Expected result:

- server is provisioned
- `.env` is created from admin answers
- machine secrets are generated
- SSH user and port are configured
- root SSH is disabled after confirmation
- Docker Compose stack is running
- HTTPS certificates exist
- Keycloak realm exists
- 130 demo users exist
- demo-user passwords are temporary
- Moodle OIDC login is configured
- root-domain welcome page loads
- Keycloak admin demo users are Moodle site admins

The old VPS is not proof.

A clean VPS test is proof.
