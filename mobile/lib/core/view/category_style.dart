import 'package:flutter/material.dart';

import '../../models/finance.dart';

extension CategoryStyle on FinanceCategory {
  Color get color =>
      Color(int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));
  IconData get symbol => switch (icon) {
    'restaurant' => Icons.restaurant_rounded,
    'directions_car' => Icons.directions_car_rounded,
    'shopping_bag' => Icons.shopping_bag_rounded,
    'receipt_long' => Icons.receipt_long_rounded,
    'movie' => Icons.movie_rounded,
    'favorite' => Icons.favorite_rounded,
    'work' => Icons.work_rounded,
    'payments' => Icons.payments_rounded,
    _ => Icons.category_rounded,
  };
}
