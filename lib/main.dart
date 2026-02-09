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

class _MatchingScreenState extends State<MatchingScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  late TabController _tabController;
  User? _user;
  bool _isWaiting = false;
  int wins = 0, losses = 0, draws = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // 累計、今月、今日の3タブ
    _loginAndListen();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loginAndListen() async {
    final userCredential = await _auth.signInAnonymously();
    if (!mounted) return;
    setState(() => _user = userCredential.user);

    final userDoc = _db.collection('users').doc(_user!.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      await userDoc.set({
        'name': '名無しさん',
        'wins': 0,
        'losses': 0,
        'draws': 0,
      }, SetOptions(merge: true));
      _nameController.text = '名無しさん';
    } else {
      _nameController.text = docSnapshot.data()?['name'] ?? '名無しさん';
    }

    _db.collection('users').doc(_user!.uid).snapshots().listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
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
          MaterialPageRoute(
            builder: (context) =>
                GameScreen(roomId: roomId, myName: _nameController.text),
          ),
        );
      }
    });
  }

  Future<void> _startMatching() async {
    if (_user == null) return;
    setState(() => _isWaiting = true);
    await _db.collection('users').doc(_user!.uid).set({
      'currentRoomId': FieldValue.delete(),
    }, SetOptions(merge: true));
    await _db.collection('matchmaking_queue').doc(_user!.uid).set({
      'uid': _user!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 期間別ランキングを表示するウィジェット
  Widget _buildRankingList(Query query) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        // データの集計 (ユーザーごとの勝利数をカウント)
        Map<String, Map<String, dynamic>> agg = {};
        for (var doc in snapshot.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final uid = d['uid'];
          if (!agg.containsKey(uid)) {
            agg[uid] = {'name': d['name'] ?? '名無しさん', 'count': 0};
          }
          agg[uid]!['count'] = (agg[uid]!['count'] as int) + 1;
        }

        // カウント順にソート
        var sorted = agg.values.toList();
        sorted.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
        final top5 = sorted.take(5).toList();

        if (top5.isEmpty) return const Center(child: Text("まだデータがありません"));

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top5.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final p = top5[index];
            return ListTile(
              leading: Text(
                "${index + 1}位",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              title: Text(p['name']),
              trailing: Text(
                "${p['count']} 勝",
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(now.year, now.month, 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "まるばつオンライン",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 戦績エリア
            Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  const Text(
                    "累計戦績",
                    style: TextStyle(fontSize: 14, color: Colors.blueGrey),
                  ),
                  Text(
                    "$wins勝 / $losses敗 / $draws分",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: TextField(
                controller: _nameController,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: "表示名",
                  prefixIcon: Icon(Icons.edit),
                ),
                onChanged: (val) async {
                  if (val.trim().isNotEmpty)
                    await _db.collection('users').doc(_user!.uid).update({
                      'name': val.trim(),
                    });
                },
              ),
            ),
            const SizedBox(height: 25),
            _isWaiting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 50,
                        vertical: 15,
                      ),
                    ),
                    onPressed: _startMatching,
                    child: const Text(
                      "対戦を開始する",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
            const SizedBox(height: 30),

            // ランキングセクション
            const Text(
              "🏆 ランキング",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: "今日"),
                Tab(text: "今月"),
                Tab(text: "累計"),
              ],
            ),
            SizedBox(
              height: 350,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 今日のランキング
                  _buildRankingList(
                    _db
                        .collection('win_logs')
                        .where(
                          'createdAt',
                          isGreaterThanOrEqualTo: startOfToday,
                        ),
                  ),
                  // 今月のランキング
                  _buildRankingList(
                    _db
                        .collection('win_logs')
                        .where(
                          'createdAt',
                          isGreaterThanOrEqualTo: startOfMonth,
                        ),
                  ),
                  // 累計ランキング (usersコレクションから直接取得)
                  StreamBuilder<QuerySnapshot>(
                    stream: _db
                        .collection('users')
                        .orderBy('wins', descending: true)
                        .limit(5)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final docs = snapshot.data!.docs;
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          return ListTile(
                            leading: Text("${i + 1}位"),
                            title: Text(d['name'] ?? '名無し'),
                            trailing: Text("${d['wins']} 勝"),
                          );
                        },
                      );
                    },
                  ),
                ],
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
  final String myName; // ログ保存用に自分の名前を受け取る
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
        // 累計勝利数を加算
        await myDoc.update({'wins': FieldValue.increment(1)});
        // 【追加】勝利ログを記録
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
      debugPrint("DEBUG: 戦績とログの保存に成功しました！");
    } catch (e) {
      debugPrint("DEBUG: 保存失敗: $e");
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
          final names = data['names'] as Map<String, dynamic>?;
          final opponentUid = players.firstWhere(
            (id) => id != myUid,
            orElse: () => "",
          );
          final opponentName = names?[opponentUid] ?? "対戦相手";

          final String? winner = _checkWinner(board, players);
          if (winner != null && !_isStatsUpdated) _updateStats(winner);

          final bool isMyTurn = (turnUid == myUid);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "🆚 $opponentName と対戦中",
                style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
              ),
              const SizedBox(height: 10),
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
                  child: const Text("結果を保存して戻る"),
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

  Widget _buildMark(int value) => value == 1
      ? const Icon(Icons.panorama_fish_eye, size: 55, color: Colors.blue)
      : (value == 2
            ? const Icon(Icons.close, size: 55, color: Colors.red)
            : const SizedBox());

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
          board[line[0]] == board[line[2]])
        return players[board[line[0]] - 1];
    }
    return !board.contains(0) ? "draw" : null;
  }
}
