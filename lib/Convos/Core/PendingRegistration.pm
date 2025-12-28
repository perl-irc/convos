# ABOUTME: PendingRegistration stores temporary registration data until verification
# ABOUTME: Used to track IRC nick registrations pending email verification
package Convos::Core::PendingRegistration;
use Mojo::Base 'Mojo::EventEmitter';

use Convos::Util qw(logf);
use Mojo::Date;
use Mojo::Path;
use Mojo::Promise;

sub core       { shift->{core}       or die 'core is required in constructor' }
sub session_id { shift->{session_id} or die 'session_id is required in constructor' }
sub nick       { shift->{nick}       or die 'nick is required in constructor' }
sub email      { shift->{email}      or die 'email is required in constructor' }

sub id { $_[0]->session_id }

has created_at => sub { Mojo::Date->new };
has expires_at => sub {
  my $self = shift;
  my $created = $self->created_at;
  return Mojo::Date->new($created->epoch + 3600);  # 1 hour expiration
};

sub new {
  my $class = shift;
  my $self  = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
  return $self->_normalize_attributes;
}

sub uri { Mojo::Path->new(sprintf 'pending/%s.json', $_[0]->session_id) }

sub save_p {
  my $self = shift;
  return $self->core->backend->save_object_p($self);
}

sub load_p {
  my $self = shift;
  return $self->core->backend->load_object_p($self)->then(sub {
    my $data = shift;

    # Check if data was loaded
    return Mojo::Promise->reject('Registration not found') unless $data->{expires_at};

    # Check if registration has expired
    my $expires_at = ref $data->{expires_at}
      ? $data->{expires_at}
      : Mojo::Date->new($data->{expires_at});

    if ($expires_at->epoch < time) {
      $self->logf(debug => 'Pending registration %s has expired', $self->session_id);
      return Mojo::Promise->reject('Registration has expired');
    }

    return $data;
  });
}

sub delete_p {
  my $self = shift;
  return $self->core->backend->delete_object_p($self);
}

sub TO_JSON {
  my ($self, $persist) = @_;
  return {
    session_id => $self->session_id,
    nick       => $self->nick,
    email      => $self->email,
    created_at => $self->created_at->to_datetime,
    expires_at => $self->expires_at->to_datetime,
  };
}

sub _normalize_attributes {
  my $self = shift;
  $self->{created_at} = $self->{created_at}
    && !ref $self->{created_at} ? Mojo::Date->new($self->{created_at}) : Mojo::Date->new;
  $self->{expires_at} = $self->{expires_at}
    && !ref $self->{expires_at} ? Mojo::Date->new($self->{expires_at})
    : Mojo::Date->new($self->{created_at}->epoch + 3600);
  return $self;
}

1;

=encoding utf8

=head1 NAME

Convos::Core::PendingRegistration - Temporary storage for pending registrations

=head1 DESCRIPTION

L<Convos::Core::PendingRegistration> is a class used to store pending IRC nick
registrations awaiting verification.

=head1 ATTRIBUTES

=head2 core

  $obj = $pr->core;

Holds a L<Convos::Core> object.

=head2 id

  $str = $pr->id;

Returns the session_id, used by the backend to identify this object.

=head2 session_id

  $str = $pr->session_id;

Unique session identifier for this pending registration.

=head2 nick

  $str = $pr->nick;

IRC nickname being registered.

=head2 email

  $str = $pr->email;

Email address for registration.

=head2 created_at

  $date = $pr->created_at;

L<Mojo::Date> object for when the registration was created.

=head2 expires_at

  $date = $pr->expires_at;

L<Mojo::Date> object for when the registration expires.

=head1 METHODS

=head2 new

  $pr = Convos::Core::PendingRegistration->new(\%attributes);

Used to construct a new object.

=head2 uri

  $path = $pr->uri;

Holds a L<Mojo::Path> object, with the URI to where this object should be
stored.

=head2 save_p

  $p = $pr->save_p;

Will save L</ATTRIBUTES> to persistent storage.
See L<Convos::Core::Backend/save_object> for details.

=head2 load_p

  $p = $pr->load_p;

Will load L</ATTRIBUTES> from persistent storage and check for expiration.
Rejects the promise if the registration has expired.
See L<Convos::Core::Backend/load_object> for details.

=head2 delete_p

  $p = $pr->delete_p;

Will delete this object from persistent storage.
See L<Convos::Core::Backend/delete_object> for details.

=head1 SEE ALSO

L<Convos::Core>.

=cut
