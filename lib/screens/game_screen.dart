import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'matching_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  final String myName;
  const GameScreen({super.key, required this.roomId, required this.myName});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;
  bool _isStatsUpdated = false;

  Future<void> _updateStats(String winner) async {
    if (_isStatsUpdated) return;
    _isStatsUpdated = true;
    final myDoc = FirebaseFirestore.instance.collection('users').doc(myUid);
    try {
      if (winner == myUid) {
        await myDoc.update({'wins': FieldValue.increment(1)});
        await FirebaseFirestore.instance.collection('win_logs').add({
          'uid': myUid,
          'name': widget.myName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (winner == "draw") {
        await myDoc.update({'draws': FieldValue.increment(1)});
      } else {
        await myDoc.update({'losses': FieldValue.increment(1)});
      }
    } catch (_) {
      _isStatsUpdated = false;
    }
  }

  Future<void> _exit() async {
    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomId)
          .delete();
    } catch (_) {}
    if (mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MatchingScreen()),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("対戦中"),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .doc(widget.roomId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("対戦が終了しました"),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: _exit, child: const Text("ロビーへ戻る")),
                ],
              ),
            );
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final board = (data['board'] as List)
              .map((e) => (e as num).toInt())
              .toList();
          final turnUid = data['turn'];
          final players = data['players'];
          final opponentUid = players.firstWhere(
            (id) => id != myUid,
            orElse: () => "",
          );
          final opponentName = (data['names'] as Map?)?[opponentUid] ?? "相手";

          final String? winner = _checkWinner(board, players);
          if (winner != null && !_isStatsUpdated) _updateStats(winner);

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("🆚 $opponentName と対戦中"),
              const SizedBox(height: 10),
              Text(
                winner != null
                    ? (winner == "draw"
                          ? "引き分け！"
                          : (winner == myUid ? "🎉 勝ち！" : "💀 負け..."))
                    : (turnUid == myUid ? "🔥 あなたの番" : "💤 相手の番"),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              _buildBoard(board, turnUid == myUid && winner == null, players),
              const SizedBox(height: 30),
              if (winner != null)
                ElevatedButton(
                  onPressed: _exit,
                  child: const Text("結果を保存して戻る"),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<int> board, bool isMyTurn, List players) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: GridView.builder(
        padding: const EdgeInsets.all(25),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: 9,
        itemBuilder: (context, i) => GestureDetector(
          onTap: (isMyTurn && board[i] == 0)
              ? () {
                  List<int> next = List.from(board);
                  next[i] = players.indexOf(myUid) + 1;
                  FirebaseFirestore.instance
                      .collection('rooms')
                      .doc(widget.roomId)
                      .update({
                        'board': next,
                        'turn': players.firstWhere((id) => id != myUid),
                      });
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: isMyTurn && board[i] == 0
                  ? Colors.blue.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: board[i] == 1
                  ? const Icon(
                      Icons.panorama_fish_eye,
                      color: Colors.blue,
                      size: 50,
                    )
                  : (board[i] == 2
                        ? const Icon(Icons.close, color: Colors.red, size: 50)
                        : null),
            ),
          ),
        ),
      ),
    );
  }

  String? _checkWinner(List<int> b, List p) {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (var l in lines) {
      if (b[l[0]] != 0 && b[l[0]] == b[l[1]] && b[l[0]] == b[l[2]])
        return p[b[l[0]] - 1];
    }
    return !b.contains(0) ? "draw" : null;
  }
}
