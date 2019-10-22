## WebSocket demo

This program is supposed to:

1. Accept a connection from websocket-client.pl at /link
2. Upgrade that connection to a websocket
3. Accept a standard HTTP request to /send
4. Send a message to the websocket client
5. Wait for a response from the websocket client
6. Send a response back to the HTTP client

The server needs to be able to handle multiple connections of each type (both HTTP and websocket), and route the messages to the right websocket. You need 3 terminal windows to try this demo as the first 2 commands (term1/term2) don't exit but continue to output debug messages.

```
term1 $ ./start-ws.sh

term2 $ perl websocket-client.pl
```

Look for the first message sent

```
  'data' => {
              'socketId' => 3
            },
  'requestId' => '886B4AAA-F4AF-11E9-94CC-1447B192773D',
  'op' => 'session'
```

The socketId value should be used in the send command below in place of $I

```
term3 $ ./send.sh $I
```

If all went well, the output from the send command should take 2 seconds to appear and should include the 'rnd' value in a json formatted string.
For some reason, the server doesn't wait for the response before it returns output to the `send.sh` client so we end up with "Ok - null" instead.

