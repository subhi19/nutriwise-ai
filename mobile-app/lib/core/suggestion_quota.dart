/// First generation is free; the user then gets [maxNew] "new suggestion" requests.
class SuggestionQuota {
  static const maxNew = 2;
  int _generated = 0;

  bool get canGenerate => _generated < 1 + maxNew;
  int get newLeft => 1 + maxNew - (_generated < 1 ? 1 : _generated);

  void recordSuccess() => _generated++; // failed calls don't use up a suggestion
  void reset() => _generated = 0;
}