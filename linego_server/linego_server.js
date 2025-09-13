const WebSocket = require("ws");
const wss = new WebSocket.Server({ port: 8080 });

let waitingPlayer = null;
let rooms = {};

// 메시지 처리
function handleFindMatch(ws)
{
  if (!waitingPlayer)
    {
        waitingPlayer = ws;
        send(ws, { type: "waiting" });
        return;
    }
  createRoom(waitingPlayer, ws);
  waitingPlayer = null;
}

// 방 생성
function createRoom(p1, p2)
{
  const roomId = Date.now();
  rooms[roomId] = [p1, p2];

  send(p1, { type: "matched", roomId, playerId: 1 });
  send(p2, { type: "matched", roomId, playerId: 2 });
}

// JSON 메시지 전송
function send(ws, data)
{
  ws.send(JSON.stringify(data));
}

// 연결 이벤트
wss.on("connection", (ws) =>
  {
    console.log("✅ 클라이언트 접속");
        
    ws.on("message", (msg) =>
      {
        const data = JSON.parse(msg);
        if (data.type === "find_match") handleFindMatch(ws);
      });
    ws.on("close", () =>
      {
        if (waitingPlayer === ws)
        waitingPlayer = null;
      });
  });
