import 'package:dio/dio.dart';

import '../domain/master_data_changes.dart';

class MasterDataApi {
  MasterDataApi({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30)));

  final Dio _dio;

  Future<MasterDataChanges> changes(
      {required String accessToken, String? cursor}) async {
    final Response<dynamic> response = await _dio.get(
      '/api/v1/master-data/changes',
      queryParameters:
          cursor == null ? null : <String, String>{'cursor': cursor},
      options: Options(
          headers: <String, String>{'Authorization': 'Bearer $accessToken'}),
    );
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return MasterDataChanges(
      cursor: body['cursor'] as String,
      fullResyncRequired: body['fullResyncRequired'] as bool,
      organizations: _entities(body['organizations'] as List<dynamic>),
      buildings: _entities(body['buildings'] as List<dynamic>),
      pens: _entities(body['pens'] as List<dynamic>),
      deletedEntities: (body['deletedEntities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> value) => DeletedMasterDataEntity(
              entityType: value['entityType'] as String,
              id: value['id'] as String))
          .toList(growable: false),
    );
  }

  List<MasterDataEntity> _entities(List<dynamic> values) => values
      .cast<Map<String, dynamic>>()
      .map((Map<String, dynamic> value) => MasterDataEntity(
            id: value['id'] as String,
            parentId: value['parentId'] as String?,
            code: value['code'] as String,
            name: value['name'] as String,
            enabled: value['enabled'] as bool,
            syncVersion: value['syncVersion'] as int,
          ))
      .toList(growable: false);
}
