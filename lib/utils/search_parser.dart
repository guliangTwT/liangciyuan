import 'package:kazumi/utils/date_time.dart';

const Object _unchanged = Object();

class SearchDateRange {
  final String start;
  final String end;

  const SearchDateRange({
    required this.start,
    required this.end,
  });

  bool get isValid => start.isNotEmpty && end.isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is SearchDateRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

class SearchIntRange {
  final int? min;
  final int? max;

  const SearchIntRange({
    this.min,
    this.max,
  });

  bool get isValid => min != null || max != null;

  String toToken() => '${min ?? ''}..${max ?? ''}';

  @override
  bool operator ==(Object other) {
    return other is SearchIntRange && other.min == min && other.max == max;
  }

  @override
  int get hashCode => Object.hash(min, max);
}

class SearchDoubleRange {
  final double? min;
  final double? max;

  const SearchDoubleRange({
    this.min,
    this.max,
  });

  bool get isValid => min != null || max != null;

  String toToken() => '${_formatDouble(min)}..${_formatDouble(max)}';

  static String _formatDouble(double? value) {
    if (value == null) return '';
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  @override
  bool operator ==(Object other) {
    return other is SearchDoubleRange && other.min == min && other.max == max;
  }

  @override
  int get hashCode => Object.hash(min, max);
}

class SearchFilterState {
  final String id;
  final String keyword;
  final List<String> tags;
  final String sort;
  final String season;
  final SearchDateRange? dateRange;
  final SearchIntRange? rankRange;
  final SearchDoubleRange? scoreRange;
  final List<int> weekdays;

  const SearchFilterState({
    this.id = '',
    this.keyword = '',
    this.tags = const [],
    this.sort = 'heat',
    this.season = '',
    this.dateRange,
    this.rankRange,
    this.scoreRange,
    this.weekdays = const [],
  });

  bool get isIdSearch => id.isNotEmpty;

  bool get hasAdvancedFilters =>
      tags.isNotEmpty ||
      sort != 'heat' ||
      season.isNotEmpty ||
      dateRange != null ||
      rankRange?.isValid == true ||
      scoreRange?.isValid == true ||
      weekdays.isNotEmpty;

  SearchDateRange? get effectiveDateRange {
    if (dateRange != null) return dateRange;
    if (season.isEmpty) return null;
    return SearchParser.seasonToDateRange(season);
  }

  SearchFilterState copyWith({
    String? id,
    String? keyword,
    List<String>? tags,
    String? sort,
    Object? season = _unchanged,
    Object? dateRange = _unchanged,
    Object? rankRange = _unchanged,
    Object? scoreRange = _unchanged,
    List<int>? weekdays,
  }) {
    return SearchFilterState(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      tags: tags ?? this.tags,
      sort: sort ?? this.sort,
      season: identical(season, _unchanged) ? this.season : season as String,
      dateRange: identical(dateRange, _unchanged)
          ? this.dateRange
          : dateRange as SearchDateRange?,
      rankRange: identical(rankRange, _unchanged)
          ? this.rankRange
          : rankRange as SearchIntRange?,
      scoreRange: identical(scoreRange, _unchanged)
          ? this.scoreRange
          : scoreRange as SearchDoubleRange?,
      weekdays: weekdays ?? this.weekdays,
    );
  }
}

class SearchParser {
  final String query;

  static const String _fieldNames =
      'id|tag|sort|season|date|rank|score|weekday|nsfw';

  final RegExp _idRegExp = RegExp(r'id:(\d+)', caseSensitive: false);
  final RegExp _tagRegExp = RegExp(
    r'(?:^|\s)tag:([^\s]+?)(?=(?:id|tag|sort|season|date|rank|score|weekday|nsfw):|\s|$)',
    caseSensitive: false,
  );
  final RegExp _sortRegExp = RegExp(r'sort:([\w\-]+)', caseSensitive: false);
  final RegExp _seasonRegExp = RegExp(
    r'season:(\d{4}Q[1-4])',
    caseSensitive: false,
  );
  final RegExp _dateRegExp = RegExp(
    r'date:(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})',
    caseSensitive: false,
  );
  final RegExp _rankRegExp = RegExp(
    r'rank:(\d*)\.\.(\d*)',
    caseSensitive: false,
  );
  final RegExp _scoreRegExp = RegExp(
    r'score:(\d+(?:\.\d+)?)?\.\.(\d+(?:\.\d+)?)?',
    caseSensitive: false,
  );
  final RegExp _weekdayRegExp = RegExp(
    r'weekday:([1-7](?:,[1-7])*)',
    caseSensitive: false,
  );

  SearchParser(this.query);

  String? parseId() {
    final match = _idRegExp.firstMatch(query);
    return match?.group(1);
  }

  List<String> parseTags() {
    return _tagRegExp
        .allMatches(query)
        .map((match) => match.group(1)?.trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  String? parseSort() {
    final match = _sortRegExp.firstMatch(query);
    return match?.group(1);
  }

  String? parseSeason() {
    final match = _seasonRegExp.firstMatch(query);
    return match?.group(1)?.toUpperCase();
  }

  SearchDateRange? parseDateRange() {
    final match = _dateRegExp.firstMatch(query);
    if (match == null) return null;
    return SearchDateRange(start: match.group(1)!, end: match.group(2)!);
  }

  SearchIntRange? parseRankRange() {
    final match = _rankRegExp.firstMatch(query);
    if (match == null) return null;
    final min = int.tryParse(match.group(1) ?? '');
    final max = int.tryParse(match.group(2) ?? '');
    final range = SearchIntRange(min: min, max: max);
    return range.isValid ? range : null;
  }

  SearchDoubleRange? parseScoreRange() {
    final match = _scoreRegExp.firstMatch(query);
    if (match == null) return null;
    final min = double.tryParse(match.group(1) ?? '');
    final max = double.tryParse(match.group(2) ?? '');
    final range = SearchDoubleRange(min: min, max: max);
    return range.isValid ? range : null;
  }

  List<int> parseWeekdays() {
    final match = _weekdayRegExp.firstMatch(query);
    final value = match?.group(1);
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .where((e) => e >= 1 && e <= 7)
        .toSet()
        .toList()
      ..sort();
  }

  String parseKeywords() {
    // 逐次剥离：每剥掉一个 token，紧邻它的下一个 token 就落到了词边界上，
    // 因此 `tag:xxx sort:rank` 与 `tag:xxxsort:rank` 两种写法都能处理。
    // 不能一次性 replaceAll：token 正则要求前导词边界（^ 或空白），
    // 而 `rapid:x`、`grid:abc` 这类普通搜索词里恰好含有字段名子串，
    // 若允许「无边界」匹配就会被削掉一段（以前 `id:abc` 甚至会把
    // 关键词清空，直接退化成「浏览全部」）。
    final pattern = _tokenRegExp();
    var text = query;
    // 每轮至少缩短一个字符，正常情况下几十轮内必然结束；上限只是防御。
    for (var guard = 0; guard < 200; guard++) {
      final match = pattern.firstMatch(text);
      if (match == null) break;
      final replaced = text.replaceRange(match.start, match.end, ' ');
      if (replaced == text) break;
      text = replaced;
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  SearchFilterState toFilterState() {
    return SearchFilterState(
      id: parseId() ?? '',
      keyword: parseKeywords(),
      tags: parseTags(),
      sort: parseSort() ?? 'heat',
      season: parseSeason() ?? '',
      dateRange: parseDateRange(),
      rankRange: parseRankRange(),
      scoreRange: parseScoreRange(),
      weekdays: parseWeekdays(),
    );
  }

  static String fromFilterState(SearchFilterState state) {
    if (state.id.isNotEmpty) {
      return 'id:${state.id}';
    }

    final tokens = <String>[];
    final keyword = state.keyword.trim();
    if (keyword.isNotEmpty) tokens.add(keyword);
    for (final tag in state.tags) {
      final normalized = tag.trim();
      if (normalized.isNotEmpty) tokens.add('tag:$normalized');
    }
    if (state.sort.isNotEmpty && state.sort != 'heat') {
      tokens.add('sort:${state.sort}');
    }
    if (state.season.isNotEmpty) {
      tokens.add('season:${state.season}');
    } else if (state.dateRange?.isValid == true) {
      tokens.add('date:${state.dateRange!.start}..${state.dateRange!.end}');
    }
    if (state.rankRange?.isValid == true) {
      tokens.add('rank:${state.rankRange!.toToken()}');
    }
    if (state.scoreRange?.isValid == true) {
      tokens.add('score:${state.scoreRange!.toToken()}');
    }
    if (state.weekdays.isNotEmpty) {
      final weekdays = state.weekdays.toSet().toList()..sort();
      tokens.add('weekday:${weekdays.join(',')}');
    }
    return tokens.join(' ').trim();
  }

  static SearchDateRange? seasonToDateRange(String season) {
    final match =
        RegExp(r'^(\d{4})Q([1-4])$', caseSensitive: false).firstMatch(season);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final quarter = int.parse(match.group(2)!);
    final startMonth = (quarter - 1) * 3 + 1;
    final start = DateTime(year, startMonth - 1, 1);
    // 结束日是闭区间（含当天）。day 传 0 表示上个月最后一天，
    // 于是 Q1 = 12/1..2/28（闰年 2/29），与搜索接口的 `<=end` 对齐。
    final end = DateTime(year, startMonth + 2, 0);
    return SearchDateRange(
      start: formatDateTime(start),
      end: formatDateTime(end),
    );
  }

  static RegExp _tokenRegExp() {
    return RegExp(
      // 前缀 (^|\s) **必需**：否则 token 会匹配到单词中间。剥离是逐次进行的
      // （见 [parseKeywords]），所以紧邻的第二个 token 会在下一轮落到词边界上。
      r'(?:^|\s)(?:' +
          _fieldNames +
          r'):[^\s]*?(?=(?:\s|$)|(?:' +
          _fieldNames +
          r'):)',
      caseSensitive: false,
    );
  }
}
