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
3. you upload CSR to your certificate platform
4. you provide signed certificate path (and optional CA chain path)
5. script builds fullchain and uses it in nginx

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
4. provide signed certificate (and optional CA chain)
5. installer continues with nginx/service/firewall and remaining steps

## Permissions

Imported/generated key and fullchain are set to restrictive permissions (`chmod 600`).

## Validation Checks

Before continuing, the script validates:
- private key format
- CSR format (when wildcard flow is used)
- certificate format
- key/certificate match
