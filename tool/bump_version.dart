import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || !{'major', 'minor', 'patch'}.contains(args.first)) {
    stderr.writeln(
      'Usage: dart run tool/bump_version.dart major|minor|patch [summary]',
    );
    exitCode = 64;
    return;
  }
  final pubspec = File('pubspec.yaml');
  final source = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) throw StateError('No semantic Flutter version found');
  var major = int.parse(match[1]!);
  var minor = int.parse(match[2]!);
  var patch = int.parse(match[3]!);
  final build = int.parse(match[4]!) + 1;
  if (args.first == 'major') {
    major++;
    minor = 0;
    patch = 0;
  } else if (args.first == 'minor') {
    minor++;
    patch = 0;
  } else {
    patch++;
  }
  final next = '$major.$minor.$patch+$build';
  pubspec.writeAsStringSync(
    source.replaceRange(match.start, match.end, 'version: $next'),
  );
  stdout.writeln(
    'Bumped a2 to $next${args.length > 1 ? ': ${args.skip(1).join(' ')}' : ''}',
  );
}
