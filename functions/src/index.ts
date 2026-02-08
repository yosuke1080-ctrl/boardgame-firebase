import { onDocumentCreated } from "firebase-functions/v2/firestore";
// 【追加】setGlobalOptions をインポート
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// 【追加】リージョンを東京に固定
setGlobalOptions({ region: "asia-northeast1" });

// マッチングを処理する関数 (Cloud Functions v2)
export const matchmaker = onDocumentCreated("matchmaking_queue/{docId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    // 1. 待機中のユーザーを古い順に2人取得
    const queueSnapshot = await db.collection("matchmaking_queue")
        .orderBy("createdAt", "asc")
        .limit(2)
        .get();

    if (queueSnapshot.size < 2) {
        console.log("対戦相手を待機中です...");
        return;
    }

    const [user1Doc, user2Doc] = queueSnapshot.docs;
    const user1 = user1Doc.data();
    const user2 = user2Doc.data();

    // 2. ユーザー情報の詳細（名前）を取得
    const user1Profile = await db.collection("users").doc(user1.uid).get();
    const user2Profile = await db.collection("users").doc(user2.uid).get();

    const name1 = user1Profile.data()?.name || "名無しさん";
    const name2 = user2Profile.data()?.name || "名無しさん";

    // 3. 部屋を作成
    const shuffledUids = [user1.uid, user2.uid].sort(() => Math.random() - 0.5);
    const roomRef = db.collection("rooms").doc();
    const roomId = roomRef.id;

    await roomRef.set({
        roomId: roomId,
        players: shuffledUids,
        names: {
            [user1.uid]: name1,
            [user2.uid]: name2,
        },
        turn: shuffledUids[0],
        board: Array(9).fill(0),
        status: "playing",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. 各ユーザーに部屋IDを通知
    const batch = db.batch();
    batch.update(db.collection("users").doc(user1.uid), { currentRoomId: roomId });
    batch.update(db.collection("users").doc(user2.uid), { currentRoomId: roomId });

    // 5. キューから削除
    batch.delete(user1Doc.ref);
    batch.delete(user2Doc.ref);

    await batch.commit();
    console.log(`マッチング成立！ 東京リージョンで実行中: ${roomId} (${name1} vs ${name2})`);
});