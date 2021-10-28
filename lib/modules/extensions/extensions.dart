import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:extensions/extensions.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import '../../config/app.dart';
import '../helpers/logger.dart';

abstract class ExtensionsManager {
  static late final List<ResolvableExtension> store;

  static Map<String, AnimeExtractor> animes = <String, AnimeExtractor>{};

  static Map<String, MangaExtractor> mangas = <String, MangaExtractor>{};

  static Future<void> initialize() async {
    await _loadStore();
    await _loadLocalExtensions();
  }

  static Future<void> install(
    final ResolvableExtension resolvable,
  ) async {
    final ResolvedExtension resolved = await resolvable.resolve();
    final String path = await _getExtensionPath(resolved);
    final File file = File(path);

    await file.create(recursive: true);
    await file.writeAsString(json.encode(resolved.toJson()));
    await _addExtension(resolved);
  }

  static Future<void> uninstall(
    final BaseExtension ext,
  ) async {
    final String path = await _getExtensionPath(ext);
    final File file = File(path);

    await file.delete();
    await _removeExtension(ext);
  }

  static bool isInstalled(
    final BaseExtension ext,
  ) =>
      isInstalledById(ext.type, ext.id);

  static bool isInstalledById(
    final ExtensionType type,
    final String id,
  ) {
    switch (type) {
      case ExtensionType.anime:
        return animes.containsKey(id);

      case ExtensionType.manga:
        return mangas.containsKey(id);
    }
  }

  static Future<void> _loadStore() async {
    final http.Response res = await http.get(Uri.parse(Config.storeURL));

    store = (json.decode(res.body)['extensions'] as List<dynamic>)
        .cast<Map<dynamic, dynamic>>()
        .map(
          (final Map<dynamic, dynamic> x) => ResolvableExtension.fromJson(x),
        )
        .toList();
  }

  static Future<void> _loadLocalExtensions() async {
    final String path = await _getPath();
    final Directory dir = Directory(path);

    if (await dir.exists()) {
      for (final FileSystemEntity x in await dir.list().toList()) {
        final File file = File(x.path);

        try {
          final String content = await file.readAsString();
          ResolvedExtension ext = ResolvedExtension.fromJson(
            json.decode(content) as Map<dynamic, dynamic>,
          );

          final ResolvableExtension? storeExt = store.firstWhereOrNull(
            (final ResolvableExtension x) =>
                ext.id == x.id && ext.type == x.type,
          );
          if (storeExt != null && storeExt.version > ext.version) {
            ext = await storeExt.resolve();
            await file.writeAsString(json.encode(ext.toJson()));
          }

          await _addExtension(ext);
        } catch (err, stack) {
          Logger.of('extensions').error(
            'Failed to load extension from "${file.path}"',
            stack,
          );
        }
      }
    }
  }

  static Future<void> _addExtension(
    final ResolvedExtension ext,
  ) async {
    switch (ext.type) {
      case ExtensionType.anime:
        animes[ext.id] = await ExtensionUtils.transpileToAnimeExtractor(
          ext,
        );
        break;

      case ExtensionType.manga:
        mangas[ext.id] = await ExtensionUtils.transpileToMangaExtractor(
          ext,
        );
        break;
    }
  }

  static Future<void> _removeExtension(
    final BaseExtension ext,
  ) async {
    switch (ext.type) {
      case ExtensionType.anime:
        animes.remove(ext.id);
        break;

      case ExtensionType.manga:
        mangas.remove(ext.id);
        break;
    }
  }

  static Future<String> _getPath() async {
    final Directory documentsDir =
        await path_provider.getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, Config.code, 'extensions');
  }

  static Future<String> _getExtensionPath(
    final BaseExtension ext,
  ) async {
    final String dir = await _getPath();
    return p.join(dir, '${ext.id}.${ext.type.type}.json');
  }
}