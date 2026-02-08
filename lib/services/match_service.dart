import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MatchService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// マッチング開始
  static Future<void> startMatching() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final waitingRef = _firestore.collection('waiting_rooms');

    await _firestore.runTransaction((tx) async {
      // waiting 状態のユーザーのみ取得
      final query = await waitingRef
          .where('status', isEqualTo: 'waiting')
          .orderBy('createdAt')
          .limit(5)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? opponent;

      // 自分以外を探す
      for (final doc in query.docs) {
        if (doc.id != uid) {
          opponent = doc;
          break;
        }
      }

      if (opponent != null) {
        final opponentUid = opponent['uid'] as String;
        final matchRef = _firestore.collection('matches').doc();

        // 相手を matched 状態にする（同時マッチ防止）
        tx.update(opponent.reference, {'status': 'matched'});

        // 自分の waiting があれば削除
        tx.delete(waitingRef.doc(uid));

        // matches 作成
        tx.set(matchRef, {
          'player1': uid,
          'player2': opponentUid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // user_matches（自分）
        tx.set(
          _firestore
              .collection('user_matches')
              .doc(uid)
              .collection('items')
              .doc(matchRef.id),
          {'matchId': matchRef.id, 'createdAt': FieldValue.serverTimestamp()},
        );

        // user_matches（相手）
        tx.set(
          _firestore
              .collection('user_matches')
              .doc(opponentUid)
              .collection('items')
              .doc(matchRef.id),
          {'matchId': matchRef.id, 'createdAt': FieldValue.serverTimestamp()},
        );
      } else {
        // 相手がいない場合は waiting 登録
        tx.set(waitingRef.doc(uid), {
          'uid': uid,
          'status': 'waiting',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// マッチ成立監視（MatchPage で使用）
  static Stream<QuerySnapshot<Map<String, dynamic>>> matchStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return _firestore
        .collection('user_matches')
        .doc(uid)
        .collection('items')
        .limit(1)
        .snapshots();
  }

  /// waiting_rooms から離脱（タイムアウト / キャンセル用）
  static Future<void> leaveWaiting() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _firestore.collection('waiting_rooms').doc(uid).delete();
  }
}
