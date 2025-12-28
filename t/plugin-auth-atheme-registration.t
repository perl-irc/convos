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
