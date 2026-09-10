# Reproducibility Plan

## Goal

Make fresh VPS deployment repeatable.

The current VPS is not proof. A clean VPS test is proof.

## Done

- Keycloak realm desired state moved to `data/keycloak-realm.json`.
- Keycloak seeded users moved to `data/keycloak-users.json`.
- Moodle OAuth2 desired state moved to `data/moodle-oidc.json`.
- Keycloak apply and verify scripts read the same JSON data.
- Seeded user passwords are deterministic and non-temporary by default.
- Normal Keycloak apply skips user reapply when live usernames already match JSON.
- `KEYCLOAK_FORCE_RESEED=1` can repair users or reset passwords.
- User repair/reseed uses Keycloak Admin REST with token refresh.
- JSON-driven Keycloak apply/verify passed on the current VPS.
- Moodle OIDC verify passed on the current VPS.
- Direct seeded-user OIDC password test passed.
- Browser login into Moodle with a seeded Keycloak user was confirmed.
- Deploy and HTTPS scripts write generated runtime mode to `.generated/deploy.env`.
- Fresh VPS orchestration has one entrypoint: `scripts/install-fresh.sh`.

## Current Password Rule

```text
{username}@unrealuni
```

Example:

```text
sara.shirazi -> sara.shirazi@unrealuni
```

## Next Tasks

- Run the full flow on a clean VPS.
- Record every manual step.
- Turn important manual steps into scripts or runbook updates.
- Decide policy for users removed from `data/keycloak-users.json`: leave, disable, or delete.
- Add DNS and HTTP/OIDC browser-level verification.
- Add schema-focused validation for the JSON files.
- Automate test courses.
- Automate in-house Moodle plugin install/config.
