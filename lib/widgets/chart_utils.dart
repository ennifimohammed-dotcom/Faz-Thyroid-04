// Fonctions pures des graphiques (testables) : graduations de dates et
// position des points.

const double _msPerDay = 86400000.0;

/// [n] graduations reparties regulierement de [minX] a [maxX] (extremites incluses).
List<double> evenTicks(double minX, double maxX, int n) {
  if (n < 2) return [minX];
  final step = (maxX - minX) / (n - 1);
  return [for (var i = 0; i < n; i++) minX + step * i];
}

/// Date lisible pour une graduation (x = jours depuis 1970).
/// Periode courte : jj/mm ; periode longue : mm/aa.
String tickLabel(double x, double spanDays) {
  final d = DateTime.fromMillisecondsSinceEpoch((x * _msPerDay).round(),
      isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return spanDays < 120
      ? '${two(d.day)}/${two(d.month)}'
      : '${two(d.month)}/${two(d.year % 100)}';
}

/// Nombre de graduations qui tiennent sans se chevaucher.
int tickCount(double plotWidth) {
  final n = (plotWidth / 64).floor();
  if (n < 2) return 2;
  return n > 5 ? 5 : n;
}

/// Position horizontale (0..1) d'une valeur dans [min, max].
double fraction(double v, double min, double max) =>
    max == min ? 0.5 : (v - min) / (max - min);
