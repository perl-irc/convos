# ABOUTME: Convos plugin providing web-based IRC nickname registration via NickServ
# ABOUTME: Uses ephemeral IRC connections to send REGISTER and VERIFY commands
package Convos::Plugin::Auth::Atheme::Registration;
use Mojo::Base 'Convos::Plugin', -async_await;

use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::URL;
use Parse::IRC ();

has irc_url => sub { Mojo::URL->new($ENV{CONVOS_AUTH_ATHEME_IRC_URL} // 'irc://localhost:6667') };
has domain  => sub { $ENV{CONVOS_AUTH_ATHEME_DOMAIN} // 'example.net' };
has timeout => sub { $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} // 30 };

# Response patterns for REGISTER command
our %REGISTER_RESPONSES = (
  success      => qr/An email containing nickname activation/i,
  nick_in_use  => qr/is already registered/i,
  bad_email    => qr/is not allowed|invalid email/i,
  rate_limit   => qr/too many accounts|try again later/i,
);

# Response patterns for VERIFY command
our %VERIFY_RESPONSES = (
  success     => qr/has been verified|registration complete/i,
  bad_code    => qr/invalid.*key|verification code.*incorrect/i,
  expired     => qr/not awaiting|no registration pending/i,
  nick_taken  => qr/already registered/i,
);

sub register {
  my ($self, $app, $config) = @_;

  # Set up configuration from config if provided
  $self->irc_url(Mojo::URL->new($config->{irc_url})) if $config->{irc_url};
  $self->domain($config->{domain})                   if $config->{domain};
  $self->timeout($config->{timeout})                 if $config->{timeout};

  # Override auth.register_p helper
  $app->helper('auth.register_p' => sub { $self->_register_p(@_) });

  # Add verification route
  $app->routes->post('/api/auth/verify')->to(cb => sub {
    my $c = shift->openapi->valid_input or return;
    $self->_verify_p($c)->then(
      sub { $c->render(openapi => shift) },
      sub { $c->render(openapi => {errors => [{message => shift}]}, status => 400) }
    );
  });

  $app->log->info("Loaded Convos::Plugin::Auth::Atheme::Registration");
}

async sub _register_p {
  my ($self, $c, $params) = @_;
  die 'Registration not yet implemented';
}

async sub _verify_p {
  my ($self, $c) = @_;
  die 'Verification not yet implemented';
}

sub _parse_register_response {
  my ($self, $response) = @_;

  for my $status (keys %REGISTER_RESPONSES) {
    my $pattern = $REGISTER_RESPONSES{$status};
    if ($response =~ $pattern) {
      return {status => $status, message => $response};
    }
  }

  return {status => 'unknown', message => $response};
}

sub _parse_verify_response {
  my ($self, $response) = @_;

  for my $status (keys %VERIFY_RESPONSES) {
    my $pattern = $VERIFY_RESPONSES{$status};
    if ($response =~ $pattern) {
      return {status => $status, message => $response};
    }
  }

  return {status => 'unknown', message => $response};
}

sub _ephemeral_irc_p {
  my ($self, $nick) = @_;

  my $url = $self->irc_url;
  my $promise = Mojo::Promise->new;
  my $timeout_id;
  my $stream;
  my $state = 'connecting';
  my @buffer;

  # Set up timeout
  $timeout_id = Mojo::IOLoop->timer($self->timeout => sub {
    return if $state eq 'disconnected';
    $state = 'disconnected';
    $stream->close if $stream;
    $promise->reject("IRC connection timeout");
  });

  # Create TCP connection
  my $tls = $url->scheme =~ /s$/ ? {SNI => 1} : undef;
  my $port = $url->port || ($tls ? 6697 : 6667);

  Mojo::IOLoop->client(
    {address => $url->host, port => $port, tls => $tls} => sub {
      my ($loop, $err, $stream_obj) = @_;

      if ($err) {
        Mojo::IOLoop->remove($timeout_id);
        $promise->reject("Connection failed: $err");
        return;
      }

      $stream = $stream_obj;

      # Handle incoming IRC messages
      $stream->on(read => sub {
        my ($stream, $bytes) = @_;
        push @buffer, $bytes;

        # Try to parse complete lines
        while (my $buf = join('', @buffer)) {
          if ($buf =~ s/^(.*?)\r?\n//) {
            @buffer = ($buf);
            my $line = $1;
            my $msg = Parse::IRC::parse_irc($line);

            # Handle nick-in-use error
            if ($msg->{command} eq '433') {
              $state = 'disconnected';
              $stream->close;
              Mojo::IOLoop->remove($timeout_id);
              $promise->reject("Nick already in use");
              return;
            }

            # Connection successful (001 = RPL_WELCOME)
            if ($msg->{command} eq '001') {
              $state = 'connected';
              Mojo::IOLoop->remove($timeout_id);
              $promise->resolve({
                stream => $stream,
                nick   => $nick,
              });
              return;
            }
          } else {
            last;
          }
        }
      });

      $stream->on(close => sub {
        return if $state eq 'disconnected';
        $state = 'disconnected';
        Mojo::IOLoop->remove($timeout_id);
        $promise->reject("Connection closed unexpectedly");
      });

      $stream->on(error => sub {
        my ($stream, $err) = @_;
        return if $state eq 'disconnected';
        $state = 'disconnected';
        Mojo::IOLoop->remove($timeout_id);
        $promise->reject("Stream error: $err");
      });

      # Send registration commands
      $stream->write("NICK $nick\r\n");
      $stream->write("USER $nick 0 * :Convos Registration Bot\r\n");
    }
  );

  return $promise;
}

sub _send_nickserv_p {
  my ($self, $irc, $command) = @_;

  my $promise = Mojo::Promise->new;
  my $stream = $irc->{stream};
  my $timeout_id;
  my @buffer;
  my @responses;
  my $collecting = 0;

  # Set up timeout
  $timeout_id = Mojo::IOLoop->timer($self->timeout => sub {
    $stream->close;
    $promise->reject("NickServ command timeout");
  });

  # Collect NickServ responses
  my $handler;
  $handler = sub {
    my ($stream, $bytes) = @_;
    push @buffer, $bytes;

    while (my $buf = join('', @buffer)) {
      if ($buf =~ s/^(.*?)\r?\n//) {
        @buffer = ($buf);
        my $line = $1;
        my $msg = Parse::IRC::parse_irc($line);

        # Look for NOTICE from NickServ
        if ($msg->{command} eq 'NOTICE' && $msg->{prefix} =~ /NickServ/i) {
          $collecting = 1;
          push @responses, $msg->{params}[-1];

          # Simple heuristic: if we get a response with "help" or end marker, we're done
          # This is a basic implementation - real NickServ parsing would be more sophisticated
          if (@responses >= 1 && $msg->{params}[-1] =~ /\.$/) {
            Mojo::IOLoop->remove($timeout_id);
            $stream->unsubscribe(read => $handler);
            $stream->close;
            $promise->resolve(join("\n", @responses));
          }
        }

        # Also accept errors as completion
        if ($msg->{command} =~ /^4\d\d$/ && $collecting) {
          Mojo::IOLoop->remove($timeout_id);
          $stream->unsubscribe(read => $handler);
          $stream->close;
          $promise->resolve(join("\n", @responses));
        }
      } else {
        last;
      }
    }
  };

  $stream->on(read => $handler);

  $stream->on(close => sub {
    Mojo::IOLoop->remove($timeout_id) if $timeout_id;
    $promise->resolve(join("\n", @responses)) unless $promise->is_finished;
  });

  $stream->on(error => sub {
    my ($stream, $err) = @_;
    Mojo::IOLoop->remove($timeout_id) if $timeout_id;
    $promise->reject("Stream error: $err") unless $promise->is_finished;
  });

  # Send the command
  $stream->write("PRIVMSG NickServ :$command\r\n");

  return $promise;
}

1;

=encoding utf8

=head1 NAME

Convos::Plugin::Auth::Atheme::Registration - IRC nickname registration plugin for Convos

=head1 DESCRIPTION

L<Convos::Plugin::Auth::Atheme::Registration> provides web-based IRC nickname
registration for Convos users. Since Atheme lacks an XMLRPC registration endpoint,
this plugin uses ephemeral IRC connections to send NickServ REGISTER and VERIFY commands.

=head1 ATTRIBUTES

=head2 irc_url

  $url = $plugin->irc_url;

The IRC server URL to connect to for registration. Defaults to the
C<CONVOS_AUTH_ATHEME_IRC_URL> environment variable or C<irc://localhost:6667>.

=head2 domain

  $domain = $plugin->domain;

The IRC domain to append to usernames for email addresses. Defaults to the
C<CONVOS_AUTH_ATHEME_DOMAIN> environment variable or C<example.net>.

=head2 timeout

  $seconds = $plugin->timeout;

Timeout in seconds for IRC operations. Defaults to the C<CONVOS_AUTH_ATHEME_TIMEOUT>
environment variable or C<30>.

=head1 METHODS

=head2 register

  $plugin->register($app, \%config);

Registers the plugin with the Convos application.

=head1 INTERNAL METHODS

=head2 _parse_register_response

  $result = $plugin->_parse_register_response($response);

Parses NickServ REGISTER command responses. Returns a hashref with C<status> and
C<message> keys. Recognized status values:

=over 4

=item * success - Email with activation instructions sent

=item * nick_in_use - Nickname already registered

=item * bad_email - Email address not allowed or invalid

=item * rate_limit - Too many registrations from host

=item * unknown - Unrecognized response

=back

=head2 _parse_verify_response

  $result = $plugin->_parse_verify_response($response);

Parses NickServ VERIFY command responses. Returns a hashref with C<status> and
C<message> keys. Recognized status values:

=over 4

=item * success - Account verified successfully

=item * bad_code - Invalid verification key/code

=item * expired - No pending registration or verification expired

=item * nick_taken - Nickname already registered to another user

=item * unknown - Unrecognized response

=back

=head2 _ephemeral_irc_p

  $p = $plugin->_ephemeral_irc_p($nick);

Creates a temporary IRC connection with the given nickname. Returns a promise that
resolves with a hashref containing C<stream> and C<nick> keys on successful connection,
or rejects with an error message if the nick is in use or connection fails.

=head2 _send_nickserv_p

  $p = $plugin->_send_nickserv_p($irc, $command);

Sends a command to NickServ and collects the response. Takes an IRC connection
hashref (from C<_ephemeral_irc_p>) and a command string. Returns a promise that
resolves with the NickServ response text or rejects on error.

The connection is automatically closed after the response is received.

=head1 SEE ALSO

L<Convos::Plugin::Auth::Atheme>, L<Convos>.

=cut
