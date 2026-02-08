import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GameRoomPage extends StatelessWidget {
  final String matchId;

  const GameRoomPage({super.key, required this.matchId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('ゲームルーム')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('matches')
            .doc(matchId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data()!;
          final player1 = data['player1'] as String;
          final player2 = data['player2'] as String;

          final isPlayer1 = uid == player1;
          final opponentUid = isPlayer1 ? player2 : player1;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉 マッチ成立！', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 24),

                Text('あなた', style: const TextStyle(fontSize: 18)),
                Text(
                  uid,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                const Text('相手', style: TextStyle(fontSize: 18)),
                Text(
                  opponentUid,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
