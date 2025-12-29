#!/usr/bin/env perl
use lib '.';
use t::Helper;
use Convos::Core;
use Convos::Plugin::Auth::Atheme::PendingRegistration;

t::Helper->subprocess_in_main_process;

my $core = Convos::Core->new(backend => 'Convos::Core::Backend::File');
my $backend = $core->backend;

subtest 'new with required attributes' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'test-session-123',
    nick       => 'testuser',
    email      => 'test@example.com',
  );

  is $pr->core, $core, 'core attribute set';
  is $pr->session_id, 'test-session-123', 'session_id attribute set';
  is $pr->nick, 'testuser', 'nick attribute set';
  is $pr->email, 'test@example.com', 'email attribute set';
  ok $pr->created_at, 'created_at auto-generated';
  ok $pr->expires_at, 'expires_at auto-generated';
  ok $pr->expires_at->epoch > $pr->created_at->epoch, 'expires_at is after created_at';
};

subtest 'uri' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'test-session-123',
    nick       => 'testuser',
    email      => 'test@example.com',
  );

  my $uri = $pr->uri;
  isa_ok $uri, 'Mojo::Path', 'uri returns Mojo::Path';
  is $uri->to_string, 'pending/test-session-123.json', 'uri path is correct';
};

subtest 'TO_JSON' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'test-session-123',
    nick       => 'testuser',
    email      => 'test@example.com',
  );

  my $json = $pr->TO_JSON;
  is ref $json, 'HASH', 'TO_JSON returns hash';
  is $json->{session_id}, 'test-session-123', 'session_id serialized';
  is $json->{nick}, 'testuser', 'nick serialized';
  is $json->{email}, 'test@example.com', 'email serialized';
  ok $json->{created_at}, 'created_at serialized';
  ok $json->{expires_at}, 'expires_at serialized';
  ok !exists $json->{core}, 'core not serialized';
};

subtest 'save_p and load_p' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'test-session-456',
    nick       => 'savetest',
    email      => 'save@example.com',
  );

  my $saved;
  $pr->save_p->then(sub { $saved = shift })->$wait_success('save_p');
  is $saved, $pr, 'save_p returns object';

  my $loaded;
  my $pr2 = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'test-session-456',
    nick       => 'placeholder',
    email      => 'placeholder@example.com',
  );
  $pr2->load_p->then(sub { $loaded = shift })->$wait_success('load_p');
  is $loaded->{session_id}, 'test-session-456', 'loaded session_id';
  is $loaded->{nick}, 'savetest', 'loaded nick';
  is $loaded->{email}, 'save@example.com', 'loaded email';
};

subtest 'load_p with expiration check' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'expired-session',
    nick       => 'expireduser',
    email      => 'expired@example.com',
  );

  # Manually set expiration to the past
  $pr->{expires_at} = Mojo::Date->new(time - 3600);

  my $saved;
  $pr->save_p->then(sub { $saved = shift })->$wait_success('save_p expired');
  is $saved, $pr, 'expired pending registration saved';

  my $pr2 = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'expired-session',
    nick       => 'placeholder',
    email      => 'placeholder@example.com',
  );

  my ($loaded, $err);
  $pr2->load_p->then(sub { $loaded = shift }, sub { $err = shift })->$wait_success('load_p expired');
  ok $err, 'loading expired registration fails';
  like $err, qr/expired/i, 'error mentions expiration';
};

subtest 'delete_p' => sub {
  my $pr = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'delete-test',
    nick       => 'deleteuser',
    email      => 'delete@example.com',
  );

  my $saved;
  $pr->save_p->then(sub { $saved = shift })->$wait_success('save_p for delete');
  is $saved, $pr, 'saved before delete';

  my $deleted;
  $pr->delete_p->then(sub { $deleted = shift })->$wait_success('delete_p');
  is $deleted, $pr, 'delete_p returns object';

  my $pr2 = Convos::Plugin::Auth::Atheme::PendingRegistration->new(
    core       => $core,
    session_id => 'delete-test',
    nick       => 'placeholder',
    email      => 'placeholder@example.com',
  );

  my ($loaded, $err);
  $pr2->load_p->then(sub { $loaded = shift }, sub { $err = shift })->$wait_success('load_p after delete');
  ok $err, 'loading deleted registration fails';
};

done_testing;
