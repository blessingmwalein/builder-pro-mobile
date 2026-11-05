import 'package:builder_pro_mobile/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendar days', () {
    test('a stored calendar day is shown by its own date', () {
      // The server keeps these at UTC midnight. Shown through the device's
      // time zone they would read as the day before anywhere behind UTC.
      expect(Fmt.calendarDay(DateTime.utc(2026, 10, 26)), 'Mon 26 Oct');
      expect(Fmt.calendarDay(DateTime.utc(2026, 11, 9)), 'Mon 9 Nov');
      expect(Fmt.calendarDay(DateTime.utc(2026, 1, 1)), 'Thu 1 Jan');
    });

    test('whatever time of day it carries, the date is the UTC date', () {
      expect(Fmt.calendarDay(DateTime.utc(2026, 10, 26, 23, 59)), 'Mon 26 Oct');
      expect(Fmt.calendarDay(DateTime.utc(2026, 10, 27, 0, 1)), 'Tue 27 Oct');
    });

    test('the API form is yyyy-MM-dd with the local date, zero padded', () {
      expect(Fmt.isoDay(DateTime(2026, 10, 27, 23, 59)), '2026-10-27');
      expect(Fmt.isoDay(DateTime(2026, 1, 5)), '2026-01-05');
      expect(Fmt.isoDay(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
