class AuthSessionEpoch {
  int _value = 0;

  int capture() => _value;

  bool isCurrent(int captured) => captured == _value;

  void advance() {
    _value++;
  }
}
