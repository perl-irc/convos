# Convos Atheme Authentication Plugin Design

## Summary

Create a Convos plugin that authenticates users against Atheme IRC Services via XMLRPC, enabling single sign-on for irc.perl.org users. Users log into Convos using their NickServ credentials.

## Problem Statement

Users of irc.perl.org who want to use Convos as a web client must maintain separate credentials for:
1. Their NickServ account (IRC identity)
2. Their Convos account (web client)

This creates friction compared to integrated platforms. By authenticating Convos against Atheme's NickServ database, we eliminate duplicate credentials and improve the onboarding experience.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth approach | Full external (Approach B) | Clean single auth source, no mixed local/NickServ accounts |
| User identity | Atheme email with fallback | Try INFO lookup, fall back to `nick@irc.perl.org` |
| XMLRPC library | RPC::XML::Client | Well-maintained, full control, no stale dependencies |
| Testing | Real Atheme in Docker | No mocks per project policy, true integration testing |
| First login | Auto-configure IRC + SASL | User immediately ready to chat |

## Architecture

### File Structure

```
lib/Convos/Plugin/Auth/Atheme.pm    # Main plugin (~150 lines)
t/plugin-auth-atheme.t              # Integration tests
t/atheme/docker-compose.yml         # Test Atheme instance
t/atheme/atheme.conf                # Atheme config for tests
t/atheme/services.db                # Pre-seeded test accounts
```

### Plugin Class

The plugin extends `Convos::Plugin::Auth` and overrides two helpers:

- **`auth.login_p`** - Authenticates against Atheme XMLRPC, creates/retrieves Convos user, auto-configures IRC connection on first login
- **`auth.register_p`** - Rejects with message directing users to NickServ REGISTER

Uses `Mojo::IOLoop->subprocess` to wrap synchronous RPC::XML::Client calls for non-blocking I/O.

## Authentication Flow

```
1. User submits: username (or username@domain) + password
                          |
2. Strip @domain suffix   |  (allow "nick" or "nick@irc.perl.org")
                          v
3. atheme.login(nick, password, client_ip)
         |
         +---> Success (authcookie returned)
         |         |
         |         v
         |   4. atheme.command(authcookie, nick, ip, "NickServ", "INFO", nick)
         |         |
         |         +---> Parse email from response
         |         |         |
         |         |         +---> Email found? Use it : fallback to nick@domain
         |         |
         |         v
         |   5. Lookup/create Convos user with resolved email
         |         |
         |         v
         |   6. First login? Run initial_setup_p (auto-config IRC + admin role)
         |         |
         |         v
         |   7. Return user object (success)
         |
         +---> Failure (fault code)
                   |
                   v
              8. Map fault code to user-friendly message, reject promise
```

### Fault Code Mapping

| Code | Message |
|------|---------|
| 1 | Missing credentials |
| 3 | Account not registered. Register with /msg NickServ REGISTER on IRC. |
| 5 | Invalid username or password |
| 6 | Account is frozen. Contact network staff. |

## IRC Auto-Configuration

On first login, after user creation, we auto-configure an irc.perl.org connection.

**Connection URL format**: `irc://nick:password@irc.perl.org:6697?tls=1&sasl=plain`

```perl
async sub _user_initial_setup_p {
  my ($self, $c, $user, $nick, $password) = @_;
  my $core = $c->app->core;

  # First user becomes admin
  $user->role(give => 'admin') if $core->n_users == 1;

  # Build IRC URL with SASL credentials
  my $url = Mojo::URL->new($self->irc_url);
  $url->userinfo("$nick:$password");
  $url->query->merge(tls => 1, sasl => 'plain');

  my $connection = await $c->user->connection_create_p($user, $url);
  $connection->connect_p->catch(sub { });  # Don't block on connect failure

  return $user;
}
```

**Security note**: The password is stored in Convos's connection config (as it would be for any SASL-enabled connection). This is existing Convos behavior, not new exposure.

**Returning users**: On subsequent logins, we skip initial_setup_p. If the user deleted their irc.perl.org connection, they can re-add it manually.

## Error Handling

### Network Errors (Atheme Unreachable)

- Wrap XMLRPC calls in try/catch
- Log the connection failure with details
- Return user-friendly message: "Authentication service unavailable. Please try again later."
- No fallback to local auth (per Approach B decision)

### Timeout Handling

- Configure `RPC::XML::Client` with reasonable timeout (10 seconds default)
- Environment variable `CONVOS_AUTH_ATHEME_TIMEOUT` for tuning
- Subprocess wrapper prevents blocking main event loop regardless

### Email Parsing Edge Cases

- NickServ INFO output varies; email line format: `Email: user@example.com`
- If HIDEMAIL is set: no email line appears -> fallback to `nick@domain`
- If email line malformed or missing -> fallback to `nick@domain`
- Regex: `/^Email\s*:\s*(\S+@\S+)/m`

### Username Normalization

- Strip `@domain` suffix if provided (user types `nick@irc.perl.org`)
- Preserve original case (NickServ is typically case-insensitive, but we preserve what user typed)
- Trim whitespace

### Logging

- Log all auth attempts (success/failure) following existing `_log_attempt` pattern
- Include: email/nick, remote_address, success/failure, fault code if applicable

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONVOS_PLUGINS` | - | Must include `Convos::Plugin::Auth::Atheme` |
| `CONVOS_AUTH_ATHEME_URL` | `http://127.0.0.1:8080/xmlrpc` | Atheme XMLRPC endpoint |
| `CONVOS_AUTH_ATHEME_DOMAIN` | `irc.perl.org` | Domain for fallback email |
| `CONVOS_AUTH_ATHEME_IRC_URL` | `irc://irc.perl.org:6697` | IRC server for auto-config |
| `CONVOS_AUTH_ATHEME_TIMEOUT` | `10` | XMLRPC timeout in seconds |

### Example Deployment

```bash
CONVOS_PLUGINS=Convos::Plugin::Auth::Atheme \
CONVOS_AUTH_ATHEME_URL=http://127.0.0.1:8080/xmlrpc \
CONVOS_AUTH_ATHEME_DOMAIN=irc.perl.org \
./script/convos daemon
```

### Atheme Requirements

Operator must configure Atheme:

```conf
# atheme.conf
loadmodule "modules/misc/httpd";
loadmodule "modules/transport/xmlrpc";

httpd {
    host = "127.0.0.1";  # Localhost only - Convos connects internally
    port = 8080;
};
```

### Security Considerations

- Atheme XMLRPC should bind to localhost only (127.0.0.1)
- If Convos and Atheme on different hosts, use SSH tunnel or private network
- Never expose XMLRPC to public internet

### Dependencies

Add to cpanfile:

```perl
requires 'RPC::XML', '0.80';  # Provides RPC::XML::Client
```

## Testing Strategy

### Docker Setup

**File**: `t/atheme/docker-compose.yml`

```yaml
services:
  atheme:
    image: atheme/atheme:latest
    ports:
      - "18080:8080"  # XMLRPC
    volumes:
      - ./atheme.conf:/etc/atheme/atheme.conf:ro
      - ./services.db:/var/lib/atheme/services.db:ro
    command: ["atheme-services", "-n"]
```

### Pre-seeded Test Data

**File**: `t/atheme/services.db`

- Account `testuser` with password `testpass123` and email `testuser@example.com`
- Account `nomail` with password `testpass123` and HIDEMAIL set
- Frozen account `frozen` for testing fault code 6

### Test Cases

1. Successful login -> returns user, creates Convos account
2. Successful login (returning user) -> returns existing user
3. Invalid password -> rejects with correct message
4. Unknown account -> rejects with "not registered" message
5. Frozen account -> rejects with "frozen" message
6. Email resolution -> uses Atheme email when available
7. Email fallback -> uses `nick@domain` when HIDEMAIL set
8. Register attempt -> rejects with NickServ instructions
9. Auto-config -> first login creates irc.perl.org connection with SASL
10. Timeout handling -> graceful error when Atheme unreachable

### CI Integration

- `docker-compose up -d` in test setup
- Wait for Atheme healthy before running tests
- `docker-compose down` in teardown
- Skip tests if Docker unavailable (with `skip_all` message)

## Acceptance Criteria

- [x] User can log into Convos with NickServ username/password
- [x] Failed logins show appropriate error messages
- [x] New users are auto-provisioned on first successful login
- [x] Registration form redirects/instructs users to use NickServ
- [x] Plugin is configurable (XMLRPC URL, email domain)
- [x] Includes tests with real Atheme instance
- [x] Works with Convos's existing session management
- [x] Auto-configure irc.perl.org connection with SASL on first login

## References

- [Atheme NickServ Docs](https://atheme.dev/docs/help/nickserv/)
- [Atheme XMLRPC Documentation](http://manual.freeshell.org/atheme/XMLRPC)
- [Atheme config example](https://github.com/atheme/atheme/blob/master/dist/atheme.conf.example)
- [Convos plugin docs](https://convos.chat/doc/develop)
- [CPAN RPC::XML](https://metacpan.org/pod/RPC::XML::Client)
