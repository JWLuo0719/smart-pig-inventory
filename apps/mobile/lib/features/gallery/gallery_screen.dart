import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../local_activity/data/local_activity_repository.dart';
import 'server_gallery_screen.dart';
import 'local_evidence_screen.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = ref
        .watch(authControllerProvider)
        .valueOrNull
        ?.user
        .activeOrganizationId;
    return DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: '服务器照片'), Tab(text: '本机草稿')]),
          Expanded(
              child: TabBarView(children: [
            ServerGalleryScreen(key: ValueKey(organization)),
            const LocalGalleryScreen()
          ])),
        ]));
  }
}

class LocalGalleryScreen extends ConsumerWidget {
  const LocalGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<LocalCaptureActivity>>(
      stream: ref
          .watch(localActivityRepositoryProvider)
          .watchRecent(auth.user.activeOrganizationId),
      builder: (BuildContext context,
          AsyncSnapshot<List<LocalCaptureActivity>> snapshot) {
        final List<LocalCaptureActivity> rows =
            snapshot.data ?? const <LocalCaptureActivity>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: <Widget>[
            Text('本机证据图库', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('按最近更新时间查看原始证据和真实上传状态；服务器确认数量只在结果页显示。',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              const _EmptyState(message: '无法读取本机图库；没有删除或修改任何原始证据。')
            else if (rows.isEmpty)
              const _EmptyState(message: '当前组织尚未保存本机采集证据。')
            else
              ...rows.map((LocalCaptureActivity row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MediaRow(
                      activity: row,
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  LocalEvidenceScreen(activity: row))),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.activity, required this.onTap});

  final LocalCaptureActivity activity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (String status, Color color) = _status(activity);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.photo_library_outlined, color: color),
        ),
        title: Text('${activity.buildingLabel} · ${activity.penLabel}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${_date(context, activity.businessDate)} · '
          '${activity.mediaCount} 张 · ${_bytes(activity.totalBytes)}\n$status',
        ),
        isThreeLine: true,
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right, semanticLabel: '翻阅本机原图'),
      ),
    );
  }

  static (String, Color) _status(LocalCaptureActivity activity) =>
      switch (activity.outboxState) {
        null => ('本机草稿，尚未进入上传队列', AppColors.straw),
        'synced' => ('已提交服务器；点击翻阅原图或查看结果', AppColors.herdTeal),
        'blocked' => ('上传被服务器阻止；原图仍保留', AppColors.alert),
        'abandoned' => ('已停止重试；原图仍保留', AppColors.review),
        'retry_wait' => ('网络失败，等待自动重试', AppColors.review),
        'waiting_authentication' => ('等待重新登录后上传', AppColors.review),
        _ => ('等待或正在上传', AppColors.straw),
      };

  static String _date(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}
