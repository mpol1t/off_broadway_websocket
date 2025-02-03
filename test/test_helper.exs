ExUnit.start()

Mox.defmock(OffBroadwayWebSocket.MockClient, for: OffBroadwayWebSocket.ClientBehaviour)
Application.put_env(:off_broadway_websocket, :client, OffBroadwayWebSocket.MockClient)
