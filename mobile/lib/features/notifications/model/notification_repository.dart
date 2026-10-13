enum NotificationPermission {
  unknown,
  notDetermined,
  denied,
  blocked,
  granted,
  provisional,
  unsupported,
}

class NotificationPreferences {
  final bool enabled, bills, budgets, cashReview;
  final int billLeadDays;
  const NotificationPreferences({
    this.enabled = false,
    this.bills = false,
    this.budgets = false,
    this.cashReview = false,
    this.billLeadDays = 1,
  });

  NotificationPreferences copy({
    bool? enabled,
    bool? bills,
    bool? budgets,
    bool? cashReview,
    int? billLeadDays,
  }) => NotificationPreferences(
    enabled: enabled ?? this.enabled,
    bills: bills ?? this.bills,
    budgets: budgets ?? this.budgets,
    cashReview: cashReview ?? this.cashReview,
    billLeadDays: billLeadDays ?? this.billLeadDays,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'bills': bills,
    'budgets': budgets,
    'cash_review': cashReview,
    'bill_lead_days': billLeadDays,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1 ||
        [
          'enabled',
          'bills',
          'budgets',
          'cash_review',
        ].any((key) => data[key] is! bool) ||
        !const [0, 1, 3, 7].contains(data['bill_lead_days'])) {
      throw const FormatException(
        'Notification preferences could not be read.',
      );
    }
    return NotificationPreferences(
      enabled: data['enabled'],
      bills: data['bills'],
      budgets: data['budgets'],
      cashReview: data['cash_review'],
      billLeadDays: data['bill_lead_days'],
    );
  }
}

abstract interface class NotificationRepository {
  Future<NotificationPreferences> load();
  Future<void> save(NotificationPreferences preferences);
  Future<NotificationPermission> permission();
  Future<NotificationPermission> requestPermission();
  Future<bool> openSettings();
}
