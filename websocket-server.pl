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


sub wait_for_reply_p {
    my $client = shift;
    my $req_id = shift;

    # Although this is synchronous, we're waiting on an
    # async process so we use begin/end to kick the oop

    # Wait for a response to request $req_id
    my $max_wait = 10; # 10 seconds;
    my $check_delay = 1; # 0.1 seconds

    my @timers = ();
    my $waiting_for = $check_delay;
    while ($waiting_for <= $max_wait) {
        my $t_id = Mojo::Promise->new(sub {
            my ($resolve, $reject) = @_;

            if (exists $clients->{ $client }->replies->{ $req_id }) {
                warn "got response for $waiting_for";
                $resolve->("success");

                #foreach (@timers) { Mojo::IOLoop->remove($_); }
            }
        })->timer($waiting_for);

        push @timers, $t_id;
        $waiting_for += $check_delay;
    }

    my $promise = Mojo::Promise->race(@timers);
    return $promise;

#    my $promise = Mojo::Promise->new(sub {
#        my ($resolve, $reject) = @_;
#
#        warn "Request id $req_id";
#
#        warn Dumper($clients->{ $client }->replies);
#        if (exists $clients->{ $client }->replies->{ $req_id }) {
#            $resolve->("Success");
#            warn "here " . __LINE__;
#            return;
#        }
#
#        warn ($max_wait <= 0 ? "timed out" : "replied") . ": " . __LINE__ . " at " . scalar(localtime(time()));
#
#        if ($max_wait <= 0) {
#            $reject->("timed out");
#        } else {
#            $resolve->("success");
#        }
#    });
#    return $promise;
}

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

    $c->render_later;

    my $wsc = $clients->{ $client };

    warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
    $wsc->tx->send({ json => { op => $op, requestId => $req_id, data => $mdata }});
    warn "line: " . __LINE__ . " at " . scalar(localtime(time()));

    my $timer_promise = Mojo::Promise->timeout(10 => "timed out");
    my $reply_promise = wait_for_reply_p($client, $req_id);

    my $output_promise = Mojo::Promise->race($timer_promise, $reply_promise);
    warn "line: " . __LINE__;
    $output_promise->then(
        sub {
            my @value = @_;

            my $rep = delete $wsc->replies->{ $req_id };

            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            warn "ok: " . Dumper($rep);
            $c->render(text => "Ok - " . encode_json($rep), format => "txt");
        },

        sub {
            my $rep = delete $wsc->replies->{ $req_id };

            warn "line: " . __LINE__ . " at " . scalar(localtime(time()));
            warn "err: " . Dumper($rep);
            $c->render(text => "Err - timeout waiting for response", format => "txt");
        }
    );

    warn "line: " . __LINE__;
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

