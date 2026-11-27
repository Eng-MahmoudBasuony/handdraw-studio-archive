import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

enum VectorMaskOperation { reveal, erase }

class VectorMaskStroke {
  const VectorMaskStroke({
    required this.geometry,
    required this.widthFraction,
    required this.operation,
    this.featherFraction = 0,
    this.clipToLayer = true,
  });

  final StrokePathGeometry geometry;
  final double widthFraction;
  final VectorMaskOperation operation;
  final double featherFraction;
  final bool clipToLayer;

  Map<String, dynamic> toJson() => {
    'geometry': geometry.toJson(),
    'widthFraction': widthFraction,
    'operation': operation.name,
    'featherFraction': featherFraction,
    'clipToLayer': clipToLayer,
  };

  factory VectorMaskStroke.fromJson(Map<String, dynamic> json) =>
      VectorMaskStroke(
        geometry: StrokePathGeometry.fromJson(
          Map<String, dynamic>.from(json['geometry'] as Map),
        ),
        widthFraction: (json['widthFraction'] as num).toDouble(),
        featherFraction: (json['featherFraction'] as num? ?? 0).toDouble(),
        clipToLayer: json['clipToLayer'] as bool? ?? true,
        operation: VectorMaskOperation.values.firstWhere(
          (value) => value.name == json['operation'],
          orElse: () => VectorMaskOperation.reveal,
        ),
      );
}
