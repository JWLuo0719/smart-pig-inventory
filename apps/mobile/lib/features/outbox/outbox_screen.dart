import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';

class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(appDatabaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('上传队列')),
      body: StreamBuilder(
        stream: database.watchOutbox(),
        builder: (BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
          final List<dynamic> rows = snapshot.data ?? <dynamic>[];
          if (rows.isEmpty) return const Center(child: Text('没有待上传的采集包'));
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final dynamic row = rows[index];
              return ListTile(title: Text(row.packageId as String), subtitle: Text(row.state as String));
            },
          );
        },
      ),
    );
  }
}

