# Atheme Test Infrastructure

Docker-based Atheme IRC Services with ngIRCd for integration testing.

## Components

- **ngIRCd**: Lightweight IRC server (port 16667)
- **Atheme**: IRC services linked to ngIRCd (XMLRPC port 18080)

## Quick Start

```bash
# Start the test infrastructure
docker-compose up -d

# Wait for healthy
docker-compose ps

# Test XMLRPC endpoint
curl http://127.0.0.1:18080/xmlrpc

# Test IRC connection
telnet 127.0.0.1 16667

# Stop infrastructure
docker-compose down
```

## Test Accounts

Test accounts can be created via:
- IRC connection to `127.0.0.1:16667` with NickServ REGISTER command
- XMLRPC API for verification and login
- Integration tests use ephemeral IRC connections for registration

## Integration Tests

Run integration tests with:

```bash
TEST_IRC=1 prove -v t/plugin-auth-atheme-registration.t
```

Tests verify:
- Full registration flow (connect, REGISTER, pending created)
- Duplicate nick detection
- Verification flow (VERIFY command)
- Error cases (bad email, missing fields, bad verification code)
- IRC connectivity and NickServ communication
