import '../../../models/finance.dart';

class SpendingTrends {
  final List<Json> months;
  SpendingTrends(List<Json> all, int count)
    : months = List.unmodifiable(
        all.skip(all.length > count ? all.length - count : 0),
      );
  List<Json> get ended => months.where((m) => m['status'] == 'ended').toList();
  int? get average => ended.isEmpty
      ? null
      : ended.fold<int>(0, (sum, m) => sum + (m['expense'] as int)) ~/
            ended.length;
  List<String> get categories {
    final ids = <String>{};
    for (final month in months) {
      ids.addAll((month['category_totals'] as Map? ?? {}).keys.cast<String>());
    }
    return ids.toList()..sort((a, b) => total(b).compareTo(total(a)));
  }

  int category(Json month, String id) =>
      (month['category_totals'] as Map?)?[id] as int? ?? 0;
  int total(String id) =>
      months.fold(0, (sum, month) => sum + category(month, id));
  int change(String id) =>
      category(months.last, id) - category(months.first, id);
}
