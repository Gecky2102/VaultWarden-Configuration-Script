# Certificate Modes

The installer supports three certificate modes.
The installer supports four certificate modes.

## Mode 1: Let's Encrypt (single domain, automatic)

- Uses certbot standalone challenge.
- Requires public reachability for ACME challenge.
- Stores cert/key under `/etc/letsencrypt/live/<domain>/`.

## Mode 2: Wildcard Manual Flow (key + CSR + import)

Use this when certificates are issued from your own PKI, panel, or provider.

Flow:
1. script generates private key in `/etc/ssl/vaultwarden/<base-domain>.key`
2. script generates CSR in `/etc/ssl/vaultwarden/<base-domain>.csr`
   - CSR includes mandatory `Organization (O)` field
3. you upload CSR to your certificate platform
4. you place the signed fullchain PEM in the configured input path
5. you confirm and the script validates/imports it for nginx

Notes:
- private key remains on server
- access key/CSR via SFTP if needed

## Mode 3: Existing Certificate + Key

If you already have cert and key files:
- provide fullchain path
- provide private key path
- script imports copies under `/etc/ssl/vaultwarden/`

## Mode 4: Resume Wildcard Flow

Use this if setup was interrupted after key/CSR generation.

Flow:
1. select mode 4
2. provide wildcard base domain
3. confirm or edit existing key/CSR paths
4. place signed fullchain in configured input path and confirm
5. installer continues with nginx/service/firewall and remaining steps

## Permissions

Imported/generated key and fullchain are set to restrictive permissions (`chmod 600`).

## Validation Checks

Before continuing, the script validates:
- private key format
- CSR format (when wildcard flow is used)
- certificate format
- key/certificate match
- domain format and email format
- certificate domain coverage (CN/SAN) for the configured domain
- wildcard certificate coverage for `*.<base-domain>` in wildcard modes
- output fullchain path writability
