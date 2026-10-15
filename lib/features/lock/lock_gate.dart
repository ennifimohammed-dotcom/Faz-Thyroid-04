import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/palette.dart';
import '../../services/app_lock.dart';
import '../state/app_state.dart';

/// Couche de verrouillage au-dessus de toute l'application.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  /// Delai passe en arriere-plan au-dela duquel le code est redemande.
  static const Duration _grace = Duration(seconds: 20);

  bool? _locked;
  DateTime? _pausedAt;
  int _fails = 0;
  DateTime? _blockedUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      _pausedAt = null;
      if (AppLock.consumeExternal()) return;
      final st = context.read<AppState>();
      if (st.pinEnabled && p != null && DateTime.now().difference(p) > _grace) {
        setState(() => _locked = true);
      }
    }
  }

  Future<String?> _check(AppState st, String pin) async {
    final s = st.s;
    final until = _blockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final left = until.difference(DateTime.now()).inSeconds + 1;
      return '${s.t('pin_blocked')} $left ${s.t('pin_seconds')}';
    }
    if (st.verifyPin(pin)) {
      _fails = 0;
      _blockedUntil = null;
      if (mounted) setState(() => _locked = false);
      return null;
    }
    _fails++;
    if (_fails >= 5) {
      _fails = 0;
      _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      return '${s.t('pin_blocked')} 30 ${s.t('pin_seconds')}';
    }
    return s.t('pin_wrong');
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    _locked ??= st.pinEnabled;
    final locked = _locked! && st.pinEnabled;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: PopScope(
              canPop: false,
              child: Scaffold(
                body: SafeArea(
                  child: PinPad(
                    title: st.s.t('pin_unlock_title'),
                    subtitle: st.s.t('pin_enter'),
                    onCompleted: (pin) => _check(st, pin),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Clavier numerique a 4 chiffres. [onCompleted] retourne un message d'erreur
/// ou null si le code est accepte (le parent decide alors de la suite).
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    required this.onCompleted,
  });

  final String title;
  final String? subtitle;
  final Future<String?> Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _entered = '';
  String? _error;
  bool _busy = false;

  void _tap(String d) {
    if (_busy || _entered.length >= 4) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == 4) _submit();
  }

  void _back() {
    if (_busy || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final err = await widget.onCompleted(_entered);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _entered = '';
      _error = err;
    });
  }

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) {
    final color = context.brand;
    return SizedBox(
      width: 78,
      height: 78,
      child: onTap == null
          ? null
          : Material(
              color: color.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(
                  child: icon != null
                      ? Icon(icon, color: color, size: 26)
                      : Text(label,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: color)),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = context.brand;
    Widget row(List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in children)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: c),
              ]),
        );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  gradient: context.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Text(widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, color: context.brandDeep)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(widget.subtitle!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length ? color : Colors.transparent,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(_error ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
            // Les chiffres restent dans le meme ordre en arabe (gauche -> droite).
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(children: [
                row([for (final d in ['1', '2', '3']) _key(d, onTap: () => _tap(d))]),
                row([for (final d in ['4', '5', '6']) _key(d, onTap: () => _tap(d))]),
                row([for (final d in ['7', '8', '9']) _key(d, onTap: () => _tap(d))]),
                row([
                  _key(''),
                  _key('0', onTap: () => _tap('0')),
                  _key('', onTap: _back, icon: Icons.backspace_outlined),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creation du code (saisie + confirmation).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final s = st.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pin_title'))),
      body: Column(
        children: [
          Expanded(
            child: PinPad(
              key: ValueKey(_first == null),
              title: _first == null ? s.t('pin_new') : s.t('pin_confirm'),
              subtitle: _first == null ? s.t('pin_warning') : null,
              onCompleted: (pin) async {
                if (_first == null) {
                  setState(() => _first = pin);
                  return null;
                }
                if (pin != _first) {
                  setState(() => _first = null);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(s.t('pin_mismatch'))));
                  return null;
                }
                await st.setPin(pin);
                if (!context.mounted) return null;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(s.t('pin_set_done'))));
                Navigator.pop(context);
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Verification du code actuel avant une action sensible.
class PinVerifyScreen extends StatelessWidget {
  const PinVerifyScreen({super.key, required this.title, required this.onVerified});

  final String title;

  /// Appelee quand le code est correct (le contexte est celui de cet ecran).
  final Future<void> Function(BuildContext context) onVerified;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final s = st.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pin_title'))),
      body: PinPad(
        title: title,
        subtitle: s.t('pin_current'),
        onCompleted: (pin) async {
          if (!st.verifyPin(pin)) return s.t('pin_wrong');
          await onVerified(context);
          return null;
        },
      ),
    );
  }
}
