#!perl
# ABOUTME: Integration tests for S3 backend against real Tigris/S3 endpoint
# ABOUTME: Requires environment variables to be set for S3 credentials

use lib '.';
use t::Helper;
use Mojo::JSON qw(decode_json encode_json);

t::Helper->subprocess_in_main_process;

# Skip all tests unless S3 credentials are provided
plan skip_all => 'Set CONVOS_S3_TEST_BUCKET, CONVOS_S3_KEY, CONVOS_S3_SECRET for integration tests'
  unless $ENV{CONVOS_S3_TEST_BUCKET} && $ENV{CONVOS_S3_KEY} && $ENV{CONVOS_S3_SECRET};

use_ok 'Convos::Core::Backend::S3';
use_ok 'Convos::Core';

# Create a unique test prefix to avoid conflicts with other tests
my $test_prefix = sprintf 'test-%d-%d', $$, time;
diag "Test prefix: $test_prefix";

# Create backend with real credentials
my $backend = Convos::Core::Backend::S3->new(
  s3_endpoint => $ENV{CONVOS_S3_ENDPOINT} || 'https://fly.storage.tigris.dev',
  s3_bucket   => $ENV{CONVOS_S3_TEST_BUCKET},
  s3_key      => $ENV{CONVOS_S3_KEY},
  s3_secret   => $ENV{CONVOS_S3_SECRET},
  s3_region   => $ENV{CONVOS_S3_REGION} || 'auto',
  home        => Mojo::File->new($ENV{CONVOS_HOME}),
);

# Create a core with the S3 backend for testing
my $core = Convos::Core->new(backend => $backend);

# Mock objects for testing
{
  package TestUser;
  use Mojo::Base -base;
  use Mojo::Path;

  has email      => sub { die 'email required' };
  has uid        => sub { shift->email };
  has registered => sub { Mojo::Date->new->to_datetime };

  sub uri { Mojo::Path->new(shift->email . '/user.json') }
  sub TO_JSON {
    my ($self, $persist) = @_;
    return {
      email      => $self->email,
      registered => $self->registered,
    };
  }
  sub logf { }
  sub isa {
    my ($self, $class) = @_;
    return 0 if $class eq 'Convos::Core::Connection';
    return $self->SUPER::isa($class);
  }
}

{
  package TestConnection;
  use Mojo::Base -base;
  use Mojo::Path;

  has id   => sub { die 'id required' };
  has user => sub { die 'user required' };
  has name => 'Test Connection';
  has url  => sub { Mojo::URL->new('irc://irc.example.com') };

  sub uri {
    my $self = shift;
    return Mojo::Path->new($self->user->email . '/' . $self->id . '/connection.json');
  }
  sub TO_JSON {
    my ($self, $persist) = @_;
    return {
      connection_id => $self->id,
      name          => $self->name,
      url           => $self->url->to_string,
    };
  }
  sub logf { }
  sub isa {
    my ($self, $class) = @_;
    return 1 if $class eq 'Convos::Core::Connection';
    return $self->SUPER::isa($class);
  }
  sub unsubscribe { }
}

# Use unique email for each test run
my $test_email = "${test_prefix}\@example.com";

subtest 'save and load user object' => sub {
  my $user = TestUser->new(email => $test_email);

  # Save user
  my $saved;
  $backend->save_object_p($user)->then(sub {
    $saved = shift;
  })->$wait_success('save user');

  is $saved->email, $test_email, 'save_object_p returns user';

  # Load user
  my $loaded;
  $backend->load_object_p($user)->then(sub {
    $loaded = shift;
  })->$wait_success('load user');

  is $loaded->{email}, $test_email, 'loaded email matches';
  ok $loaded->{registered}, 'loaded has registered field';
};

subtest 'list users' => sub {
  # Make sure we have at least one user from previous test
  my $users;
  $backend->users_p->then(sub {
    $users = shift;
  })->$wait_success('list users');

  ok ref($users) eq 'ARRAY', 'users_p returns arrayref';
  my @test_users = grep { $_->{email} && $_->{email} =~ /^\Q$test_prefix\E/ } @$users;
  ok @test_users >= 1, 'found at least one test user';
};

subtest 'save and load connection' => sub {
  my $user = TestUser->new(email => $test_email);
  my $conn = TestConnection->new(
    id   => 'irc-test',
    user => $user,
    name => 'Test IRC',
  );

  # Save connection
  my $saved;
  $backend->save_object_p($conn)->then(sub {
    $saved = shift;
  })->$wait_success('save connection');

  is $saved->id, 'irc-test', 'save_object_p returns connection';

  # Load connection
  my $loaded;
  $backend->load_object_p($conn)->then(sub {
    $loaded = shift;
  })->$wait_success('load connection');

  is $loaded->{connection_id}, 'irc-test', 'loaded connection_id matches';
  is $loaded->{name}, 'Test IRC', 'loaded name matches';
};

subtest 'list connections for user' => sub {
  my $user = TestUser->new(email => $test_email);

  my $connections;
  $backend->connections_p($user)->then(sub {
    $connections = shift;
  })->$wait_success('list connections');

  ok ref($connections) eq 'ARRAY', 'connections_p returns arrayref';
  my @test_conns = grep { $_->{connection_id} && $_->{connection_id} eq 'irc-test' } @$connections;
  is scalar(@test_conns), 1, 'found test connection';
};

subtest 'delete connection' => sub {
  my $user = TestUser->new(email => $test_email);
  my $conn = TestConnection->new(
    id   => 'irc-test',
    user => $user,
  );

  # Delete connection
  my $deleted;
  $backend->delete_object_p($conn)->then(sub {
    $deleted = shift;
  })->$wait_success('delete connection');

  is $deleted->id, 'irc-test', 'delete_object_p returns connection';

  # Verify it's gone
  my $loaded;
  $backend->load_object_p($conn)->then(sub {
    $loaded = shift;
  })->$wait_success('load deleted connection');

  is_deeply $loaded, {}, 'deleted connection returns empty hash';
};

subtest 'delete user' => sub {
  my $user = TestUser->new(email => $test_email);

  # Delete user
  my $deleted;
  $backend->delete_object_p($user)->then(sub {
    $deleted = shift;
  })->$wait_success('delete user');

  is $deleted->email, $test_email, 'delete_object_p returns user';

  # Verify it's gone
  my $loaded;
  $backend->load_object_p($user)->then(sub {
    $loaded = shift;
  })->$wait_success('load deleted user');

  is_deeply $loaded, {}, 'deleted user returns empty hash';
};

subtest 'files_p with empty upload directory' => sub {
  my $user = TestUser->new(email => $test_email);

  my $result;
  $backend->files_p($user, {})->then(sub {
    $result = shift;
  })->$wait_success('list files');

  isa_ok $result->{files}, 'Mojo::Collection', 'files is a Mojo::Collection';
  is $result->{files}->size, 0, 'no files for non-existent user';
};

done_testing;

=encoding utf8

=head1 NAME

t/backend-s3-integration.t - Integration tests for S3 backend

=head1 SYNOPSIS

  # Run with real Tigris credentials
  CONVOS_S3_TEST_BUCKET=my-test-bucket \
  CONVOS_S3_KEY=tid_xxxx \
  CONVOS_S3_SECRET=tsec_xxxx \
  prove -l t/backend-s3-integration.t

=head1 DESCRIPTION

These tests run against a real S3-compatible endpoint (Tigris by default)
to verify the S3 backend works correctly in production-like conditions.

=head2 Required Environment Variables

=over 4

=item * CONVOS_S3_TEST_BUCKET - The S3 bucket to use for testing

=item * CONVOS_S3_KEY - AWS/Tigris access key ID

=item * CONVOS_S3_SECRET - AWS/Tigris secret access key

=back

=head2 Optional Environment Variables

=over 4

=item * CONVOS_S3_ENDPOINT - S3 endpoint URL (default: https://fly.storage.tigris.dev)

=item * CONVOS_S3_REGION - AWS region (default: auto)

=back

=head1 NOTES

Tests create objects with a unique prefix based on PID and timestamp to
avoid conflicts. Objects are cleaned up after tests complete.

=cut
