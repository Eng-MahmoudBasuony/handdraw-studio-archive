import 'dart:math' as math;

import 'package:xml/xml.dart';

class SvgRenderSources {
  const SvgRenderSources({
    required this.complete,
    required this.withoutText,
    required this.filledArtwork,
    required this.strokeArtwork,
    required this.globalStrokeArtwork,
    required this.textArtwork,
  });

  final String complete;
  final String withoutText;
  final String filledArtwork;
  final String strokeArtwork;
  final String globalStrokeArtwork;
  final String textArtwork;

  bool get hasGlobalStrokes => complete.contains(
    '$_revealLayerAttribute="${_SvgRevealLayer.globalStroke.name}"',
  );
}

/// Produces renderer-friendly SVG sources while keeping the imported DOM order.
///
/// flutter_svg does not currently paint SVG marker elements. Expanding the
/// common line/polyline marker form into regular transformed paths also makes
/// arrowheads available to Preview and export. A second source excludes text
/// so filled artwork can reveal independently without rectangular patches.
class SvgRenderSourceBuilder {
  const SvgRenderSourceBuilder();

  SvgRenderSources build(String source) {
    final completeDocument = XmlDocument.parse(source);
    _tagGlobalStrokes(completeDocument);
    _expandMarkers(completeDocument);
    final complete = completeDocument.toXmlString();
    final baseDocument = XmlDocument.parse(complete);
    for (final text
        in baseDocument.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local.toLowerCase() == 'text')
            .toList(growable: false)) {
      text.parent?.children.remove(text);
    }
    final filledDocument = XmlDocument.parse(complete);
    _retainRevealLayer(filledDocument, _SvgRevealLayer.fill);
    final strokeDocument = XmlDocument.parse(complete);
    _retainRevealLayer(strokeDocument, _SvgRevealLayer.stroke);
    final globalStrokeDocument = XmlDocument.parse(complete);
    _retainRevealLayer(globalStrokeDocument, _SvgRevealLayer.globalStroke);
    final textDocument = XmlDocument.parse(complete);
    _retainTextLayer(textDocument);
    return SvgRenderSources(
      complete: complete,
      withoutText: baseDocument.toXmlString(),
      filledArtwork: filledDocument.toXmlString(),
      strokeArtwork: strokeDocument.toXmlString(),
      globalStrokeArtwork: globalStrokeDocument.toXmlString(),
      textArtwork: textDocument.toXmlString(),
    );
  }

  void _tagGlobalStrokes(XmlDocument document) {
    final root = document.rootElement;
    final viewBox = _numbers(root.getAttribute('viewBox'));
    final width = viewBox.length == 4 && viewBox[2] > 0
        ? viewBox[2]
        : _number(root.getAttribute('width')) ?? 1;
    final height = viewBox.length == 4 && viewBox[3] > 0
        ? viewBox[3]
        : _number(root.getAttribute('height')) ?? 1;
    for (final line in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == 'line',
    )) {
      final x1 = _number(line.getAttribute('x1')) ?? 0;
      final y1 = _number(line.getAttribute('y1')) ?? 0;
      final x2 = _number(line.getAttribute('x2')) ?? 0;
      final y2 = _number(line.getAttribute('y2')) ?? 0;
      if ((x2 - x1).abs() / width >= 0.60 && (y2 - y1).abs() / height >= 0.35) {
        line.setAttribute(
          _revealLayerAttribute,
          _SvgRevealLayer.globalStroke.name,
        );
      }
    }
  }

  void _retainTextLayer(XmlDocument document) {
    for (final element
        in document.descendants
            .whereType<XmlElement>()
            .where(
              (element) =>
                  _drawableElements.contains(
                    element.name.local.toLowerCase(),
                  ) &&
                  element.name.local.toLowerCase() != 'text',
            )
            .toList(growable: false)) {
      element.parent?.children.remove(element);
    }
  }

  void _retainRevealLayer(XmlDocument document, _SvgRevealLayer layer) {
    final root = document.rootElement;

    void visit(
      XmlElement element,
      _RevealPaint inherited, {
      bool insideDefinition = false,
    }) {
      final name = element.name.local.toLowerCase();
      final definition = insideDefinition || _definitionElements.contains(name);
      final paint = inherited.merge(element);
      final forcedLayer = element.getAttribute(_revealLayerAttribute);
      if (!definition && forcedLayer != null) {
        if (forcedLayer != layer.name) {
          element.parent?.children.remove(element);
          return;
        }
        return;
      }
      if (!definition && _drawableElements.contains(name)) {
        final elementLayer = _layerFor(element, paint);
        if (elementLayer == null || elementLayer != layer) {
          element.parent?.children.remove(element);
        }
        return;
      }
      for (final child in element.childElements.toList(growable: false)) {
        visit(child, paint, insideDefinition: definition);
      }
    }

    visit(root, const _RevealPaint());
  }

  void _expandMarkers(XmlDocument document) {
    final markers = <String, XmlElement>{};
    for (final marker in document.descendants.whereType<XmlElement>()) {
      final id = marker.getAttribute('id');
      if (marker.name.local.toLowerCase() == 'marker' && id != null) {
        markers[id] = marker;
      }
    }
    if (markers.isEmpty) return;
    final drawables = document.descendants
        .whereType<XmlElement>()
        .where(
          (element) => const {
            'line',
            'polyline',
            'polygon',
          }.contains(element.name.local.toLowerCase()),
        )
        .toList(growable: false);
    for (final drawable in drawables) {
      for (final placement in const ['marker-start', 'marker-end']) {
        final reference = _markerReference(drawable.getAttribute(placement));
        final marker = reference == null ? null : markers[reference];
        if (marker == null) continue;
        final endpoints = _endpoints(drawable);
        if (endpoints == null) continue;
        final start = placement == 'marker-start';
        final anchor = start ? endpoints.$1 : endpoints.$2;
        var angle = math.atan2(
          endpoints.$2.$2 - endpoints.$1.$2,
          endpoints.$2.$1 - endpoints.$1.$1,
        );
        final orient = marker.getAttribute('orient')?.trim().toLowerCase();
        if (orient != null &&
            orient != 'auto' &&
            orient != 'auto-start-reverse') {
          angle =
              (double.tryParse(orient) ?? angle * 180 / math.pi) *
              math.pi /
              180;
        } else if (start && orient == 'auto-start-reverse') {
          angle += math.pi;
        }
        final viewBox = _numbers(marker.getAttribute('viewBox'));
        final viewWidth = viewBox.length == 4 && viewBox[2] > 0
            ? viewBox[2]
            : 1.0;
        final viewHeight = viewBox.length == 4 && viewBox[3] > 0
            ? viewBox[3]
            : 1.0;
        final markerWidth = _number(marker.getAttribute('markerWidth')) ?? 3;
        final markerHeight = _number(marker.getAttribute('markerHeight')) ?? 3;
        final strokeScale =
            marker.getAttribute('markerUnits')?.toLowerCase() ==
                'userspaceonuse'
            ? 1.0
            : _number(drawable.getAttribute('stroke-width')) ?? 1;
        final refX = _number(marker.getAttribute('refX')) ?? 0;
        final refY = _number(marker.getAttribute('refY')) ?? 0;
        final transform = [
          'translate(${anchor.$1} ${anchor.$2})',
          'rotate(${angle * 180 / math.pi})',
          'scale(${markerWidth * strokeScale / viewWidth} ${markerHeight * strokeScale / viewHeight})',
          'translate(${-refX} ${-refY})',
        ].join(' ');
        final expanded = XmlElement(const XmlName.parts('g'), [
          XmlAttribute(const XmlName.parts('transform'), transform),
          XmlAttribute(
            const XmlName.parts(_revealLayerAttribute),
            drawable.getAttribute(_revealLayerAttribute) ??
                _SvgRevealLayer.stroke.name,
          ),
        ], marker.children.map((child) => child.copy()));
        final parent = drawable.parent;
        if (parent == null) continue;
        final index = parent.children.indexOf(drawable);
        parent.children.insert(index + 1, expanded);
        drawable.removeAttribute(placement);
      }
    }
    for (final marker in markers.values) {
      marker.parent?.children.remove(marker);
    }
  }
}

const _revealLayerAttribute = 'data-handdraw-reveal-layer';
const _definitionElements = {
  'defs',
  'clippath',
  'mask',
  'pattern',
  'symbol',
  'lineargradient',
  'radialgradient',
};
const _drawableElements = {
  'path',
  'line',
  'polyline',
  'polygon',
  'rect',
  'circle',
  'ellipse',
  'text',
  'image',
  'use',
  'foreignobject',
};

enum _SvgRevealLayer { fill, stroke, globalStroke }

_SvgRevealLayer? _layerFor(XmlElement element, _RevealPaint paint) {
  final name = element.name.local.toLowerCase();
  if (name == 'text') return null;
  if (name == 'line' || name == 'polyline') return _SvgRevealLayer.stroke;
  if (name == 'image' || name == 'use' || name == 'foreignobject') {
    return _SvgRevealLayer.fill;
  }
  if (name == 'path') {
    final closed = RegExp(
      r'[zZ](?:\s|,|$)',
    ).hasMatch(element.getAttribute('d') ?? '');
    return closed && paint.hasFill
        ? _SvgRevealLayer.fill
        : _SvgRevealLayer.stroke;
  }
  if (name == 'polygon') {
    return paint.hasFill ? _SvgRevealLayer.fill : _SvgRevealLayer.stroke;
  }
  return paint.hasFill ? _SvgRevealLayer.fill : _SvgRevealLayer.stroke;
}

class _RevealPaint {
  const _RevealPaint({this.fill = 'black', this.stroke = 'none'});

  final String fill;
  final String stroke;

  bool get hasFill => fill.trim().toLowerCase() != 'none';

  _RevealPaint merge(XmlElement element) {
    final declarations = <String, String>{};
    for (final declaration in (element.getAttribute('style') ?? '').split(
      ';',
    )) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;
      declarations[declaration.substring(0, separator).trim().toLowerCase()] =
          declaration.substring(separator + 1).trim();
    }
    return _RevealPaint(
      fill: element.getAttribute('fill') ?? declarations['fill'] ?? fill,
      stroke:
          element.getAttribute('stroke') ?? declarations['stroke'] ?? stroke,
    );
  }
}

String? _markerReference(String? value) => RegExp(
  r'^url\(\s*#([^)\s]+)\s*\)$',
).firstMatch(value?.trim() ?? '')?.group(1);

((double, double), (double, double))? _endpoints(XmlElement element) {
  final name = element.name.local.toLowerCase();
  if (name == 'line') {
    return (
      (
        _number(element.getAttribute('x1')) ?? 0,
        _number(element.getAttribute('y1')) ?? 0,
      ),
      (
        _number(element.getAttribute('x2')) ?? 0,
        _number(element.getAttribute('y2')) ?? 0,
      ),
    );
  }
  final values = _numbers(element.getAttribute('points'));
  if (values.length < 4 || values.length.isOdd) return null;
  return ((values[0], values[1]), (values[values.length - 2], values.last));
}

double? _number(String? value) => value == null
    ? null
    : double.tryParse(
        RegExp(
              r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
            ).firstMatch(value)?.group(0) ??
            '',
      );

List<double> _numbers(String? value) => value == null
    ? const []
    : RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
          .allMatches(value)
          .map((match) => double.parse(match.group(0)!))
          .toList(growable: false);
