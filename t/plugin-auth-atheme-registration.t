#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN { use_ok('Convos::Plugin::Auth::Atheme::Registration') };

# Mock classes for testing
package Test::MockCore {
  use Mojo::Base -base;
  has backend => sub { Test::MockBackend->new };
}

package Test::MockBackend {
  use Mojo::Base -base;
  use Mojo::Promise;
  sub save_object_p { Mojo::Promise->new->resolve($_[1]) }
  sub load_object_p {
    # Return empty hashref to trigger "not found" condition
    Mojo::Promise->new->resolve({});
  }
}

package Test::MockRoutes {
  use Mojo::Base -base;
  sub post {
    my ($self, $path) = @_;
    return Test::MockRoute->new(path => $path);
  }
}

package Test::MockRoute {
  use Mojo::Base -base;
  has 'path';
  sub to { shift }
}

package Test::MockLog {
  use Mojo::Base -base;
  sub debug { shift }
  sub info { shift }
  sub warn { shift }
  sub error { shift }
}

package Test::MockApp {
  use Mojo::Base -base;
  has core => sub { Test::MockCore->new };
  has routes => sub { Test::MockRoutes->new };
  has log => sub { Test::MockLog->new };
  sub helper {
    my ($self, $name, $code) = @_;
    # Store helpers for verification
    $self->{_helpers}{$name} = $code;
  }
}

package Test::MockSession {
  use Mojo::Base -base;
  sub id { 'test-session-123' }
}

package Test::MockReq {
  use Mojo::Base -base;
  has 'json';
}

package Test::MockController {
  use Mojo::Base -base;
  has 'app';
  has 'req' => sub { Test::MockReq->new };
  has session => sub { Test::MockSession->new };
}

package main;

# Test plugin can be instantiated
my $plugin = Convos::Plugin::Auth::Atheme::Registration->new;
isa_ok($plugin, 'Convos::Plugin::Auth::Atheme::Registration');

# Test configuration attributes
is($plugin->domain, 'example.net', 'default domain');
is($plugin->timeout, 30, 'default timeout');
isa_ok($plugin->irc_url, 'Mojo::URL', 'irc_url is Mojo::URL');
is($plugin->irc_url->host, 'localhost', 'default irc host');

# Test can methods exist
can_ok($plugin, '_ephemeral_irc_p');
can_ok($plugin, '_send_nickserv_p');
can_ok($plugin, '_register_p');
can_ok($plugin, '_verify_p');
can_ok($plugin, 'register');

# Test plugin can be instantiated with custom config
subtest 'plugin custom configuration' => sub {
  my $custom_plugin = Convos::Plugin::Auth::Atheme::Registration->new;

  # Create mock app for registration
  my $app = Test::MockApp->new;

  # Test configuration via register() method
  my $config = {
    irc_url => 'irc://custom.irc.net:6667',
    domain  => 'custom.net',
    timeout => 60,
  };

  $custom_plugin->register($app, $config);

  is($custom_plugin->domain, 'custom.net', 'custom domain applied via config');
  is($custom_plugin->timeout, 60, 'custom timeout applied via config');
  isa_ok($custom_plugin->irc_url, 'Mojo::URL', 'custom irc_url is Mojo::URL');
  is($custom_plugin->irc_url->host, 'custom.irc.net', 'custom irc host applied via config');
  is($custom_plugin->irc_url->port, 6667, 'custom irc port applied via config');
};

# Test environment variables are read correctly
subtest 'environment variable configuration' => sub {
  # Save original env vars
  my $orig_irc_url = $ENV{CONVOS_AUTH_ATHEME_IRC_URL};
  my $orig_domain = $ENV{CONVOS_AUTH_ATHEME_DOMAIN};
  my $orig_timeout = $ENV{CONVOS_AUTH_ATHEME_TIMEOUT};

  # Set custom env vars
  $ENV{CONVOS_AUTH_ATHEME_IRC_URL} = 'irc://env.irc.net:7000';
  $ENV{CONVOS_AUTH_ATHEME_DOMAIN} = 'env.net';
  $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} = 45;

  # Create new plugin to pick up env vars
  my $env_plugin = Convos::Plugin::Auth::Atheme::Registration->new;

  is($env_plugin->domain, 'env.net', 'CONVOS_AUTH_ATHEME_DOMAIN read correctly');
  is($env_plugin->timeout, 45, 'CONVOS_AUTH_ATHEME_TIMEOUT read correctly');
  isa_ok($env_plugin->irc_url, 'Mojo::URL', 'env irc_url is Mojo::URL');
  is($env_plugin->irc_url->host, 'env.irc.net', 'CONVOS_AUTH_ATHEME_IRC_URL host read correctly');
  is($env_plugin->irc_url->port, 7000, 'CONVOS_AUTH_ATHEME_IRC_URL port read correctly');

  # Restore original env vars
  if (defined $orig_irc_url) {
    $ENV{CONVOS_AUTH_ATHEME_IRC_URL} = $orig_irc_url;
  } else {
    delete $ENV{CONVOS_AUTH_ATHEME_IRC_URL};
  }
  if (defined $orig_domain) {
    $ENV{CONVOS_AUTH_ATHEME_DOMAIN} = $orig_domain;
  } else {
    delete $ENV{CONVOS_AUTH_ATHEME_DOMAIN};
  }
  if (defined $orig_timeout) {
    $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} = $orig_timeout;
  } else {
    delete $ENV{CONVOS_AUTH_ATHEME_TIMEOUT};
  }
};

# Test register() method sets auth.register_p helper
subtest 'register() method wiring' => sub {
  my $test_plugin = Convos::Plugin::Auth::Atheme::Registration->new;
  my $app = Test::MockApp->new;

  # Register the plugin
  $test_plugin->register($app, {});

  # Verify helper was set
  ok(exists $app->{_helpers}{'auth.register_p'}, 'auth.register_p helper was set');
  ok(ref($app->{_helpers}{'auth.register_p'}) eq 'CODE', 'helper code is a coderef');
};

# Test _parse_register_response method
subtest '_parse_register_response' => sub {
  # Success case
  my $response = 'An email containing nickname activation instructions has been sent to your@email.com.';
  my $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'success', 'success response parsed correctly');

  # Nick already in use
  $response = 'The nickname TestUser is already registered.';
  $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'nick_in_use', 'nick_in_use response parsed correctly');

  # Bad email
  $response = 'The email address is not allowed.';
  $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'bad_email', 'bad_email response parsed correctly');

  # Invalid email alternative
  $response = 'Invalid email address provided.';
  $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'bad_email', 'invalid email response parsed correctly');

  # Rate limit
  $response = 'Too many accounts registered from your host. Please try again later.';
  $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'rate_limit', 'rate_limit response parsed correctly');

  # Unknown response
  $response = 'Something completely unexpected happened.';
  $result = $plugin->_parse_register_response($response);
  is($result->{status}, 'unknown', 'unknown response returns unknown status');
  ok(exists $result->{message}, 'unknown response includes message');
};

# Test _parse_verify_response method
subtest '_parse_verify_response' => sub {
  # Success case
  my $response = 'Your account has been verified. Registration complete!';
  my $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'success', 'success response parsed correctly');

  # Success alternative
  $response = 'The account registration has been verified.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'success', 'registration complete response parsed correctly');

  # Bad code
  $response = 'Invalid verification key provided.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'bad_code', 'bad_code response parsed correctly');

  # Bad code alternative
  $response = 'The verification code is incorrect.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'bad_code', 'incorrect code response parsed correctly');

  # Expired
  $response = 'No registration pending for this nickname.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'expired', 'expired response parsed correctly');

  # Expired alternative
  $response = 'This nick is not awaiting verification.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'expired', 'not awaiting response parsed correctly');

  # Nick already taken
  $response = 'This nickname is already registered to another user.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'nick_taken', 'nick_taken response parsed correctly');

  # Unknown response
  $response = 'Something completely unexpected happened.';
  $result = $plugin->_parse_verify_response($response);
  is($result->{status}, 'unknown', 'unknown response returns unknown status');
  ok(exists $result->{message}, 'unknown response includes message');
};

# Test _register_p input validation
subtest '_register_p input validation' => sub {
  plan tests => 9;

  # Mock controller and app
  my $app = Test::MockApp->new;
  my $c = Test::MockController->new(app => $app);

  # Missing username
  my $err;
  $plugin->_register_p($c, {password => 'pass123', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/username.*required/i, 'dies when username missing');

  # Empty username
  $err = undef;
  $plugin->_register_p($c, {username => '', password => 'pass123', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/username.*required/i, 'dies when username empty');

  # Whitespace-only username
  $err = undef;
  $plugin->_register_p($c, {username => '   ', password => 'pass123', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/username.*required/i, 'dies when username is whitespace');

  # Missing password
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/password.*required/i, 'dies when password missing');

  # Empty password
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', password => '', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/password.*required/i, 'dies when password empty');

  # Missing email
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', password => 'pass123'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/email.*required/i, 'dies when email missing');

  # Empty email
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', password => 'pass123', email => ''})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/email.*required/i, 'dies when email empty');

  # Invalid email format
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', password => 'pass123', email => 'notanemail'})
    ->catch(sub { $err = shift })->wait;
  like($err, qr/email.*invalid/i, 'dies when email format invalid');

  # Valid inputs should fail on IRC connection (we're not testing that here)
  $err = undef;
  $plugin->_register_p($c, {username => 'testuser', password => 'pass123', email => 'test@example.com'})
    ->catch(sub { $err = shift })->wait;
  # Should get past validation and fail on IRC connection
  ok($err !~ /required|invalid/i, 'valid inputs pass validation');
};

# Test _verify_p input validation
subtest '_verify_p input validation' => sub {
  plan tests => 3;

  # Mock controller and app
  my $app = Test::MockApp->new;
  my $c = Test::MockController->new(app => $app);

  # Missing code
  my $err;
  $c->req->json({});
  $plugin->_verify_p($c)
    ->catch(sub { $err = shift })->wait;
  like($err, qr/verification code.*required/i, 'dies when code missing');

  # Empty code
  $err = undef;
  $c->req->json({code => ''});
  $plugin->_verify_p($c)
    ->catch(sub { $err = shift })->wait;
  like($err, qr/verification code.*required/i, 'dies when code empty');

  # Whitespace-only code
  $err = undef;
  $c->req->json({code => '   '});
  $plugin->_verify_p($c)
    ->catch(sub { $err = shift })->wait;
  like($err, qr/verification code.*required/i, 'dies when code is whitespace');
};

# Test _verify_p pending registration lookup
subtest '_verify_p pending registration lookup' => sub {
  plan tests => 1;

  # Mock controller and app
  my $app = Test::MockApp->new;
  my $c = Test::MockController->new(app => $app);

  # Valid code but no pending registration (will fail to load from backend)
  my $err;
  $c->req->json({code => 'ABC123'});
  $plugin->_verify_p($c)
    ->catch(sub { $err = shift })->wait;
  # Should fail when trying to load pending registration
  ok($err, 'dies when pending registration not found');
};

# Integration tests - require running IRC server
SKIP: {
  skip 'Set TEST_IRC=1 to run IRC integration tests', 5 unless $ENV{TEST_IRC};

  # These tests would require a running IRC server
  # TODO: Add integration tests with Docker Atheme

  pass('placeholder for IRC connection test');
  pass('placeholder for nick-in-use test');
  pass('placeholder for NickServ command test');
  pass('placeholder for NickServ response test');
  pass('placeholder for timeout test');
}

done_testing;
