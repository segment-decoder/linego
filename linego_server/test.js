// test_server.js
const WebSocket = require("ws");

// 8080 포트에서 서버 실행
const wss = new WebSocket.Server({ port: 8080 });

console.log("✅ 서버 실행 중: ws://localhost:8080");

// 클라이언트 연결 이벤트
wss.on("connection", (ws) => {
  console.log("📌 클라이언트 연결됨");

  // 메시지 받았을 때
  ws.on("message", (msg) => {
    console.log("클라이언트:", msg.toString());

    // 받은 메시지를 다시 클라이언트에게 돌려줌 (Echo)
    ws.send("서버가 받음: " + msg.toString());
  });

  // 연결 종료
  ws.on("close", () => {
    console.log("❌ 클라이언트 연결 종료");
  });
});
