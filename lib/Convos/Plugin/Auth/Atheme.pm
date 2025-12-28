# ABOUTME: Convos authentication plugin that delegates auth to Atheme IRC Services via XMLRPC
# ABOUTME: Provides login and registration through Atheme's NickServ service

# Exception class for Atheme XMLRPC faults
package Convos::Plugin::Auth::Atheme::Fault;
use Mojo::Base -base;
has ['code', 'message'];
sub TO_JSON { {code => shift->code, message => shift->message} }
use overload '""' => sub { my $s = shift; $s->message }, fallback => 1;

package Convos::Plugin::Auth::Atheme;
use Mojo::Base 'Convos::Plugin::Auth', -async_await;

use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::URL;
use Scalar::Util qw(blessed);

has xmlrpc_url => sub { Mojo::URL->new($ENV{CONVOS_AUTH_ATHEME_URL} || 'http://localhost:8080/xmlrpc') };
has domain     => sub { $ENV{CONVOS_AUTH_ATHEME_DOMAIN} || 'example.net' };
has irc_url    => sub { Mojo::URL->new($ENV{CONVOS_AUTH_ATHEME_IRC_URL} || 'irc://localhost:6667') };
has timeout    => sub { $ENV{CONVOS_AUTH_ATHEME_TIMEOUT} || 30 };

sub register {
  my ($self, $app, $config) = @_;

  # Set up configuration from config if provided
  $self->xmlrpc_url(Mojo::URL->new($config->{xmlrpc_url})) if $config->{xmlrpc_url};
  $self->domain($config->{domain})                         if $config->{domain};
  $self->irc_url(Mojo::URL->new($config->{irc_url}))       if $config->{irc_url};
  $self->timeout($config->{timeout})                       if $config->{timeout};

  # Override auth helpers
  $app->helper('auth.login_p'    => sub { $self->_login_p(@_) });
  $app->helper('auth.register_p' => sub { $self->_register_p(@_) });

  # Log plugin load
  $app->log->info("Loaded Convos::Plugin::Auth::Atheme " . $self->xmlrpc_url);
}

sub _normalize_username {
  my ($self, $input) = @_;
  $input //= '';
  $input =~ s/^\s+|\s+$//g;  # trim
  $input =~ s/\@.*$//;        # strip @domain
  return $input;
}

sub _fault_message {
  my ($self, $code) = @_;
  my %messages = (
    1 => 'Missing credentials',
    3 => 'Account not registered. Register with /msg NickServ REGISTER on IRC.',
    5 => 'Invalid username or password',
    6 => 'Account is frozen. Contact network staff.',
  );
  return $messages{$code} // 'Authentication service unavailable. Please try again later.';
}

async sub _login_p {
  my ($self, $c, $params) = @_;

  my $username  = $self->_normalize_username($params->{email});
  my $password  = $params->{password};
  my $source_ip = $c->tx->remote_address;

  die 'Username is required' unless length $username;
  die 'Password is required' unless length $password;

  # Authenticate with Atheme
  my $authcookie;
  eval {
    $authcookie = await $self->_atheme_login_p($username, $password, $source_ip);
  } or do {
    my $err = $@;
    my $code = (blessed($err) && $err->can('code')) ? $err->code : 0;
    my $msg = $self->_fault_message($code);
    $c->app->log->warn("Atheme login failed for $username: $msg");
    die $msg;
  };

  # Resolve email
  my $email = await $self->_resolve_email_p($authcookie, $username, $source_ip);

  # Lookup or create user
  my $core = $c->app->core;
  my $user = $core->get_user({email => $email});

  unless ($user) {
    $c->app->log->info("Creating new user $email from Atheme auth");
    $user = $core->user({email => $email});
    await $user->save_p;
    await $self->_user_initial_setup_p($c, $user, $username, $password);
  }

  $c->app->log->info("Atheme login success for $username ($email)");
  return $user;
}

sub _register_p {
  my ($self, $c, $args) = @_;
  die 'Not implemented';
}

sub _atheme_login_p {
  my ($self, $username, $password, $source_ip) = @_;
  $source_ip //= '';

  return Mojo::IOLoop->subprocess->run_p(sub {
    require RPC::XML::Client;
    my $client = RPC::XML::Client->new($self->xmlrpc_url->to_string);
    $client->useragent->timeout($self->timeout);

    my $resp = $client->send_request('atheme.login', $username, $password, $source_ip);

    if (ref $resp && $resp->is_fault) {
      die Convos::Plugin::Auth::Atheme::Fault->new(
        code => $resp->code,
        message => $resp->string
      );
    }

    return ref $resp ? $resp->value : $resp;
  });
}

sub _atheme_command_p {
  my ($self, $authcookie, $username, $source_ip, $service, $command, @args) = @_;
  $source_ip //= '';

  return Mojo::IOLoop->subprocess->run_p(sub {
    require RPC::XML::Client;
    my $client = RPC::XML::Client->new($self->xmlrpc_url->to_string);
    $client->useragent->timeout($self->timeout);

    my $resp = $client->send_request(
      'atheme.command', $authcookie, $username, $source_ip,
      $service, $command, @args
    );

    if (ref $resp && $resp->is_fault) {
      die Convos::Plugin::Auth::Atheme::Fault->new(
        code => $resp->code,
        message => $resp->string
      );
    }

    return ref $resp ? $resp->value : $resp;
  });
}

sub _parse_email_from_info {
  my ($self, $info_output) = @_;
  return undef unless $info_output;
  return $1 if $info_output =~ /^Email\s*:\s*(\S+@\S+)/m;
  return undef;
}

async sub _resolve_email_p {
  my ($self, $authcookie, $username, $source_ip) = @_;

  my $email;
  eval {
    my $info = await $self->_atheme_command_p(
      $authcookie, $username, $source_ip, 'NickServ', 'INFO', $username
    );
    $email = $self->_parse_email_from_info($info);
  };

  # Fallback to nick@domain
  return $email // sprintf('%s@%s', $username, $self->domain);
}

1;

=encoding utf8

=head1 NAME

Convos::Plugin::Auth::Atheme - Atheme IRC Services authentication plugin for Convos

=head1 DESCRIPTION

L<Convos::Plugin::Auth::Atheme> is a plugin that delegates authentication to
Atheme IRC Services via XMLRPC. It provides login and registration through
Atheme's NickServ service.

=head1 ATTRIBUTES

=head2 xmlrpc_url

  $url = $plugin->xmlrpc_url;

The URL for the Atheme XMLRPC endpoint. Defaults to the C<CONVOS_AUTH_ATHEME_URL>
environment variable or C<http://localhost:8080/xmlrpc>.

=head2 domain

  $domain = $plugin->domain;

The IRC domain to append to usernames for email addresses. Defaults to the
C<CONVOS_AUTH_ATHEME_DOMAIN> environment variable or C<example.net>.

=head2 irc_url

  $url = $plugin->irc_url;

The IRC server URL to connect users to. Defaults to the C<CONVOS_AUTH_ATHEME_IRC_URL>
environment variable or C<irc://localhost:6667>.

=head2 timeout

  $seconds = $plugin->timeout;

Timeout in seconds for XMLRPC requests. Defaults to the C<CONVOS_AUTH_ATHEME_TIMEOUT>
environment variable or C<30>.

=head1 METHODS

=head2 register

  $plugin->register($app, \%config);

Registers the plugin with the Convos application.

=head1 SEE ALSO

L<Convos::Plugin::Auth>, L<Convos>.

=cut
