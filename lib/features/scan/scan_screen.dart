import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:provider/provider.dart';

import '../../app/palette.dart';
import '../../core/format.dart';
import '../../core/medical.dart';
import '../../l10n/strings.dart';
import '../../services/file_saver.dart';
import '../../services/ocr_parser.dart';
import '../../services/scan_commit.dart';
import '../../widgets/common.dart';
import '../attachments/attachments_section.dart';
import '../state/app_state.dart';

enum _Exist { none, same, different }

class _RowCtl {
  _RowCtl(this.p)
      : name = TextEditingController(text: p.name),
        value = TextEditingController(text: formatNum(p.value)),
        unit = TextEditingController(text: p.unit),
        min = TextEditingController(text: formatNum(p.min)),
        max = TextEditingController(text: formatNum(p.max)),
        candidate = p.defaultCandidate {
    final i = candidate;
    if (i != null) {
      min.text = formatNum(p.candidates[i].min);
      max.text = formatNum(p.candidates[i].max);
    }
  }

  final ParsedResult p;
  final TextEditingController name, value, unit, min, max;
  int? candidate;
  bool include = true;

  void dispose() {
    for (final c in [name, value, unit, min, max]) {
      c.dispose();
    }
  }
}

/// Scan d'une feuille de laboratoire : photo -> lecture locale (OCR) ->
/// verification par l'utilisatrice -> enregistrement.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final date = TextEditingController();
  final lab = TextEditingController();
  final List<_RowCtl> rows = [];
  ParsedSheet? sheet;
  String? photo;
  String? error;
  bool busy = false;
  bool committed = false;

  void _clearRows() {
    for (final r in rows) {
      r.dispose();
    }
    rows.clear();
  }

  @override
  void dispose() {
    _clearRows();
    date.dispose();
    lab.dispose();
    final p = photo;
    if (p != null && !committed) deleteLocalFile(p);
    super.dispose();
  }

  Future<void> _start({required bool camera}) async {
    final st = context.read<AppState>();
    final s = st.s;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path =
          camera ? await FileSaver.captureImage() : await FileSaver.pickImage();
      if (path == null) return;
      final old = photo;
      if (old != null && !committed) await deleteLocalFile(old);
      photo = path;
      final lines = await FileSaver.recognizeText(path);
      final parsed = parseLabRows(
        reconstructRows(lines),
        female: true,
        profileName: '${st.profile.nameFr} ${st.profile.nameAr}',
      );
      _clearRows();
      for (final r in parsed.results) {
        rows.add(_RowCtl(r));
      }
      sheet = parsed;
      date.text = parsed.date == null ? '' : formatDate(parsed.date!);
      if (parsed.results.isEmpty) error = s.t('scan_none');
      _applyDefaults(st);
    } on MissingPluginException {
      error = s.t('att_unavailable');
    } on PlatformException catch (e) {
      error = '${s.t('scan_error')} [${e.code}] : ${e.message ?? ''}';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  DateTime? get _date => parseDate(date.text);

  void _applyDefaults(AppState st) {
    for (final r in rows) {
      r.include = _exist(st, r) == _Exist.none;
    }
  }

  bool _same(double? a, double? b) =>
      a != null && b != null && (a - b).abs() < 1e-6;

  ({_Exist kind, double? existing}) _existInfo(AppState st, _RowCtl r) {
    final d = _date;
    if (d == null) return (kind: _Exist.none, existing: null);
    final v = parseNumber(r.value.text);
    final key = r.p.thyroidKey;
    bool sameDay(DateTime x) =>
        x.year == d.year && x.month == d.month && x.day == d.day;
    if (key != null) {
      for (final e in st.thyroid.where((e) => sameDay(e.date))) {
        final cur = key == 'TSH' ? e.tsh : (key == 'FT4' ? e.ft4 : e.ft3);
        if (cur == null) return (kind: _Exist.none, existing: null);
        return (
          kind: _same(cur, v) ? _Exist.same : _Exist.different,
          existing: cur
        );
      }
      return (kind: _Exist.none, existing: null);
    }
    final n = foldText(r.name.text.trim());
    for (final a in st.others) {
      if (sameDay(a.date) && foldText(a.name) == n) {
        return (
          kind: _same(a.value, v) ? _Exist.same : _Exist.different,
          existing: a.value
        );
      }
    }
    return (kind: _Exist.none, existing: null);
  }

  _Exist _exist(AppState st, _RowCtl r) => _existInfo(st, r).kind;

  Future<void> _save() async {
    final st = context.read<AppState>();
    final s = st.s;
    final messenger = ScaffoldMessenger.of(context);
    final d = _date;
    final p = photo;
    if (d == null || p == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('err_date'))));
      return;
    }
    final data = <ScanRowData>[];
    for (final r in rows) {
      final v = parseNumber(r.value.text);
      final include = r.include && _exist(st, r) == _Exist.none;
      if (include && (v == null || r.name.text.trim().isEmpty)) {
        messenger.showSnackBar(SnackBar(content: Text(s.t('err_number'))));
        return;
      }
      String comment = s.t('scan_ocr_note');
      final ci = r.candidate;
      if (ci != null) comment += ' – ${r.p.candidates[ci].label}';
      data.add(ScanRowData(
        name: r.name.text.trim(),
        thyroidKey: r.p.thyroidKey,
        value: v,
        unit: r.unit.text.trim(),
        min: parseNumber(r.min.text),
        max: parseNumber(r.max.text),
        include: include,
        comment: comment,
      ));
    }
    final res = await commitScan(st,
        date: d, lab: lab.text, photoPath: p, rows: data);
    if (res.nothing) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('scan_nothing'))));
      return;
    }
    committed = true;
    messenger.showSnackBar(SnackBar(
      content: Text(
          '${s.t('scan_done')} : ${res.added} ${s.t('scan_added')} · ${res.completed} ${s.t('scan_completed')} · ${res.attached} ${s.t('scan_photos')}'),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final sh = sheet;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('scan_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            icon: Icons.document_scanner_rounded,
            title: s.t('scan_title'),
            child: Text(s.t('scan_info')),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => _start(camera: true),
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(s.t('scan_camera')),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _start(camera: false),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(s.t('scan_gallery')),
              ),
            ],
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(s.t('scan_reading')),
              ]),
            ),
          if (error != null && !busy)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
          if (sh != null && photo != null && !busy) ...[
            const SizedBox(height: 14),
            _photoCard(context, s),
            if (sh.patientMatches == false)
              _warn(context, s.t('scan_patient_warn')),
            if (_labRangesDiffer(st, sh)) _warn(context, s.t('scan_lab_diff')),
            if (rows.isNotEmpty) ...[
              Text(s.t('scan_review'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: context.brandDeep)),
              const SizedBox(height: 8),
              DateField(controller: date, label: s.t('date'), s: s),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                    sh.dateFromSample
                        ? s.t('scan_date_sample')
                        : s.t('scan_date_guess'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextFormField(
                controller: lab,
                decoration: InputDecoration(labelText: s.t('lab')),
              ),
              const SizedBox(height: 10),
              for (final r in rows) _rowCard(context, st, r),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(s.t('scan_save')),
              ),
            ],
          ],
        ],
      ),
    );
  }

  bool _labRangesDiffer(AppState st, ParsedSheet sh) {
    final r = st.refs;
    for (final x in sh.results) {
      if (x.thyroidKey == null || (x.min == null && x.max == null)) continue;
      final mn = x.thyroidKey == 'TSH'
          ? r.tshMin
          : (x.thyroidKey == 'FT4' ? r.ft4Min : r.ft3Min);
      final mx = x.thyroidKey == 'TSH'
          ? r.tshMax
          : (x.thyroidKey == 'FT4' ? r.ft4Max : r.ft3Max);
      if (!_same(x.min, mn) || !_same(x.max, mx)) return true;
    }
    return false;
  }

  Widget _warn(BuildContext context, String text) => Card(
        color: Colors.orange.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        ),
      );

  Widget _photoCard(BuildContext context, S s) {
    final p = photo!;
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ImageViewerScreen(paths: [p]))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(p),
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 84,
                      height: 84,
                      child: Icon(Icons.broken_image_outlined))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(s.t('scan_compare_hint'))),
          ]),
        ),
      ),
    );
  }

  Widget _rowCard(BuildContext context, AppState st, _RowCtl r) {
    final s = st.s;
    final info = _existInfo(st, r);
    final locked = info.kind != _Exist.none;
    final v = parseNumber(r.value.text);
    final mn = parseNumber(r.min.text);
    final mx = parseNumber(r.max.text);
    final status = statusOf(v, mn, mx);
    final color = levelColor(levelOf(v, mn, mx));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Checkbox(
                value: locked ? false : r.include,
                onChanged: locked
                    ? null
                    : (b) => setState(() => r.include = b ?? false),
              ),
              Expanded(
                child: TextField(
                  controller: r.name,
                  enabled: r.p.thyroidKey == null && !locked,
                  decoration: InputDecoration(
                      isDense: true,
                      labelText: r.p.thyroidKey == null
                          ? s.t('analysis_name')
                          : s.t('type_bilan')),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: r.value,
                  enabled: !locked,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(isDense: true, labelText: s.t('value')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: r.unit,
                  enabled: !locked,
                  decoration:
                      InputDecoration(isDense: true, labelText: s.t('unit')),
                ),
              ),
              const SizedBox(width: 8),
              if (v != null) StatusChip(label: statusLabel(s, status), color: color),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: r.min,
                  enabled: !locked,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(isDense: true, labelText: s.t('ref_min')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: r.max,
                  enabled: !locked,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(isDense: true, labelText: s.t('ref_max')),
                ),
              ),
            ]),
            if (r.p.candidates.isNotEmpty && !locked) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: r.candidate,
                isExpanded: true,
                hint: Text(s.t('scan_choose_ref')),
                decoration: InputDecoration(
                    isDense: true, labelText: s.t('scan_ref')),
                items: [
                  for (var i = 0; i < r.p.candidates.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${r.p.candidates[i].label} : ${formatNum(r.p.candidates[i].min)} – ${formatNum(r.p.candidates[i].max)} ${r.p.candidates[i].unit}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (i) {
                  if (i == null) return;
                  setState(() {
                    r.candidate = i;
                    r.min.text = formatNum(r.p.candidates[i].min);
                    r.max.text = formatNum(r.p.candidates[i].max);
                  });
                },
              ),
            ],
            if (info.kind == _Exist.same)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.t('scan_exists_same'),
                    style: TextStyle(color: kMint, fontWeight: FontWeight.w600)),
              ),
            if (info.kind == _Exist.different)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${s.t('scan_exists_diff')} ${formatNum(info.existing)}',
                    style: const TextStyle(
                        color: Color(0xFFEF9A4B), fontWeight: FontWeight.w600)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${s.t('scan_read_as')} ${r.p.raw}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
