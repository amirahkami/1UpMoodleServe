# Desired State

The `data/` directory contains non-secret platform state.

Scripts read these files and apply them to live services.

## Keycloak Realm

File:

```text
data/keycloak-realm.json
```

Defines:

- realm name
- Moodle client
- realm roles
- Moodle client roles
- groups
- protocol mappers
- seed password rule

Current realm:

```text
unrealuni
```

Current client:

```text
moodle
```

## Keycloak Users

File:

```text
data/keycloak-users.json
```

Defines seeded simulation users.

Current count:

```text
130
```

Seed password pattern:

```text
{username}@unrealuni
```

Example:

```text
sara.shirazi / sara.shirazi@unrealuni
```

## Moodle OIDC

File:

```text
data/moodle-oidc.json
```

Defines Moodle's built-in OAuth2 issuer settings:

- issuer name
- login button name
- scopes
- account creation policy
- field mappings

Current login button:

```text
UnrealUni Login
```

## Secrets

Desired-state files do not contain secrets.

Secrets come from `.env` on the VPS.

Example:

```text
KEYCLOAK_MOODLE_CLIENT_SECRET
```

## Apply

```bash
bash scripts/keycloak-realm.sh apply
bash scripts/moodle-oidc.sh apply
```

## Verify

```bash
bash scripts/verify-keycloak-realm.sh
bash scripts/moodle-oidc.sh verify
```
