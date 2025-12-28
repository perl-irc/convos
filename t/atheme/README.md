# Atheme Test Infrastructure

Docker-based Atheme IRC Services for integration testing.

## Quick Start

```bash
# Start Atheme
docker-compose up -d

# Wait for healthy
docker-compose ps

# Test XMLRPC endpoint
curl http://127.0.0.1:18080/xmlrpc

# Stop Atheme
docker-compose down
```

## Test Accounts

Test accounts must be created dynamically via the XMLRPC API or by connecting an IRC client to a linked IRC server. The Atheme XMLRPC interface does not support account registration directly.

For integration tests, use the atheme.login fault code 3 (unregistered) to test failure cases.
