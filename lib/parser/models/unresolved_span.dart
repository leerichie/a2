class UnresolvedSpan {
  const UnresolvedSpan(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;

  @override
  String toString() => 'UnresolvedSpan("$text" @$start-$end)';

  @override
  bool operator ==(Object other) =>
      other is UnresolvedSpan &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);
}
