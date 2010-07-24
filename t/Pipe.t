#!/usr/bin/perl;
use strict;
use warnings;

use Test::More;
our $CLASS = 'Child::Socket';

require_ok( $CLASS );

my $one = $CLASS->new( sub {
    my $self = shift;
    $self->say( "Have self" );
    $self->say( "parent: " . $self->parent );
    my $in = $self->read();
    $self->say( $in );
}, pipe => 1 );

$one->start;
is( $one->read(), "Have self\n", "child has self" );
is( $one->read(), "parent: $$\n", "child has parent PID" );
{
    local $SIG{ALRM} = sub { die "non-blocking timeout" };
    alarm 5;
    ok( !$one->is_complete, "Not Complete" );
    alarm 0;
}
$one->say("XXX");
is( $one->read(), "XXX\n", "Full IPC" );
ok( $one->wait, "wait" );
ok( $one->is_complete, "Complete" );
is( $one->exit_status, 0, "Exit clean" );

$one = $CLASS->new( sub {
    my $self = shift;
    $SIG{INT} = sub { exit( 2 ) };
    $self->say( "go" );
    sleep 100;
}, pipe => 1 )->start;

$one->read;
sleep 1;
ok( $one->kill(2), "Send signal" );
ok( !$one->wait, "wait" );
ok( $one->is_complete, "Complete" );
is( $one->exit_status, 2, "Exit 2" );
ok( $one->unix_exit > 2, "Real exit" );

$one = $CLASS->new( sub {
    my $self = shift;
    $self->autoflush(0);
    $self->say( "A" );
    $self->flush;
    $self->say( "B" );
    sleep 5;
    $self->flush;
}, pipe => 1 );

$one->start;
is( $one->read(), "A\n", "A" );
my $start = time;
is( $one->read(), "B\n", "B" );
my $end = time;

ok( $end - $start > 2, "No autoflush" );

$one = $CLASS->new( sub {
    my $self = shift;
    $self->detach;
    $self->say( $self->detached );
}, pipe => 1 )->start;

is( $one->read(), $one->pid . "\n", "Child detached" );


$one = $CLASS->new( sub {
    my $self = shift;
    $self->say( "go" );
    $self->read;
    $self->say( $self->detached );
}, pipe => 1 )->start;

$one->read();
$one->detach;
sleep 1;
$one->say("go");

is( $one->read(), $one->pid . "\n", "Child detached remotely" );

done_testing;
