import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RankingList extends StatelessWidget {
  final Query query;
  final String? myUid;

  const RankingList({super.key, required this.query, this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        // win_logsの場合は集計、usersの場合はそのままリスト化
        List<Map<String, dynamic>> players = [];

        if (snapshot.data!.docs.isNotEmpty &&
            snapshot.data!.docs.first.reference.parent.id == 'win_logs') {
          // 集計ロジック
          Map<String, Map<String, dynamic>> agg = {};
          for (var doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final uid = d['uid'];
            if (!agg.containsKey(uid)) {
              agg[uid] = {'uid': uid, 'name': d['name'] ?? '名無しさん', 'count': 0};
            }
            agg[uid]!['count'] = (agg[uid]!['count'] as int) + 1;
          }
          players = agg.values.toList();
          players.sort(
            (a, b) => (b['count'] as int).compareTo(a['count'] as int),
          );
        } else {
          // 累計ランキング
          players = snapshot.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return {
              'uid': doc.id,
              'name': d['name'] ?? '名無しさん',
              'count': d['wins'] ?? 0,
            };
          }).toList();
        }

        final displayList = players.take(5).toList();
        if (displayList.isEmpty) return const Center(child: Text("データがありません"));

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayList.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final p = displayList[index];
            final bool isMe = (p['uid'] == myUid);

            return ListTile(
              tileColor: isMe ? Colors.yellow.withOpacity(0.15) : null,
              leading: Text(
                "${index + 1}位",
                style: TextStyle(
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              title: Text(
                isMe ? "${p['name']} (あなた)" : p['name'],
                style: TextStyle(
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                ),
              ),
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
}
