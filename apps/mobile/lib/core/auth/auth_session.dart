class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final DateTime refreshTokenExpiresAt;
}

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.subjectId,
    required this.displayName,
    required this.activeOrganizationId,
    required this.activeOrganizationCode,
    required this.activeOrganizationName,
    required this.roles,
    required this.lastVerifiedAt,
  });

  final String subjectId;
  final String displayName;
  final String activeOrganizationId;
  final String activeOrganizationCode;
  final String activeOrganizationName;
  final List<String> roles;
  final DateTime lastVerifiedAt;
}

class AuthState {
  const AuthState({
    required this.session,
    required this.user,
    required this.isOffline,
  });

  final AuthSession session;
  final AuthenticatedUser user;
  final bool isOffline;
}
