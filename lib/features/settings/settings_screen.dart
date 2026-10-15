import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/palette.dart';
import '../lock/lock_gate.dart';
import '../state/app_state.dart';
import 'forms.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    void open(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(s.t('menu_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('language'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'fr', label: Text('Français')),
            ],
            selected: {st.lang},
            onSelectionChanged: (v) => st.setLang(v.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(s.t('theme_dark')),
            value: st.dark,
            onChanged: st.setDark,
          ),
          const SizedBox(height: 8),
          Text(s.t('theme_color'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final p in kPalettes)
                GestureDetector(
                  onTap: () => st.setPalette(p.id),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: p.gradient,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: st.paletteId == p.id
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: st.paletteId == p.id
                            ? const Icon(Icons.check_rounded, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(s.t(p.nameKey), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: Text(s.t('pin_enable')),
            subtitle: Text(s.t('pin_hint')),
            value: st.pinEnabled,
            onChanged: (v) {
              if (v) {
                open(const PinSetupScreen());
              } else {
                open(PinVerifyScreen(
                  title: s.t('pin_disable_title'),
                  onVerified: (ctx) async {
                    await st.clearPin();
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(s.t('pin_off_done'))));
                    Navigator.pop(ctx);
                  },
                ));
              }
            },
          ),
          if (st.pinEnabled)
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: Text(s.t('pin_change')),
              onTap: () => open(PinVerifyScreen(
                title: s.t('pin_enter'),
                onVerified: (ctx) async {
                  if (!ctx.mounted) return;
                  Navigator.pushReplacement(ctx,
                      MaterialPageRoute(builder: (_) => const PinSetupScreen()));
                },
              )),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(s.t('profile')),
            onTap: () => open(const ProfileScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(s.t('ref_values')),
            onTap: () => open(const RefsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text(s.t('next_control')),
            onTap: () => open(const NextControlScreen()),
          ),
          const Divider(),
          Text(s.t('privacy_note'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(s.t('disclaimer'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
