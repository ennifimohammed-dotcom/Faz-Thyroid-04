import '../database/schema.dart';
import '../features/state/app_state.dart';
import '../models/models.dart';
import 'ocr_parser.dart';

/// Une ligne validee (ou non) par l'utilisatrice dans l'ecran de verification.
class ScanRowData {
  const ScanRowData({
    required this.name,
    required this.thyroidKey,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.include,
    this.comment = '',
  });
  final String name, unit, comment;
  final String? thyroidKey; // 'TSH' | 'FT4' | 'FT3' | null
  final double? value, min, max;
  final bool include;
}

class ScanCommitResult {
  int added = 0; // nouvelles lignes creees
  int completed = 0; // champs vides d'un bilan existant completes
  int attached = 0; // lignes auxquelles la photo a ete jointe
  bool get nothing => added == 0 && completed == 0 && attached == 0;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Enregistre le resultat d'un scan, SANS jamais ecraser une valeur deja
/// presente : un bilan existant n'est complete que dans ses champs vides, et
/// une analyse deja enregistree (meme date + meme nom) reste inchangee.
/// La photo est jointe a chaque ligne concernee, nouvelle ou existante.
Future<ScanCommitResult> commitScan(
  AppState st, {
  required DateTime date,
  required String lab,
  required String photoPath,
  required List<ScanRowData> rows,
}) async {
  final res = ScanCommitResult();

  // ---- Bilan thyroidien -------------------------------------------------
  final thyroidRows = rows.where((r) => r.thyroidKey != null).toList();
  if (thyroidRows.isNotEmpty) {
    double? pick(String key) {
      for (final r in thyroidRows) {
        if (r.thyroidKey == key && r.include) return r.value;
      }
      return null;
    }

    final tsh = pick('TSH'), ft4 = pick('FT4'), ft3 = pick('FT3');
    ThyroidEntry? ex;
    for (final e in st.thyroid) {
      if (_sameDay(e.date, date)) ex = e;
    }
    if (ex != null) {
      final nTsh = ex.tsh ?? tsh;
      final nFt4 = ex.ft4 ?? ft4;
      final nFt3 = ex.ft3 ?? ft3;
      final filled = (ex.tsh == null && tsh != null ? 1 : 0) +
          (ex.ft4 == null && ft4 != null ? 1 : 0) +
          (ex.ft3 == null && ft3 != null ? 1 : 0);
      if (filled > 0) {
        await st.save(
          thyroidT,
          ThyroidEntry(
            id: ex.id,
            date: ex.date,
            tsh: nTsh,
            ft4: nFt4,
            ft3: nFt3,
            doseUg: ex.doseUg,
            comment: ex.comment,
            decision: ex.decision,
            source: markEdited(ex.source),
          ),
        );
        res.completed += filled;
      }
      if (ex.id != null) {
        await st.addAttachment(kAttThyroid, ex.id!, photoPath);
        res.attached++;
      }
    } else if (tsh != null || ft4 != null || ft3 != null) {
      final id = await st.save(
        thyroidT,
        ThyroidEntry(
            date: date, tsh: tsh, ft4: ft4, ft3: ft3, source: kSrcScan),
      );
      res.added += [tsh, ft4, ft3].where((v) => v != null).length;
      await st.addAttachment(kAttThyroid, id, photoPath);
      res.attached++;
    }
  }

  // ---- Autres analyses (ordre de la feuille conserve) --------------------
  for (final r in rows.where((r) => r.thyroidKey == null)) {
    final name = r.name.trim();
    if (name.isEmpty) continue;
    OtherAnalysis? ex;
    for (final a in st.others) {
      if (_sameDay(a.date, date) && foldText(a.name) == foldText(name)) ex = a;
    }
    if (ex != null) {
      if (ex.id != null) {
        await st.addAttachment(kAttOther, ex.id!, photoPath);
        res.attached++;
      }
      continue;
    }
    if (!r.include || r.value == null) continue;
    final id = await st.save(
      otherT,
      OtherAnalysis(
        date: date,
        name: name,
        value: r.value,
        unit: r.unit,
        refMin: r.min,
        refMax: r.max,
        lab: lab.trim(),
        comment: r.comment,
        source: kSrcScan,
      ),
    );
    res.added++;
    await st.addAttachment(kAttOther, id, photoPath);
    res.attached++;
  }
  return res;
}
