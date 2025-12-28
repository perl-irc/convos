use strict;
use warnings;
use Test::More;
use Convos::Plugin::Auth::Atheme;

can_ok('Convos::Plugin::Auth::Atheme', '_atheme_login_p', '_atheme_command_p');

done_testing;
