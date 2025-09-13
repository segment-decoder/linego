// server.js

// 1. 필요한 모듈 가져오기
import { WebSocketServer } from 'ws';
import { v4 as uuidv4 } from 'uuid'; // 플레이어 ID 생성을 위한 라이브러리 (npm install uuid)

// 2. 서버 설정
const PORT = 8080;
const wss = new WebSocketServer({ port: PORT });

// 3. 매칭 관련 변수
let waitingQueue = []; // 매칭을 기다리는 플레이어들을 담을 대기열(큐)

// 4. WebSocket 서버 로직
wss.on('connection', (ws) => {
    // 새로운 클라이언트가 접속했을 때 실행될 코드

    // A. 플레이어에게 고유 ID 부여
    ws.playerId = uuidv4();
    console.log(`[Server] Player ${ws.playerId} connected.`);

    // B. 클라이언트로부터 메시지를 받았을 때 실행될 코드
    ws.on('message', (message) => {
        const parsedMessage = JSON.parse(message);

        // 'joinQueue' 타입의 메시지만 처리
        if (parsedMessage.type === 'joinQueue') {
            console.log(`[Server] Player ${ws.playerId} joined the queue.`);
            
            // 플레이어 정보를 대기열에 추가
            ws.playerName = parsedMessage.data.playerName;
            waitingQueue.push(ws);

            // C. 매칭 성사 로직
            if (waitingQueue.length >= 2) {
                console.log('[Server] Match found! Starting a game...');

                // 대기열에서 2명(선공, 후공)을 순서대로 꺼냄
                const player1 = waitingQueue.shift();
                const player2 = waitingQueue.shift();
                
                // 게임 룸 정보 생성 (추후 확장 가능)
                const gameId = `game_${uuidv4()}`;

                // Player 1 (선공) 에게 매칭 정보 전송
                player1.send(JSON.stringify({
                    type: 'matchFound',
                    data: {
                        gameId: gameId,
                        opponentName: player2.playerName,
                        myTurn: true // 선공
                    }
                }));

                // Player 2 (후공) 에게 매칭 정보 전송
                player2.send(JSON.stringify({
                    type: 'matchFound',
                    data: {
                        gameId: gameId,
                        opponentName: player1.playerName,
                        myTurn: false // 후공
                    }
                }));

                console.log(`[Server] Game ${gameId} started between ${player1.playerId} and ${player2.playerId}.`);
            }
        }
    });

    // D. 클라이언트 접속이 끊어졌을 때 실행될 코드
    ws.on('close', () => {
        console.log(`[Server] Player ${ws.playerId} disconnected.`);
        // 만약 플레이어가 대기열에 있었다면, 대기열에서 제거
        waitingQueue = waitingQueue.filter(player => player !== ws);
    });
});

console.log(`WebSocket server is running on ws://localhost:${PORT}`);