/// An exact rational frame rate.
///
/// Fractional broadcast rates such as 30000/1001 remain rational throughout
/// timeline and frame-sampling calculations.
final class FrameRate implements Comparable<FrameRate> {
  factory FrameRate({required int numerator, int denominator = 1}) {
    if (numerator <= 0) {
      throw RangeError.value(
        numerator,
        'numerator',
        'Frame-rate numerator must be positive.',
      );
    }
    if (denominator <= 0) {
      throw RangeError.value(
        denominator,
        'denominator',
        'Frame-rate denominator must be positive.',
      );
    }
    final divisor = _greatestCommonDivisor(numerator, denominator);
    return FrameRate._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const FrameRate._(this.numerator, this.denominator);

  static const fps24 = FrameRate._(24, 1);
  static const fps25 = FrameRate._(25, 1);
  static const fps30 = FrameRate._(30, 1);
  static const fps50 = FrameRate._(50, 1);
  static const fps60 = FrameRate._(60, 1);
  static const ntsc2997 = FrameRate._(30000, 1001);

  final int numerator;
  final int denominator;

  @override
  int compareTo(FrameRate other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is FrameRate &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator fps';
}

int _greatestCommonDivisor(int first, int second) {
  var a = first;
  var b = second;
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}
