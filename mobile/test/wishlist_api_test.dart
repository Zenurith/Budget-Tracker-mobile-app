import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketwise/data/api_funding_repository.dart';
import 'package:pocketwise/services/api.dart';

void main() {
  test(
    'purchase expense search includes candidates after the first page',
    () async {
      final pages = <int>[];
      final api = Api(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(query['type'], 'expense');
          expect(query['start'], '2026-10-05');
          expect(query['end'], '2026-10-05');
          expect(query['min_amount'], '500');
          expect(query['max_amount'], '500');
          final page = int.parse(query['page']!);
          pages.add(page);
          return http.Response(
            jsonEncode({
              'total': 101,
              'items': page == 1
                  ? List.generate(
                      100,
                      (i) => {'id': '$i', 'wishlist_purchase_id': 'linked'},
                    )
                  : [
                      {'id': 'available'},
                    ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.client.close);
      final result = await ApiFundingRepository(
        api,
      ).expenses('2026-10-05', 500);
      expect(pages, [1, 2]);
      expect(result['items'].length, 101);
      expect(result['items'].last['id'], 'available');
    },
  );
}
