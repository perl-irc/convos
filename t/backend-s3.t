#!perl
use lib '.';
use t::Helper;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;

t::Helper->subprocess_in_main_process;

# Mock UserAgent to avoid real HTTP calls
{
  package MockUserAgent;
  use Mojo::Base 'Mojo::UserAgent';

  our $MOCK_RESPONSE;
  our @REQUESTS;

  sub get_p {
    my ($self, $url, $headers) = @_;
    push @REQUESTS, {method => 'GET', url => $url, headers => $headers};
    return Mojo::Promise->resolve(MockTransaction->new(res => $MOCK_RESPONSE));
  }

  sub put_p {
    my ($self, $url, $headers, $body) = @_;
    push @REQUESTS, {method => 'PUT', url => $url, headers => $headers, body => $body};
    return Mojo::Promise->resolve(MockTransaction->new(res => $MOCK_RESPONSE));
  }

  sub delete_p {
    my ($self, $url, $headers) = @_;
    push @REQUESTS, {method => 'DELETE', url => $url, headers => $headers};
    return Mojo::Promise->resolve(MockTransaction->new(res => $MOCK_RESPONSE));
  }
}

{
  package MockTransaction;
  use Mojo::Base -base;
  has 'res';
}

{
  package MockResponse;
  use Mojo::Base -base;
  has 'code';
  has 'body' => '';

  sub is_success { shift->code >= 200 && shift->code < 300 }
}

# Mock the object with uri() method
{
  package TestObject;
  use Mojo::Base -base;
  has 'email' => 'test@example.com';

  sub uri { Mojo::Path->new('test@example.com/user.json') }
  sub TO_JSON { {email => shift->email} }
  sub logf { }
  sub isa {
    my ($self, $class) = @_;
    return 1 if $class eq 'Convos::Core::Connection';
    return $self->SUPER::isa($class);
  }
  sub unsubscribe { }
}

use_ok 'Convos::Core::Backend::S3';

# Create backend with test credentials
my $backend = Convos::Core::Backend::S3->new(
  s3_endpoint => 'https://fly.storage.tigris.dev',
  s3_bucket   => 'test-bucket',
  s3_key      => 'test-key',
  s3_secret   => 'test-secret',
  s3_region   => 'auto',
  home        => Mojo::File->new($ENV{CONVOS_HOME}),
);

isa_ok $backend, 'Convos::Core::Backend::S3';
isa_ok $backend, 'Convos::Core::Backend::File';

# Test _s3_key mapping
is $backend->_s3_key(TestObject->new), 'users/test@example.com/user.json',
  '_s3_key prefixes user objects with users/';

# Test save_object_p
subtest 'save_object_p' => sub {
  my $obj = TestObject->new;

  # Mock successful PUT
  $MockUserAgent::MOCK_RESPONSE = MockResponse->new(code => 200);
  @MockUserAgent::REQUESTS = ();

  # Override ua to use mock
  $backend->{ua} = MockUserAgent->new;

  my $result;
  $backend->save_object_p($obj)->then(sub {
    $result = shift;
  })->$wait_success('save_object_p');

  is $result->email, 'test@example.com', 'save_object_p returns object';
  is scalar(@MockUserAgent::REQUESTS), 1, 'made one request';
  is $MockUserAgent::REQUESTS[0]{method}, 'PUT', 'used PUT method';
  like $MockUserAgent::REQUESTS[0]{url}, qr{/test-bucket/users/}, 'URL contains bucket and users prefix';
};

# Test load_object_p
subtest 'load_object_p with data' => sub {
  my $obj = TestObject->new;

  # Mock successful GET with JSON body
  $MockUserAgent::MOCK_RESPONSE = MockResponse->new(
    code => 200,
    body => encode_json({email => 'loaded@example.com'})
  );
  @MockUserAgent::REQUESTS = ();

  $backend->{ua} = MockUserAgent->new;

  my $data;
  $backend->load_object_p($obj)->then(sub {
    $data = shift;
  })->$wait_success('load_object_p');

  is $data->{email}, 'loaded@example.com', 'load_object_p returns decoded data';
  is $MockUserAgent::REQUESTS[0]{method}, 'GET', 'used GET method';
};

subtest 'load_object_p on 404' => sub {
  my $obj = TestObject->new;

  # Mock 404 response
  $MockUserAgent::MOCK_RESPONSE = MockResponse->new(code => 404);
  @MockUserAgent::REQUESTS = ();

  $backend->{ua} = MockUserAgent->new;

  my $data;
  $backend->load_object_p($obj)->then(sub {
    $data = shift;
  })->$wait_success('load_object_p 404');

  is_deeply $data, {}, 'load_object_p returns {} on 404';
};

# Test delete_object_p
subtest 'delete_object_p' => sub {
  my $obj = TestObject->new;

  # Mock successful DELETE
  $MockUserAgent::MOCK_RESPONSE = MockResponse->new(code => 204);
  @MockUserAgent::REQUESTS = ();

  $backend->{ua} = MockUserAgent->new;

  my $result;
  $backend->delete_object_p($obj)->then(sub {
    $result = shift;
  })->$wait_success('delete_object_p');

  is $result->email, 'test@example.com', 'delete_object_p returns object';
  is $MockUserAgent::REQUESTS[0]{method}, 'DELETE', 'used DELETE method';
};

done_testing;
