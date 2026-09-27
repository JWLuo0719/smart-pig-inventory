/// 归一化矩形区域：栏舍有效区，或"不计入本栏"的排除区（邻栏、料槽、走道等）。
///
/// 坐标基于 EXIF 纠正后的图像，取值 0..1，且必须完整落在图像内。
/// 契约对应 `contracts/openapi.yaml` 的 `RoiRegion`。
class RoiRegion {
  RoiRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    if (!isValid) {
      throw ArgumentError('ROI region must be finite, positive, and inside the image');
    }
  }

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid => isValidRect(x, y, width, height);

  Map<String, Object?> toJson() => <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  static RoiRegion fromJson(Object? source) {
    if (source is! Map<String, Object?>) {
      throw ArgumentError.value(
          source, 'source', 'ROI region must be an object');
    }
    return RoiRegion(
      x: _coordinate(source['x'], 'x'),
      y: _coordinate(source['y'], 'y'),
      width: _coordinate(source['width'], 'width'),
      height: _coordinate(source['height'], 'height'),
    );
  }
}

/// 栏舍在单张图像上的归属规则：有效区 + 排除区 + 最小包含比例。
///
/// 检测框中心落在排除区内时不计入本栏（对应现场需求"隔壁栏舍的猪不能计入本栏舍"）；
/// [minContainment] 大于 0 时，检测框落在有效区内的面积占比必须达到该阈值才计入，
/// 用于排除半身在邻栏的目标。缺省值下行为与历史版本完全一致。
class Roi {
  Roi({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.exclusions = const <RoiRegion>[],
    this.minContainment = 0,
  }) {
    if (!isValid) {
      throw ArgumentError('ROI must be finite, positive, and inside the image');
    }
    if (exclusions.length > maxExclusions) {
      throw ArgumentError(
          'ROI must not declare more than $maxExclusions exclusion regions');
    }
    if (!minContainment.isFinite ||
        minContainment < 0 ||
        minContainment > 1) {
      throw ArgumentError('ROI minimum containment must be within 0..1');
    }
  }

  /// 与服务端 `Roi.MAX_EXCLUSIONS` 保持一致。
  static const int maxExclusions = 8;

  final double x;
  final double y;
  final double width;
  final double height;

  /// 不计入本栏的区域；空列表表示有效区内的目标都算本栏。
  final List<RoiRegion> exclusions;

  /// 检测框需落在有效区内的最小面积占比；0 表示只判定框中心点。
  final double minContainment;

  bool get isValid => isValidRect(x, y, width, height);

  /// 缺省值不写入 JSON，保证历史载荷逐字不变。
  Map<String, Object?> toJson() => <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        if (exclusions.isNotEmpty)
          'exclusions': exclusions
              .map((RoiRegion region) => region.toJson())
              .toList(growable: false),
        if (minContainment != 0) 'minContainment': minContainment,
      };

  static Roi? fromJson(Object? source) {
    if (source == null) return null;
    if (source is! Map<String, Object?>) {
      throw ArgumentError.value(
          source, 'source', 'ROI must be an object or null');
    }
    return Roi(
      x: _coordinate(source['x'], 'x'),
      y: _coordinate(source['y'], 'y'),
      width: _coordinate(source['width'], 'width'),
      height: _coordinate(source['height'], 'height'),
      exclusions: _exclusions(source['exclusions']),
      minContainment: _minContainment(source['minContainment']),
    );
  }

  static List<RoiRegion> _exclusions(Object? source) {
    if (source == null) return const <RoiRegion>[];
    if (source is! List<Object?>) {
      throw ArgumentError.value(
          source, 'exclusions', 'ROI exclusions must be a list');
    }
    return source.map(RoiRegion.fromJson).toList(growable: false);
  }

  static double _minContainment(Object? source) {
    if (source == null) return 0;
    if (source is! num) {
      throw ArgumentError.value(source, 'minContainment',
          'ROI minimum containment must be numeric');
    }
    return source.toDouble();
  }
}

bool isValidRect(double x, double y, double width, double height) =>
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

double _coordinate(Object? value, String field) {
  if (value is! num) {
    throw ArgumentError.value(value, field, 'ROI coordinate must be numeric');
  }
  return value.toDouble();
}
