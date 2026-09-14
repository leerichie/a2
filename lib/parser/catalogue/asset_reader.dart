import 'package:flutter/services.dart' show rootBundle;

typedef AssetReader = Future<String> Function(String path);

Future<String> defaultAssetReader(String path) => rootBundle.loadString(path);
