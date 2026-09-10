# Current VPS Checkpoint

This VPS is a reference test bench. It is not the product.

## Server

```text
ip: 138.68.64.183
app path: /opt/1upmoodleserve
ssh user: underroot
ssh port: 44422
ssh mode: password-based
```

## Domains

```text
unrealuni.xyz
moodle.unrealuni.xyz
iam.unrealuni.xyz
```

## Repo State

```text
last known working checkpoint: 5f1b7f1 Use REST for Keycloak user seeding
latest known local commit before doc cleanup: f8c0f6f Add fresh VPS install orchestrator
```

## Confirmed Working

- Docker Compose deploy completed.
- Keycloak realm apply completed from repo JSON.
- Forced Keycloak user reseed completed for 130 users.
- Keycloak verifier completed with `313 pass, 0 warn, 0 fail`.
- Moodle OIDC apply completed.
- Moodle OIDC verifier passed.
- Public Moodle login page exposed the Keycloak login button.
- Moodle OAuth redirect returned HTTP 303 to the Keycloak authorization endpoint.
- Direct OIDC token test passed for `sara.shirazi`.
- Browser login into Moodle as `sara.shirazi` was confirmed.

## Seed User Password Rule

The password rule is defined in `data/keycloak-realm.json`.

```text
{username}@unrealuni
```

Example:

```text
sara.shirazi / sara.shirazi@unrealuni
```

## Final Validation Commands Used

```bash
KEYCLOAK_FORCE_RESEED=1 bash scripts/keycloak-realm.sh apply
bash scripts/verify-keycloak-realm.sh
bash scripts/moodle-oidc.sh verify
```

The direct OIDC token test used Keycloak's password grant against the Moodle client. Secrets were not stored in the repo.

## Remaining Reproducibility Risks

- Fresh VPS end-to-end flow has not been tested yet.
- `.env` is still manually created and filled.
- DNS, HTTPS, OIDC redirect, and browser-login readiness are not yet one automated verification path.
- Policy is undecided for users removed from `data/keycloak-users.json`.
