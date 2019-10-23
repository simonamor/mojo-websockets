#!/usr/bin/env perl

use Mojolicious::Lite;
use JSON;
use lib "lib";
use WSClient;
use Data::GUID;
use Mojo::IOLoop;
# use Mojo::IOLoop::Delay;

use Data::Dumper;

my $clients = {};

post '/send' => sub {
    my $c = shift;

    $c->app->log->debug("Request to send:" . Dumper($c->req->params->to_hash));

    my $client = $c->req->param("id") || "unknown";
    my $msg = $c->req->param("msg") || "{}";
    my $op = $c->req->param("op") || "random";
    my $mdata = eval { decode_json($msg); };
    $mdata ||= {};

    my $req_id = Data::GUID->new->as_string;

    $c->app->log->debug("Recv: send request for client $client, msg $msg");

    unless (exists $clients->{$client}) {
        $c->render(text => "Err - unknown client $client", format => "txt");
        return;
    }

    my $wsc = $clients->{ $client };

    warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
    my $reply_promise = Mojo::Promise->new(sub {
        my ($resolve, $reject) = @_;

        warn "promise triggered line: " . __LINE__ . " at " . scalar(localtime(time()));

#        my $response = $wsc->replies->{ $req_id };
#        $resolve->($response);
    });
    warn "promise attached to $req_id: " . __LINE__;
    $wsc->promises->{ $req_id } = $reply_promise;

    # This might need some pre-checks like Mojolicious::Controller->on()
    # Adds a second message handler
    $wsc->tx->on(message => sub {
        my ($c, $msg) = @_;
        # $c is $wsc->tx

        my $json = eval { decode_json($msg); };
        if ($@ || !defined $json) {
            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            return;
        }
        unless (exists $json->{ requestId } && defined $json->{ requestId } && $json->{ requestId } =~ /^[0-9a-z\-]+$/i) {
            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            return;
        }
        my $inc_id = $json->{ requestId } || "";
        if ($inc_id eq $req_id) {
            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            ## Need to return the promise or something...
            $reply_promise->resolve($json);
        }
        warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
        return;
    });

    warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
    $wsc->tx->send({ json => { op => $op, requestId => $req_id, data => $mdata }});
    warn "line: " . __LINE__ . " at " . scalar(localtime(time()));

    $c->render_later;

    my $timer_promise = Mojo::Promise->timeout(10 => "timed out");
    my $output_promise = Mojo::Promise->race($timer_promise, $reply_promise);
    warn "line: " . __LINE__;
    $output_promise->then(
        sub {
            my @value = @_;

            delete $wsc->replies->{ $req_id };
            my $rep = $value[0]->{ data };

            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            warn "ok: " . Dumper(@value);
            $c->render(text => "Ok - " . encode_json($rep), format => "txt");
        },

        sub {
            my @value = @_;

            delete $wsc->replies->{ $req_id };
            my $rep = $value[0]->{ data };

            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            warn "err: " . Dumper(@value);
            $c->render(text => "Err - timeout waiting for response", format => "txt");
        }
    );

};

websocket '/link' => sub {
    my $c = shift;

    $c->render_later;

    $c->app->log->debug("WebSocket opened");

    $c->inactivity_timeout(60);
    my $id = undef;
    my $wsc = WSClient->new(tx => $c->tx);
    $c->on(message => sub {
        my ($c, $msg) = @_;

        $wsc->log($c, "msg: $msg");

        my $json = eval { decode_json($msg); };
        if ($@ || !defined $json) {
            $wsc->log($c, "Invalid message '$msg' received");
            $wsc->respond($c, undef, "status", { status => "error", error => "Invalid message" });
            return;
        }

        my $req_id = $json->{ requestId } || undef;

        my $op = $json->{ op } || undef;
        $wsc->log($c, "opname $op");

        unless (exists $json->{ requestId } && defined $json->{ requestId } && $json->{ requestId } =~ /^[0-9a-z\-]+$/i) {
            $wsc->log($c, "Invalid requestId received");
            $wsc->respond($c, $req_id, "status", { status => "error", error => "Invalid requestId" });
            return;
        }

        unless ($op && $op =~ /^[a-z0-9]+$/ && $wsc->can("op_$op")) {
            $wsc->log($c, "Invalid operation received");
            $wsc->respond($c, $req_id, "status", { status => "error", error => "Invalid operation" });
            return;
        }

        $wsc->log($c, "Got a message");
        $wsc->log($c, "Setting reply for " . $json->{ requestId });

        # We don't store the status replies
        if ($op ne "status") {
            $wsc->replies->{ $json->{ requestId } } = $json;
        }
        $wsc->log($c, "Set $json->{ requestId } for op $op ..." . Dumper($wsc->replies));

        my $opname = "op_$op";
        $wsc->$opname( $c, $json );
        $wsc->log($c, "processed $opname");

        $clients->{ $wsc->id } = $wsc if ($wsc->id && !exists $clients->{ $wsc->id });
    });

    $c->on(finish => sub {
        my ($c, $code, $reason) = @_;
        $reason ||= "";
        $wsc->log($c, "WebSocket closed with status $code reason $reason");
        delete $clients->{$wsc->id} if (defined $wsc->id);
    });
};



app->start;

