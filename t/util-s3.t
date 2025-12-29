use Mojo::Base -strict;
use Test::More;
use Convos::Util::S3 qw(sign_request);

subtest 'sign GET request' => sub {
  my $signed = sign_request(
    method  => 'GET',
    url     => 'https://bucket.s3.amazonaws.com/test.txt',
    headers => {'Host' => 'bucket.s3.amazonaws.com'},
    payload => '',
    key     => 'AKIAIOSFODNN7EXAMPLE',
    secret  => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region  => 'us-east-1',
    date    => '20130524T000000Z',  # Fixed date for testing
  );

  ok $signed, 'got signed headers';
  ok $signed->{Authorization}, 'has Authorization header';
  like $signed->{Authorization}, qr/^AWS4-HMAC-SHA256/, 'Authorization starts with AWS4-HMAC-SHA256';
  like $signed->{Authorization}, qr/Credential=AKIAIOSFODNN7EXAMPLE/, 'Authorization contains credential';
  like $signed->{Authorization}, qr/SignedHeaders=/, 'Authorization contains SignedHeaders';
  like $signed->{Authorization}, qr/Signature=/, 'Authorization contains Signature';
  ok $signed->{'x-amz-date'}, 'has x-amz-date header';
  ok $signed->{'x-amz-content-sha256'}, 'has x-amz-content-sha256 header';
};

subtest 'sign PUT request with JSON body' => sub {
  my $payload = '{"test":"data"}';
  my $signed = sign_request(
    method  => 'PUT',
    url     => 'https://bucket.s3.amazonaws.com/test.json',
    headers => {
      'Host'         => 'bucket.s3.amazonaws.com',
      'Content-Type' => 'application/json',
    },
    payload => $payload,
    key     => 'AKIAIOSFODNN7EXAMPLE',
    secret  => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region  => 'us-east-1',
    date    => '20130524T000000Z',
  );

  ok $signed, 'got signed headers';
  ok $signed->{Authorization}, 'has Authorization header';
  like $signed->{Authorization}, qr/^AWS4-HMAC-SHA256/, 'Authorization starts with AWS4-HMAC-SHA256';
  like $signed->{Authorization}, qr/SignedHeaders=/, 'Authorization contains SignedHeaders';
  like $signed->{Authorization}, qr/SignedHeaders=Content-Type;/, 'SignedHeaders includes Content-Type';
  ok $signed->{'x-amz-content-sha256'}, 'has x-amz-content-sha256 header';
  isnt $signed->{'x-amz-content-sha256'}, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'payload hash is not empty string hash';
};

subtest 'sign request with query parameters' => sub {
  my $signed = sign_request(
    method  => 'GET',
    url     => 'https://bucket.s3.amazonaws.com/test.txt?max-keys=100&prefix=photos/',
    headers => {'Host' => 'bucket.s3.amazonaws.com'},
    payload => '',
    key     => 'AKIAIOSFODNN7EXAMPLE',
    secret  => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region  => 'us-east-1',
    date    => '20130524T000000Z',
  );

  ok $signed, 'got signed headers';
  ok $signed->{Authorization}, 'has Authorization header';
  like $signed->{Authorization}, qr/^AWS4-HMAC-SHA256/, 'Authorization starts with AWS4-HMAC-SHA256';
  ok $signed->{'x-amz-date'}, 'has x-amz-date header';
  ok $signed->{'x-amz-content-sha256'}, 'has x-amz-content-sha256 header';
};

done_testing;
