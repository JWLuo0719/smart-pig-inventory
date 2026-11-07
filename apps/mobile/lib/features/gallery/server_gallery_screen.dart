import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../shared/widgets/local_video_player.dart';
import '../../shared/evidence_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_browse_api.dart';
import '../master_data/data/drift_master_data_repository.dart';
import '../master_data/domain/master_data_changes.dart';
import 'application/thumbnail_request_queue.dart';

final serverGalleryApiProvider = Provider<InventoryBrowseApi>(
  (ref) => InventoryBrowseApi(ref.watch(apiBaseUrlProvider)),
);

class ServerGalleryScreen extends ConsumerStatefulWidget {
  const ServerGalleryScreen(
      {this.sessionId, this.showHeader = true, super.key});
  final String? sessionId;
  final bool showHeader;
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
  int _thumbnailGeneration = 0;
  ThumbnailRequestQueue _thumbnailRequests = ThumbnailRequestQueue();
  final Map<String, String> _deleteKeys = {};
  InventoryBrowseApi get _api => ref.read(serverGalleryApiProvider);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ServerGalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) _load();
  }

  @override
  void dispose() {
    _thumbnailRequests.dispose();
    super.dispose();
  }

  bool _sameIdentity(AuthState? expected) {
    if (!mounted || expected == null) return false;
    final current = ref.read(authControllerProvider).valueOrNull;
    return current?.user.subjectId == expected.user.subjectId &&
        current?.user.activeOrganizationId ==
            expected.user.activeOrganizationId &&
        current?.isOffline == false;
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
    if (!append) {
      _thumbnailGeneration++;
      _thumbnailRequests.dispose();
      _thumbnailRequests = ThumbnailRequestQueue();
    }
    final auth = ref.read(authControllerProvider).valueOrNull;
    final date = _date, penId = _penId, sessionId = widget.sessionId;
    final offset = append ? _media.length : 0;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _media = [];
    });
    try {
      final rows = await _request((token) => sessionId == null
          ? _api.media(token, date, penId: penId, offset: offset)
          : _api.sessionMedia(token, sessionId));
      if (_sameIdentity(auth) && generation == _generation) {
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
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (!_sameIdentity(auth)) return;
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
          if (!mounted || !_sameIdentity(auth)) return;
          await showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                  child: _identityBoundPreview(
                      auth!,
                      Scaffold(
                        appBar: AppBar(title: const Text('视频证据 · 人工复核')),
                        body: Center(child: LocalVideoPlayer(file: file)),
                      ))));
        } finally {
          // Only this temporary playback copy is removed; original evidence stays intact.
          if (await file.exists()) await file.delete();
        }
        return;
      }
      final bytes =
          await _request((token) => _api.content(token, item.assetId));
      if (!mounted || !_sameIdentity(auth)) return;
      await showDialog<void>(
          context: context,
          builder: (context) => Dialog.fullscreen(
              child: _identityBoundPreview(
                  auth!,
                  Scaffold(
                    appBar: AppBar(
                        title: Text(
                            '${item.buildingCode} / ${item.penCode} · ${evidencePositionLabel(item.position)}')),
                    body: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 8,
                        child: Center(
                            child: Image.memory(bytes,
                                errorBuilder: (_, __, ___) =>
                                    const Text('当前设备不能预览此媒体格式。')))),
                  ))));
    } catch (error) {
      if (_sameIdentity(auth)) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(LibraryMedia item) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
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
    if (accepted != true || !_sameIdentity(auth)) return;
    setState(() => _busy = true);
    try {
      final key =
          _deleteKeys.putIfAbsent(item.assetId, () => const Uuid().v4());
      await _request((token) => _api.delete(token, item.assetId, key));
      if (_sameIdentity(auth)) await _load();
    } catch (error) {
      if (_sameIdentity(auth)) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.valueOrNull, after = next.valueOrNull;
      if (before?.user.subjectId != after?.user.subjectId ||
          before?.user.activeOrganizationId !=
              after?.user.activeOrganizationId ||
          before?.isOffline != after?.isOffline) {
        _penId = null;
        _deleteKeys.clear();
        _load();
      }
    });
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    // Pagination extends this logical query; refresh/filter/identity changes
    // create a new thumbnail scope and discard all queued work from the old one.
    final thumbnailGeneration = _thumbnailGeneration;
    return ListView(
        shrinkWrap: widget.sessionId != null,
        physics: widget.sessionId == null
            ? null
            : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.showHeader) ...[
            Text('栏舍照片库', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('按日期查询服务器证据；已确认照片锁定，只能由管理员在后台处理。'),
            const SizedBox(height: 12),
          ],
          if (widget.sessionId == null)
            TextButton(
                onPressed: _loading || _busy ? null : _pickDate,
                child: Text(
                    '日期：${MaterialLocalizations.of(context).formatMediumDate(_date)}')),
          if (widget.sessionId == null)
            StreamBuilder<List<PenChoice>>(
                key: ValueKey(auth.user.activeOrganizationId),
                stream: ref
                    .watch(masterDataRepositoryProvider)
                    .watchPens(auth.user.activeOrganizationId),
                builder: (context, snapshot) => DropdownButtonFormField<String>(
                      key:
                          ValueKey('${auth.user.activeOrganizationId}/$_penId'),
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
                        if (!item.deleted)
                          _ServerThumbnail(
                              key: ValueKey(
                                  '${auth.user.subjectId}/${auth.user.activeOrganizationId}/$thumbnailGeneration/${item.assetId}'),
                              media: item,
                              queue: _thumbnailRequests,
                              isQueryCurrent: () =>
                                  mounted &&
                                  thumbnailGeneration == _thumbnailGeneration &&
                                  _sameIdentity(auth),
                              onOpen: _busy ? null : () => _preview(item)),
                        Text(
                            '${item.buildingCode} / ${item.penCode} · ${evidencePositionLabel(item.position)}',
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

  Widget _identityBoundPreview(AuthState owner, Widget child) =>
      Consumer(builder: (context, ref, _) {
        final current = ref.watch(authControllerProvider).valueOrNull;
        return current?.user.subjectId == owner.user.subjectId &&
                current?.user.activeOrganizationId ==
                    owner.user.activeOrganizationId
            ? child
            : const Scaffold(body: Center(child: Text('账号已变化，请重新打开当前组织证据。')));
      });

  String _message(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is DioException && error.response?.statusCode == 409) {
      return '照片状态已变化或已锁定，请刷新；已确认证据需管理员处理。';
    }
    return '操作未完成，请联网后重试；未清除本机原图。';
  }
}

class _ServerThumbnail extends ConsumerStatefulWidget {
  const _ServerThumbnail(
      {super.key,
      required this.media,
      required this.onOpen,
      required this.queue,
      required this.isQueryCurrent});
  final LibraryMedia media;
  final VoidCallback? onOpen;
  final ThumbnailRequestQueue queue;
  final bool Function() isQueryCurrent;
  @override
  ConsumerState<_ServerThumbnail> createState() => _ServerThumbnailState();
}

class _ServerThumbnailState extends ConsumerState<_ServerThumbnail> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) return;
    if (!['image/jpeg', 'image/png'].contains(widget.media.contentType)) {
      _error = '此格式请打开原图';
      return;
    }
    bool isCurrent() {
      if (!mounted || !widget.isQueryCurrent()) return false;
      final current = ref.read(authControllerProvider).valueOrNull;
      return current?.user.subjectId == auth.user.subjectId &&
          current?.user.activeOrganizationId ==
              auth.user.activeOrganizationId &&
          current?.isOffline == false;
    }

    try {
      final bytes = await widget.queue.load(
          isCurrent: isCurrent,
          request: () => retryOnceAfterUnauthorized(
              initialAuth: auth,
              reconnect: () =>
                  ref.read(authControllerProvider.notifier).reconnect(),
              request: (token) {
                // A queued request or 401 replay must never inherit a later login.
                if (!isCurrent()) throw StateError('缩略图查询已失效');
                return ref
                    .read(serverGalleryApiProvider)
                    .thumbnail(token, widget.media.assetId);
              }));
      if (bytes == null || !isCurrent()) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (isCurrent()) setState(() => _error = '缩略图暂不可用，可打开原图');
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
      image: true,
      label: '${evidencePositionLabel(widget.media.position)}缩略图，仅作预览，点击核验原图',
      child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _error != null
                  ? Text(_error!)
                  : _bytes == null
                      ? const SizedBox(
                          height: 96,
                          width: 128,
                          child: Center(child: Text('缩略图读取中…')))
                      : Image.memory(_bytes!,
                          height: 96,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Text('缩略图无法显示，可打开原图')))));
}
