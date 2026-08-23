import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_session.dart';
import '../data/drift_master_data_repository.dart';
import '../data/master_data_api.dart';

class MasterDataSynchronizer {
  MasterDataSynchronizer(
      {required MasterDataApi api,
      required DriftMasterDataRepository repository})
      : _api = api,
        _repository = repository;

  final MasterDataApi _api;
  final DriftMasterDataRepository _repository;

  Future<void> sync(AuthState auth) async {
    if (auth.isOffline) throw const MasterDataSyncUnavailable();
    final String? cursor =
        await _repository.cursor(auth.user.activeOrganizationId);
    final changes = await _api.changes(
        accessToken: auth.session.accessToken, cursor: cursor);
    await _repository.apply(auth.user.activeOrganizationId, changes);
  }
}

class MasterDataSyncUnavailable implements Exception {
  const MasterDataSyncUnavailable();
}

final masterDataApiProvider = Provider<MasterDataApi>(
    (ref) => MasterDataApi(baseUrl: ref.watch(apiBaseUrlProvider)));
final masterDataSynchronizerProvider = Provider<MasterDataSynchronizer>(
  (ref) => MasterDataSynchronizer(
    api: ref.watch(masterDataApiProvider),
    repository: ref.watch(masterDataRepositoryProvider),
  ),
);
