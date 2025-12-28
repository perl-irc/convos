# Atheme Auth Plugin - Implementation Plan

**Design Doc:** [2025-12-27-atheme-auth-plugin-design.md](./2025-12-27-atheme-auth-plugin-design.md)
**Worktree:** `.worktrees/atheme-auth`
**Branch:** `feature/atheme-auth-plugin`

## Component Dependency Graph

```
Test Infrastructure ─────────────────────────────────────┐
                                                         │
Plugin Skeleton ──┬── XMLRPC Client ── Email Resolution ─┼── Login Handler ── Auto-Config ─┐
                  │                                      │                                  │
                  └── Register Handler ──────────────────┼──────────────────────────────────┼── Integration Tests
                                                         │                                  │
                                                         └──────────────────────────────────┘
```

**Parallel tracks:**
- Track A: Test Infrastructure (independent)
- Track B: Plugin Skeleton → XMLRPC Client → Email Resolution → Login Handler → Auto-Config
- Track C: Plugin Skeleton → Register Handler

---

## Component 1: Test Infrastructure (Docker Atheme)

**Status:** [ ] Not Started
**Blocked by:** None
**Blocks:** Integration Tests

### Files
- Create: `t/atheme/docker-compose.yml`
- Create: `t/atheme/atheme.conf`
- Create: `t/atheme/README.md` (test account docs)

### Tasks

#### 1.1 Create directory structure
- [ ] Run: `mkdir -p t/atheme`
- [ ] Verify: `ls -la t/atheme/`

#### 1.2 Write docker-compose.yml
- [ ] Create file with Atheme service config
- [ ] Verify: `cat t/atheme/docker-compose.yml`

```yaml
# t/atheme/docker-compose.yml
services:
  atheme:
    image: atheme/atheme:latest
    ports:
      - "18080:8080"
    volumes:
      - ./atheme.conf:/etc/atheme/atheme.conf:ro
    command: ["atheme-services", "-n", "-c", "/etc/atheme/atheme.conf"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/xmlrpc"]
      interval: 5s
      timeout: 3s
      retries: 5
```

#### 1.3 Write atheme.conf
- [ ] Create minimal Atheme config enabling XMLRPC
- [ ] Verify: `cat t/atheme/atheme.conf`

```conf
# t/atheme/atheme.conf - Minimal config for testing
loadmodule "modules/misc/httpd";
loadmodule "modules/transport/xmlrpc";
loadmodule "modules/nickserv/main";
loadmodule "modules/nickserv/register";
loadmodule "modules/nickserv/identify";
loadmodule "modules/nickserv/info";
loadmodule "modules/nickserv/set_core";
loadmodule "modules/nickserv/set_hidemail";

serverinfo {
    name = "services.test";
    desc = "Test Atheme Services";
    netname = "TestNet";
    numeric = "00A";
};

general {
    commit_interval = 5;
};

httpd {
    host = "0.0.0.0";
    port = 8080;
};

nickserv {
    nick = "NickServ";
    user = "NickServ";
    host = "services.test";
    real = "Nickname Services";
    no_nick_ownership;
};
```

#### 1.4 Document test setup
- [ ] Write README with test account creation instructions
- [ ] Note: Accounts created dynamically in tests via XMLRPC or need IRC connection

#### 1.5 Verify Docker setup
- [ ] Run: `cd t/atheme && docker-compose up -d`
- [ ] Wait: `docker-compose ps` shows healthy
- [ ] Test: `curl -s http://127.0.0.1:18080/xmlrpc | head`
- [ ] Teardown: `docker-compose down`
- [ ] Commit: `git add t/atheme/ && git commit -m "test: add Docker Atheme infrastructure"`

---

## Component 2: Plugin Skeleton

**Status:** [ ] Not Started
**Blocked by:** None
**Blocks:** XMLRPC Client, Register Handler

### Files
- Create: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 2.1 Write failing test for plugin loading
- [ ] Create test file `t/plugin-auth-atheme.t`
- [ ] Write test: `use_ok('Convos::Plugin::Auth::Atheme')`
- [ ] Run: `PLENV_VERSION=claude-perl PERL5LIB=local/lib/perl5 prove -l t/plugin-auth-atheme.t`
- [ ] Verify test fails (module not found)

```perl
# t/plugin-auth-atheme.t
use Mojo::Base -strict;
use Test::More;

use_ok('Convos::Plugin::Auth::Atheme');

done_testing;
```

#### 2.2 Create minimal plugin module
- [ ] Create `lib/Convos/Plugin/Auth/Atheme.pm`
- [ ] Extend `Convos::Plugin::Auth`
- [ ] Add ABOUTME comment header
- [ ] Run test: verify passes
- [ ] Commit: `git commit -m "feat: add Atheme auth plugin skeleton"`

```perl
# lib/Convos/Plugin/Auth/Atheme.pm
package Convos::Plugin::Auth::Atheme;
# ABOUTME: Convos authentication plugin using Atheme IRC Services XMLRPC.
# ABOUTME: Authenticates users against NickServ accounts.

use Mojo::Base 'Convos::Plugin::Auth', -async_await;

our $VERSION = '0.01';

has xmlrpc_url => sub { $ENV{CONVOS_AUTH_ATHEME_URL} // 'http://127.0.0.1:8080/xmlrpc' };
has domain     => sub { $ENV{CONVOS_AUTH_ATHEME_DOMAIN} // 'irc.perl.org' };
has irc_url    => sub { $ENV{CONVOS_AUTH_ATHEME_IRC_URL} // 'irc://irc.perl.org:6697' };
has timeout    => sub { $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} // 10 };

sub register {
  my ($self, $app, $config) = @_;

  $self->xmlrpc_url($config->{xmlrpc_url}) if $config->{xmlrpc_url};
  $self->domain($config->{domain})         if $config->{domain};
  $self->irc_url($config->{irc_url})       if $config->{irc_url};
  $self->timeout($config->{timeout})       if $config->{timeout};

  $app->helper('auth.login_p'    => sub { $self->_login_p(@_) });
  $app->helper('auth.register_p' => sub { $self->_register_p(@_) });

  $app->log->info("Loaded Convos::Plugin::Auth::Atheme " . $self->xmlrpc_url);
}

# Placeholder - implemented in Component 5
async sub _login_p {
  my ($self, $c, $params) = @_;
  die 'Not implemented';
}

# Placeholder - implemented in Component 6
async sub _register_p {
  my ($self, $c, $params) = @_;
  die 'Not implemented';
}

1;
```

#### 2.3 Add RPC::XML dependency
- [ ] Install: `PLENV_VERSION=claude-perl plenv exec cpanm -l local RPC::XML`
- [ ] Verify: `PLENV_VERSION=claude-perl PERL5LIB=local/lib/perl5 perl -MRPC::XML::Client -e1`

---

## Component 3: XMLRPC Client

**Status:** [ ] Not Started
**Blocked by:** Component 2 (Plugin Skeleton)
**Blocks:** Email Resolution, Login Handler

### Files
- Modify: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 3.1 Write failing test for atheme.login
- [ ] Add test to `t/plugin-auth-atheme.t`
- [ ] Test `_atheme_login_p` method exists
- [ ] Run test, verify fails

```perl
# Add to t/plugin-auth-atheme.t
can_ok('Convos::Plugin::Auth::Atheme', '_atheme_login_p');
```

#### 3.2 Implement _atheme_login_p
- [ ] Add method using RPC::XML::Client
- [ ] Use Mojo::IOLoop->subprocess for non-blocking
- [ ] Handle success (return authcookie)
- [ ] Handle fault codes
- [ ] Run test, verify passes

```perl
sub _atheme_login_p {
  my ($self, $username, $password, $source_ip) = @_;
  $source_ip //= '';

  return Mojo::IOLoop->subprocess->run_p(sub {
    require RPC::XML::Client;
    my $client = RPC::XML::Client->new($self->xmlrpc_url);
    $client->useragent->timeout($self->timeout);

    my $resp = $client->send_request('atheme.login', $username, $password, $source_ip);

    if (ref $resp && $resp->is_fault) {
      die { code => $resp->code, message => $resp->string };
    }

    return ref $resp ? $resp->value : $resp;
  });
}
```

#### 3.3 Write failing test for atheme.command
- [ ] Add test for `_atheme_command_p` method
- [ ] Run test, verify fails

#### 3.4 Implement _atheme_command_p
- [ ] Add method for running NickServ INFO
- [ ] Run test, verify passes
- [ ] Commit: `git commit -m "feat(atheme): add XMLRPC client methods"`

```perl
sub _atheme_command_p {
  my ($self, $authcookie, $username, $source_ip, $service, $command, @args) = @_;

  return Mojo::IOLoop->subprocess->run_p(sub {
    require RPC::XML::Client;
    my $client = RPC::XML::Client->new($self->xmlrpc_url);
    $client->useragent->timeout($self->timeout);

    my $resp = $client->send_request(
      'atheme.command', $authcookie, $username, $source_ip // '',
      $service, $command, @args
    );

    if (ref $resp && $resp->is_fault) {
      die { code => $resp->code, message => $resp->string };
    }

    return ref $resp ? $resp->value : $resp;
  });
}
```

---

## Component 4: Email Resolution

**Status:** [ ] Not Started
**Blocked by:** Component 3 (XMLRPC Client)
**Blocks:** Login Handler

### Files
- Modify: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 4.1 Write failing test for email parsing
- [ ] Add test for `_parse_email_from_info` method
- [ ] Test with email present
- [ ] Test with HIDEMAIL (no email)
- [ ] Run test, verify fails

```perl
# Add to t/plugin-auth-atheme.t
my $plugin = Convos::Plugin::Auth::Atheme->new(domain => 'test.org');

is($plugin->_parse_email_from_info("Email: foo\@bar.com\nOther: stuff"),
   'foo@bar.com', 'parses email from INFO');

is($plugin->_parse_email_from_info("Other: stuff\nNo email here"),
   undef, 'returns undef when no email');
```

#### 4.2 Implement _parse_email_from_info
- [ ] Parse NickServ INFO output for Email line
- [ ] Return email or undef
- [ ] Run test, verify passes

```perl
sub _parse_email_from_info {
  my ($self, $info_output) = @_;
  return undef unless $info_output;
  return $1 if $info_output =~ /^Email\s*:\s*(\S+@\S+)/m;
  return undef;
}
```

#### 4.3 Write failing test for email resolution with fallback
- [ ] Add test for `_resolve_email_p` method
- [ ] Run test, verify fails

#### 4.4 Implement _resolve_email_p
- [ ] Call atheme.command for NickServ INFO
- [ ] Parse email from response
- [ ] Fallback to nick@domain
- [ ] Run test, verify passes
- [ ] Commit: `git commit -m "feat(atheme): add email resolution with fallback"`

```perl
async sub _resolve_email_p {
  my ($self, $authcookie, $username, $source_ip) = @_;

  my $email;
  eval {
    my $info = await $self->_atheme_command_p(
      $authcookie, $username, $source_ip, 'NickServ', 'INFO', $username
    );
    $email = $self->_parse_email_from_info($info);
  };

  # Fallback to nick@domain
  return $email // sprintf('%s@%s', $username, $self->domain);
}
```

---

## Component 5: Login Handler

**Status:** [ ] Not Started
**Blocked by:** Component 3 (XMLRPC Client), Component 4 (Email Resolution)
**Blocks:** Auto-Config, Integration Tests

### Files
- Modify: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 5.1 Write failing test for successful login
- [ ] Add test using Test::Mojo
- [ ] Mock or use real Atheme
- [ ] Run test, verify fails

#### 5.2 Implement _login_p - username normalization
- [ ] Strip @domain suffix
- [ ] Trim whitespace
- [ ] Add test, verify passes

```perl
sub _normalize_username {
  my ($self, $input) = @_;
  $input //= '';
  $input =~ s/^\s+|\s+$//g;  # trim
  $input =~ s/\@.*$//;        # strip @domain
  return $input;
}
```

#### 5.3 Implement _login_p - main flow
- [ ] Normalize username
- [ ] Call atheme.login
- [ ] Resolve email
- [ ] Lookup or create Convos user
- [ ] Run tests, verify passes

```perl
async sub _login_p {
  my ($self, $c, $params) = @_;

  my $username  = $self->_normalize_username($params->{email});
  my $password  = $params->{password};
  my $source_ip = $c->tx->remote_address;

  die 'Username is required' unless length $username;
  die 'Password is required' unless length $password;

  # Authenticate with Atheme
  my $authcookie;
  eval {
    $authcookie = await $self->_atheme_login_p($username, $password, $source_ip);
  } or do {
    my $err = $@;
    my $msg = $self->_fault_message(ref $err eq 'HASH' ? $err->{code} : 0);
    $c->app->log->warn("Atheme login failed for $username: $msg");
    die $msg;
  };

  # Resolve email
  my $email = await $self->_resolve_email_p($authcookie, $username, $source_ip);

  # Lookup or create user
  my $core = $c->app->core;
  my $user = $core->get_user({email => $email});

  unless ($user) {
    $c->app->log->info("Creating new user $email from Atheme auth");
    $user = $core->user({email => $email});
    await $user->save_p;
    await $self->_user_initial_setup_p($c, $user, $username, $password);
  }

  $c->app->log->info("Atheme login success for $username ($email)");
  return $user;
}
```

#### 5.4 Implement fault code mapping
- [ ] Add _fault_message method
- [ ] Map codes 1, 3, 5, 6 to user-friendly messages
- [ ] Run tests, verify passes
- [ ] Commit: `git commit -m "feat(atheme): implement login handler"`

```perl
sub _fault_message {
  my ($self, $code) = @_;
  my %messages = (
    1 => 'Missing credentials',
    3 => 'Account not registered. Register with /msg NickServ REGISTER on IRC.',
    5 => 'Invalid username or password',
    6 => 'Account is frozen. Contact network staff.',
  );
  return $messages{$code} // 'Authentication service unavailable. Please try again later.';
}
```

---

## Component 6: Register Handler

**Status:** [ ] Not Started
**Blocked by:** Component 2 (Plugin Skeleton)
**Blocks:** Integration Tests

### Files
- Modify: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 6.1 Write failing test for register rejection
- [ ] Add test that register_p rejects with NickServ message
- [ ] Run test, verify fails

#### 6.2 Implement _register_p
- [ ] Reject with helpful message
- [ ] Run test, verify passes
- [ ] Commit: `git commit -m "feat(atheme): reject registration with NickServ instructions"`

```perl
async sub _register_p {
  my ($self, $c, $params) = @_;
  die 'Registration is handled by NickServ. Connect to IRC and use: /msg NickServ REGISTER <password> <email>';
}
```

---

## Component 7: Auto-Config (IRC Connection Setup)

**Status:** [ ] Not Started
**Blocked by:** Component 5 (Login Handler)
**Blocks:** Integration Tests

### Files
- Modify: `lib/Convos/Plugin/Auth/Atheme.pm`

### Tasks

#### 7.1 Write failing test for first-login auto-config
- [ ] Add test that first login creates IRC connection
- [ ] Verify connection URL has SASL credentials
- [ ] Run test, verify fails

#### 7.2 Implement _user_initial_setup_p
- [ ] Build IRC URL with SASL credentials
- [ ] Create connection via connection_create_p
- [ ] Set admin role for first user
- [ ] Run tests, verify passes
- [ ] Commit: `git commit -m "feat(atheme): auto-configure IRC connection on first login"`

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

  eval {
    my $connection = await $c->user->connection_create_p($user, $url);
    $connection->connect_p->catch(sub { });  # Don't block on connect failure
  };

  return $user;
}
```

---

## Component 8: Integration Tests

**Status:** [ ] Not Started
**Blocked by:** All previous components
**Blocks:** None (final component)

### Files
- Modify: `t/plugin-auth-atheme.t`

### Tasks

#### 8.1 Add Docker Atheme skip logic
- [ ] Skip tests if Docker unavailable
- [ ] Add setup/teardown for docker-compose

```perl
use Test::More;

BEGIN {
  my $docker_available = !system('docker info >/dev/null 2>&1');
  plan skip_all => 'Docker not available' unless $docker_available;
}

# Setup
sub setup_atheme {
  system('cd t/atheme && docker-compose up -d --wait');
}

sub teardown_atheme {
  system('cd t/atheme && docker-compose down');
}
```

#### 8.2 Add integration tests
- [ ] Test successful login creates user
- [ ] Test successful login returns existing user
- [ ] Test invalid password rejects
- [ ] Test unknown account rejects
- [ ] Test registration rejects with message
- [ ] Test email resolution with fallback
- [ ] Test first login creates IRC connection

#### 8.3 Finalize and verify
- [ ] Run full test suite: `prove -l t/plugin-auth-atheme.t`
- [ ] Verify all tests pass
- [ ] Commit: `git commit -m "test(atheme): add integration tests"`

---

## Verification Checklist

Before marking complete, verify:

- [ ] All unit tests pass: `PLENV_VERSION=claude-perl PERL5LIB=local/lib/perl5 prove -l t/plugin-auth-atheme.t`
- [ ] Full test suite passes: `PLENV_VERSION=claude-perl PERL5LIB=local/lib/perl5 prove -l t/*.t`
- [ ] Plugin loads via env: `CONVOS_PLUGINS=Convos::Plugin::Auth::Atheme ./script/convos version`
- [ ] Documentation in POD is complete
- [ ] All commits have meaningful messages

## Test Commands Reference

```bash
# Set up environment
cd /Users/perigrin/dev/convos/.worktrees/atheme-auth
export PLENV_VERSION=claude-perl
export PERL5LIB=/Users/perigrin/dev/convos/local/lib/perl5

# Run single test file
plenv exec prove -l t/plugin-auth-atheme.t -v

# Run all tests
plenv exec prove -l t/*.t

# Start test Atheme
cd t/atheme && docker-compose up -d

# Stop test Atheme
cd t/atheme && docker-compose down
```
