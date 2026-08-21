class Roi {
  Roi({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    if (!isValid) {
      throw ArgumentError('ROI must be finite, positive, and inside the image');
    }
  }

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid =>
      x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1 &&
      y + height <= 1;

  Map<String, double> toJson() => <String, double>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  static Roi? fromJson(Object? source) {
    if (source == null) return null;
    if (source is! Map<String, Object?>) {
      throw ArgumentError.value(
          source, 'source', 'ROI must be an object or null');
    }
    return Roi(
      x: _number(source['x'], 'x'),
      y: _number(source['y'], 'y'),
      width: _number(source['width'], 'width'),
      height: _number(source['height'], 'height'),
    );
  }

  static double _number(Object? value, String field) {
    if (value is! num) {
      throw ArgumentError.value(value, field, 'ROI coordinate must be numeric');
    }
    return value.toDouble();
  }
}
