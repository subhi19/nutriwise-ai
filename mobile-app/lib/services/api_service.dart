import 'package:dio/dio.dart';
import '../models/auth_session.dart';
import '../models/family_member.dart';

// ---------- Error handling ----------

class ApiException implements Exception {
  final String code;
  final String message;
  final bool retry;
  ApiException({required this.code, required this.message, required this.retry});

  // AI-pipeline envelope: { "error": { "code", "message", "retry" } }
  factory ApiException.fromAiEnvelope(Map<String, dynamic> body) {
    final err = body['error'];
    return ApiException(
      code: err['code'] ?? 'INTERNAL',
      message: err['message'] ?? 'Something went wrong',
      retry: err['retry'] ?? false,
    );
  }

  // Standard FastAPI auth envelope: { "detail": "..." }
  factory ApiException.fromDetail(String detail) =>
      ApiException(code: 'AUTH_ERROR', message: detail, retry: false);

  @override
  String toString() => message;
}

// ---------- Abstract interface ----------

abstract class NutriApi {
  Future<AuthSession> login(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<List<FamilyMember>> getMembers(int userId);
  Future<FamilyMember> createMember(int userId, FamilyMember member);
  Future<FamilyMember> updateMember(String memberId, FamilyMember member);
  Future<void> deleteMember(String memberId);
  Future<void> forgotPassword(String email);
}

// ---------- Mock implementation ----------

class MockApi implements NutriApi {
  final List<FamilyMember> _members = [];
  int _nextId = 1;

  @override
  Future<AuthSession> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return AuthSession(
      accessToken: 'mock-token',
      userId: 1,
      name: 'Mock User',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  @override
  Future<void> register(String name, String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<List<FamilyMember>> getMembers(int userId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.of(_members);
  }

  @override
  Future<FamilyMember> createMember(int userId, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final saved = member.copyWith(id: 'mock-${_nextId++}');
    _members.add(saved);
    return saved;
  }

  @override
  Future<FamilyMember> updateMember(String memberId, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final index = _members.indexWhere((m) => m.id == memberId);
    final updated = member.copyWith(id: memberId);
    if (index != -1) _members[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMember(String memberId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _members.removeWhere((m) => m.id == memberId);
  }

  @override
  Future<void> forgotPassword(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

// ---------- Real implementation ----------

class RealApi implements NutriApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8000', // 10.0.2.2:8000 for Android emulator
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Never _handleError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      if (data.containsKey('error')) throw ApiException.fromAiEnvelope(data);
      if (data.containsKey('detail')) throw ApiException.fromDetail(data['detail'].toString());
    }
    throw ApiException(
      code: 'INTERNAL',
      message: 'Network error. Please check your connection and try again.',
      retry: true,
    );
  }

  @override
  Future<AuthSession> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
      return AuthSession.fromLoginResponse(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> register(String name, String email, String password) async {
    try {
      await _dio.post('/auth/register', data: {'name': name, 'email': email, 'password': password});
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<List<FamilyMember>> getMembers(int userId) async {
    try {
      final res = await _dio.get('/api/family/members', queryParameters: {'user_id': userId});
      return (res.data as List).map((e) => FamilyMember.fromJson(e)).toList();
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> createMember(int userId, FamilyMember member) async {
    try {
      final res = await _dio.post('/api/family/members',
          queryParameters: {'user_id': userId}, data: member.toJson());
      return FamilyMember.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> updateMember(String memberId, FamilyMember member) async {
    try {
      final res = await _dio.put('/api/family/members/$memberId', data: member.toJson());
      return FamilyMember.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> deleteMember(String memberId) async {
    try {
      await _dio.delete('/api/family/members/$memberId');
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> forgotPassword(String email) async {
    try {
      // TODO: confirm this endpoint with backend — not yet documented in v2.0 contract.
      await _dio.post('/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      _handleError(e);
    }
  }
}