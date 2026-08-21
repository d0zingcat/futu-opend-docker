# FUTU OpenD Docker

Security-hardened Docker image for the official FUTU OpenD command-line gateway.
It verifies the official archive SHA-256, runs non-root, and reads login secrets only from mounted files.

> Not affiliated with FUTU. This convenience image contains FUTU OpenD; users must comply with FUTU terms and applicable rules.

## Quick start

Mount a directory containing `password-md5` and `futu.pem`, then run:

```yaml
services:
  futu-opend:
    image: ghcr.io/d0zingcat/futu-opend-docker:stable
    environment:
      FUTU_OPEND_IP: 0.0.0.0
      FUTU_ACCOUNT_ID: "your-account-id"
      FUTU_ACCOUNT_PWD_MD5_FILE: /run/secrets/password-md5
      FUTU_RSA_KEY_FILE: /run/secrets/futu.pem
    volumes:
      - futu-state:/home/futu/.com.futunn.FutuOpenD
      - ./secrets:/run/secrets:ro
    ports: ["127.0.0.1:11111:11111", "127.0.0.1:22222:22222"]
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    stdin_open: true
    tty: true
volumes: {futu-state: {}}
```

The named volume persists OpenD login/device state. Use `docker attach` or the loopback-only telnet port for SMS/CAPTCHA input. Never expose these ports publicly.

## Interface

- `FUTU_ACCOUNT_ID` — optional account hint.
- `FUTU_ACCOUNT_PWD_MD5_FILE` — readable password-MD5 file.
- `FUTU_RSA_KEY_FILE` — readable PEM key file.
- `FUTU_OPEND_IP`, `FUTU_OPEND_PORT`, `FUTU_OPEND_TELNET_PORT` — listener configuration.

## Releases

Pushing a version tag, for example `v10.9.6918-gm1`, builds and publishes the
matching image tag, `stable`, and an immutable `sha-<commit>` tag. Releases
include SBOM and provenance. Repository code is MIT licensed; FUTU OpenD
itself is not.
