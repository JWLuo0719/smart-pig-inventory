import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/auth/authorized_retry.dart';

void main() {
  test('session review request retries once with a refreshed access token',
      () async {
    final List<String> usedTokens = <String>[];
    int refreshes = 0;
    final String result = await retryOnceAfterUnauthorized<String>(
      initialAuth: _auth('expired-access'),
      reconnect: () async {
        refreshes++;
        return _auth('refreshed-access');
      },
      request: (String accessToken) async {
        usedTokens.add(accessToken);
        if (accessToken == 'expired-access') {
          throw DioException(
            requestOptions:
                RequestOptions(path: '/api/v1/inventory-sessions/session'),
            response: Response<void>(
              requestOptions:
                  RequestOptions(path: '/api/v1/inventory-sessions/session'),
              statusCode: 401,
            ),
          );
        }
        return 'review-loaded';
      },
    );

    expect(result, 'review-loaded');
    expect(refreshes, 1);
    expect(usedTokens, <String>['expired-access', 'refreshed-access']);
  });
}

AuthState _auth(String accessToken) => AuthState(
      session: AuthSession(
        accessToken: accessToken,
        refreshToken: 'r' * 32,
        accessTokenExpiresAt: DateTime.utc(2026),
        refreshTokenExpiresAt: DateTime.utc(2026, 1, 2),
      ),
      user: AuthenticatedUser(
        subjectId: 'synthetic-subject',
        displayName: 'Synthetic reviewer',
        activeOrganizationId: 'org',
        activeOrganizationCode: 'E2E',
        activeOrganizationName: 'Synthetic organization',
        roles: const <String>['REVIEWER'],
        lastVerifiedAt: DateTime.utc(2026),
      ),
      isOffline: false,
    );
