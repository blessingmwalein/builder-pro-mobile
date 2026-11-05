import 'package:intl/intl.dart';

/// Display formatting shared by the field screens. Server timestamps are UTC
/// ISO strings; everything shown to the user is converted to local time.
abstract final class Fmt {
  /// `2h 05m`, `45m`, `0m`.
  static String duration(Duration d) {
    final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  /// `02:05:09` for the live clock-in timer.
  static String timer(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  /// `7.5 h` (one decimal, trailing `.0` dropped).
  static String hours(double h) {
    final v = (h * 10).round() / 10;
    return '${v == v.roundToDouble() ? v.toInt() : v} h';
  }

  /// `12`, `12.5`, `0.125` — no trailing zeros, at most 3 decimals.
  static String quantity(double q) {
    var s = q.toStringAsFixed(3);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// `$1,234.50` for dollars, `ZWL 1,234.50` for currencies without a symbol:
  /// the company's own currency, two decimals, same look as the web app
  /// (`Intl.NumberFormat('en-US', …)`). A code used as the symbol gets a
  /// non-breaking space so it never glues onto the number.
  static String money(num amount, String currency) {
    final code = currency.trim().isEmpty
        ? 'USD'
        : currency.trim().toUpperCase();
    final f = NumberFormat.simpleCurrency(
      locale: 'en_US',
      name: code,
      decimalDigits: 2,
    );
    final text = f.format(amount);
    final symbol = f.currencySymbol;
    if (RegExp(r'[A-Za-z]$').hasMatch(symbol)) {
      return text.replaceFirst(symbol, '$symbol ');
    }
    return text;
  }

  /// A percentage with at most one decimal: `12%`, `12.5%`.
  static String percent(num value) {
    final v = (value * 10).round() / 10;
    return '${v == v.roundToDouble() ? v.toInt() : v}%';
  }

  static String time(DateTime t) => DateFormat('HH:mm').format(t.toLocal());

  /// `Mon 26 Oct`.
  static String day(DateTime t) => DateFormat('EEE d MMM').format(t.toLocal());

  /// A date the server keeps as a calendar day (UTC midnight, no time zone):
  /// `Mon 26 Oct`. Shown by its own date, so it never slips a day in a time
  /// zone behind UTC the way [day] would.
  static String calendarDay(DateTime t) {
    final u = t.toUtc();
    return DateFormat('EEE d MMM').format(DateTime(u.year, u.month, u.day));
  }

  /// `2026-10-26`, the form the API accepts for a calendar day.
  static String isoDay(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

  /// `Mon 26 Oct, 14:05`.
  static String dayTime(DateTime t) =>
      DateFormat('EEE d MMM, HH:mm').format(t.toLocal());

  /// `Today`, `Yesterday` or `Mon 26 Oct`.
  static String relativeDay(DateTime t, {DateTime? now}) {
    final local = t.toLocal();
    final today = _dateOnly(now ?? DateTime.now());
    final diff = today.difference(_dateOnly(local)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return day(local);
  }

  /// `Due today`, `Due tomorrow`, `Overdue by 3 days`, `Due Mon 26 Oct`.
  static String due(DateTime due, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final d = _dateOnly(due.toLocal());
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    if (diff == -1) return 'Overdue by 1 day';
    if (diff < 0) return 'Overdue by ${-diff} days';
    return 'Due ${day(d)}';
  }

  /// `now`, `5 min ago`, `3 h ago`, else the date.
  static String ago(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(t);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && _dateOnly(n) == _dateOnly(t.toLocal())) {
      return '${diff.inHours} h ago';
    }
    return dayTime(t);
  }

  static String bytes(int? size) {
    if (size == null || size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Monday 00:00 (local) of the week containing [day].
  static DateTime weekStart(DateTime day) {
    final d = _dateOnly(day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}
