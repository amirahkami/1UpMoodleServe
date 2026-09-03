# Reproducibility Plan

## Done In This Pass

- Keycloak realm desired state moved to `data/keycloak-realm.json`.
- Keycloak seeded users moved to `data/keycloak-users.json`.
- Moodle OAuth2 desired state moved to `data/moodle-oidc.json`.
- Keycloak apply and verify scripts read the same JSON data.
- Seeded user passwords are deterministic and non-temporary by default.
- Normal Keycloak apply skips user reapply when live usernames already match JSON; use `KEYCLOAK_FORCE_RESEED=1` to repair users or reset passwords.
- User repair/reseed uses Keycloak Admin REST with token refresh, so fresh imports and forced password resets avoid slow per-user Docker exec calls.
- JSON-driven Keycloak apply/verify passed on the current VPS; Moodle OIDC verify and one direct seeded-user OIDC password test also passed.

## Current Password Rule

```text
{username}@unrealuni
```

Example:

```text
sara.shirazi -> sara.shirazi@unrealuni
```

## Next Tasks

- Browser-test Moodle login with one seeded user.
- Decide policy for users removed from `data/keycloak-users.json`: leave, disable, or delete.
- Stop mutating `.env` during deploy/HTTPS flow.
- Add a single fresh-VPS orchestrator script.
- Add DNS and HTTP/OIDC browser-level verification.
- Add schema-focused validation for the JSON files.
