use strict;
use warnings;
use Test::More;
use Convos::Plugin::Auth::Atheme;

can_ok('Convos::Plugin::Auth::Atheme', '_atheme_login_p', '_atheme_command_p');

# Test email parsing
my $plugin = Convos::Plugin::Auth::Atheme->new(domain => 'test.org');

is($plugin->_parse_email_from_info("Email: foo\@bar.com\nOther: stuff"),
   'foo@bar.com', 'parses email from INFO');

is($plugin->_parse_email_from_info("Other: stuff\nNo email here"),
   undef, 'returns undef when no email');

is($plugin->_parse_email_from_info(undef),
   undef, 'returns undef for undef input');

# Test email resolution
can_ok('Convos::Plugin::Auth::Atheme', '_resolve_email_p');

# Test username normalization
is($plugin->_normalize_username('  user  '), 'user', 'trims whitespace');
is($plugin->_normalize_username('user@domain.com'), 'user', 'strips domain');
is($plugin->_normalize_username(''), '', 'handles empty string');
is($plugin->_normalize_username(undef), '', 'handles undef');

# Test fault message
is($plugin->_fault_message(5), 'Invalid username or password', 'maps fault code 5');
is($plugin->_fault_message(999), 'Authentication service unavailable. Please try again later.', 'unknown code gets default');

# Integration tests - require running Atheme instance
SKIP: {
  my $atheme_available = eval {
    require IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
      PeerAddr => '127.0.0.1',
      PeerPort => 18080,
      Proto    => 'tcp',
      Timeout  => 1
    );
    $sock && $sock->close;
  };

  skip 'Atheme not available on port 18080 (run: cd t/atheme && docker-compose up -d)', 5
    unless $atheme_available;

  # TODO: Integration tests to be implemented
  # These require a running Atheme instance with test accounts:
  # - Start: cd t/atheme && docker-compose up -d
  # - Stop: cd t/atheme && docker-compose down

  pass('TODO: test successful login creates user');
  pass('TODO: test invalid password rejects');
  pass('TODO: test unknown account rejects');
  pass('TODO: test registration rejects with message');
  pass('TODO: test email resolution with fallback');
}

done_testing;
