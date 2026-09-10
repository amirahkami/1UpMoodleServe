# Desired State

The `data/` directory contains public, non-secret platform state.

Scripts read these files and apply them to live services.

## Keycloak Realm

File:

```text
data/keycloak-realm.json
```

Defines:

- default realm name
- Moodle client
- realm roles
- Moodle client roles
- groups
- protocol mappers
- seed-user policy

The admin can override the realm name during bootstrap.

## Keycloak Users

File:

```text
data/keycloak-users.json
```

Defines 130 fake demo university users.

Passwords are not stored in public data.

The temporary demo-user password comes from `.env`:

```text
KEYCLOAK_SEED_USER_TEMP_PASSWORD
```

Keycloak forces users to change it on first login.

## Moodle OIDC

File:

```text
data/moodle-oidc.json
```

Defines Moodle's OAuth2 issuer settings:

- issuer name
- login button name
- scopes
- account creation policy
- field mappings

## Apply

```bash
bash scripts/keycloak-realm.sh apply
bash scripts/moodle-oidc.sh apply
```
