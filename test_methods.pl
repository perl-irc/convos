#!/usr/bin/env perl
use strict;
use warnings;
use lib '/Users/perigrin/dev/convos/.worktrees/atheme-auth/lib';

print "Loading module...\n";
use Convos::Plugin::Auth::Atheme;

print "INC: $INC{'Convos/Plugin/Auth/Atheme.pm'}\n";

print "Module loaded\n";

my $obj = Convos::Plugin::Auth::Atheme->new;
print "Object created: ", ref($obj), "\n";

print "\nChecking methods:\n";
for my $method (qw/register _login_p _register_p _atheme_login_p _atheme_command_p/) {
    my $can = $obj->can($method);
    printf "  %-20s: %s\n", $method, ($can ? "YES" : "NO");
}

print "\nSymbol table:\n";
{
    no strict 'refs';
    for my $sym (sort keys %Convos::Plugin::Auth::Atheme::) {
        next unless defined &{"Convos::Plugin::Auth::Atheme::$sym"};
        print "  $sym\n";
    }
}
