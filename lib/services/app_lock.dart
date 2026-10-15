/// Evite de verrouiller l'application quand on la quitte pour une action
/// externe (appareil photo, galerie, partage) puis qu'on y revient.
class AppLock {
  static bool _external = false;
  static DateTime? _doneAt;

  static void beginExternal() {
    _external = true;
    _doneAt = null;
  }

  static void endExternal() {
    _doneAt = DateTime.now();
  }

  /// true si la reprise de l'application vient d'une action externe.
  /// Consomme l'indicateur (un seul usage).
  static bool consumeExternal() {
    final ext = _external;
    final done = _doneAt;
    _external = false;
    _doneAt = null;
    if (!ext) return false;
    return done == null ||
        DateTime.now().difference(done) < const Duration(seconds: 5);
  }
}
