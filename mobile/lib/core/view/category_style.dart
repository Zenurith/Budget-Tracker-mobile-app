import 'package:flutter/material.dart';

import '../../models/finance.dart';

const categoryIcons = <String, IconData>{
  'category': Icons.category_rounded,
  'restaurant': Icons.restaurant_rounded,
  'directions_car': Icons.directions_car_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'movie': Icons.movie_rounded,
  'favorite': Icons.favorite_rounded,
  'work': Icons.work_rounded,
  'payments': Icons.payments_rounded,
};
const categoryColors = <String, String>{
  '#4D8B70': 'Green',
  '#E3A25F': 'Orange',
  '#6D9DC5': 'Blue',
  '#AC8FC0': 'Purple',
  '#D88679': 'Coral',
  '#D48FA6': 'Pink',
  '#9AA6A0': 'Gray',
};

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
