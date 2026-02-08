import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'まるばつオンライン',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP')],
      locale: const Locale('ja', 'JP'),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        textTheme: GoogleFonts.notoSansJpTextTheme(Theme.of(context).textTheme),
      ),
      home: const MatchingScreen(),
    );
  }
}

// --- 1. マッチング画面 ---
class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});
  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  User? _user;
  bool _isWaiting = false;
  int wins = 0, losses = 0, draws = 0;

  @override
  void initState() {
    super.initState();
    _loginAndListen();
  }

  Future<void> _loginAndListen() async {
    final userCredential = await _auth.signInAnonymously();
    if (!mounted) return;
    setState(() => _user = userCredential.user);

    _db.collection('users').doc(_user!.uid).snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (mounted) {
        setState(() {
          wins = data?['wins'] ?? 0;
          losses = data?['losses'] ?? 0;
          draws = data?['draws'] ?? 0;
        });
        final roomId = data?['currentRoomId'];
        if (_isWaiting && roomId != null) {
          setState(() => _isWaiting = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => GameScreen(roomId: roomId)),
          );
        }
      }
    });
  }

  Future<void> _startMatching() async {
    if (_user == null) return;
    setState(() => _isWaiting = true);

    // 以前の部屋情報をリセット
    await _db.collection('users').doc(_user!.uid).set({
      'currentRoomId': FieldValue.delete(),
    }, SetOptions(merge: true));

    // キューに追加
    await _db.collection('matchmaking_queue').doc(_user!.uid).set({
      'uid': _user!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "まるばつオンライン",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  const Text(
                    "あなたの戦績",
                    style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "$wins勝 / $losses敗 / $draws分",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
            _isWaiting
                ? const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text(
                        "対戦相手を探しています...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 60,
                        vertical: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _startMatching,
                    child: const Text(
                      "対戦を開始する",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// --- 2. ゲーム画面 ---
class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;
  bool _isStatsUpdated = false;

  // 【修正ポイント】更地の状態でもエラーにならないよう set(merge: true) を使用
  Future<void> _updateStats(String winner) async {
    if (_isStatsUpdated) return;
    setState(() => _isStatsUpdated = true);

    final myDoc = FirebaseFirestore.instance.collection('users').doc(myUid);
    Map<String, dynamic> updateData = {};

    if (winner == "draw") {
      updateData = {'draws': FieldValue.increment(1)};
    } else if (winner == myUid) {
      updateData = {'wins': FieldValue.increment(1)};
    } else {
      updateData = {'losses': FieldValue.increment(1)};
    }

    await myDoc.set(updateData, SetOptions(merge: true));
  }

  Future<void> _exit() async {
    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomId)
          .delete();
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MatchingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("対戦中"),
        leading: IconButton(
          icon: const Icon(Icons.exit_to_app),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MatchingScreen()),
          ),
        ),
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
                  const Text("対戦が終了しました", style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MatchingScreen(),
                      ),
                    ),
                    child: const Text("ロビーへ戻る"),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List<int> board = (data['board'] as List)
              .map((e) => (e as num).toInt())
              .toList();
          final String turnUid = data['turn'];
          final List<dynamic> players = data['players'];
          final String? winner = _checkWinner(board, players);
          final bool isMyTurn = (turnUid == myUid);

          if (winner != null && !_isStatsUpdated) {
            _updateStats(winner);
          }

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                winner != null
                    ? (winner == "draw"
                          ? "引き分け！"
                          : (winner == myUid ? "🎉 あなたの勝ち！" : "💀 相手の勝ち..."))
                    : (isMyTurn ? "🔥 あなたの番です" : "💤 相手の番です"),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              AspectRatio(
                aspectRatio: 1.0,
                child: GridView.builder(
                  padding: const EdgeInsets.all(25),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: 9,
                  itemBuilder: (context, index) {
                    final val = board[index];
                    return GestureDetector(
                      onTap: (isMyTurn && val == 0 && winner == null)
                          ? () => _onTapTile(index, board, players)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isMyTurn && val == 0
                              ? Colors.blue.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isMyTurn && val == 0
                                ? Colors.blue.shade200
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Center(child: _buildMark(val)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),
              if (winner != null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  onPressed: _exit,
                  child: const Text(
                    "結果を保存して戻る",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onTapTile(
    int index,
    List<int> currentBoard,
    List<dynamic> players,
  ) async {
    List<int> nextBoard = List<int>.from(currentBoard);
    nextBoard[index] = players.indexOf(myUid) + 1;
    final opponentUid = players.firstWhere((id) => id != myUid);
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .update({
          'board': nextBoard,
          'turn': opponentUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Widget _buildMark(int value) {
    if (value == 1)
      return const Icon(Icons.panorama_fish_eye, size: 55, color: Colors.blue);
    if (value == 2) return const Icon(Icons.close, size: 55, color: Colors.red);
    return const SizedBox();
  }

  String? _checkWinner(List<int> board, List<dynamic> players) {
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
    for (var line in lines) {
      if (board[line[0]] != 0 &&
          board[line[0]] == board[line[1]] &&
          board[line[0]] == board[line[2]]) {
        return players[board[line[0]] - 1];
      }
    }
    return !board.contains(0) ? "draw" : null;
  }
}
