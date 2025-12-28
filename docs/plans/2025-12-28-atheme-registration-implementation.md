# Atheme Registration Plugin Implementation Plan

**Design Doc:** 2025-12-28-atheme-registration-plugin-design.md
**Branch:** feature/atheme-registration-plugin

## Components

### Component 1: PendingRegistration Model

Create the storage model for pending registrations.

**Files:**
- Create: `lib/Convos/Core/PendingRegistration.pm`
- Create: `t/pending-registration.t`

**Tasks:**
- [ ] Write failing test for PendingRegistration->new with required attributes
- [ ] Run test: `prove -lv t/pending-registration.t`
- [ ] Implement PendingRegistration with core, session_id, nick, email, created_at, expires_at
- [ ] Run test to verify pass
- [ ] Write failing test for uri() method returns correct path
- [ ] Implement uri() returning `Mojo::Path->new("pending/$session_id.json")`
- [ ] Run test to verify pass
- [ ] Write failing test for TO_JSON() serialization
- [ ] Implement TO_JSON()
- [ ] Run test to verify pass
- [ ] Write failing test for save_p/load_p/delete_p via backend
- [ ] Implement save_p, load_p (with expiration check), delete_p
- [ ] Run test to verify pass
- [ ] Commit: `feat(atheme): add PendingRegistration model`

### Component 2: Ephemeral IRC Connection

Add IRC connection methods to the Registration plugin.

**Files:**
- Create: `lib/Convos/Plugin/Auth/Atheme/Registration.pm` (initial skeleton)
- Create: `t/plugin-auth-atheme-registration.t`

**Tasks:**
- [ ] Write failing test for _ephemeral_irc_p connects successfully
- [ ] Run test (will skip without IRC server)
- [ ] Implement _ephemeral_irc_p using Mojo::IRC::UA
- [ ] Write failing test for _ephemeral_irc_p rejects on nick-in-use
- [ ] Implement nick-in-use handling
- [ ] Write failing test for _send_nickserv_p sends command and collects response
- [ ] Implement _send_nickserv_p
- [ ] Run tests to verify
- [ ] Commit: `feat(atheme): add ephemeral IRC connection for registration`

### Component 3: NickServ Response Parsing

Add response parsing for NickServ REGISTER and VERIFY commands.

**Files:**
- Modify: `lib/Convos/Plugin/Auth/Atheme/Registration.pm`
- Modify: `t/plugin-auth-atheme-registration.t`

**Tasks:**
- [ ] Write failing tests for _parse_register_response with success pattern
- [ ] Implement %REGISTER_RESPONSES patterns and _parse_register_response
- [ ] Run test to verify pass
- [ ] Write failing tests for _parse_register_response with error patterns (nick_in_use, bad_email, rate_limit)
- [ ] Add error patterns to implementation
- [ ] Run tests to verify pass
- [ ] Write failing tests for _parse_verify_response with success pattern
- [ ] Implement %VERIFY_RESPONSES patterns and _parse_verify_response
- [ ] Run test to verify pass
- [ ] Write failing tests for _parse_verify_response with error patterns (bad_code, expired, nick_taken)
- [ ] Add error patterns to implementation
- [ ] Run tests to verify pass
- [ ] Commit: `feat(atheme): add NickServ response parsing`

### Component 4: Registration Handler

Implement _register_p that orchestrates the registration flow.

**Files:**
- Modify: `lib/Convos/Plugin/Auth/Atheme/Registration.pm`
- Modify: `t/plugin-auth-atheme-registration.t`

**Tasks:**
- [ ] Write failing test for _register_p rejects without required fields
- [ ] Implement input validation in _register_p
- [ ] Run test to verify pass
- [ ] Write failing test for _register_p connects, sends REGISTER, stores pending on success
- [ ] Implement full _register_p flow (will need mock or skip for IRC parts)
- [ ] Run test to verify pass
- [ ] Write failing test for _register_p returns appropriate error on nick_in_use
- [ ] Implement error handling
- [ ] Run tests to verify pass
- [ ] Commit: `feat(atheme): add registration handler`

### Component 5: Verification Handler

Implement _verify_p and the /api/auth/verify route.

**Files:**
- Modify: `lib/Convos/Plugin/Auth/Atheme/Registration.pm`
- Modify: `t/plugin-auth-atheme-registration.t`

**Tasks:**
- [ ] Write failing test for _verify_p rejects without code
- [ ] Implement code validation
- [ ] Run test to verify pass
- [ ] Write failing test for _verify_p rejects when no pending registration
- [ ] Implement pending lookup with error handling
- [ ] Run test to verify pass
- [ ] Write failing test for _verify_p connects, sends VERIFY, returns success
- [ ] Implement full _verify_p flow
- [ ] Run test to verify pass
- [ ] Write failing test for _verify_p deletes pending on success
- [ ] Implement cleanup
- [ ] Run tests to verify pass
- [ ] Commit: `feat(atheme): add verification handler`

### Component 6: Plugin Registration

Wire up the plugin with Convos.

**Files:**
- Modify: `lib/Convos/Plugin/Auth/Atheme/Registration.pm`
- Modify: `t/plugin-auth-atheme-registration.t`

**Tasks:**
- [ ] Write failing test for plugin->register sets auth.register_p helper
- [ ] Implement register() method with helper override
- [ ] Run test to verify pass
- [ ] Write failing test for POST /api/auth/verify route exists
- [ ] Implement route registration
- [ ] Run test to verify pass
- [ ] Add configuration attributes (irc_url, domain, timeout)
- [ ] Add environment variable support
- [ ] Run all tests to verify pass
- [ ] Commit: `feat(atheme): complete registration plugin wiring`

### Component 7: Integration Tests

Add integration tests with Docker Atheme.

**Files:**
- Modify: `t/plugin-auth-atheme-registration.t`
- Possibly modify: `t/atheme/docker-compose.yml` (if IRC server needed)

**Tasks:**
- [ ] Add SKIP block for integration tests when Atheme unavailable
- [ ] Write integration test for full registration flow
- [ ] Write integration test for full verification flow
- [ ] Write integration test for error cases (nick taken, bad code)
- [ ] Run integration tests with Docker Atheme
- [ ] Commit: `test(atheme): add registration integration tests`

## Verification

After all components complete:

```bash
# Run all Atheme-related tests
prove -lv t/pending-registration.t t/plugin-auth-atheme*.t

# Run with Docker Atheme for integration tests
cd t/atheme && docker-compose up -d
prove -lv t/plugin-auth-atheme-registration.t
```

## Notes

- This plugin extends the existing Auth::Atheme plugin
- Must load AFTER Auth::Atheme in plugin order
- Uses existing IRC infrastructure (Mojo::IRC::UA)
- Pending registrations stored via Backend abstraction for future-proofing
