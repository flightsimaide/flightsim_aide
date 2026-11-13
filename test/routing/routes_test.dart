import 'package:flightsim_aide/routing/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Routes', () {
    test('constants', () {
      expect(Routes.home, '/');
      expect(Routes.list, '/checklists');
      expect(Routes.detail, '/checklists/:name');
    });

    test('detailPath encodes spaces', () {
      expect(Routes.detailPath('Before Start'), '/checklists/Before%20Start');
    });

    test('detailPath encodes slash', () {
      expect(Routes.detailPath('a/b'), '/checklists/a%2Fb');
    });

    test('detailPath("Before Start / Taxi") has no raw / in last segment', () {
      final path = Routes.detailPath('Before Start / Taxi');
      final last = path.substring('/checklists/'.length);
      expect(last, isNot(contains('/')));
      expect(Uri.decodeComponent(last), 'Before Start / Taxi');
    });
  });
}
