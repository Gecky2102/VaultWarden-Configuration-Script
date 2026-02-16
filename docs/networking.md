# Networking and Port Forwarding

The script separates:
- **External HTTPS port**: client-facing port
- **Internal HTTPS port**: local nginx listen port

This supports custom NAT setups, for example:
- external `4443` -> internal `80`

## Example: External 4443 to Internal 80

During setup:
- set external HTTPS port: `4443`
- set internal HTTPS port: `80`

Then configure your router/firewall:
- WAN TCP `4443` -> server TCP `80`

Access URL becomes:
- `https://<domain>:4443`

## Firewall Behavior

The script opens:
- SSH (`22/tcp`)
- HTTP (`80/tcp`)
- internal HTTPS port (`<internal>/tcp`)

## Important

If you use automatic Let's Encrypt, ACME challenge may still require temporary/public HTTP handling depending on your DNS/network path.
