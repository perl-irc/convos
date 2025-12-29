# ABOUTME: S3-compatible storage backend for Convos
# ABOUTME: Extends File backend to store objects in S3/Tigris while keeping logs local
package Convos::Core::Backend::S3;
use Mojo::Base 'Convos::Core::Backend::File', -async_await;

use Convos::Util::S3 qw(sign_request);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent;
use Mojo::URL;

has s3_endpoint => sub { $ENV{CONVOS_S3_ENDPOINT} || 'https://fly.storage.tigris.dev' };
has s3_bucket   => sub { $ENV{CONVOS_S3_BUCKET}   || die 'CONVOS_S3_BUCKET required' };
has s3_key      => sub { $ENV{CONVOS_S3_KEY}      || die 'CONVOS_S3_KEY required' };
has s3_secret   => sub { $ENV{CONVOS_S3_SECRET}   || die 'CONVOS_S3_SECRET required' };
has s3_region   => sub { $ENV{CONVOS_S3_REGION}   || 'auto' };
has ua          => sub { Mojo::UserAgent->new };

async sub save_object_p {
  my ($self, $obj) = @_;
  my $key     = $self->_s3_key($obj);
  my $content = encode_json($obj->TO_JSON('private'));

  await $self->_s3_request_p('PUT', $key, $content, 'application/json');
  $obj->logf(debug => 'Save success. (s3://%s/%s)', $self->s3_bucket, $key);

  return $obj;
}

async sub load_object_p {
  my ($self, $obj) = @_;
  my $key = $self->_s3_key($obj);

  my $res = await $self->_s3_request_p('GET', $key);

  # Return empty hash on 404 (object doesn't exist yet)
  return {} unless $res->is_success;

  my $data = {};
  eval { $data = decode_json($res->body); };
  return Mojo::Promise->reject($@ || 'Invalid JSON from S3') unless $data;

  return $data;
}

async sub delete_object_p {
  my ($self, $obj) = @_;

  if ($obj->isa('Convos::Core::Connection')) {
    $obj->unsubscribe($_) for qw(conversation message state);
  }

  my $key = $self->_s3_key($obj);
  await $self->_s3_request_p('DELETE', $key);

  return $obj;
}

sub _s3_key {
  my ($self, $obj) = @_;
  my $path = $obj->uri->to_string;

  # Prefix user-related objects with 'users/' for organization
  return "users/$path";
}

async sub _s3_request_p {
  my ($self, $method, $key, $body, $content_type) = @_;
  $body         //= '';
  $content_type //= 'application/octet-stream';

  my $url = sprintf '%s/%s/%s', $self->s3_endpoint, $self->s3_bucket, $key;

  # Generate AWS4 signature
  my $headers = sign_request(
    method  => $method,
    url     => $url,
    headers => {'Content-Type' => $content_type},
    payload => $body,
    key     => $self->s3_key,
    secret  => $self->s3_secret,
    region  => $self->s3_region,
  );

  # Add Content-Type to final headers
  $headers->{'Content-Type'} = $content_type;

  # Execute request based on method
  my $tx;
  if ($method eq 'GET') {
    $tx = await $self->ua->get_p($url => $headers);
  }
  elsif ($method eq 'PUT') {
    $tx = await $self->ua->put_p($url => $headers => $body);
  }
  elsif ($method eq 'DELETE') {
    $tx = await $self->ua->delete_p($url => $headers);
  }
  else {
    die "Unsupported HTTP method: $method";
  }

  my $res = $tx->res;

  # Return response for caller to check status
  return $res;
}

1;

=encoding utf8

=head1 NAME

Convos::Core::Backend::S3 - S3-compatible storage backend

=head1 SYNOPSIS

  use Convos::Core::Backend::S3;

  my $backend = Convos::Core::Backend::S3->new(
    s3_endpoint => 'https://fly.storage.tigris.dev',
    s3_bucket   => 'my-bucket',
    s3_key      => $access_key,
    s3_secret   => $secret_key,
    s3_region   => 'auto',
    home        => '/path/to/local/logs',
  );

=head1 DESCRIPTION

L<Convos::Core::Backend::S3> is a storage backend that stores objects
(users, connections, settings) in S3-compatible storage while keeping
message logs and notifications on the local filesystem.

This is useful for deploying Convos in environments like Fly.io where
you want persistent object storage without maintaining local volumes,
but still want fast local access to message logs.

=head2 Environment Variables

=over 4

=item * CONVOS_S3_ENDPOINT - S3 endpoint URL (default: https://fly.storage.tigris.dev)

=item * CONVOS_S3_BUCKET - S3 bucket name (required)

=item * CONVOS_S3_KEY - AWS access key ID (required)

=item * CONVOS_S3_SECRET - AWS secret access key (required)

=item * CONVOS_S3_REGION - AWS region or 'auto' for Tigris (default: auto)

=back

=head1 ATTRIBUTES

L<Convos::Core::Backend::S3> inherits all attributes from
L<Convos::Core::Backend::File> and implements the following new ones.

=head2 s3_endpoint

S3-compatible endpoint URL.

=head2 s3_bucket

S3 bucket name for object storage.

=head2 s3_key

AWS access key ID.

=head2 s3_secret

AWS secret access key.

=head2 s3_region

AWS region identifier or 'auto' for Tigris.

=head2 ua

L<Mojo::UserAgent> instance for HTTP requests.

=head1 METHODS

L<Convos::Core::Backend::S3> inherits all methods from
L<Convos::Core::Backend::File> and implements the following new ones.

=head2 save_object_p

  $p = $backend->save_object_p($obj);

Saves object to S3 as JSON. Returns a promise that resolves to C<$obj>.

=head2 load_object_p

  $p = $backend->load_object_p($obj);

Loads object data from S3. Returns a promise that resolves to a hashref
of object data, or an empty hashref if the object doesn't exist (404).

=head2 delete_object_p

  $p = $backend->delete_object_p($obj);

Deletes object from S3. Returns a promise that resolves to C<$obj>.

=head1 SEE ALSO

L<Convos::Core::Backend::File>, L<Convos::Util::S3>.

=cut
