import 'package:dio/dio.dart';
import '../models/family_member.dart';

// ---------- Error handling ----------

class ApiException implements Exception {
  final String code;
  final String message;
  final bool retry;
  ApiException({required this.code, required this.message, required this.retry});

  factory ApiException.fromResponse(Map<String, dynamic> body) {
    final err = body['error'];
    return ApiException(
      code: err['code'] ?? 'INTERNAL',
      message: err['message'] ?? 'Something went wrong',
      retry: err['retry'] ?? false,
    );
  }

  @override
  String toString() => message;
}

// ---------- Abstract interface ----------

abstract class NutriApi {
  Future<List<FamilyMember>> getMembers(String userId);
  Future<FamilyMember> createMember(String userId, FamilyMember member);
  Future<FamilyMember> updateMember(String memberId, FamilyMember member);
  Future<void> deleteMember(String memberId);
}

// ---------- Mock implementation (use this today) ----------

class MockApi implements NutriApi {
  final List<FamilyMember> _members = [];
  int _nextId = 1;

  @override
  Future<List<FamilyMember>> getMembers(String userId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.of(_members);
  }

  @override
  Future<FamilyMember> createMember(String userId, FamilyMember member) async {
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
    if (index != -1) {
      _members[index] = updated;
    }
    return updated;
  }

  @override
  Future<void> deleteMember(String memberId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _members.removeWhere((m) => m.id == memberId);
  }
}

// ---------- Real implementation (switch to this once backend is live) ----------

class RealApi implements NutriApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8000', // 10.0.2.2:8000 for Android emulator
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Never _handleError(DioException e) {
    if (e.response?.data is Map<String, dynamic> &&
        (e.response!.data as Map).containsKey('error')) {
      throw ApiException.fromResponse(e.response!.data);
    }
    throw ApiException(
      code: 'INTERNAL',
      message: 'Network error. Please check your connection and try again.',
      retry: true,
    );
  }

  @override
  Future<List<FamilyMember>> getMembers(String userId) async {
    try {
      final res = await _dio.get('/api/family/members',
          queryParameters: {'user_id': userId});
      return (res.data as List).map((e) => FamilyMember.fromJson(e)).toList();
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> createMember(String userId, FamilyMember member) async {
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
}