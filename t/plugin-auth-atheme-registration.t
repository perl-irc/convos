use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojo::URL;

plan skip_all => 'TEST_IRC=1' unless $ENV{TEST_IRC};

use_ok 'Convos::Plugin::Auth::Atheme::Registration';

# Test _ephemeral_irc_p connects successfully
subtest '_ephemeral_irc_p connects' => sub {
  plan skip_all => 'Requires IRC server';

  my $plugin = Convos::Plugin::Auth::Atheme::Registration->new(
    irc_url => Mojo::URL->new('irc://localhost:6667'),
    timeout => 5,
  );

  my ($irc, $err);
  eval {
    $irc = $plugin->_ephemeral_irc_p('testnick')->wait;
  } or do {
    $err = $@;
  };

  ok !$err, 'no error on connect' or diag $err;
  ok $irc, 'got IRC connection object';
};

# Test _ephemeral_irc_p rejects on nick-in-use
subtest '_ephemeral_irc_p nick-in-use' => sub {
  plan skip_all => 'Requires IRC server with nick collision setup';

  my $plugin = Convos::Plugin::Auth::Atheme::Registration->new(
    irc_url => Mojo::URL->new('irc://localhost:6667'),
    timeout => 5,
  );

  my $err;
  eval {
    $plugin->_ephemeral_irc_p('NickServ')->wait;
  } or do {
    $err = $@;
  };

  ok $err, 'got error on nick-in-use';
  like $err, qr/nick.*in use|already in use/i, 'error indicates nick collision';
};

# Test _send_nickserv_p sends command and collects response
subtest '_send_nickserv_p' => sub {
  plan skip_all => 'Requires IRC server';

  my $plugin = Convos::Plugin::Auth::Atheme::Registration->new(
    irc_url => Mojo::URL->new('irc://localhost:6667'),
    timeout => 5,
  );

  my ($irc, $response, $err);
  eval {
    $irc = $plugin->_ephemeral_irc_p('testbot')->wait;
    $response = $plugin->_send_nickserv_p($irc, 'HELP')->wait;
  } or do {
    $err = $@;
  };

  ok !$err, 'no error sending to NickServ' or diag $err;
  ok $response, 'got response from NickServ';
  like $response, qr/help|command/i, 'response looks like help text';
};

done_testing;
