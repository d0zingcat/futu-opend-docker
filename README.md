# FUTU OpenD Docker

Security-hardened Docker image for the official FUTU OpenD command-line gateway.
It verifies the official archive SHA-256, runs non-root, and reads login secrets only from mounted files.

> Not affiliated with FUTU. This convenience image contains FUTU OpenD; users must comply with FUTU terms and applicable rules.

## Dokploy deployment

Use this repository as a separate Dokploy Compose service with Compose path
`./docker-compose.yml`. It runs the released image
`ghcr.io/d0zingcat/futu-opend-docker:10.9.6918-1`; deployment never builds from
an application checkout and never publishes OpenD ports.

The Compose project owns these resources:

- `futu-broker` — an internal Docker network shared with a client application;
- `futu-opend-state` — OpenD login/device state;
- `futu-opend-secrets` — password-MD5 file and the generated RSA key.

`futu-init` creates `futu.pem` once before OpenD starts. It never overwrites a
key, so a client application's matching key remains valid on every redeploy.
Create the password-MD5 file in the secrets volume out of band; do not put the
password, MD5 digest, or PEM contents in Compose, Git, or Dokploy Environment.

Set only non-secret variables in this service's Dokploy Environment when
needed:

```dotenv
FUTU_ACCOUNT_ID=
FUTU_OPEND_NETWORK=futu-broker
FUTU_OPEND_STATE_VOLUME=futu-opend-state
FUTU_OPEND_SECRETS_VOLUME=futu-opend-secrets
```

A client application must use the same `FUTU_OPEND_NETWORK` and
`FUTU_OPEND_SECRETS_VOLUME`. It connects to the network alias `futu-opend` on
port `11111` and mounts the secrets volume read-only for RSA encryption.

### Migrate an existing sidecar

1. Record and back up the current OpenD state volume. In the running Dokploy
   stack, its name is normally `<compose-project>_<volume-name>`; inspect the
   actual volume name before continuing.
2. Stop the old `futu-opend` service. Do not run old and new OpenD containers
   against the same state volume at once.
3. In this service's Dokploy Environment, set `FUTU_OPEND_STATE_VOLUME` to the
   recorded old state-volume name and `FUTU_OPEND_SECRETS_VOLUME` to the old
   secrets-volume name. Deploy this service. The init
   job detects and keeps the existing RSA key; the login/device cache remains
   in place.
4. Deploy the client application's Compose change with the same secrets-volume
   name and `FUTU_OPEND_NETWORK=futu-broker`. The client application needs no
   OpenD password.
5. From the OpenD service's Dokploy terminal, complete any FUTU SMS/email/CAPTCHA
   prompt. Confirm the container becomes healthy, then refresh FUTU in the
   client application.

The state volume persists OpenD login/device state. Use Dokploy's terminal for
SMS/CAPTCHA input. Never expose API port `11111` or telnet port `22222` publicly.

## Interface

- `FUTU_ACCOUNT_ID` — optional account hint.
- `FUTU_ACCOUNT_PWD_MD5_FILE` — readable password-MD5 file.
- `FUTU_RSA_KEY_FILE` — readable PEM key file.
- `FUTU_OPEND_IP`, `FUTU_OPEND_PORT`, `FUTU_OPEND_TELNET_PORT` — listener configuration.

## Releases

Pushing a version tag, for example `v10.9.6918-1`, builds and publishes the
matching image tag without the `v` prefix (`10.9.6918-1`), `stable`, and an
immutable `sha-<7-character-commit>` tag. Releases include SBOM and
provenance. `10.9.6918` is the official OpenD binary version; `-1` is this
repository's first packaging revision for that binary. Repository code is MIT
licensed; FUTU OpenD itself is not.
