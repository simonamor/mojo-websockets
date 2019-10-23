package WSClient;


use strict;
use warnings;

use Moose;
use Types::Standard qw(Maybe HashRef Str);

use JSON;

has 'tx' => (
    is => 'rw',
#    isa => 'Mojo::Transaction::WebSocket',
);

has 'id' => (
    is => 'rw',
    isa => 'Maybe[Str]',
);

has 'requests' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

has 'replies' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

has 'promises' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

sub log {
    my $self = shift;
    my $c = shift;

    $c->app->log->debug("Client " . ($self->id || "") . " - " . join(" ", @_));
}

sub respond {
    my $self = shift;
    my ($c, $req_id, $op, $data) = @_;

    $self->log($c, encode_json({ requestId => $req_id, op => $op, data => $data }));
    return $c->send({ json => { requestId => $req_id, op => $op, data => $data }});
}

sub op_ping {
    my $self = shift;
    my ($c, $json) = @_;

    $json->{ ping } ||= "pong";

    my $request_id = $json->{ requestId };

    $self->log($c, "ping/pong");
    $self->respond($c, $request_id, "pong", { "ping" => $json->{ ping } });
}

sub op_status {
    my $self = shift;
    my ($c, $json) = @_;

    my $request_id = $json->{ requestId };
    if (exists $self->requests->{ $request_id }) {
        $self->log($c, "removing $request_id containing " . Dumper($self->requests->{ $request_id }));
        delete $self->requests->{ $request_id };
        $self->replies->{ $request_id } = $json;
    }
}

sub op_session {
    my $self = shift;
    my ($c, $json) = @_;

    my $request_id = $json->{ requestId };

    unless (exists $json->{ data } && exists $json->{ data }{ socketId }) {
        $self->log($c, "error - no socket id");
        $self->respond($c, $request_id, "status", { "status" => "error", "error" => "Missing or invalid id" });
        return;
    }

    # Check session ID against the database
    # If not found, return an error
    # If found, set session id

    $self->log($c, "setting id");
    $self->id($json->{ data }{ socketId });
    $self->respond($c, $request_id, "status", { status => "ok" });
}

1;
