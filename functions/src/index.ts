import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";

// リージョンを東京に固定
setGlobalOptions({ region: "asia-northeast1" });
admin.initializeApp();

export const matchmaker = onDocumentCreated("matchmaking_queue/{uid}", async (event) => {
    const db = admin.firestore();
    const queueRef = db.collection("matchmaking_queue");

    // 1. 待機ユーザーを先着2名取得
    const snapshot = await queueRef
        .orderBy("createdAt", "asc")
        .limit(2)
        .get();

    // 二人揃うまで待機
    if (snapshot.size < 2) {
        console.log("二人目の参加を待機中...");
        return; 
    }

    const user1 = snapshot.docs[0].data();
    const user2 = snapshot.docs[1].data();
    const uids = [user1.uid, user2.uid];

    console.log(`マッチング成立: ${uids[0]} vs ${uids[1]}`);

    // 2. 先攻・後攻をランダムに入れ替え
    const shuffledUids = [...uids].sort(() => Math.random() - 0.5);

    // 3. 部屋を作成
    const roomRef = db.collection("rooms").doc();
    await roomRef.set({
        roomId: roomRef.id,
        players: shuffledUids,
        turn: shuffledUids[0],
        board: Array(9).fill(0),
        status: "playing",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. 各ユーザーに部屋IDを通知し、キューから削除
    const batch = db.batch();
    uids.forEach(uid => {
        batch.update(db.collection("users").doc(uid), { currentRoomId: roomRef.id });
        batch.delete(queueRef.doc(uid));
    });

    await batch.commit();
    console.log(`部屋 ${roomRef.id} を作成しました。`);
});