import 'dart:io';

import 'package:flutter/services.dart';

import 'ocr_parser.dart';

/// Pont natif (MainActivity.kt) : Telechargements, partage, photos.
/// Aucun plugin tiers.
class FileSaver {
  static const MethodChannel _channel = MethodChannel('faztyroid/files');

  /// Retourne l'URI du fichier cree.
  static Future<String> saveToDownloads(String name, Uint8List bytes) async {
    final uri = await _channel
        .invokeMethod<String>('saveToDownloads', {'name': name, 'bytes': bytes});
    if (uri == null) {
      throw PlatformException(code: 'NO_RESULT', message: 'Aucun fichier créé');
    }
    return uri;
  }

  static Future<void> share(String uri) async {
    await _channel.invokeMethod<void>('shareFile', {'uri': uri});
  }

  /// Choisit une photo dans la galerie ; la copie dans le stockage prive de
  /// l'application. Retourne le chemin du fichier, ou null si annule.
  static Future<String?> pickImage() =>
      _channel.invokeMethod<String>('pickImage');

  /// Prend une photo avec l'appareil photo ; meme retour que [pickImage].
  static Future<String?> captureImage() =>
      _channel.invokeMethod<String>('captureImage');

  /// Lit le texte d'une photo avec l'OCR du telephone (ML Kit embarque,
  /// aucun envoi sur Internet). Retourne les lignes avec leur position.
  static Future<List<OcrLine>> recognizeText(String path) async {
    final raw = await _channel
        .invokeMethod<List<Object?>>('recognizeText', {'path': path});
    final out = <OcrLine>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map) continue;
      final text = item['text'];
      final corners = item['corners'];
      if (text is! String || corners is! List || corners.length < 8) continue;
      out.add(OcrLine.fromCorners(
          text, [for (final c in corners) (c as num).toDouble()]));
    }
    return out;
  }
}

/// Supprime un fichier local sans jamais lever d'erreur.
Future<void> deleteLocalFile(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
