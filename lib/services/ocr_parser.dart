import 'dart:math' as math;

import '../core/format.dart';

/// Lecture d'une feuille de resultats de laboratoire a partir du texte
/// reconnu par l'OCR du telephone. Aucune donnee ne quitte l'appareil.

// ----------------------------------------------------------- OCR brut ----

/// Une ligne reconnue par l'OCR avec sa position (quadrilatere de 4 coins :
/// haut-gauche, haut-droite, bas-droite, bas-gauche).
class OcrLine {
  OcrLine(this.text, this.cx, this.cy, this.width, this.height, this.angle);

  factory OcrLine.fromCorners(String text, List<double> c) {
    double d(double x, double y) => math.sqrt(x * x + y * y);
    return OcrLine(
      text,
      (c[0] + c[2] + c[4] + c[6]) / 4,
      (c[1] + c[3] + c[5] + c[7]) / 4,
      d(c[2] - c[0], c[3] - c[1]),
      d(c[6] - c[0], c[7] - c[1]),
      math.atan2(c[3] - c[1], c[2] - c[0]),
    );
  }

  final String text;
  final double cx, cy, width, height, angle;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Regroupe les lignes OCR en rangees de texte (une rangee = une ligne de la
/// feuille), apres correction de l'inclinaison de la photo.
List<String> reconstructRows(List<OcrLine> lines) {
  if (lines.isEmpty) return [];
  final angles = [
    for (final l in lines)
      if (l.width > l.height * 3) l.angle,
  ];
  final theta = angles.isEmpty ? 0.0 : _median(angles);
  final c = math.cos(theta), s = math.sin(theta);
  final pts = [
    for (final l in lines)
      (line: l, x: l.cx * c + l.cy * s, y: -l.cx * s + l.cy * c),
  ]..sort((a, b) => a.y.compareTo(b.y));
  final h = _median([for (final l in lines) l.height]);
  final rows = <List<({OcrLine line, double x, double y})>>[];
  var meanY = 0.0;
  for (final p in pts) {
    if (rows.isEmpty || (p.y - meanY) > h * 0.6) {
      rows.add([p]);
      meanY = p.y;
    } else {
      rows.last.add(p);
      meanY = rows.last.fold(0.0, (a, b) => a + b.y) / rows.last.length;
    }
  }
  return [
    for (final r in rows)
      (r..sort((a, b) => a.x.compareTo(b.x)))
          .map((p) => p.line.text.trim())
          .where((t) => t.isNotEmpty)
          .join(' '),
  ];
}

// ---------------------------------------------------------- Analyse -----

class RangeCandidate {
  const RangeCandidate(this.label, this.min, this.max, this.unit);
  final String label, unit;
  final double? min, max;
}

class ParsedResult {
  ParsedResult({
    required this.name,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.raw,
    required this.order,
    this.thyroidKey,
    this.candidates = const [],
    this.defaultCandidate,
  });

  final String name, unit, raw;
  final double? value, min, max;
  final int order;

  /// 'TSH', 'FT4' ou 'FT3' pour le bilan thyroidien ; null sinon.
  final String? thyroidKey;

  /// Intervalles proposes par la feuille (ex. selon le sexe / l'age).
  final List<RangeCandidate> candidates;
  final int? defaultCandidate;
}

class ParsedSheet {
  ParsedSheet({
    required this.date,
    required this.dateFromSample,
    required this.results,
    this.patientLine,
    this.patientMatches,
    this.labLine,
  });

  final DateTime? date;
  final bool dateFromSample;
  final List<ParsedResult> results;
  final String? patientLine, labLine;
  final bool? patientMatches;
}

const _acc = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
  'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ç': 'c', 'œ': 'oe', '’': "'",
};

/// Minuscules sans accents (pour comparer des textes).
String foldText(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_acc[ch] ?? ch);
  }
  return b.toString();
}

const _num = r'\d+(?:[.,]\d+)?';
final _rangeRe =
    RegExp('($_num)\\s*(?:à|a|-|–|—)\\s*($_num)', caseSensitive: false);
final _ltRe = RegExp('<\\s*($_num)');
final _gtRe = RegExp('>\\s*($_num)');
final _unitRe = RegExp(r'^\s*([A-Za-zµμ]+(?:/[A-Za-zµμ]+)?%?|%)');
final _sepRe = RegExp(r'\.{2,}|…|:');
final _candRe = RegExp(
    '^(.*?)\\s*:\\s*($_num)\\s*(?:-|–|à)\\s*($_num)\\s*([A-Za-zµμ/%]+)\\s*\$');
final _dateRe = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4}|\d{2})');
final _numRe = RegExp(_num);

const _skip = [
  'resultats', 'prelevement', 'antecedent', 'dossier', 'age', 'page',
  'total', 'demande', 'tel', 'il est', 'des fluct', 'les changements',
  'ou de certains', 'interpret', 'laboratoire', 'edite',
];

// (motifs sur texte replie, nom affiche, cle thyroide)
const _known = <(List<String>, String, String?)>[
  (['ft3', 't3 libre', 'triiodothyronine'], 'FT3', 'FT3'),
  (['ft4', 't4 libre', 'thyroxine libre'], 'FT4', 'FT4'),
  (['tsh'], 'TSH', 'TSH'),
  (['ferritine'], 'Ferritine', null),
  (['vitamine d', '25-oh', '25 oh'], 'Vitamine D', null),
  (['sodium', 'natremie'], 'Sodium', null),
  (['potassium', 'kaliemie'], 'Potassium', null),
  (['cortisol'], 'Cortisol', null),
  (['acth'], 'ACTH', null),
  (['anti-tpo', 'anti tpo', 'atpo', 'peroxydase'], 'Anticorps ATPO', null),
  (['anti-tg', 'anti tg', 'atg', 'thyroglobuline'], 'Anticorps ATG', null),
  (['glycemie'], 'Glycémie', null),
  (['hba1c', 'hemoglobine glyquee'], 'HbA1c', null),
  (['creatinine'], 'Créatinine', null),
  (['fer serique', 'sideremie'], 'Fer sérique', null),
  (['vitamine b12', 'b12'], 'Vitamine B12', null),
  (['calcium', 'calcemie'], 'Calcium', null),
  (['cholesterol'], 'Cholestérol', null),
];

(String?, String?) _knownOf(String label) {
  final f = foldText(label);
  for (final k in _known) {
    if (k.$1.any(f.contains)) return (k.$2, k.$3);
  }
  return (null, null);
}

String _strip(String s, String chars) {
  var a = 0, b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

String _lstrip(String s, String chars) {
  var a = 0;
  while (a < s.length && chars.contains(s[a])) {
    a++;
  }
  return s.substring(a);
}

String _pretty(String label) {
  final l = _strip(label.replaceAll(RegExp(r'\s+'), ' '), ' .:-');
  if (l.isEmpty) return l;
  return l[0].toUpperCase() + l.substring(1).toLowerCase();
}

String _norm(String row) => row.replaceAllMapped(
    RegExp(r'(\d)\s*([,.])\s*(\d)'), (m) => '${m[1]}${m[2]}${m[3]}');

List<DateTime> _datesIn(String row) {
  final out = <DateTime>[];
  for (final m in _dateRe.allMatches(row)) {
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final mo = int.parse(m[2]!), d = int.parse(m[1]!);
    final dt = DateTime(y, mo, d);
    if (dt.year == y && dt.month == mo && dt.day == d) out.add(dt);
  }
  return out;
}

ParsedResult? _parseRow(String rawRow, int order) {
  final row = _norm(rawRow);
  final f = foldText(row).trim();
  if (_skip.any(f.startsWith)) return null;

  String label, rest;
  final sep = _sepRe.firstMatch(row);
  if (sep != null) {
    label = row.substring(0, sep.start);
    rest = _lstrip(row.substring(sep.end), '.: ');
  } else {
    final mm = RegExp('\\s$_num\\b').firstMatch(row);
    if (mm == null) return null;
    label = row.substring(0, mm.start);
    rest = row.substring(mm.start);
    if (_knownOf(label).$1 == null) return null;
  }
  label = _strip(label, ' .:');
  if (label.length < 2 ||
      label.length > 60 ||
      !RegExp(r'[A-Za-z]{2}').hasMatch(label)) {
    return null;
  }
  final vm = _numRe.firstMatch(rest);
  if (vm == null) return null;
  final value = parseNumber(vm.group(0)!);
  var after = rest.substring(vm.end);

  var unit = '';
  final um = _unitRe.firstMatch(after);
  if (um != null && !const ['a', 'à'].contains(um.group(1)!.toLowerCase())) {
    unit = um.group(1)!;
    after = after.substring(um.end);
  }

  double? rmin, rmax;
  final rm = _rangeRe.firstMatch(after);
  if (rm != null) {
    rmin = parseNumber(rm.group(1)!);
    rmax = parseNumber(rm.group(2)!);
  } else {
    final lt = _ltRe.firstMatch(after);
    final gt = _gtRe.firstMatch(after);
    if (lt != null) rmax = parseNumber(lt.group(1)!);
    if (gt != null) rmin = parseNumber(gt.group(1)!);
  }

  final k = _knownOf(label);
  if (k.$1 == null && unit.isEmpty && rmin == null && rmax == null) {
    return null;
  }
  return ParsedResult(
    name: k.$1 ?? _pretty(label),
    thyroidKey: k.$2,
    value: value,
    unit: unit,
    min: rmin,
    max: rmax,
    raw: row.trim(),
    order: order,
  );
}

/// Analyse les rangees de texte d'une feuille de resultats.
/// [female] / [age] servent a pre-choisir l'intervalle de reference quand la
/// feuille en propose plusieurs (ex. ferritine : homme / femme).
ParsedSheet parseLabRows(
  List<String> rows, {
  bool female = true,
  int? age,
  String profileName = '',
}) {
  final parsed = <ParsedResult>[];
  final cands = <RangeCandidate>[];
  final dates = <DateTime>[];
  DateTime? sample;
  String? patient, lab;
  var inInterp = false;

  for (final row in rows) {
    final f = foldText(row);
    if (f.contains('interpret')) {
      inInterp = true;
      continue;
    }
    final ds = _datesIn(row);
    if (f.contains('prelevement') && ds.isNotEmpty) sample ??= ds.first;
    dates.addAll(ds);
    if (patient == null &&
        RegExp(r'^(mme|mr|mlle|m\.|madame|monsieur)\b').hasMatch(f)) {
      patient = row.trim();
    }
    if (lab == null && f.contains('laboratoire')) lab = row.trim();

    if (inInterp) {
      final cm = _candRe.firstMatch(_norm(row).trim());
      if (cm != null) {
        cands.add(RangeCandidate(cm.group(1)!.trim(), parseNumber(cm.group(2)!),
            parseNumber(cm.group(3)!), cm.group(4)!));
      }
      continue;
    }
    final r = _parseRow(row, parsed.length);
    if (r != null) parsed.add(r);
  }

  DateTime? date = sample;
  if (date == null && dates.isNotEmpty) {
    date = dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  final results = <ParsedResult>[];
  for (final r in parsed) {
    if (r.min == null && r.max == null) {
      final c = [
        for (final x in cands)
          if (x.unit.toLowerCase() == r.unit.toLowerCase()) x,
      ];
      int? sel;
      for (var i = 0; i < c.length; i++) {
        final fl = foldText(c[i].label);
        if (female &&
            fl.contains('femme') &&
            !fl.contains('menopaus') &&
            (age == null || age < 50)) {
          sel = i;
          break;
        }
      }
      results.add(ParsedResult(
        name: r.name,
        thyroidKey: r.thyroidKey,
        value: r.value,
        unit: r.unit,
        min: r.min,
        max: r.max,
        raw: r.raw,
        order: r.order,
        candidates: c,
        defaultCandidate: sel,
      ));
    } else {
      results.add(r);
    }
  }

  bool? match;
  if (patient != null && profileName.trim().isNotEmpty) {
    final toks =
        foldText(profileName).split(RegExp(r'\s+')).where((t) => t.length >= 3);
    final p = foldText(patient);
    match = toks.any(p.contains);
  }

  return ParsedSheet(
    date: date,
    dateFromSample: sample != null,
    results: results,
    patientLine: patient,
    patientMatches: match,
    labLine: lab,
  );
}
