package Child::Socket;
use strict;
use warnings;

use base 'Child';
use vars qw/%META/;

use Scalar::Util qw/blessed/;
use IO::Socket::UNIX;
use Carp;

our $VERSION = '0.001';
*META = \%Child::META;

sub child(&;@) {
    my ( $code, %params ) = @_;
    my $caller = caller;
    return __PACKAGE__->new($code, %{$META{$caller}}, %params )->start;
}

sub new {
    my ( $class, $code, %params ) = @_;
    croak "You cannot specify both a pipe and a socket, pick one."
        if $params{ pipe }
        && $params{ socket };

    my $self = $class->SUPER::new( $code, %params );
    $self->_ipc($params{ socket })
        if $params{ socket };
    return $self;
}

sub existing {
    my $class = shift;
    my ( $file ) = @_;
    croak "You must specify a file"
        unless $file;

    my $self = bless(
        {
            socket_file => $file,
            _ipc => 1,
        },
        $class
    );
    chomp( my $pid = $self->connect );
    $self->_pid( $pid );
    return $self;
}

sub is_pipe {
    my $self = shift;
    return unless $self->ipc;
    return ref( $self->ipc ) eq 'ARRAY';
}

sub _init_ipc {
    my $self = shift;
    return unless $self->ipc;

    return $self->SUPER::_init_ipc( @_ )
        if $self->is_pipe;

    $self->socket_file( $self->ipc );

    return $self->connect(5)
        if $self->pid;

    $self->_init_server;
    $self->connect;
}

sub _read_handle  {
    my $self = shift;
    $self->_no_pipe unless ref $self->ipc;
    return $self->is_pipe
        ? $self->SUPER::_read_handle()
        : $self->ipc;
}

sub _write_handle {
    my $self = shift;
    $self->_no_pipe unless ref $self->ipc;
    return $self->is_pipe
        ? $self->SUPER::_write_handle()
        : $self->ipc;
}

sub _no_pipe {
    croak( "No connection between parent and child." );
}

sub _listener {
    my $self = shift;
    ($self->{_listener}) = @_ if @_;
    return $self->{_listener};
}

sub _init_server {
    my $self = shift;
    my $file = $self->socket_file;

    $self->_listener(
        IO::Socket::UNIX->new(
            Local => $file,
            Listen => 1,
        ) || die ( "Could not create socket: $!" )
    );
}

sub connect {
    my $self = shift;
    my ( $timeout ) = @_;

    croak "Not a socket child"
        unless $self->is_socket;

    return if ref $self->ipc;

    if ( $self->parent ) {
        my $client;
        $timeout ||= "NONE";

        while ( !$client && $timeout ) {
            $client = $self->_listener->accept;
            $timeout-- unless $timeout eq 'NONE';
            sleep 1 unless $client;
        }
        return unless $client;

        $self->_ipc( $client );
        $self->say( $$ );
        return $client;
    }

    my $file = $self->socket_file;
    while ( ! -e $file && $timeout ) {
        $timeout--;
        sleep 1;
    }

    my $socket = IO::Socket::UNIX->new( $file )
        || croak ( "Could not connect to socket '" . $file . "': $!" );
    $self->_ipc( $socket );

    return $self->read();
}

sub disconnect {
    my $self = shift;

    croak "Not a socket child"
        unless $self->is_socket;

    return unless blessed( $self->ipc );

    my $socket = $self->ipc;
    close( $socket );
    $self->_ipc(1);
}

sub is_socket {
    return shift->socket_file;
}

sub socket_file {
    my $self = shift;
    return $self->{ socket_file }
        || $self->_socket_file( @_ );
}

sub _socket_file {
    my $self = shift;
    my ( $in ) = @_;

    unless ( $self->{socket_file} ) {
        if ( $in && $in !~ m/^\d+$/ ) {
            $self->{socket_file} = $in;
            return $in;
        }

        require File::Spec;
        my $dir = File::Spec->tmpdir();
        my $pid = $self->parent
            ? $$
            : $self->pid;
        my $name = "$dir/Child-Socket.$pid";
        $name =~ s|/+|/|g;
        $self->{socket_file} = $name;
    }

    return $self->{socket_file};
}

1;

__END__

=head1 NAME

Child::Socket - Child with socket support.

=head1 DESCRIPTION

Lets you create a Child object, disconnect from it, and reconnect later in the
same or different process.

=head1 REQUIREMENT NOTE

Requires UNIX socket support.

=head1 SYNOPSIS

=head2 BASIC

    use Child::Socket;

    # Build with IPC
    my $child = Child::Socket->new(sub {
        my $self = shift;
        $self->say("message1");
        my $reply = $self->read();
    }, socket => 1 );

    my $message1 = $child1->read();
    $child->say("reply");

=head1 CONSTRUCTOR

=over 4

=item $class->new( sub { ... } )

=item $class->new( sub { ... }, pipe => 1 )

=item $class->new( sub { ... }, socket => 1 )

=item $class->new( sub { ... }, socket => $file )

Create a new Child object. Does not start the child.

=item $class->existing( $socket_filename )

Create a new instance that connects to an existing child.

=back

=head1 OBJECT METHODS

Inherits everything from L<Child>.

=over

=item $child->connect( $timeout )

In parent process this will attempt to connect to the child unless already
connected. Throws an exception if the socket file does not exist after the
timeout expires. Once connected, the child PID will be returned.

In the child process this will accept an incomming connection. This will return
undef if no incomming connection occurs before the timeout expires.

B<NOTE>: Only one connection can be maintained at a time. Will return undef if
already connected.

=item $child->disconnect()

Disconnects if connected.

=item $child->socket_file()

Get the socket file name.

=item $child->is_socket()

Check if this is a socket connection.

=item $child->is_pipe()

Check if this is a pipe connection.

=back

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2010 Chad Granum

Child-Socket is free software; Standard perl licence.

Child-Socket is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the license for more details.
