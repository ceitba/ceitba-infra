# ceitba-infra
CEITBA Infrastructure and orchestration for all services

## Generate Secure Keys

To generate secure encryption keys for Appsmith and other services:

```bash
# For JWT tokens and general encryption
openssl rand -base64 32

# For Appsmith encryption password (32 chars)
openssl rand -base64 32

# For Appsmith encryption salt (16 chars)
openssl rand -hex 16
```
