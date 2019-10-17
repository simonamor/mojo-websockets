## WebSocket demo

This program is supposed to:

1. Accept a connection from websocket-client.pl at /link
2. Upgrade that connection to a websocket
3. Accept a standard HTTP request to /send
4. Send a message to the websocket client
5. Wait for a response from the websocket client
6. Send a response back to the HTTP client

The server needs to be able to handle multiple connections of each type (both HTTP and websocket), and route the messages to the right websocket.


