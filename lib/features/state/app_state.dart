import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/palette.dart';
import '../../database/schema.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../repositories/health_repository.dart';
import '../../services/backup_service.dart';
import '../../services/file_saver.dart' show deleteLocalFile;

/// Etat de l'application : charge les donnees, expose des vues triees.
class AppState extends ChangeNotifier {
  AppState({required this.repo, required this.prefs});

  final HealthRepository repo;
  final SharedPreferences prefs;

  String lang = 'fr';
  bool dark = false;
  String paletteId = 'rose';
  String? _pinHash;
  String? _pinSalt;
  RefRanges refs = RefRanges.defaults();
  PatientProfile profile = const PatientProfile();

  List<ThyroidEntry> thyroid = [];
  List<OtherAnalysis> others = [];
  List<Consultation> consultations = [];
  List<DoseEvent> doseEvents = [];
  List<SymptomLog> symptoms = [];
  List<Attachment> attachments = [];
  bool loaded = false;

  S get s => S(lang);

  AppPalette get palette => paletteById(paletteId);

  // ---- Nom de la patiente -----------------------------------------------
  bool get hasName =>
      profile.nameFr.trim().isNotEmpty || profile.nameAr.trim().isNotEmpty;

  /// Nom affiche : celui de la langue courante, sinon l'autre, sinon
  /// l'invitation « Entrez le nom ».
  String get displayName {
    final primary = lang == 'ar' ? profile.nameAr : profile.nameFr;
    final other = lang == 'ar' ? profile.nameFr : profile.nameAr;
    if (primary.trim().isNotEmpty) return primary.trim();
    if (other.trim().isNotEmpty) return other.trim();
    return s.t('enter_name');
  }

  // ---- Code secret --------------------------------------------------------
  bool get pinEnabled => (_pinHash ?? '').isNotEmpty;

  static String _hashPin(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt =
        List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
    _pinSalt = salt;
    _pinHash = _hashPin(salt, pin);
    await prefs.setString('pin_salt', salt);
    await prefs.setString('pin_hash', _pinHash!);
    notifyListeners();
  }

  bool verifyPin(String pin) =>
      pinEnabled && _hashPin(_pinSalt ?? '', pin) == _pinHash;

  Future<void> clearPin() async {
    _pinHash = null;
    _pinSalt = null;
    await prefs.remove('pin_hash');
    await prefs.remove('pin_salt');
    notifyListeners();
  }

  Future<void> setPalette(String id) async {
    paletteId = paletteById(id).id;
    await prefs.setString('palette', paletteId);
    notifyListeners();
  }

  Future<void> load() async {
    final l = prefs.getString('lang');
    lang = (l == 'ar' || l == 'fr') ? l! : 'fr';
    dark = prefs.getBool('dark') ?? false;
    paletteId = paletteById(prefs.getString('palette')).id;
    _pinHash = prefs.getString('pin_hash');
    _pinSalt = prefs.getString('pin_salt');
    refs = _decode(prefs.getString('refs'), RefRanges.fromMap, RefRanges.defaults());
    profile = _decode(prefs.getString('profile'), PatientProfile.fromMap, const PatientProfile());
    // L'ancien nom par defaut (pre-rempli) est retire : le champ est vide.
    if (profile.nameFr == 'Fatma Zahra Belqas' &&
        profile.nameAr == 'فاطمة الزهراء بلقاس') {
      final m = profile.toMap();
      m['nameFr'] = '';
      m['nameAr'] = '';
      profile = PatientProfile.fromMap(m);
      if (prefs.getString('profile') != null) {
        await prefs.setString('profile', jsonEncode(profile.toMap()));
      }
    }
    await reload();
  }

  T _decode<T>(String? raw, T Function(Map<String, Object?>) f, T fallback) {
    if (raw == null) return fallback;
    try {
      final o = jsonDecode(raw);
      if (o is Map) return f(Map<String, Object?>.from(o));
    } catch (_) {}
    return fallback;
  }

  Future<void> reload() async {
    thyroid = (await repo.all(thyroidT))..sort((a, b) => a.date.compareTo(b.date));
    others = (await repo.all(otherT))
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    consultations = (await repo.all(consultT))..sort((a, b) => b.date.compareTo(a.date));
    doseEvents = await repo.all(doseT);
    symptoms = (await repo.all(symptomT))..sort((a, b) => b.date.compareTo(a.date));
    attachments = await repo.all(attachmentT);
    loaded = true;
    notifyListeners();
  }

  /// Enregistre et retourne l'identifiant de la ligne.
  Future<int> save<T>(TableDef<T> t, T item) async {
    final id = await repo.save(t, item);
    await reload();
    return id;
  }

  Future<void> remove<T>(TableDef<T> t, int id) async {
    final kind = t.name == thyroidT.name
        ? kAttThyroid
        : (t.name == otherT.name ? kAttOther : null);
    if (kind != null) {
      for (final a in attachmentsFor(kind, id)) {
        if (a.id != null) await repo.delete(attachmentT, a.id!);
        if (!_pathShared(a)) await deleteLocalFile(a.path);
      }
    }
    await repo.delete(t, id);
    await reload();
  }

  // ---- Photos jointes --------------------------------------------------

  List<Attachment> attachmentsFor(String kind, int? refId) => refId == null
      ? const <Attachment>[]
      : [
          for (final a in attachments)
            if (a.kind == kind && a.refId == refId) a,
        ];

  int attachmentCount(String kind, int? refId) =>
      attachmentsFor(kind, refId).length;

  Future<void> addAttachment(String kind, int refId, String path) async {
    await repo.save(attachmentT, Attachment(kind: kind, refId: refId, path: path));
    await reload();
  }

  Future<void> attachPending(String kind, int refId, List<String> paths) async {
    if (paths.isEmpty) return;
    for (final p in paths) {
      await repo.save(attachmentT, Attachment(kind: kind, refId: refId, path: p));
    }
    await reload();
  }

  Future<void> deleteAttachment(Attachment a) async {
    if (a.id != null) await repo.delete(attachmentT, a.id!);
    if (!_pathShared(a)) await deleteLocalFile(a.path);
    await reload();
  }

  /// Une meme photo peut etre jointe a plusieurs analyses (scan d'une feuille).
  bool _pathShared(Attachment a) =>
      attachments.any((o) => o.path == a.path && o.id != a.id);

  Future<void> setLang(String l) async {
    lang = l;
    await prefs.setString('lang', l);
    notifyListeners();
  }

  Future<void> setDark(bool v) async {
    dark = v;
    await prefs.setBool('dark', v);
    notifyListeners();
  }

  Future<void> setRefs(RefRanges r) async {
    refs = r;
    await prefs.setString('refs', jsonEncode(r.toMap()));
    notifyListeners();
  }

  Future<void> setProfile(PatientProfile p) async {
    profile = p;
    await prefs.setString('profile', jsonEncode(p.toMap()));
    notifyListeners();
  }

  // ---- Vues derivees -------------------------------------------------

  /// Derniere entree (par date) ayant une valeur pour [f].
  ThyroidEntry? lastWith(double? Function(ThyroidEntry) f, {int skip = 0}) {
    var seen = 0;
    for (var i = thyroid.length - 1; i >= 0; i--) {
      if (f(thyroid[i]) != null) {
        if (seen == skip) return thyroid[i];
        seen++;
      }
    }
    return null;
  }

  List<ChartPoint> points(double? Function(ThyroidEntry) f) => [
        for (final e in thyroid)
          if (f(e) != null) ChartPoint(e.date, f(e)!),
      ];

  DoseEvent? get latestPrescribed {
    DoseEvent? best;
    for (final e in doseEvents.where((e) => e.kind == kDosePrescribed)) {
      if (best == null) {
        best = e;
        continue;
      }
      final a = best.date ?? DateTime(1900);
      final b = e.date ?? DateTime(1900);
      if (b.isAfter(a) || (b == a && (e.id ?? 0) > (best.id ?? 0))) best = e;
    }
    return best;
  }

  DateTime? get nextControlDate {
    if (profile.nextControlDate != null) return profile.nextControlDate;
    for (final c in consultations) {
      if (c.nextControl != null) return c.nextControl;
    }
    return null;
  }

  /// Timeline Levothyrox : doses de l'historique + evenements, par date.
  List<DoseItem> get doseItems {
    final items = <DoseItem>[
      for (final e in thyroid)
        if (e.doseUg != null)
          DoseItem(
              date: e.date,
              kind: kDoseRecorded,
              doseUg: e.doseUg!,
              source: e.source,
              tsh: e.tsh,
              ft4: e.ft4,
              ft3: e.ft3),
      for (final ev in doseEvents)
        DoseItem(
            date: ev.date,
            kind: ev.kind,
            doseUg: ev.doseUg,
            note: ev.note,
            source: ev.source,
            event: ev),
    ];
    items.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });
    return items;
  }

  // ---- Sauvegarde ----------------------------------------------------

  Future<String> exportBackupJson() async => encodeBackup(
        profile: profile.toMap(),
        refs: refs.toMap(),
        tables: await repo.dumpRaw(),
      );

  /// Verifie qu'une sauvegarde est lisible AVANT de remplacer les donnees.
  void validateBundle(BackupBundle b) {
    final checks = <String, void Function(Map<String, Object?>)>{
      thyroidT.name: (m) => thyroidT.fromMap(m),
      otherT.name: (m) => otherT.fromMap(m),
      consultT.name: (m) => consultT.fromMap(m),
      doseT.name: (m) => doseT.fromMap(m),
      symptomT.name: (m) => symptomT.fromMap(m),
      attachmentT.name: (m) => attachmentT.fromMap(m),
    };
    for (final e in checks.entries) {
      for (final row in b.tables[e.key] ?? const <Map<String, Object?>>[]) {
        try {
          e.value(row);
        } catch (_) {
          throw FormatException('Ligne illisible dans ${e.key}');
        }
      }
    }
  }

  Future<void> restoreBackup(BackupBundle b) async {
    validateBundle(b);
    await repo.replaceAll(b.tables);
    await setProfile(PatientProfile.fromMap(b.profile));
    await setRefs(RefRanges.fromMap(b.refs));
    await reload();
  }
}
