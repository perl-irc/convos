# ABOUTME: Convos authentication plugin that delegates auth to Atheme IRC Services via XMLRPC
# ABOUTME: Provides login and registration through Atheme's NickServ service
package Convos::Plugin::Auth::Atheme;
use Mojo::Base 'Convos::Plugin::Auth', -async_await;

use Mojo::Promise;
use Mojo::URL;

has xmlrpc_url => sub { Mojo::URL->new($ENV{CONVOS_ATHEME_XMLRPC_URL} || 'http://localhost:8080/xmlrpc') };
has domain     => sub { $ENV{CONVOS_ATHEME_DOMAIN} || 'example.net' };
has irc_url    => sub { Mojo::URL->new($ENV{CONVOS_ATHEME_IRC_URL} || 'irc://localhost:6667') };
has timeout    => sub { $ENV{CONVOS_ATHEME_TIMEOUT} || 30 };

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

  # Call parent to set up remaining helpers
  $self->SUPER::register($app, $config);
}

sub _login_p {
  my ($self, $c, $args) = @_;
  die 'Not implemented';
}

sub _register_p {
  my ($self, $c, $args) = @_;
  die 'Not implemented';
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

The URL for the Atheme XMLRPC endpoint. Defaults to the C<CONVOS_ATHEME_XMLRPC_URL>
environment variable or C<http://localhost:8080/xmlrpc>.

=head2 domain

  $domain = $plugin->domain;

The IRC domain to append to usernames for email addresses. Defaults to the
C<CONVOS_ATHEME_DOMAIN> environment variable or C<example.net>.

=head2 irc_url

  $url = $plugin->irc_url;

The IRC server URL to connect users to. Defaults to the C<CONVOS_ATHEME_IRC_URL>
environment variable or C<irc://localhost:6667>.

=head2 timeout

  $seconds = $plugin->timeout;

Timeout in seconds for XMLRPC requests. Defaults to the C<CONVOS_ATHEME_TIMEOUT>
environment variable or C<30>.

=head1 METHODS

=head2 register

  $plugin->register($app, \%config);

Registers the plugin with the Convos application.

=head1 SEE ALSO

L<Convos::Plugin::Auth>, L<Convos>.

=cut
