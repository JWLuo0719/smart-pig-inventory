import 'package:dio/dio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../shared/widgets/local_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_browse_api.dart';
import '../master_data/data/drift_master_data_repository.dart';
import '../master_data/domain/master_data_changes.dart';

class ServerGalleryScreen extends ConsumerStatefulWidget {
  const ServerGalleryScreen({this.sessionId, super.key});
  final String? sessionId;
  @override
  ConsumerState<ServerGalleryScreen> createState() =>
      _ServerGalleryScreenState();
}

class _ServerGalleryScreenState extends ConsumerState<ServerGalleryScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String? _penId;
  List<LibraryMedia> _media = [];
  String? _error;
  bool _loading = true, _busy = false, _more = false;
  int _generation = 0;
  final Map<String, String> _deleteKeys = {};
  InventoryBrowseApi get _api =>
      InventoryBrowseApi(ref.read(apiBaseUrlProvider));
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T> _request<T>(Future<T> Function(String) request) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      throw StateError('离线时请使用本机图库，联网后可读取服务器照片。');
    }
    return retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: request);
  }

  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    final offset = append ? _media.length : 0;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _media = [];
    });
    try {
      final rows = await _request((token) => widget.sessionId == null
          ? _api.media(token, _date, penId: _penId, offset: offset)
          : _api.sessionMedia(token, widget.sessionId!));
      if (mounted && generation == _generation) {
        setState(() {
          _media = append ? [..._media, ...rows] : rows;
          _more = widget.sessionId == null && rows.length == 50;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final next = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (next != null && mounted) {
      setState(() => _date = next);
      await _load();
    }
  }

  Future<void> _preview(LibraryMedia item) async {
    setState(() => _busy = true);
    try {
      if (item.contentType == 'video/mp4') {
        final directory = await Directory(
                '${(await getTemporaryDirectory()).path}/video-preview')
            .create(recursive: true);
        final file = File('${directory.path}/${const Uuid().v4()}.mp4');
        try {
          await _request(
              (token) => _api.download(token, item.assetId, file.path));
          if (!mounted) return;
          await showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                      child: Scaffold(
                    appBar: AppBar(title: const Text('视频证据 · 人工复核')),
                    body: Center(child: LocalVideoPlayer(file: file)),
                  )));
        } finally {
          // Only this temporary playback copy is removed; original evidence stays intact.
          if (await file.exists()) await file.delete();
        }
        return;
      }
      final bytes =
          await _request((token) => _api.content(token, item.assetId));
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => Dialog.fullscreen(
                  child: Scaffold(
                appBar: AppBar(
                    title: Text(
                        '${item.buildingCode} / ${item.penCode} · ${item.position}')),
                body: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 8,
                    child: Center(
                        child: Image.memory(bytes,
                            errorBuilder: (_, __, ___) =>
                                const Text('当前设备不能预览此媒体格式。')))),
              )));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(LibraryMedia item) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('删除上传错误的照片？'),
              content: const Text('服务器将标记删除并保留审计。本机原图保留，此采集会话不能再确认，需重新采集。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除错图'))
              ],
            ));
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final key =
          _deleteKeys.putIfAbsent(item.assetId, () => const Uuid().v4());
      await _request((token) => _api.delete(token, item.assetId, key));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    return ListView(
        shrinkWrap: widget.sessionId != null,
        physics: widget.sessionId == null
            ? null
            : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text('栏舍照片库', style: Theme.of(context).textTheme.headlineSmall),
          const Text('按日期查询服务器证据；已确认照片锁定，只能由管理员在后台处理。'),
          if (widget.sessionId == null)
            TextButton(
                onPressed: _loading || _busy ? null : _pickDate,
                child: Text(
                    '日期：${MaterialLocalizations.of(context).formatMediumDate(_date)}')),
          if (widget.sessionId == null)
            StreamBuilder<List<PenChoice>>(
                stream: ref
                    .watch(masterDataRepositoryProvider)
                    .watchPens(auth.user.activeOrganizationId),
                builder: (context, snapshot) => DropdownButtonFormField<String>(
                      initialValue: _penId ?? '',
                      decoration: const InputDecoration(labelText: '栏舍'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部栏舍')),
                        ...?snapshot.data?.map((p) => DropdownMenuItem(
                            value: p.penId,
                            child: Text(
                                '${p.buildingCode} / ${p.penCode} · ${p.penName}',
                                overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: _loading || _busy
                          ? null
                          : (value) {
                              setState(
                                  () => _penId = value == '' ? null : value);
                              _load();
                            },
                    )),
          OutlinedButton(
              onPressed: _loading || _busy ? null : () => _load(),
              child: const Text('刷新照片')),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_loading || _busy) const LinearProgressIndicator(),
          if (!_loading && _error == null && _media.isEmpty)
            const Text('所选日期和栏舍没有上传照片。'),
          ..._media.map((item) => Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${item.buildingCode} / ${item.penCode} · ${item.position}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(item.deleted
                            ? '已删除 · 审计保留'
                            : item.locked
                                ? '盘点已确认 · 原图锁定'
                                : '未确认 · 可复核'),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: _busy || item.deleted
                                  ? null
                                  : () => _preview(item),
                              child: const Text('翻阅原图')),
                          if (widget.sessionId == null)
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => context.push(
                                        '/inventory-sessions/${item.sessionId}'),
                                child: const Text('查看盘点')),
                          if (!item.locked && !item.deleted)
                            TextButton(
                                onPressed: _busy ? null : () => _delete(item),
                                child: const Text('删除错图')),
                        ]),
                      ])))),
          if (_more && _media.length < 10000)
            OutlinedButton(
                onPressed: _loading || _busy ? null : () => _load(append: true),
                child: const Text('加载更多')),
        ]);
  }

  String _message(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is DioException && error.response?.statusCode == 409) {
      return '照片状态已变化或已锁定，请刷新；已确认证据需管理员处理。';
    }
    return '操作未完成，请联网后重试；未清除本机原图。';
  }
}
