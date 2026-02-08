import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/match_service.dart';
import 'game_room_page.dart';

class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  String status = '未接続';
  StreamSubscription? _matchSub;
  Timer? _timeoutTimer;
  bool _navigated = false;

  static const matchTimeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _login();
  }

  Future<void> _login() async {
    await AuthService.signInAnonymously();
    setState(() {
      status = 'ログイン完了';
    });
  }

  Future<void> _startMatch() async {
    setState(() {
      status = 'マッチング中...';
    });

    _navigated = false;

    // ★ マッチ成立監視
    _matchSub = MatchService.matchStream().listen((snapshot) {
      if (snapshot.docs.isNotEmpty && !_navigated) {
        _navigated = true;

        _timeoutTimer?.cancel();
        _matchSub?.cancel();

        final matchId = snapshot.docs.first.id;

        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GameRoomPage(matchId: matchId)),
        );
      }
    });

    // ★ タイムアウト処理
    _timeoutTimer = Timer(matchTimeout, () async {
      if (_navigated) return;

      await MatchService.leaveWaiting();

      if (mounted) {
        setState(() {
          status = '相手が見つかりませんでした';
        });
      }
    });

    await MatchService.startMatching();
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('オンラインマッチング')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(status),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startMatch,
              child: const Text('マッチング開始'),
            ),
          ],
        ),
      ),
    );
  }
}
