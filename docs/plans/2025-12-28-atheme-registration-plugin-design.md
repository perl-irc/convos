# Convos Atheme Registration Plugin Design

**Date:** 2025-12-28
**Status:** Design Complete
**Companion to:** Auth::Atheme plugin (login via XMLRPC)

## Overview

This plugin enables web-based NickServ registration for Convos users. Since Atheme lacks an XMLRPC registration endpoint, we use ephemeral IRC connections to send NickServ REGISTER/VERIFY commands.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin scope | Atheme-specific | Assumes Atheme response formats |
| State storage | Convos Backend abstraction | Future-proof for non-file backends |
| Nick collision | Fail with error | User must restart with different nick |
| IRC connection identity | User's desired nick | Natural flow, avoids coordination |
| Verification resumption | Same session only | Simpler, no cross-session lookup |
| Post-verification auth | Prompt for password | No password storage needed |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin Loading Order                      │
├─────────────────────────────────────────────────────────────┤
│  1. Auth::Atheme              - handles login (XMLRPC)      │
│  2. Auth::Atheme::Registration - handles register (IRC)     │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. PendingRegistration Model

New class following Convos storage patterns:

**File:** `lib/Convos/Core/PendingRegistration.pm`

```perl
package Convos::Core::PendingRegistration;
use Mojo::Base 'Mojo::EventEmitter';

use Convos::Util qw(logf);
use Mojo::Date;
use Mojo::Path;

has 'core';                                    # Required - for backend access
has 'session_id';                              # Mojo session ID
has 'nick';
has 'email';
has 'created_at'  => sub { Mojo::Date->new };
has 'expires_at'  => sub { Mojo::Date->new(time + 86400) };  # 24h

sub uri {
  Mojo::Path->new(sprintf 'pending/%s.json', $_[0]->session_id);
}

sub TO_JSON {
  my ($self, $persist) = @_;
  return {
    session_id => $self->session_id,
    nick       => $self->nick,
    email      => $self->email,
    created_at => $self->created_at->to_datetime,
    expires_at => $self->expires_at->to_datetime,
  };
}

sub save_p   { shift->core->backend->save_object_p(@_) }
sub load_p   { ... }  # Load + check expiration
sub delete_p { shift->core->backend->delete_object_p(@_) }
```

**Storage location:** `$CONVOS_HOME/pending/{session_id}.json`

### 2. Registration Plugin

**File:** `lib/Convos/Plugin/Auth/Atheme/Registration.pm`

```perl
package Convos::Plugin::Auth::Atheme::Registration;
use Mojo::Base 'Convos::Plugin', -async_await;

has irc_url => sub { Mojo::URL->new($ENV{CONVOS_AUTH_ATHEME_IRC_URL} // 'irc://irc.perl.org:6697') };
has domain  => sub { $ENV{CONVOS_AUTH_ATHEME_DOMAIN} // 'irc.perl.org' };
has timeout => sub { $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} // 30 };

sub register {
  my ($self, $app, $config) = @_;

  # Override registration helper
  $app->helper('auth.register_p' => sub { $self->_register_p(@_) });

  # Add verification route
  $app->routes->post('/api/auth/verify')->to(cb => sub { ... });

  $app->log->info("Loaded Convos::Plugin::Auth::Atheme::Registration");
}
```

### 3. Ephemeral IRC Connection

Temporary connection for NickServ commands:

```perl
sub _ephemeral_irc_p {
  my ($self, $nick) = @_;

  my $irc = Mojo::IRC::UA->new(
    nick   => $nick,
    user   => $nick,
    name   => 'Convos Registration',
    server => $self->irc_url->host_port,
    tls    => ($self->irc_url->scheme =~ /s$/ ? {} : undef),
  );

  # Returns promise that resolves with $irc on connect
  # Rejects on nick-in-use, timeout, or error
}

sub _send_nickserv_p {
  my ($self, $irc, $command) = @_;
  # Send PRIVMSG NickServ :$command
  # Collect NOTICE responses until complete
  # Auto-disconnect after response
}
```

### 4. NickServ Response Parsing

```perl
my %REGISTER_RESPONSES = (
  success      => qr/An email containing nickname activation/i,
  nick_in_use  => qr/is already registered/i,
  bad_email    => qr/is not allowed|invalid email/i,
  rate_limit   => qr/too many accounts|try again later/i,
);

my %VERIFY_RESPONSES = (
  success      => qr/has been verified|registration complete/i,
  bad_code     => qr/invalid key|verification code.*incorrect/i,
  expired      => qr/not awaiting|no registration pending/i,
  nick_taken   => qr/already registered/i,
);
```

**Error messages:**

| Status | User Message |
|--------|--------------|
| `nick_in_use` | "This nickname is already registered" |
| `bad_email` | "Email address not accepted" |
| `rate_limit` | "Too many registration attempts, try later" |
| `bad_code` | "Invalid verification code" |
| `expired` | "Verification expired, please register again" |
| `unknown` | "Registration failed, please try on IRC" |

## Flows

### Registration Flow

```
1. User submits: nick, password, email
                │
                ▼
2. Plugin connects to IRC as "nick"
   ┌─────────────────────────────────┐
   │ NICK desirednick                │
   │ USER desirednick 0 * :Convos    │
   └─────────────────────────────────┘
                │
                ▼
3. Send registration command
   ┌─────────────────────────────────┐
   │ PRIVMSG NickServ :REGISTER      │
   │         <password> <email>      │
   └─────────────────────────────────┘
                │
                ▼
4. Parse NickServ response
   - Success → store pending, show "check email"
   - Error → return error message
                │
                ▼
5. Store pending registration
   ┌─────────────────────────────────┐
   │ $CONVOS_HOME/pending/{sid}.json │
   │ { nick, email, expires_at }     │
   └─────────────────────────────────┘
```

### Verification Flow

```
1. User enters verification code
                │
                ▼
2. Load pending registration by session_id
   - Not found → error
   - Expired → error
                │
                ▼
3. Connect to IRC as nick
                │
                ▼
4. Send verify command
   ┌─────────────────────────────────┐
   │ PRIVMSG NickServ :VERIFY        │
   │         REGISTER <nick> <code>  │
   └─────────────────────────────────┘
                │
                ▼
5. Parse response
   - Success → delete pending, redirect to login
   - Error → return error message
```

### UI Flow

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────┐    ┌─────────────┐
│ Register    │───▶│ "Check email"    │───▶│ Enter code  │───▶│ Login page  │
│ nick/pass/  │    │ waiting screen   │    │ [____]      │    │ nick/pass   │
│ email       │    │                  │    │ [Verify]    │    │ (prefilled) │
└─────────────┘    └──────────────────┘    └─────────────┘    └─────────────┘
```

## API Endpoints

### POST /api/user/register (existing, overridden)

**Request:**
```json
{
  "username": "desirednick",
  "password": "secret",
  "email": "user@example.com"
}
```

**Response (success):**
```json
{
  "status": "pending_verification",
  "nick": "desirednick",
  "email": "user@example.com"
}
```

**Response (error):**
```json
{
  "errors": [{"message": "Nickname is already registered"}]
}
```

### POST /api/auth/verify (new)

**Request:**
```json
{
  "code": "ABC123"
}
```

**Response (success):**
```json
{
  "status": "verified",
  "nick": "desirednick"
}
```

**Response (error):**
```json
{
  "errors": [{"message": "Invalid verification code"}]
}
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONVOS_AUTH_ATHEME_IRC_URL` | `irc://irc.perl.org:6697` | IRC server for registration |
| `CONVOS_AUTH_ATHEME_DOMAIN` | `irc.perl.org` | Domain for user emails |
| `CONVOS_AUTH_ATHEME_TIMEOUT` | `30` | Connection timeout (seconds) |

### Plugin Config

```perl
plugin 'Auth::Atheme' => {
  xmlrpc_url => 'http://services.irc.perl.org:8080/xmlrpc',
  irc_url    => 'irc://irc.perl.org:6697',
  domain     => 'irc.perl.org',
};

plugin 'Auth::Atheme::Registration' => {
  irc_url => 'irc://irc.perl.org:6697',
  domain  => 'irc.perl.org',
  timeout => 30,
};
```

## File Structure

```
lib/
├── Convos/
│   ├── Core/
│   │   └── PendingRegistration.pm    # NEW: Pending registration model
│   └── Plugin/
│       └── Auth/
│           └── Atheme/
│               └── Registration.pm   # NEW: Registration plugin

$CONVOS_HOME/
├── pending/                          # NEW: Pending registrations
│   └── {session_id}.json
├── user@example.com/
└── settings.json
```

## Testing Strategy

1. **Unit tests** - Response parsing, PendingRegistration model
2. **Integration tests** - Full flow with mock IRC server
3. **Docker tests** - Real Atheme instance (extends existing t/atheme/ setup)

## Security Considerations

- Passwords sent to NickServ over IRC (use TLS)
- Pending registrations expire after 24h
- Session-bound verification prevents hijacking
- Rate limiting inherited from Atheme
- No password storage in pending registration

## Future Considerations

- Password reset via NickServ SENDPASS
- Email change via NickServ SET EMAIL
- Account linking (multiple nicks)
