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

done_testing;
