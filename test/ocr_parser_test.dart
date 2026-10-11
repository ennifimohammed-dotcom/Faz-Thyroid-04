import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fatma_zahra_thyroid_tracker/database/schema.dart';
import 'package:fatma_zahra_thyroid_tracker/features/state/app_state.dart';
import 'package:fatma_zahra_thyroid_tracker/models/models.dart';
import 'package:fatma_zahra_thyroid_tracker/repositories/health_repository.dart';
import 'package:fatma_zahra_thyroid_tracker/services/ocr_parser.dart';
import 'package:fatma_zahra_thyroid_tracker/services/scan_commit.dart';

// Texte tel que l'OCR le restitue pour les 3 photos de laboratoire fournies.
const _sheetTsh = [
  'LABORATOIRE D’ANALYSES',
  'Prélèvement du : 28/09/2026 à 07:44',
  'Résultats édités le: 28/09/2026',
  'MME BELQAS FATIMA ZAHRA',
  'Dossier N° 21F428',
  'Age: 33 ans',
  'Page: 1/1',
  'HORMONES SANG',
  '( Automates Cobas e411 ROCHE - VIDAS BioMérieux )',
  'TSH ultra-sensible................: 11,930 mU/L (*) 0,270 à 4,200 mU/L',
  '(Electrochimiluminescence)',
  'Antécédent du 08/05/26 - 08:00 : 10,900 mU/L',
  '20,9 8,48 10,9 11,93',
  '11/11/2025 17/01/2026 08/05/2026 28/09/2026',
  'Résultat controlé',
  'Il est à noter :',
  'Des fluctuations rapides du taux de la TSH peuvent survenir en rapport avec :',
  'THYROXINE LIBRE.T4 LIBRE (FT4)....: 14,17 pmol/l 10,60 à 19,40 pmol/l',
  '(ELFA - VIDAS Biomérieux)',
  'TRIIODOTHYRONINE LIBRE.T3 LIBRE...: 3,40 pmol/l 3,00 à 8,50 pmol/l',
  'Demande validée biologiquement par: Dr. ALAMI OUALI Zouheir',
  'Total de pages: 1',
];

const _sheetFerritin = [
  'FERRITINE SERIQUE...............: 137,17 ng/ml',
  '(ELFA - VIDAS Biomérieux)',
  'Antécédent du 11/11/25 - 06:36 : 126,02 ng/ml',
  '160 159,81',
  '140 126,02 137,17',
  '04/02/2025 11/11/2025 08/05/2026',
  'Interprétations :',
  'Nouveau-né : 50 - 400 ng/ml',
  'Nourrisson 1 - 2 mois : 140 - 400 ng/ml',
  'Nourrisson 2 - 6 mois : 40 - 220 ng/ml',
  'Nourrisson 6 mois - Enfant jusqu\'à 15 ans : 15 - 80 ng/ml',
  'Homme : 30 - 300 ng/ml',
  'Femme cyclique : 20 - 200 ng/ml',
  'Femme ménopausée : 25 - 280 ng/ml',
  'Demande validée biologiquement par: Dr. ALAMI OUALI Zouhe',
];

const _sheetTshCropped = [
  'HORMONES SANG',
  '( Automates Cobas e411 ROCHE - VIDAS BioMérieux )',
  'TSH ultra-sensible................: 10,900 mU/L (*) 0,270 à 4,200 mU/L',
  '(Electrochimiluminescence)',
  'Antécédent du 17/01/26 - 07:00 : 8,480 mU/L',
  '40 0,024 20,9 8,48 10,9',
  '04/02/2025 11/11/2025 17/01/2026 08/05/2026',
  'Il est à noter :',
];

OcrLine _line(String text, double x, double y, {double rot = 0}) {
  final c = math.cos(rot), s = math.sin(rot);
  return OcrLine(text, x * c - y * s, x * s + y * c, 200, 20, rot);
}

Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final st = AppState(repo: MemoryRepository.seeded(), prefs: prefs);
  await st.load();
  return st;
}

void main() {
  group('reconstruction des rangées', () {
    test('photo inclinée : les morceaux d\'une même ligne sont regroupés', () {
      final lines = [
        _line('FT4 LIBRE....:', 100, 140, rot: 0.05),
        _line('TSH ultra-sensible....:', 100, 100, rot: 0.05),
        _line('14,17 pmol/l', 400, 140, rot: 0.05),
        _line('11,930 mU/L', 400, 100, rot: 0.05),
      ];
      expect(reconstructRows(lines), [
        'TSH ultra-sensible....: 11,930 mU/L',
        'FT4 LIBRE....: 14,17 pmol/l',
      ]);
    });
    test('liste vide', () => expect(reconstructRows([]), isEmpty));
  });

  group('photo 1 : bilan thyroïdien du 28/09/2026', () {
    final sheet = parseLabRows(_sheetTsh, profileName: 'Fatma Zahra Belqas');
    test('date du prélèvement', () {
      expect(sheet.date, DateTime(2026, 9, 28));
      expect(sheet.dateFromSample, isTrue);
    });
    test('trois résultats, antécédent ignoré', () {
      expect(sheet.results.length, 3);
      final tsh = sheet.results[0];
      expect([tsh.thyroidKey, tsh.value, tsh.unit, tsh.min, tsh.max],
          ['TSH', 11.93, 'mU/L', 0.27, 4.2]);
      final ft4 = sheet.results[1];
      expect([ft4.thyroidKey, ft4.value, ft4.min, ft4.max],
          ['FT4', 14.17, 10.6, 19.4]);
      final ft3 = sheet.results[2];
      expect([ft3.thyroidKey, ft3.value, ft3.min, ft3.max],
          ['FT3', 3.4, 3.0, 8.5]);
    });
    test('nom de la patiente reconnu', () {
      expect(sheet.patientMatches, isTrue);
      expect(
          parseLabRows(_sheetTsh, profileName: 'Autre Personne').patientMatches,
          isFalse);
    });
  });

  group('photo 2 : ferritine et intervalles selon le profil', () {
    final sheet = parseLabRows(_sheetFerritin);
    test('valeur et date estimée', () {
      expect(sheet.results.length, 1);
      final f = sheet.results.single;
      expect([f.name, f.value, f.unit], ['Ferritine', 137.17, 'ng/ml']);
      expect(sheet.date, DateTime(2026, 5, 8));
      expect(sheet.dateFromSample, isFalse);
    });
    test('7 intervalles proposés, « femme cyclique » présélectionné', () {
      final f = sheet.results.single;
      expect(f.candidates.length, 7);
      final i = f.defaultCandidate!;
      expect(f.candidates[i].label, 'Femme cyclique');
      expect([f.candidates[i].min, f.candidates[i].max], [20, 200]);
    });
    test('aucun préchoix pour un homme', () {
      expect(parseLabRows(_sheetFerritin, female: false)
          .results.single.defaultCandidate, isNull);
    });
  });

  test('photo 3 : feuille recadrée sans date de prélèvement', () {
    final sheet = parseLabRows(_sheetTshCropped);
    expect(sheet.results.length, 1);
    expect(sheet.results.single.value, 10.9);
    expect(sheet.date, DateTime(2026, 5, 8));
    expect(sheet.dateFromSample, isFalse);
  });

  test('tolérance au bruit de l\'OCR', () {
    final sheet = parseLabRows([
      'TSH ultra-sensible.....: 11 ,930 mU/L 0,270 a 4,200 mU/L',
      'SODIUM.....: 139,5 mmol/l 135,0 - 145,0 mmol/l',
      'Glycémie à jeun ...: 0,92 g/l < 1,10',
      'ANTI-TPO........: 196,59 UI/ml < 50',
      'TSH ultra-sensible 11,930 mU/L 0,270 à 4,200 mU/L',
    ]);
    final r = sheet.results;
    expect(r[0].value, 11.93);
    expect([r[0].min, r[0].max], [0.27, 4.2]);
    expect([r[1].name, r[1].value, r[1].min, r[1].max],
        ['Sodium', 139.5, 135, 145]);
    expect([r[2].name, r[2].value, r[2].max], ['Glycémie', 0.92, 1.1]);
    expect([r[3].name, r[3].value, r[3].max], ['Anticorps ATPO', 196.59, 50]);
    expect(r[4].value, 11.93); // sans séparateur « : »
  });

  test('lignes sans résultat ignorées', () {
    final sheet = parseLabRows([
      'Dossier N° 21F428',
      'Age: 33 ans',
      'Page: 1/1',
      'Résultats édités le: 28/09/2026',
      'Tél : 05 24 32 48 45',
    ]);
    expect(sheet.results, isEmpty);
  });

  group('enregistrement sans écrasement', () {
    test('bilan identique : rien d\'ajouté, photo jointe à l\'existant', () async {
      final st = await _state();
      final before = st.thyroid.length;
      final sheet = parseLabRows(_sheetTsh);
      final rows = [
        for (final r in sheet.results)
          ScanRowData(
              name: r.name,
              thyroidKey: r.thyroidKey,
              value: r.value,
              unit: r.unit,
              min: r.min,
              max: r.max,
              include: false), // déjà présent : non cochable
      ];
      final res = await commitScan(st,
          date: sheet.date!, lab: '', photoPath: '/tmp/faz_scan_1.jpg', rows: rows);
      expect(res.added, 0);
      expect(res.completed, 0);
      expect(res.attached, 1);
      expect(st.thyroid.length, before);
      final e = st.thyroid.firstWhere((e) => e.date == DateTime(2026, 9, 28));
      expect(e.tsh, 11.93);
      expect(e.ft4, 14.17);
      expect(st.attachmentCount(kAttThyroid, e.id), 1);
    });

    test('nouvelle analyse : ajoutée avec sa photo et ses bornes', () async {
      final st = await _state();
      final sheet = parseLabRows(_sheetFerritin);
      final r = sheet.results.single;
      final c = r.candidates[r.defaultCandidate!];
      final res = await commitScan(st,
          date: sheet.date!,
          lab: 'Labo test',
          photoPath: '/tmp/faz_scan_2.jpg',
          rows: [
            ScanRowData(
                name: r.name,
                thyroidKey: null,
                value: r.value,
                unit: r.unit,
                min: c.min,
                max: c.max,
                include: true,
                comment: 'Lu par OCR'),
          ]);
      expect(res.added, 1);
      final a = st.others.firstWhere((a) => a.name == 'Ferritine');
      expect([a.value, a.refMin, a.refMax, a.lab, a.source],
          [137.17, 20, 200, 'Labo test', kSrcScan]);
      expect(st.attachmentCount(kAttOther, a.id), 1);
    });

    test('bilan existant : seuls les champs vides sont complétés', () async {
      final st = await _state();
      final before = st.thyroid.firstWhere((e) => e.date == DateTime(2026, 5, 8));
      expect(before.ft4, isNull);
      final res = await commitScan(st,
          date: DateTime(2026, 5, 8),
          lab: '',
          photoPath: '/tmp/faz_scan_3.jpg',
          rows: const [
            ScanRowData(
                name: 'TSH', thyroidKey: 'TSH', value: 99, unit: '',
                min: null, max: null, include: true),
            ScanRowData(
                name: 'FT4', thyroidKey: 'FT4', value: 15, unit: '',
                min: null, max: null, include: true),
          ]);
      expect(res.completed, 1); // FT4 seulement
      final after = st.thyroid.firstWhere((e) => e.date == DateTime(2026, 5, 8));
      expect(after.tsh, 10.9); // jamais écrasé
      expect(after.ft4, 15);
      expect(after.doseUg, 75);
      expect(after.source, endsWith('+edit'));
    });

    test('nouveau bilan : créé avec la source « scan »', () async {
      final st = await _state();
      await commitScan(st,
          date: DateTime(2026, 10, 20),
          lab: '',
          photoPath: '/tmp/faz_scan_4.jpg',
          rows: const [
            ScanRowData(
                name: 'TSH', thyroidKey: 'TSH', value: 6.2, unit: 'mU/L',
                min: null, max: null, include: true),
          ]);
      final e = st.thyroid.firstWhere((e) => e.date == DateTime(2026, 10, 20));
      expect([e.tsh, e.ft4, e.source], [6.2, null, kSrcScan]);
    });

    test('photo partagée : le fichier survit à la suppression d\'une ligne', () async {
      final st = await _state();
      final e = st.thyroid.last;
      await st.addAttachment(kAttThyroid, e.id!, '/tmp/faz_shared.jpg');
      final other = st.others.first;
      await st.addAttachment(kAttOther, other.id!, '/tmp/faz_shared.jpg');
      await st.deleteAttachment(st.attachmentsFor(kAttThyroid, e.id).single);
      expect(st.attachmentCount(kAttOther, other.id), 1);
      await st.remove(otherT, other.id!);
      expect(st.attachments, isEmpty);
    });
  });
}
