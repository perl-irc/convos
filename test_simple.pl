#!/usr/bin/env perl
use strict;
use warnings;

package Test::Simple;
use Mojo::Base -base, -async_await;

sub method1 {
    my ($self) = @_;
    return "method1";
}

sub method2 {
    my ($self) = @_;
    return Mojo::Promise->new->resolve("method2");
}

package main;

my $obj = Test::Simple->new;
print "method1: ", ($obj->can("method1") ? "YES" : "NO"), "\n";
print "method2: ", ($obj->can("method2") ? "YES" : "NO"), "\n";
