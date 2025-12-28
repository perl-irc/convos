#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN { use_ok('Convos::Plugin::Auth::Atheme::Registration') };

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
