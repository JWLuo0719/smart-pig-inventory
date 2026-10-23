import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../shared/widgets/local_video_player.dart';
import '../../shared/evidence_labels.dart';
import 'application/create_video_draft.dart';
import 'application/abandon_unqueued_capture_draft.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/database_provider.dart';
import '../../core/storage/image_metadata_reader.dart';
import '../../core/storage/media_materializer.dart';
import '../../core/storage/platform_image_metadata_reader.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/network_status_banner.dart';
import 'application/add_capture_view.dart';
import 'application/abandon_blocked_capture_draft.dart';
import 'application/create_single_image_draft.dart';
import 'application/create_three_view_draft.dart';
import 'application/update_capture_roi.dart';
import 'data/drift_capture_draft_repository.dart';
import 'domain/capture_draft_repository.dart';
import 'domain/capture_target.dart';
import 'domain/roi.dart';
import 'roi_editor_page.dart';
import '../outbox/application/queue_capture_draft.dart';
import '../sync/outbox_background_sync.dart';

final captureImagePickerProvider =
    Provider<ImagePicker>((ref) => ImagePicker());
final captureDocumentsDirectoryProvider =
    Provider<Future<Directory> Function()>(
        (ref) => getApplicationDocumentsDirectory);

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({required this.target, super.key});

  final CaptureTarget target;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  ImagePicker get _picker => ref.read(captureImagePickerProvider);
  final PlatformImageMetadataReader _metadataReader =
      PlatformImageMetadataReader();
  final List<String> _savedPositions = <String>[];
  final List<_LocalEvidence> _savedEvidence = <_LocalEvidence>[];
  CreatedCaptureDraft? _savedDraft;
  String? _replacementId;
  bool _threeView = false;
  bool _video = false;
  bool _saving = false;
  bool _restoring = true;
  bool _queueing = false;
  bool _isQueued = false;
  bool _canAbandonBlockedDraft = false;
  bool _abandoning = false;
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
    final DriftCaptureDraftRepository repository = DriftCaptureDraftRepository(
        ref.read(appDatabaseProvider),
        replaceDraftId: _replacementId);
    try {
      final snapshot = await repository.findLatestForTarget(
        organizationId: widget.target.organizationId,
        penId: widget.target.penId,
        businessDate: widget.target.businessDate,
        draftId: widget.target.draftId,
      );
      if (!mounted) return;
      if (snapshot == null) {
        await _recoverLostPickerData();
        return;
      }
      if (snapshot.media.isEmpty ||
          !await File(snapshot.media.first.materializedPath).exists()) {
        setState(() {
          _error = '已恢复草稿记录，但本地原图不可用。请勿覆盖该证据，联系管理员处理。';
        });
        return;
      }
      final OutboxEntry? outbox = await (ref.read(appDatabaseProvider).select(
                ref.read(appDatabaseProvider).outboxEntries,
              )
            ..where((OutboxEntries entry) =>
                entry.draftId.equals(snapshot.draftId)))
          .getSingleOrNull();
      setState(() {
        _threeView = snapshot.captureKind == 'left_center_right';
        _video = snapshot.captureKind == 'video';
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
                position: media.position,
                file: File(media.materializedPath),
                assetId: media.assetId,
                roiJson: media.roiJson,
                width: media.width,
                height: media.height,
              )));
        _isQueued = snapshot.state == 'queued';
        _canAbandonBlockedDraft =
            outbox?.state == 'blocked' && outbox?.sessionId == null;
      });
      // A recovered picker result belongs to the restored mode and next
      // direction, never a new implicit single-image group.
      await _recoverLostPickerData();
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
    if (_isQueued ||
        (_savedDraft != null && (!_threeView || _threeViewComplete))) {
      setState(() => _error = '已有完整或入队草稿，上次拍摄未覆盖原证据；可返回查看或明确重新采集整组。');
      return;
    }
    await _savePicked(response.file!, restoringLostData: true);
  }

  Future<void> _pickAndSave(ImageSource source) async {
    if (!_canAddPhoto) return;
    try {
      final XFile? picked = _video
          ? await _picker.pickVideo(
              source: source, maxDuration: const Duration(minutes: 2))
          : await _picker.pickImage(source: source, imageQuality: 92);
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
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null ||
        auth.user.activeOrganizationId != widget.target.organizationId) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final File sourceFile = File(picked.path);
      if (_video || picked.name.toLowerCase().endsWith('.mp4')) {
        await _saveVideo(sourceFile, picked.name);
        return;
      }
      final ImageMetadata metadata = await _metadataReader.read(sourceFile);
      final Directory documents =
          await ref.read(captureDocumentsDirectoryProvider)();
      final DriftCaptureDraftRepository repository =
          DriftCaptureDraftRepository(ref.read(appDatabaseProvider),
              replaceDraftId: _replacementId);
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
          if (_replacementId != null) {
            _savedEvidence.clear();
            _savedPositions.clear();
            _replacementId = null;
          }
          _savedDraft = saved;
          _savedPositions.add('single');
          _savedEvidence.add(_LocalEvidence(
            position: 'single',
            file: saved.materializedFile,
            assetId: saved.assetId,
            width: metadata.width,
            height: metadata.height,
          ));
        });
      }
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
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

  Future<void> _saveVideo(File source, String name) async {
    if (!name.toLowerCase().endsWith('.mp4') ||
        await source.length() > 30 * 1024 * 1024) {
      throw ArgumentError('视频需为 MP4，且不超过 30 MB。');
    }
    final player = VideoPlayerController.file(source);
    try {
      await player.initialize();
      if (player.value.duration > const Duration(minutes: 2) ||
          player.value.duration <= Duration.zero) {
        throw ArgumentError('视频时长需大于 0 且不超过 2 分钟。');
      }
      final saved = await CreateVideoDraft(
        materializer: MediaMaterializer(
            await ref.read(captureDocumentsDirectoryProvider)()),
        repository: DriftCaptureDraftRepository(ref.read(appDatabaseProvider),
            replaceDraftId: _replacementId),
      ).execute(
          source: source,
          originalName: name,
          organizationId: widget.target.organizationId,
          penId: widget.target.penId,
          businessDate: widget.target.businessDate,
          width: player.value.size.width.round(),
          height: player.value.size.height.round());
      if (!mounted) return;
      setState(() {
        _video = true;
        _threeView = false;
        if (_replacementId != null) {
          _savedEvidence.clear();
          _savedPositions.clear();
          _replacementId = null;
        }
        _savedDraft = saved;
        _savedPositions.add('video');
        _savedEvidence.add(_LocalEvidence(
          position: 'video',
          file: saved.materializedFile,
          assetId: saved.assetId,
        ));
      });
    } finally {
      await player.dispose();
    }
  }

  /// 在已拍照片上标注"不计入本栏"的排除区（相邻栏舍、料槽、走道等）。
  ///
  /// 只有草稿还在 `draft` 状态时可写；进入上传队列后 `UpdateCaptureRoi` 会拒绝并提示。
  Future<void> _openRoiEditor(_LocalEvidence item) async {
    final String? assetId = item.assetId;
    if (assetId == null) return;
    if (_isQueued) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已入队的证据标注只读，原图保留')));
      return;
    }
    final AppDatabase database = ref.read(appDatabaseProvider);
    Roi? savedRoi;
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => RoiEditorPage(
          image: item.file,
          aspectRatio: item.aspectRatio,
          initialRoi: _roiFromJson(item.roiJson),
          onSave: (Roi? roi) async {
            if (ref
                    .read(authControllerProvider)
                    .valueOrNull
                    ?.user
                    .activeOrganizationId !=
                widget.target.organizationId) {
              throw StateError('账号已变化');
            }
            await UpdateCaptureRoi(database).execute(
                organizationId: widget.target.organizationId,
                assetId: assetId,
                roi: roi);
            savedRoi = roi;
          },
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final int index = _savedEvidence.indexOf(item);
    if (index >= 0) {
      setState(() {
        _savedEvidence[index] =
            item.copyWith(roiJson: jsonEncode(savedRoi?.toJson()));
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存排除区标注')),
    );
  }

  Roi? _roiFromJson(String? raw) {
    if (raw == null || raw.isEmpty || raw == '{}') return null;
    try {
      return Roi.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _queueForUpload() async {
    final CreatedCaptureDraft? draft = _savedDraft;
    if (draft == null || _queueing || _isQueued) return;
    if (ref
            .read(authControllerProvider)
            .valueOrNull
            ?.user
            .activeOrganizationId !=
        widget.target.organizationId) {
      return;
    }
    setState(() {
      _queueing = true;
      _error = null;
    });
    try {
      await QueueCaptureDraft(
        ref.read(appDatabaseProvider),
        scheduleSync: scheduleOutboxSync,
      ).execute(draft.draftId, organizationId: widget.target.organizationId);
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

  Future<void> _abandonUnqueued() async {
    final draft = _savedDraft;
    if (draft == null || _isQueued || _saving || _queueing) return;
    final consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('放弃这组未上传草稿？'),
                content: const Text('本机原始照片会保留，这组草稿停止使用；不会修改服务器或锁定证据。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('继续本组')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('放弃本组'))
                ]));
    if (consent != true || !mounted) return;
    try {
      final auth = ref.read(authControllerProvider).valueOrNull;
      if (auth?.user.activeOrganizationId != widget.target.organizationId) {
        return;
      }
      await AbandonUnqueuedCaptureDraft(ref.read(appDatabaseProvider))
          .execute(draft.draftId, organizationId: widget.target.organizationId);
      if (mounted) {
        setState(() {
          _savedDraft = null;
          _savedEvidence.clear();
          _savedPositions.clear();
        });
      }
    } on StateError {
      if (mounted) setState(() => _error = '草稿已入队或账号发生变化，原证据保持不变');
    }
  }

  Future<void> _recaptureGroup() async {
    final old = _savedDraft;
    if (old == null || _saving || _isQueued || _queueing) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('重新采集整组？'),
                content:
                    const Text('三图会从左图重新开始；新照片安全保存后才停止旧草稿，旧原图保留。取消拍摄不会改变旧组。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('重新拍摄'))
                ]));
    if (confirmed != true || !mounted) return;
    try {
      final picked = _video
          ? await _picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 2))
          : await _picker.pickImage(
              source: ImageSource.camera, imageQuality: 92);
      if (picked == null || !mounted) return;
      _replacementId = old.draftId;
      await _savePicked(picked, restoringLostData: true);
    } catch (_) {
      if (mounted) setState(() => _error = '重新采集未完成，旧草稿仍保留');
    } finally {
      _replacementId = null;
    }
  }

  Future<void> _abandonBlockedDraft() async {
    final CreatedCaptureDraft? draft = _savedDraft;
    if (draft == null || !_canAbandonBlockedDraft || _abandoning) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('放弃失败草稿并重新采集？'),
        content: const Text(
          '这只会停止该失败草稿的重试，让本栏舍可以重新拍摄。手机原图会保留，服务器中已确认或已锁定的证据不会被修改。',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('停止重试')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (ref
            .read(authControllerProvider)
            .valueOrNull
            ?.user
            .activeOrganizationId !=
        widget.target.organizationId) {
      return;
    }
    setState(() => _abandoning = true);
    try {
      await AbandonBlockedCaptureDraft(ref.read(appDatabaseProvider))
          .execute(draft.draftId, organizationId: widget.target.organizationId);
      if (!mounted) return;
      setState(() {
        _savedDraft = null;
        _savedPositions.clear();
        _savedEvidence.clear();
        _isQueued = false;
        _canAbandonBlockedDraft = false;
        _error = '失败草稿已停止重试。原图仍保留在本机，可以拍摄一张新图片。';
      });
    } on StateError catch (_) {
      if (mounted) {
        setState(() => _error = '该草稿已被提交，不能在本机放弃。请刷新上传队列。');
      }
    } finally {
      if (mounted) setState(() => _abandoning = false);
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
    if (_savedDraft == null || _replacementId != null) {
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
        if (_replacementId != null) {
          _savedEvidence.clear();
          _savedPositions.clear();
          _replacementId = null;
        }
        _savedDraft = saved;
        _savedPositions.add('left');
        _savedEvidence.add(_LocalEvidence(
            position: 'left',
            file: saved.materializedFile,
            assetId: saved.assetId,
            width: metadata.width,
            height: metadata.height));
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
      draftId: _savedDraft!.draftId,
    );
    if (!mounted) return;
    setState(() {
      _savedPositions.add(position);
      final CapturedMediaRecord? saved = snapshot?.media
          .where((CapturedMediaRecord media) => media.position == position)
          .firstOrNull;
      if (saved != null) {
        _savedEvidence.add(_LocalEvidence(
          position: position,
          file: File(saved.materializedPath),
          assetId: saved.assetId,
          roiJson: saved.roiJson,
          width: saved.width,
          height: saved.height,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null ||
        auth.user.activeOrganizationId != widget.target.organizationId) {
      return const Scaffold(body: Center(child: Text('当前账号无法访问此采集组，请返回当前组织')));
    }
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
              onChanged:
                  savedDraft == null && !_saving && !_restoring && !_video
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
          SwitchListTile(
            title: const Text('视频证据模式'),
            subtitle: const Text('MP4，最多 2 分钟 / 30 MB；上传后人工复核，不生成自动计数。'),
            value: _video,
            onChanged: savedDraft == null && !_saving && !_restoring
                ? (value) => setState(() {
                      _video = value;
                      if (value) _threeView = false;
                    })
                : null,
          ),
          Text(
              _video
                  ? '视频采集'
                  : _threeView
                      ? '左 / 中 / 右采集'
                      : '单图采集',
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
                            : !_threeView
                                ? '媒体已保存，等待加入上传队列。'
                                : '已保存 ${_savedPositions.length}/3 张；当前需要：$_nextPositionLabel。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (savedDraft != null)
            _SavedEvidenceList(
              evidence: _savedEvidence,
              onAnnotate: _openRoiEditor,
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
          if (_savedDraft != null && !_isQueued)
            OutlinedButton(
                onPressed: _saving || _queueing ? null : _recaptureGroup,
                child: const Text('重新采集整组')),
          if (_savedDraft != null && !_isQueued)
            TextButton(
                onPressed: _saving || _queueing ? null : _abandonUnqueued,
                child: const Text('放弃未上传草稿')),
          if (_isQueued)
            OutlinedButton(
                onPressed: () => context.push('/outbox'),
                child: const Text('查看上传进度')),
          if (_canAbandonBlockedDraft) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _abandoning ? null : _abandonBlockedDraft,
              icon: const Icon(Icons.restart_alt_outlined),
              label: Text(_abandoning ? '正在停止重试…' : '放弃失败草稿并重新采集'),
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
                  ? '正在安全保存媒体…'
                  : _threeViewComplete
                      ? '三张图片已安全保存'
                      : _video
                          ? '录制视频并保存'
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
  const _LocalEvidence({
    required this.position,
    required this.file,
    this.assetId,
    this.roiJson,
    this.width,
    this.height,
  });

  final String position;
  final File file;
  final String? assetId;
  final String? roiJson;
  final int? width;
  final int? height;

  /// 视频在合同上不允许携带图像 ROI，因此只有图片可以标注排除区。
  bool get canAnnotate => assetId != null && position != 'video';

  double get aspectRatio => (width != null && height != null && height! > 0)
      ? width! / height!
      : 4 / 3;

  _LocalEvidence copyWith({String? roiJson}) => _LocalEvidence(
        position: position,
        file: file,
        assetId: assetId,
        roiJson: roiJson ?? this.roiJson,
        width: width,
        height: height,
      );
}

class _SavedEvidenceList extends StatelessWidget {
  const _SavedEvidenceList({
    required this.evidence,
    required this.status,
    required this.onAnnotate,
  });

  final List<_LocalEvidence> evidence;
  final String status;
  final Future<void> Function(_LocalEvidence item) onAnnotate;

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
                      .map((item) => _EvidenceThumbnail(
                            item: item,
                            onAnnotate: onAnnotate,
                          ))
                      .toList(growable: false),
                ),
              ]),
        ),
      ),
    );
  }
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.item, required this.onAnnotate});

  final _LocalEvidence item;
  final Future<void> Function(_LocalEvidence item) onAnnotate;

  String get _label {
    return evidencePositionLabel(item.position);
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
                    child: item.position == 'video'
                        ? SizedBox(
                            height: 360,
                            child: LocalVideoPlayer(file: item.file))
                        : InteractiveViewer(
                            child: Image.file(item.file, fit: BoxFit.contain)),
                  ),
                  if (item.canAnnotate)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          onAnnotate(item);
                        },
                        icon: const Icon(Icons.crop_free),
                        label: const Text('标注不计入本栏的区域'),
                      ),
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
                    child: item.position == 'video'
                        ? const SizedBox(
                            width: 92,
                            height: 92,
                            child: Icon(Icons.play_circle_outline, size: 48))
                        : Image.file(
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
