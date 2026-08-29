import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/storage/database_provider.dart';
import '../../core/storage/image_metadata_reader.dart';
import '../../core/storage/media_materializer.dart';
import '../../core/storage/platform_image_metadata_reader.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/network_status_banner.dart';
import 'application/add_capture_view.dart';
import 'application/create_single_image_draft.dart';
import 'application/create_three_view_draft.dart';
import 'data/drift_capture_draft_repository.dart';
import 'domain/capture_draft_repository.dart';
import 'domain/capture_target.dart';
import '../outbox/application/queue_capture_draft.dart';
import '../sync/outbox_background_sync.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({required this.target, super.key});

  final CaptureTarget target;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final PlatformImageMetadataReader _metadataReader =
      PlatformImageMetadataReader();
  final List<String> _savedPositions = <String>[];
  final List<_LocalEvidence> _savedEvidence = <_LocalEvidence>[];
  CreatedCaptureDraft? _savedDraft;
  bool _threeView = false;
  bool _saving = false;
  bool _restoring = true;
  bool _queueing = false;
  bool _isQueued = false;
  String? _error;

  bool get _threeViewComplete => _threeView && _savedPositions.length == 3;

  String get _nextThreeViewPosition => switch (_savedPositions.length) {
        0 => 'left',
        1 => 'center',
        2 => 'right',
        _ => throw StateError('Three-view draft already complete'),
      };

  String get _nextPositionLabel =>
      switch (_threeView ? _nextThreeViewPosition : 'single') {
        'left' => '左侧',
        'center' => '中间',
        'right' => '右侧',
        _ => '单图',
      };

  bool get _canAddPhoto =>
      !_restoring &&
      !_saving &&
      !_isQueued &&
      (!_threeView || !_threeViewComplete) &&
      (_savedDraft == null || _threeView);

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_restoreCaptureScreen);
  }

  Future<void> _restoreCaptureScreen() async {
    await _recoverLostPickerData();
    final DriftCaptureDraftRepository repository =
        DriftCaptureDraftRepository(ref.read(appDatabaseProvider));
    try {
      final snapshot = await repository.findLatestForTarget(
        organizationId: widget.target.organizationId,
        penId: widget.target.penId,
        businessDate: widget.target.businessDate,
      );
      if (!mounted || snapshot == null) return;
      if (snapshot.media.isEmpty ||
          !await File(snapshot.media.first.materializedPath).exists()) {
        setState(() {
          _error = '已恢复草稿记录，但本地原图不可用。请勿覆盖该证据，联系管理员处理。';
        });
        return;
      }
      setState(() {
        _threeView = snapshot.captureKind == 'left_center_right';
        _savedDraft = CreatedCaptureDraft(
          draftId: snapshot.draftId,
          captureSetId: snapshot.captureSetId,
          assetId: snapshot.media.first.assetId,
          materializedFile: File(snapshot.media.first.materializedPath),
        );
        _savedPositions
          ..clear()
          ..addAll(snapshot.media.map((media) => media.position));
        _savedEvidence
          ..clear()
          ..addAll(snapshot.media.map((media) => _LocalEvidence(
              position: media.position, file: File(media.materializedPath))));
        _isQueued = snapshot.state == 'queued';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '本地草稿恢复失败。已有证据没有被删除，请重试或联系管理员。';
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _recoverLostPickerData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (!mounted || response.isEmpty) return;
    if (response.file == null) {
      setState(
        () => _error = '上次拍摄未能恢复。已有本地草稿没有被删除，请重新拍摄。',
      );
      return;
    }
    await _savePicked(response.file!, restoringLostData: true);
  }

  Future<void> _pickAndSave(ImageSource source) async {
    if (!_canAddPhoto) return;
    try {
      final XFile? picked =
          await _picker.pickImage(source: source, imageQuality: 92);
      if (picked != null) await _savePicked(picked);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '无法打开相机或图库。已有本地草稿没有被删除，请检查权限后重试。',
        );
      }
    }
  }

  Future<void> _savePicked(
    XFile picked, {
    bool restoringLostData = false,
  }) async {
    if (!_canAddPhoto && !restoringLostData) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final File sourceFile = File(picked.path);
      final ImageMetadata metadata = await _metadataReader.read(sourceFile);
      final Directory documents = await getApplicationDocumentsDirectory();
      final DriftCaptureDraftRepository repository =
          DriftCaptureDraftRepository(ref.read(appDatabaseProvider));
      final MediaMaterializer materializer = MediaMaterializer(documents);
      final DateTime capturedAt = DateTime.now();

      if (_threeView) {
        await _saveThreeView(
          source: sourceFile,
          picked: picked,
          metadata: metadata,
          materializer: materializer,
          repository: repository,
          capturedAt: capturedAt,
        );
      } else {
        final CreatedCaptureDraft saved = await CreateSingleImageDraft(
          materializer: materializer,
          repository: repository,
        ).execute(
          source: sourceFile,
          originalName: picked.name,
          contentType: metadata.contentType,
          organizationId: widget.target.organizationId,
          penId: widget.target.penId,
          businessDate: widget.target.businessDate,
          capturedAt: capturedAt,
          width: metadata.width,
          height: metadata.height,
          exif: metadata.exif,
        );
        if (!mounted) return;
        setState(() {
          _savedDraft = saved;
          _savedPositions.add('single');
          _savedEvidence.add(
              _LocalEvidence(position: 'single', file: saved.materializedFile));
        });
      }
    } on UnsupportedImageFormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (_) {
      if (mounted) {
        setState(
          () => _error = '照片未能安全保存到本机。请检查存储空间后重试，原草稿没有改变。',
        );
      }
    } on StateError catch (_) {
      if (mounted) {
        setState(() => _error = '该采集方向已保存。请继续下一方向，已有草稿没有被删除。');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '保存照片时发生错误，原图和已有草稿没有被删除。请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _queueForUpload() async {
    final CreatedCaptureDraft? draft = _savedDraft;
    if (draft == null || _queueing || _isQueued) return;
    setState(() {
      _queueing = true;
      _error = null;
    });
    try {
      await QueueCaptureDraft(
        ref.read(appDatabaseProvider),
        scheduleSync: scheduleOutboxSync,
      ).execute(draft.draftId);
      if (!mounted) return;
      setState(() => _isQueued = true);
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _error = '当前采集组尚不完整，不能保存到待上传：${error.message}');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '未能写入上传队列。原图和草稿仍安全保存在本机，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _queueing = false);
    }
  }

  Future<void> _saveThreeView({
    required File source,
    required XFile picked,
    required ImageMetadata metadata,
    required MediaMaterializer materializer,
    required DriftCaptureDraftRepository repository,
    required DateTime capturedAt,
  }) async {
    if (_savedDraft == null) {
      final CreatedCaptureDraft saved = await CreateThreeViewDraft(
        materializer: materializer,
        repository: repository,
      ).execute(
        source: source,
        originalName: picked.name,
        contentType: metadata.contentType,
        organizationId: widget.target.organizationId,
        penId: widget.target.penId,
        businessDate: widget.target.businessDate,
        capturedAt: capturedAt,
        width: metadata.width,
        height: metadata.height,
        exif: metadata.exif,
      );
      if (!mounted) return;
      setState(() {
        _savedDraft = saved;
        _savedPositions.add('left');
        _savedEvidence.add(
            _LocalEvidence(position: 'left', file: saved.materializedFile));
      });
      return;
    }

    final String position = _nextThreeViewPosition;
    await AddCaptureView(materializer: materializer, repository: repository)
        .execute(
      source: source,
      originalName: picked.name,
      contentType: metadata.contentType,
      organizationId: widget.target.organizationId,
      draftId: _savedDraft!.draftId,
      assetId: const Uuid().v4(),
      position: position,
      capturedAt: capturedAt,
      width: metadata.width,
      height: metadata.height,
      exif: metadata.exif,
    );
    final CaptureDraftSnapshot? snapshot = await repository.findLatestForTarget(
      organizationId: widget.target.organizationId,
      penId: widget.target.penId,
      businessDate: widget.target.businessDate,
    );
    if (!mounted) return;
    setState(() {
      _savedPositions.add(position);
      final CapturedMediaRecord? saved = snapshot?.media
          .where((CapturedMediaRecord media) => media.position == position)
          .firstOrNull;
      if (saved != null) {
        _savedEvidence.add(_LocalEvidence(
            position: position, file: File(saved.materializedPath)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CreatedCaptureDraft? savedDraft = _savedDraft;
    final bool? offline =
        ref.watch(authControllerProvider).valueOrNull?.isOffline;
    return Scaffold(
      appBar: AppBar(title: Text(widget.target.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: <Widget>[
          NetworkStatusBanner(offline: offline),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              value: _threeView,
              onChanged: savedDraft == null && !_saving && !_restoring
                  ? (bool value) => setState(() => _threeView = value)
                  : null,
              title: const Text('左 / 中 / 右三图模式',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                savedDraft == null
                    ? '三张图会保存为同一采集组，未验证去重前不会自动相加。'
                    : '已开始采集后不能切换模式，以保护已保存证据。',
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(_threeView ? '左 / 中 / 右采集' : '单图采集',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _restoring
                ? '正在恢复本地草稿和待上传证据…'
                : savedDraft == null
                    ? '当前需要：$_nextPositionLabel。拍摄或导入后会先安全保存到本机。'
                    : _isQueued
                        ? '采集组和待上传状态已恢复，尚未生成盘点数量。'
                        : _threeViewComplete
                            ? '三张照片已保存为同一采集组，等待加入上传队列。'
                            : '已保存 ${_savedPositions.length}/3 张；当前需要：$_nextPositionLabel。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (savedDraft != null)
            _SavedEvidenceList(
              evidence: _savedEvidence,
              status: _isQueued
                  ? '已保存到待上传 · 尚未生成盘点数量'
                  : _threeView
                      ? '已保存 ${_savedPositions.length}/3 张 · 不会显示数量'
                      : '待上传 · 尚未生成盘点数量',
            ),
          if (savedDraft != null &&
              (!_threeView || _threeViewComplete)) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _queueing || _isQueued ? null : _queueForUpload,
              icon: _queueing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(!_isQueued
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done_outlined),
              label: Text(_queueing
                  ? '正在写入待上传队列…'
                  : !_isQueued
                      ? '保存到待上传'
                      : '已保存到待上传'),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _CaptureError(message: _error!),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed:
                _canAddPhoto ? () => _pickAndSave(ImageSource.camera) : null,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(
              _saving
                  ? '正在安全保存照片…'
                  : _threeViewComplete
                      ? '三张图片已安全保存'
                      : '拍摄$_nextPositionLabel并保存',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed:
                _canAddPhoto ? () => _pickAndSave(ImageSource.gallery) : null,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从图库导入'),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.shield_outlined,
                    color: AppColors.barnBlue, size: 20),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '照片会复制到本机持久目录并计算 SHA-256。服务器 Commit 成功前不会清理原图，也不会显示推测数量。',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalEvidence {
  const _LocalEvidence({required this.position, required this.file});

  final String position;
  final File file;
}

class _SavedEvidenceList extends StatelessWidget {
  const _SavedEvidenceList({required this.evidence, required this.status});

  final List<_LocalEvidence> evidence;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '采集证据已安全保存到本机，待上传',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  const Expanded(
                    child: Text('已保存为本地草稿',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.check_circle, color: AppColors.herdTeal),
                ]),
                const SizedBox(height: 3),
                Text(status),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: evidence
                      .map((item) => _EvidenceThumbnail(item: item))
                      .toList(growable: false),
                ),
              ]),
        ),
      ),
    );
  }
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.item});

  final _LocalEvidence item;

  String get _label {
    return switch (item.position) {
      'left' => '左图',
      'center' => '中图',
      'right' => '右图',
      _ => '单图',
    };
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '已保存的$_label，点击查看大图',
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (BuildContext dialogContext) => Dialog(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Row(children: <Widget>[
                    Text(_label,
                        style: Theme.of(dialogContext).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 520),
                    child: InteractiveViewer(
                        child: Image.file(item.file, fit: BoxFit.contain)),
                  ),
                ]),
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 92,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      item.file,
                      width: 92,
                      height: 92,
                      cacheWidth: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 92,
                        height: 92,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      );
}

class _CaptureError extends StatelessWidget {
  const _CaptureError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1B3AD)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, color: AppColors.alert),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
