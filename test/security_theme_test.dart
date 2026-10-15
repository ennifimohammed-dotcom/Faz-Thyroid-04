import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fatma_zahra_thyroid_tracker/app/palette.dart';
import 'package:fatma_zahra_thyroid_tracker/features/lock/lock_gate.dart';
import 'package:fatma_zahra_thyroid_tracker/features/state/app_state.dart';
import 'package:fatma_zahra_thyroid_tracker/models/models.dart';
import 'package:fatma_zahra_thyroid_tracker/repositories/health_repository.dart';
import 'package:fatma_zahra_thyroid_tracker/services/app_lock.dart';
import 'package:fatma_zahra_thyroid_tracker/widgets/chart_utils.dart';
import 'package:fatma_zahra_thyroid_tracker/widgets/common.dart';

Future<AppState> _state([Map<String, Object> prefsInit = const {}]) async {
  SharedPreferences.setMockInitialValues(prefsInit);
  final prefs = await SharedPreferences.getInstance();
  final st = AppState(repo: MemoryRepository.seeded(), prefs: prefs);
  await st.load();
  return st;
}

void main() {
  group('code secret', () {
    test('activation, vérification, persistance, désactivation', () async {
      final st = await _state();
      expect(st.pinEnabled, isFalse);
      await st.setPin('1234');
      expect(st.pinEnabled, isTrue);
      expect(st.verifyPin('1234'), isTrue);
      expect(st.verifyPin('0000'), isFalse);
      expect(st.verifyPin(''), isFalse);

      // le code n'est jamais stocké en clair
      final raw = st.prefs.getString('pin_hash')!;
      expect(raw.contains('1234'), isFalse);
      expect(raw.length, 64); // SHA-256 en hexadécimal

      // relance de l'application : le code est toujours demandé
      final again = AppState(repo: MemoryRepository.seeded(), prefs: st.prefs);
      await again.load();
      expect(again.pinEnabled, isTrue);
      expect(again.verifyPin('1234'), isTrue);

      await again.clearPin();
      expect(again.pinEnabled, isFalse);
      expect(again.verifyPin('1234'), isFalse);
    });

    test('deux activations donnent des empreintes différentes (sel)', () async {
      final st = await _state();
      await st.setPin('1111');
      final a = st.prefs.getString('pin_hash');
      await st.setPin('1111');
      expect(st.prefs.getString('pin_hash'), isNot(a));
    });

    test('retour d\'une action externe : pas de verrouillage', () {
      AppLock.beginExternal();
      AppLock.endExternal();
      expect(AppLock.consumeExternal(), isTrue);
      expect(AppLock.consumeExternal(), isFalse); // un seul usage
    });

    testWidgets('écran de verrouillage : mauvais puis bon code', (tester) async {
      final st = await _state();
      await st.setPin('1234');
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: MaterialApp(
            builder: (c, child) => LockGate(child: child!),
            home: const Scaffold(body: Text('CONTENU')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PinPad), findsOneWidget);

      for (final d in ['0', '0', '0', '0']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Code incorrect'), findsOneWidget);
      expect(find.byType(PinPad), findsOneWidget);

      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsNothing);
    });
  });

  group('nom de la patiente', () {
    test('plus de nom pré-rempli : invitation à saisir', () async {
      final st = await _state();
      expect(st.hasName, isFalse);
      expect(st.displayName, 'Entrez le nom');
      await st.setLang('ar');
      expect(st.displayName, 'أدخل الاسم');
    });

    test('le nom saisi s\'affiche, avec repli sur l\'autre langue', () async {
      final st = await _state();
      await st.setProfile(const PatientProfile(nameFr: 'Amina'));
      expect(st.hasName, isTrue);
      expect(st.displayName, 'Amina');
      await st.setLang('ar');
      expect(st.displayName, 'Amina'); // pas de nom arabe : on affiche l'autre
    });

    test('l\'ancien nom pré-rempli est supprimé des profils enregistrés', () async {
      final old = jsonEncode({
        'nameFr': 'Fatma Zahra Belqas',
        'nameAr': 'فاطمة الزهراء بلقاس',
        'weight': '89 kg',
      });
      final st = await _state({'profile': old});
      expect(st.profile.nameFr, '');
      expect(st.profile.nameAr, '');
      expect(st.profile.weight, '89 kg'); // le reste est conservé
      expect(st.displayName, 'Entrez le nom');
    });

    test('un nom saisi par l\'utilisatrice n\'est jamais effacé', () async {
      final mine = jsonEncode({'nameFr': 'Sara', 'nameAr': ''});
      final st = await _state({'profile': mine});
      expect(st.profile.nameFr, 'Sara');
    });
  });

  group('thèmes de couleur', () {
    test('quatre thèmes distincts', () {
      expect(kPalettes.length, 4);
      expect(kPalettes.map((p) => p.id).toSet().length, 4);
      expect(kPalettes.map((p) => p.seed).toSet().length, 4);
    });

    test('choix mémorisé, identifiant inconnu ramené au thème par défaut', () async {
      final st = await _state();
      expect(st.palette.id, 'rose');
      await st.setPalette('mint');
      expect(st.palette.id, 'mint');
      final again = AppState(repo: MemoryRepository.seeded(), prefs: st.prefs);
      await again.load();
      expect(again.palette.id, 'mint');
      await again.setPalette('inconnu');
      expect(again.palette.id, 'rose');
    });
  });

  group('graphique : dates et valeurs', () {
    test('graduations régulières, extrémités incluses', () {
      expect(evenTicks(0, 100, 5), [0, 25, 50, 75, 100]);
      expect(evenTicks(10, 20, 2), [10, 20]);
    });

    test('nombre de graduations adapté à la largeur', () {
      expect(tickCount(40), 2);
      expect(tickCount(200), 3);
      expect(tickCount(600), 5);
    });

    test('libellés de dates courts et lisibles', () {
      final x = ChartPoint(DateTime(2026, 9, 28), 1).x;
      expect(tickLabel(x, 700), '09/26'); // longue période : mois/année
      expect(tickLabel(x, 30), '28/09'); // courte période : jour/mois
    });

    test('x est un nombre entier de jours (indépendant de l\'heure)', () {
      final a = ChartPoint(DateTime(2026, 9, 28, 0, 0), 1).x;
      final b = ChartPoint(DateTime(2026, 9, 28, 23, 59), 1).x;
      expect(a, b);
      expect(a, a.roundToDouble());
    });

    testWidgets('valeurs affichées sur les points et dates aux extrémités',
        (tester) async {
      final pts = [
        ChartPoint(DateTime(2025, 11, 11), 20.9),
        ChartPoint(DateTime(2026, 1, 17), 8.48),
        ChartPoint(DateTime(2026, 5, 8), 10.9),
        ChartPoint(DateTime(2026, 9, 28), 11.93),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: TrendChart(
                points: pts,
                color: Colors.pink,
                emptyText: 'aucune donnée',
                refMin: 0.27,
                refMax: 4.2,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('20.9'), findsOneWidget);
      expect(find.text('8.48'), findsOneWidget);
      expect(find.text('10.9'), findsOneWidget);
      expect(find.text('11.93'), findsOneWidget);
      expect(find.text('11/25'), findsOneWidget); // première date
      expect(find.text('09/26'), findsOneWidget); // dernière date
    });
  });
}
