use strict;
use warnings;
use Test::More;

BEGIN { use_ok('Convos::Plugin::Auth::Atheme') };

can_ok('Convos::Plugin::Auth::Atheme', '_atheme_login_p');
can_ok('Convos::Plugin::Auth::Atheme', '_atheme_command_p');

done_testing;
