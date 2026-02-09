import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/ranking_list.dart';
import 'game_screen.dart';

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
    _tabController = TabController(length: 3, vsync: this);
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
            _buildStatCard(),
            const SizedBox(height: 15),
            _buildNameField(),
            const SizedBox(height: 25),
            _buildMatchButton(),
            const SizedBox(height: 30),
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
                  RankingList(
                    myUid: _user?.uid,
                    query: _db
                        .collection('win_logs')
                        .where(
                          'createdAt',
                          isGreaterThanOrEqualTo: DateTime(
                            now.year,
                            now.month,
                            now.day,
                          ),
                        ),
                  ),
                  RankingList(
                    myUid: _user?.uid,
                    query: _db
                        .collection('win_logs')
                        .where(
                          'createdAt',
                          isGreaterThanOrEqualTo: DateTime(
                            now.year,
                            now.month,
                            1,
                          ),
                        ),
                  ),
                  RankingList(
                    myUid: _user?.uid,
                    query: _db
                        .collection('users')
                        .orderBy('wins', descending: true)
                        .limit(5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard() {
    return Container(
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
    );
  }

  Widget _buildNameField() {
    return Padding(
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
    );
  }

  Widget _buildMatchButton() {
    return _isWaiting
        ? const CircularProgressIndicator()
        : ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
            ),
            onPressed: _startMatching,
            child: const Text("対戦を開始する", style: TextStyle(fontSize: 18)),
          );
  }
}
