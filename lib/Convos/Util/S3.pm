# ABOUTME: AWS Signature Version 4 signing utility for S3-compatible APIs
# ABOUTME: Provides cryptographic request signing for Tigris, AWS S3, and other S3-compatible services
package Convos::Util::S3;
use Mojo::Base -strict, -signatures;

use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use Mojo::URL;
use Mojo::Util qw(url_escape);

use Exporter qw(import);
our @EXPORT_OK = qw(sign_request);

sub sign_request (%params) {
  my $method  = uc($params{method} // 'GET');
  my $url     = Mojo::URL->new($params{url});
  my $headers = $params{headers} // {};
  my $payload = $params{payload} // '';
  my $key     = $params{key}     or die 'key required';
  my $secret  = $params{secret}  or die 'secret required';
  my $region  = $params{region}  // 'auto';
  my $date    = $params{date}    // _iso8601_now();

  # Extract components from date
  my ($datestamp) = $date =~ /^(\d{8})/;

  # Calculate payload hash
  my $payload_hash = sha256_hex($payload);

  # Build canonical headers (must be sorted)
  # Auto-inject Host from URL if not provided
  my %canonical_headers = (
    'host'                 => $url->host_port,
    %$headers,
    'x-amz-content-sha256' => $payload_hash,
    'x-amz-date'           => $date,
  );

  my $signed_headers = join ';', sort { lc($a) cmp lc($b) } keys %canonical_headers;
  my $canonical_headers_str = join "\n",
    map { lc($_) . ':' . $canonical_headers{$_} }
    sort { lc($a) cmp lc($b) } keys %canonical_headers;

  # Build canonical URI (path component)
  my $canonical_uri = $url->path->to_string || '/';

  # Build canonical query string (sorted by key)
  my $canonical_query = '';
  if (my $query = $url->query) {
    my @pairs;
    for my $name (sort @{$query->names}) {
      for my $value (sort @{$query->every_param($name)}) {
        push @pairs, url_escape($name) . '=' . url_escape($value // '');
      }
    }
    $canonical_query = join '&', @pairs;
  }

  # Build canonical request
  my $canonical_request = join "\n",
    $method,
    $canonical_uri,
    $canonical_query,
    $canonical_headers_str,
    '',  # Empty line after headers
    $signed_headers,
    $payload_hash;

  # Build string to sign
  my $algorithm = 'AWS4-HMAC-SHA256';
  my $credential_scope = "$datestamp/$region/s3/aws4_request";
  my $string_to_sign = join "\n",
    $algorithm,
    $date,
    $credential_scope,
    sha256_hex($canonical_request);

  # Calculate signing key (HMAC chain)
  my $k_date    = hmac_sha256($datestamp, "AWS4$secret");
  my $k_region  = hmac_sha256($region, $k_date);
  my $k_service = hmac_sha256('s3', $k_region);
  my $k_signing = hmac_sha256('aws4_request', $k_service);

  # Calculate signature
  my $signature = hmac_sha256_hex($string_to_sign, $k_signing);

  # Build authorization header
  my $authorization = "$algorithm Credential=$key/$credential_scope, " .
                      "SignedHeaders=$signed_headers, Signature=$signature";

  return {
    'Authorization'          => $authorization,
    'x-amz-date'             => $date,
    'x-amz-content-sha256'   => $payload_hash,
  };
}

sub _iso8601_now {
  my @t = gmtime;
  return sprintf '%04d%02d%02dT%02d%02d%02dZ',
    $t[5] + 1900, $t[4] + 1, $t[3],
    $t[2], $t[1], $t[0];
}

1;

=encoding utf8

=head1 NAME

Convos::Util::S3 - AWS Signature Version 4 signing utility

=head1 SYNOPSIS

  use Convos::Util::S3 qw(sign_request);

  my $headers = sign_request(
    method  => 'PUT',
    url     => 'https://bucket.s3.amazonaws.com/key',
    headers => {'Content-Type' => 'application/json'},
    payload => '{"data":"value"}',
    key     => $access_key,
    secret  => $secret_key,
    region  => 'us-east-1',
  );

=head1 DESCRIPTION

L<Convos::Util::S3> provides AWS Signature Version 4 signing for S3-compatible
APIs including Tigris, AWS S3, and others.

=head1 FUNCTIONS

=head2 sign_request

  \%headers = sign_request(%params);

Signs an HTTP request for S3-compatible APIs. Parameters:

=over 4

=item * method - HTTP method (GET, PUT, DELETE, etc.)

=item * url - Full URL including bucket and key

=item * headers - Optional hashref of additional headers

=item * payload - Request body (empty string for GET)

=item * key - Access key ID

=item * secret - Secret access key

=item * region - AWS region or 'auto' for Tigris

=item * date - Optional ISO8601 date (for testing)

=back

Returns hashref with Authorization, x-amz-date, and x-amz-content-sha256 headers.

=head1 SEE ALSO

L<Convos>.

=cut
