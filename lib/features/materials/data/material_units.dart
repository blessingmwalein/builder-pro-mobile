/// The units a material is counted in on a construction site, grouped so the
/// dropdown is easy to scan. The server keeps a unit as plain text, so anything
/// already stored (for example "bags") stays valid; this list is what the app
/// offers for new materials and request lines.
const constructionUnitGroups = <String, List<String>>{
  'Count': [
    'each',
    'pair',
    'set',
    'box',
    'carton',
    'bundle',
    'pack',
    'bag',
    'roll',
    'sheet',
    'length',
    'drum',
    'bucket',
    'tin',
  ],
  'Weight': ['kg', 'tonne'],
  'Volume': ['litre', 'm³'],
  'Length and area': ['m', 'm²', 'mm'],
};

/// Every offered unit, in the order shown.
final List<String> constructionUnits = [
  for (final units in constructionUnitGroups.values) ...units,
];

/// The group a unit belongs to, or null for one the app does not list.
String? unitGroup(String unit) {
  for (final e in constructionUnitGroups.entries) {
    if (e.value.contains(unit)) return e.key;
  }
  return null;
}

/// What to offer in a unit dropdown: the list, plus [current] first when it is
/// something else (a unit typed earlier on the web app must not disappear).
List<String> unitChoices({String? current}) {
  final c = current?.trim();
  if (c == null || c.isEmpty || constructionUnits.contains(c)) {
    return constructionUnits;
  }
  return [c, ...constructionUnits];
}
