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

# Test _s3_list_p
subtest '_s3_list_p' => sub {
  my $xml_response = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Contents>
    <Key>users/joe@example.com/user.json</Key>
  </Contents>
  <Contents>
    <Key>users/jane@example.com/user.json</Key>
  </Contents>
  <CommonPrefixes>
    <Prefix>users/joe@example.com/</Prefix>
  </CommonPrefixes>
  <CommonPrefixes>
    <Prefix>users/jane@example.com/</Prefix>
  </CommonPrefixes>
</ListBucketResult>
XML

  # Mock successful LIST request
  $MockUserAgent::MOCK_RESPONSE = MockResponse->new(
    code => 200,
    body => $xml_response
  );
  @MockUserAgent::REQUESTS = ();

  $backend->{ua} = MockUserAgent->new;

  my $result;
  $backend->_s3_list_p('users/', '/')->then(sub {
    $result = shift;
  })->$wait_success('_s3_list_p');

  is scalar(@{$result->{keys}}), 2, 'found 2 keys';
  is scalar(@{$result->{prefixes}}), 2, 'found 2 prefixes';
  is $result->{keys}[0], 'users/joe@example.com/user.json', 'first key correct';
  is $result->{prefixes}[0], 'users/joe@example.com/', 'first prefix correct';
  like $MockUserAgent::REQUESTS[0]{url}, qr{\?prefix=users/&delimiter=/}, 'URL has query params';
};

# Test users_p
subtest 'users_p' => sub {
  # Mock LIST response showing two user directories
  my $list_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <CommonPrefixes>
    <Prefix>users/joe@example.com/</Prefix>
  </CommonPrefixes>
  <CommonPrefixes>
    <Prefix>users/jane@example.com/</Prefix>
  </CommonPrefixes>
</ListBucketResult>
XML

  # Mock GET responses for each user.json file
  my %user_data = (
    'users/joe@example.com/user.json' => encode_json({
      email => 'joe@example.com',
      registered => '2023-01-01T00:00:00Z',
    }),
    'users/jane@example.com/user.json' => encode_json({
      email => 'jane@example.com',
      registered => '2023-01-02T00:00:00Z',
    }),
  );

  # Create a more sophisticated mock that returns different responses
  my $call_count = 0;
  my $mock_ua = MockUserAgent->new;
  $mock_ua->{_get_p_handler} = sub {
    my ($self, $url, $headers) = @_;
    push @MockUserAgent::REQUESTS, {method => 'GET', url => $url, headers => $headers};

    if ($call_count++ == 0) {
      # First call is LIST
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 200, body => $list_xml))
      );
    } else {
      # Subsequent calls are GET for user.json files
      for my $key (keys %user_data) {
        if ($url =~ /\Q$key\E$/) {
          return Mojo::Promise->resolve(
            MockTransaction->new(res => MockResponse->new(code => 200, body => $user_data{$key}))
          );
        }
      }
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 404))
      );
    }
  };

  no warnings 'redefine';
  local *MockUserAgent::get_p = sub {
    shift->{_get_p_handler}->(@_);
  };
  use warnings;

  @MockUserAgent::REQUESTS = ();
  $backend->{ua} = $mock_ua;
  $call_count = 0;

  my $users;
  $backend->users_p->then(sub {
    $users = shift;
  })->$wait_success('users_p');

  is scalar(@$users), 2, 'found 2 users';
  is $users->[0]{email}, 'joe@example.com', 'first user is joe';
  is $users->[1]{email}, 'jane@example.com', 'second user is jane';
};

# Test connections_p
subtest 'connections_p' => sub {
  # Create a mock user object
  my $user = TestObject->new(email => 'joe@example.com');
  $user->{_uri} = Mojo::Path->new('joe@example.com');
  no warnings 'redefine';
  local *TestObject::uri = sub { shift->{_uri} };
  use warnings;

  # Mock LIST response showing two connection directories
  my $list_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <CommonPrefixes>
    <Prefix>users/joe@example.com/irc-libera/</Prefix>
  </CommonPrefixes>
  <CommonPrefixes>
    <Prefix>users/joe@example.com/irc-freenode/</Prefix>
  </CommonPrefixes>
</ListBucketResult>
XML

  # Mock GET responses for each connection.json file
  my %connection_data = (
    'users/joe@example.com/irc-libera/connection.json' => encode_json({
      connection_id => 'irc-libera',
      name => 'Libera Chat',
    }),
    'users/joe@example.com/irc-freenode/connection.json' => encode_json({
      connection_id => 'irc-freenode',
      name => 'Freenode',
    }),
  );

  my $call_count = 0;
  my $mock_ua = MockUserAgent->new;
  $mock_ua->{_get_p_handler} = sub {
    my ($self, $url, $headers) = @_;
    push @MockUserAgent::REQUESTS, {method => 'GET', url => $url, headers => $headers};

    if ($call_count++ == 0) {
      # First call is LIST
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 200, body => $list_xml))
      );
    } else {
      # Subsequent calls are GET for connection.json files
      for my $key (keys %connection_data) {
        if ($url =~ /\Q$key\E$/) {
          return Mojo::Promise->resolve(
            MockTransaction->new(res => MockResponse->new(code => 200, body => $connection_data{$key}))
          );
        }
      }
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 404))
      );
    }
  };

  no warnings 'redefine';
  local *MockUserAgent::get_p = sub {
    shift->{_get_p_handler}->(@_);
  };
  use warnings;

  @MockUserAgent::REQUESTS = ();
  $backend->{ua} = $mock_ua;
  $call_count = 0;

  my $connections;
  $backend->connections_p($user)->then(sub {
    $connections = shift;
  })->$wait_success('connections_p');

  is scalar(@$connections), 2, 'found 2 connections';
  is $connections->[0]{connection_id}, 'irc-libera', 'first connection is libera';
  is $connections->[1]{connection_id}, 'irc-freenode', 'second connection is freenode';
};

# Test files_p
subtest 'files_p' => sub {
  # Create a mock user object with email
  my $user = TestObject->new(email => 'joe@example.com');

  # Mock LIST response showing upload files
  my $list_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Contents>
    <Key>users/joe@example.com/upload/abc123.json</Key>
  </Contents>
  <Contents>
    <Key>users/joe@example.com/upload/abc123.data</Key>
  </Contents>
  <Contents>
    <Key>users/joe@example.com/upload/def456.json</Key>
  </Contents>
  <Contents>
    <Key>users/joe@example.com/upload/def456.data</Key>
  </Contents>
  <Contents>
    <Key>users/joe@example.com/upload/orphan.json</Key>
  </Contents>
</ListBucketResult>
XML

  # Mock GET responses for each metadata JSON file
  my %file_data = (
    'users/joe@example.com/upload/abc123.json' => encode_json({
      filename => 'photo.jpg',
      saved    => '2023-01-02T00:00:00Z',
      size     => 1024,
    }),
    'users/joe@example.com/upload/def456.json' => encode_json({
      filename => 'document.pdf',
      saved    => '2023-01-01T00:00:00Z',
      size     => 2048,
    }),
  );

  my $call_count = 0;
  my $mock_ua = MockUserAgent->new;
  $mock_ua->{_get_p_handler} = sub {
    my ($self, $url, $headers) = @_;
    push @MockUserAgent::REQUESTS, {method => 'GET', url => $url, headers => $headers};

    if ($call_count++ == 0) {
      # First call is LIST
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 200, body => $list_xml))
      );
    } else {
      # Subsequent calls are GET for file metadata
      for my $key (keys %file_data) {
        if ($url =~ /\Q$key\E$/) {
          return Mojo::Promise->resolve(
            MockTransaction->new(res => MockResponse->new(code => 200, body => $file_data{$key}))
          );
        }
      }
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 404))
      );
    }
  };

  no warnings 'redefine';
  local *MockUserAgent::get_p = sub {
    shift->{_get_p_handler}->(@_);
  };
  use warnings;

  @MockUserAgent::REQUESTS = ();
  $backend->{ua} = $mock_ua;
  $call_count = 0;

  my $result;
  $backend->files_p($user, {})->then(sub {
    $result = shift;
  })->$wait_success('files_p');

  isa_ok $result->{files}, 'Mojo::Collection', 'files is a Mojo::Collection';
  is $result->{files}->size, 2, 'found 2 files (orphan.json excluded - no .data file)';

  # Files should be sorted by saved date descending
  is $result->{files}[0]{id}, 'abc123', 'first file is abc123 (newer)';
  is $result->{files}[0]{name}, 'photo.jpg', 'first file name is photo.jpg';
  is $result->{files}[1]{id}, 'def456', 'second file is def456 (older)';
  is $result->{files}[1]{name}, 'document.pdf', 'second file name is document.pdf';
};

# Test files_p with pagination
subtest 'files_p with pagination' => sub {
  my $user = TestObject->new(email => 'joe@example.com');

  # Mock LIST response with many files for pagination testing
  my @keys;
  for my $i (1..5) {
    push @keys, sprintf '<Key>users/joe@example.com/upload/file%03d.json</Key>', $i;
    push @keys, sprintf '<Key>users/joe@example.com/upload/file%03d.data</Key>', $i;
  }
  my $list_xml = <<XML;
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Contents>
    @{[join "\n  </Contents>\n  <Contents>\n    ", @keys]}
  </Contents>
</ListBucketResult>
XML

  # Create mock metadata for each file
  my %file_data;
  for my $i (1..5) {
    my $key = sprintf 'users/joe@example.com/upload/file%03d.json', $i;
    $file_data{$key} = encode_json({
      filename => sprintf('file%03d.txt', $i),
      saved    => sprintf('2023-01-%02dT00:00:00Z', 6 - $i),  # file001 is newest
      size     => $i * 100,
    });
  }

  my $call_count = 0;
  my $mock_ua = MockUserAgent->new;
  $mock_ua->{_get_p_handler} = sub {
    my ($self, $url, $headers) = @_;
    push @MockUserAgent::REQUESTS, {method => 'GET', url => $url, headers => $headers};

    if ($call_count++ == 0) {
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 200, body => $list_xml))
      );
    } else {
      for my $key (keys %file_data) {
        if ($url =~ /\Q$key\E$/) {
          return Mojo::Promise->resolve(
            MockTransaction->new(res => MockResponse->new(code => 200, body => $file_data{$key}))
          );
        }
      }
      return Mojo::Promise->resolve(
        MockTransaction->new(res => MockResponse->new(code => 404))
      );
    }
  };

  no warnings 'redefine';
  local *MockUserAgent::get_p = sub {
    shift->{_get_p_handler}->(@_);
  };
  use warnings;

  @MockUserAgent::REQUESTS = ();
  $backend->{ua} = $mock_ua;
  $call_count = 0;

  my $result;
  $backend->files_p($user, {limit => 2})->then(sub {
    $result = shift;
  })->$wait_success('files_p with limit');

  is $result->{files}->size, 2, 'limited to 2 files';
  is $result->{files}[0]{id}, 'file001', 'first file is file001 (newest)';
  ok $result->{next}, 'has next page indicator';
};

done_testing;
