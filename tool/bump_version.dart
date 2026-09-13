import 'dart:io';

void main(List<String> args) {
  final pubspec = File('pubspec.yaml');
  final source = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) throw StateError('No semantic Flutter version found');
  final build = int.parse(match[4]!) + 1;
  final next = '1.0.0+$build';
  pubspec.writeAsStringSync(
    source.replaceRange(match.start, match.end, 'version: $next'),
  );
  stdout.writeln(
    'Bumped a2 to $next${args.isNotEmpty ? ': ${args.join(' ')}' : ''}',
  );
}
