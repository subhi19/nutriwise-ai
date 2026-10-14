import 'package:flutter/services.dart';

final _emailRegex = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
);

class Validators {
  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email';
    if (!_emailRegex.hasMatch(v.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? newPassword(String? v) {
    if (v == null || v.length < 8 || v.length > 16) return '8 to 16 characters';
    if (!RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) {
      return 'Include at least one number or special character';
    }
    return null;
  }

  // Letters (any language) separated by spaces. No digits or symbols.
  static final _nameRegex = RegExp(r'^\p{L}+(?: +\p{L}+)*$', unicode: true);

  static String? personName(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 2) return 'Please enter a name';
    if (!_nameRegex.hasMatch(s)) return 'Use letters only (no numbers or symbols)';
    return null;
  }

  /// Stops digits and symbols being typed at all.
  static final List<TextInputFormatter> nameInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[\p{L} ]', unicode: true)),
    LengthLimitingTextInputFormatter(50),
  ];
}