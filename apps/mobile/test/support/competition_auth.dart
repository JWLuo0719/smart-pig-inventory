import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';

AuthState competitionAuth({String org = 'org-a', bool offline = false}) =>
    AuthState(
        session: AuthSession(
            accessToken: 'synthetic-$org',
            refreshToken: 'synthetic-$org',
            accessTokenExpiresAt: DateTime(2030),
            refreshTokenExpiresAt: DateTime(2030)),
        user: AuthenticatedUser(
            subjectId: 'user-$org',
            displayName: '合成账号',
            activeOrganizationId: org,
            activeOrganizationCode: org,
            activeOrganizationName: '合成组织',
            roles: const ['REVIEWER'],
            lastVerifiedAt: DateTime(2026)),
        isOffline: offline);

class CompetitionAuthController extends AuthController {
  @override
  Future<AuthState?> build() async => competitionAuth();
  void switchTo(AuthState auth) => state = AsyncData(auth);
}
