#!/usr/bin/env perl

use strict;
use warnings;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

use AnyEvent;
use Data::Dumper;

use AnyEvent::WebSocket::Client;
use JSON::XS;
use Data::GUID;

use HTTP::Headers;
use LWP::UserAgent;
use Digest::SHA qw(sha256_hex);

my $client = AnyEvent::WebSocket::Client->new( ssl_no_verify => 1 );

my $websocketUrl = 'ws://localhost:3019/link';

$client->connect( $websocketUrl )->cb(
    sub {
        # make $connection an our variable rather than
        # my so that it will stick around.  Once the
        # connection falls out of scope any callbacks
        # tied to it will be destroyed.

        print "Connecting...\n";
        our $connection = eval { shift->recv };

        # Requests that are pending a response
        our $requests = { };

        if($@) {
            # handle error...
            warn $@;
            exit;
        }

        # recieve message from the websocket...
        $connection->on(each_message => sub {
            # $connection is the same connection object
            # $message isa AnyEvent::WebSocket::Message
            my($connection, $message) = @_;
            # ...

            my $content = decode_json($message->body);

            print "Message received " . scalar(localtime(time())) . ": " . Dumper($content) . "\n";

            unless (exists $content->{ requestId } && $content->{ requestId }) {
                print "No requestId found\n";
                return;
            }

            if ($content->{ op } eq "status") {
                if (exists $requests->{ $content->{ requestId } }) {
                    print "Deleting request $content->{ requestId } containing " . Dumper($requests->{ $content->{ requestId } });;
                    delete $requests->{ $content->{ requestId } };
                }
                return;
            }

# Just acknowledge the request for now - normally other code
# would go here to handle the content of the request.
            my $data = {
                op => "status",
                requestId => $content->{ requestId },
                data => {
                    status => "ok",
                }
            };

            # This operation sends a random number back
            if ($content->{ op } eq "random") {
                $data->{ data }{ rnd } = int(rand(10));
            } else {
                $data->{ data }{ req } = $content;
            }

# This simulates a slow client
            print "Sleeping 2 seconds...\n";
            sleep(2);
            print "Waking up...\n";
##

            print "Message sent(resp) " . scalar(localtime(time())) . ": " . Dumper($data);
            $connection->send(encode_json($data));
        });

        # handle a closed connection...
        $connection->on(finish => sub {
            # $connection is the same connection object
            my($connection) = @_;
            # ...
            print "Disconnecting...\n";
            $connection->close();

            # How do we disconnect the client?
            exit;
        });

        # Init the connection - tell the server what client id we are
        my $req_id = Data::GUID->new->as_string;
        my $data = {
            op => "session",
            requestId => $req_id,
            data => {
                socketId => int(rand(9)) + 1,
            },
        };
        $requests->{ $req_id } = $data;
        print "Message sent(sess) " . scalar(localtime(time())) . ": " . Dumper($data);
        $connection->send(encode_json($data));

        # A proper low-level ping every 30s
        our $timer = AnyEvent->timer(after => 10, interval => 30, cb => sub {
            print "ping at " . scalar(localtime(time())) . "\n";
            $connection->send(
                AnyEvent::WebSocket::Message->new( opcode => 0x9, body => "Hello Server" )
            );
        });
    }
);

# This enters some kind of loop
AnyEvent->condvar->recv;

