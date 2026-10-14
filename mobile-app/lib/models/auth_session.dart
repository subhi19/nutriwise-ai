class AuthSession {
  final String accessToken;
  final int userId;
  final String name;
  final DateTime expiresAt;

  AuthSession({
    required this.accessToken,
    required this.userId,
    required this.name,
    required this.expiresAt,
  });

  factory AuthSession.fromLoginResponse(Map<String, dynamic> j) => AuthSession(
        accessToken: j['access_token'],
        userId: j['user_id'],
        name: j['name'],
        expiresAt: DateTime.now().add(Duration(seconds: j['expires_in'] ?? 86400)),
      );
}