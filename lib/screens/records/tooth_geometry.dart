import 'dart:math' as math;

/// The odontogram's geometry, with no Flutter behind it.
///
/// Everything the chart draws — crown outlines, occlusal fissures, the five
/// surfaces of each crown and the arch each crown is placed on — is measured
/// here in plain Dart, so the on-screen chart and the exported vector asset
/// (`assets/images/tooth_map.svg`, written by `tool/generate_tooth_map_svg.dart`)
/// are the same drawing rather than two drawings that resemble each other.
/// Tooth numbers, hit targets and surface boundaries therefore agree between
/// them by construction.
///
/// `lib/screens/records/tooth_glyphs.dart` turns these shapes into `dart:ui`
/// paths for the painter; nothing here imports `dart:ui`.

/// A point, in the same coordinate space as the caller's box.
class Pt {
  final double x;
  final double y;

  const Pt(this.x, this.y);

  Pt operator +(Pt other) => Pt(x + other.x, y + other.y);
  Pt operator -(Pt other) => Pt(x - other.x, y - other.y);
  Pt operator *(double scale) => Pt(x * scale, y * scale);

  double get distance => math.sqrt(x * x + y * y);

  @override
  String toString() => 'Pt($x, $y)';
}

/// The four crown shapes the odontogram draws. Every tooth is one of these,
/// so incisors never come out looking like molars — the reference chart
/// distinguishes them clearly and so does this.
enum ToothType { incisor, canine, premolar, molar }

/// The five surfaces of a crown, as a chart divides it up. [outer] and
/// [towardMidline] are named by position rather than by clinical term because
/// the clinical term depends on which quadrant the tooth is in; [surfaceName]
/// resolves that.
enum ToothSurface {
  /// The biting surface: occlusal on a molar or premolar, incisal on an
  /// incisor or canine.
  centre,

  /// The cheek- or lip-facing side: buccal at the back, facial at the front.
  outer,

  /// The tongue-facing side.
  lingual,

  /// The side that points along the arch towards the midline.
  towardMidline,

  /// The side that points along the arch away from the midline.
  awayFromMidline,
}

/// Crown type for a Universal tooth number (#1-32).
ToothType toothTypeOf(int tooth) {
  // Position within the quadrant, counting back from the midline: 1 = central
  // incisor, 3 = canine, 4-5 = premolars, 6-8 = molars.
  final fromMidline = positionFromMidline(tooth);
  if (fromMidline <= 2) return ToothType.incisor;
  if (fromMidline == 3) return ToothType.canine;
  if (fromMidline <= 5) return ToothType.premolar;
  return ToothType.molar;
}

/// How far [tooth] sits from the midline within its quadrant: 1 for a central
/// incisor, 8 for a third molar.
int positionFromMidline(int tooth) {
  return switch (tooth) {
    <= 8 => 9 - tooth, // #8 central -> 1, #1 third molar -> 8
    <= 16 => tooth - 8, // #9 central -> 1, #16 third molar -> 8
    <= 24 => 25 - tooth, // #24 central -> 1, #17 third molar -> 8
    _ => tooth - 24, // #25 central -> 1, #32 third molar -> 8
  };
}

/// The clinical name of [surface] on [tooth]: which of its two sides is mesial
/// and which distal depends on the quadrant, and the biting surface and the
/// cheek side are named differently front and back.
String surfaceName(int tooth, ToothSurface surface) {
  final posterior = toothTypeOf(tooth) == ToothType.molar || toothTypeOf(tooth) == ToothType.premolar;
  return switch (surface) {
    ToothSurface.centre => posterior ? 'occlusal' : 'incisal',
    ToothSurface.outer => posterior ? 'buccal' : 'facial',
    ToothSurface.lingual => 'lingual',
    ToothSurface.towardMidline => 'mesial',
    ToothSurface.awayFromMidline => 'distal',
  };
}

/// Crown width for a Universal tooth number, as a multiple of the chart's
/// cell size. Mandibular front teeth are markedly narrower than maxillary
/// ones, which is what gives a real arch its shape — and the reference's.
double toothWidthFactor(int tooth) {
  final lower = tooth >= 17;
  return switch (tooth) {
    1 || 16 || 17 || 32 => 0.95, // third molars
    2 || 15 || 18 || 31 => 1.00, // second molars
    3 || 14 || 19 || 30 => 1.06, // first molars
    4 || 13 || 20 || 29 => 0.82, // second premolars
    5 || 12 || 21 || 28 => 0.84, // first premolars
    6 || 11 => 0.84, // maxillary canines
    22 || 27 => 0.78, // mandibular canines
    7 || 10 => 0.76, // maxillary laterals
    23 || 26 => 0.70, // mandibular laterals
    8 || 9 => 0.86, // maxillary centrals
    _ => lower ? 0.66 : 0.86, // mandibular centrals
  };
}

/// Crown length, again in cell sizes. Occlusal crowns are close to square,
/// so these stay near the width factors.
double toothHeightFactor(int tooth) {
  return switch (toothTypeOf(tooth)) {
    ToothType.molar => 0.98,
    ToothType.premolar => 0.90,
    ToothType.canine => 1.02,
    ToothType.incisor => 0.92,
  };
}

/// The largest half-extent any tooth reaches, used to inset the arch from the
/// edge of the canvas so no crown is ever clipped.
double get maxToothExtent => 1.06;

// --- Crown shapes ---------------------------------------------------------

/// One step of an outline: a straight run to [end], or — when [control] is
/// set — a quadratic curve through it.
class ShapeSegment {
  final Pt? control;
  final Pt end;

  const ShapeSegment(this.end, {this.control});

  bool get isCurve => control != null;
}

/// A run of segments starting at [start]. Crown outlines are closed; the
/// fissures scored across a crown are not.
class ShapeContour {
  final Pt start;
  final List<ShapeSegment> segments;
  final bool closed;

  const ShapeContour(this.start, this.segments, {this.closed = false});

  /// The contour as a polyline, with every curve sampled into [perCurve]
  /// straight runs. Used for surface partitioning and for hit testing.
  List<Pt> flatten({int perCurve = 10}) {
    final points = <Pt>[start];
    var from = start;
    for (final segment in segments) {
      final control = segment.control;
      if (control == null) {
        points.add(segment.end);
      } else {
        for (var i = 1; i <= perCurve; i++) {
          final t = i / perCurve;
          final inverse = 1 - t;
          points.add(Pt(
            inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * segment.end.x,
            inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * segment.end.y,
          ));
        }
      }
      from = segment.end;
    }
    return points;
  }
}

/// One tooth as the chart draws it: the crown silhouette, the fissures scored
/// across its biting surface, and the five surfaces the crown divides into.
///
/// The surfaces are closed regions that tile the crown exactly — they share
/// their boundaries and together cover the whole outline — so a tap can be
/// resolved to a surface, and the exported asset can carry one path per
/// surface for the same purpose.
class ToothShape {
  final ShapeContour outline;
  final List<ShapeContour> grooves;
  final Map<ToothSurface, ShapeContour> surfaces;

  const ToothShape(this.outline, this.grooves, this.surfaces);
}

/// Builds [tooth]'s crown in a box of [w] x [h], seen from above as the
/// reference draws it. The box's top edge (y = 0) is the tooth's outer,
/// cheek-facing side; the chart rotates the box so that edge points out of
/// the arch. The box's right edge (x = w) is the side that faces along the
/// arch in the direction the Universal numbers run.
ToothShape buildToothShape(int tooth, double w, double h) {
  Pt p(double x, double y) => Pt(x * w, y * h);
  double s(double v) => v * math.min(w, h);

  final ShapeContour outline = switch (toothTypeOf(tooth)) {
    // A rounded square with four lobes, the widest crown on the arch.
    ToothType.molar => roundedPolygon(
        [
          p(0.06, 0.24),
          p(0.25, 0.05),
          p(0.75, 0.05),
          p(0.94, 0.24),
          p(0.95, 0.74),
          p(0.77, 0.95),
          p(0.23, 0.95),
          p(0.05, 0.74),
        ],
        s(0.17),
      ),

    // Smaller and rounder than a molar.
    ToothType.premolar => roundedPolygon(
        [
          p(0.07, 0.27),
          p(0.29, 0.06),
          p(0.71, 0.06),
          p(0.93, 0.27),
          p(0.94, 0.71),
          p(0.73, 0.94),
          p(0.27, 0.94),
          p(0.06, 0.71),
        ],
        s(0.21),
      ),

    // Tapers to a cusp on its outer edge — the sharpest crown on the arch.
    ToothType.canine => roundedPolygon(
        [
          p(0.50, 0.00),
          p(0.88, 0.26),
          p(0.95, 0.68),
          p(0.71, 0.97),
          p(0.29, 0.97),
          p(0.05, 0.68),
          p(0.12, 0.26),
        ],
        s(0.08),
      ),

    // A soft rounded wedge.
    ToothType.incisor => roundedPolygon(
        [
          p(0.50, 0.03),
          p(0.86, 0.23),
          p(0.94, 0.66),
          p(0.73, 0.96),
          p(0.27, 0.96),
          p(0.06, 0.66),
          p(0.14, 0.23),
        ],
        s(0.10),
      ),
  };

  final grooves = _groovesOf(tooth, w, h);

  return ToothShape(outline, grooves, _surfacesOf(tooth, outline, w, h));
}

/// The fissure pattern scored across [tooth]'s biting surface.
///
/// Patterns are written mesial-first — x = 1 is the side facing the midline,
/// x = 0 the side facing the back of the mouth, y = 0 the cheek or lip side
/// and y = 1 the tongue side — and mirrored onto the crown's own box, whose
/// +x points along the arch in the direction the Universal numbers run. That
/// is what lets a groove be named for the cusp it runs to: a buccal groove
/// stays buccal in all four quadrants, and a distal one stays distal.
///
/// The patterns themselves are the ones the reference chart draws, which are
/// the textbook ones: a Y about the central fossa on a maxillary molar, a
/// mesiodistal central groove with buccal and lingual branches on a mandibular
/// molar, a single central fissure between the two cusps of a premolar, and a
/// crescent just inside the biting edge of an incisor or canine.
List<ShapeContour> _groovesOf(int tooth, double w, double h) {
  final mesialIsPlusX = _plusXIsMesial(tooth);
  // x as written is mesialward; flip it for the quadrants laid out the other
  // way round, so every pattern below reads the same whichever side it is on.
  Pt p(double mesial, double lingual) =>
      Pt((mesialIsPlusX ? mesial : 1 - mesial) * w, lingual * h);

  final upper = tooth <= 16;

  return switch (toothTypeOf(tooth)) {
    // Maxillary molars are four-cusped with an oblique ridge across them, so
    // the fissures meet the central fossa from three sides only: the mesial
    // pit, the buccal groove, and the distal oblique groove running out
    // between the distal cusps. Nothing crosses the ridge itself.
    ToothType.molar when upper => [
        curve(p(0.86, 0.38), p(0.66, 0.40), p(0.50, 0.47)),
        curve(p(0.50, 0.47), p(0.50, 0.28), p(0.44, 0.09)),
        curve(p(0.50, 0.47), p(0.36, 0.64), p(0.20, 0.84)),
      ],

    // Mandibular molars run one central groove the length of the crown, with
    // a branch out to each developmental groove between the cusps: two on the
    // cheek side, one on the tongue side.
    ToothType.molar => [
        ShapeContour(p(0.88, 0.44), [
          ShapeSegment(p(0.52, 0.50), control: p(0.70, 0.45)),
          ShapeSegment(p(0.13, 0.45), control: p(0.32, 0.51)),
        ]),
        curve(p(0.62, 0.48), p(0.66, 0.28), p(0.64, 0.10)),
        curve(p(0.27, 0.48), p(0.23, 0.29), p(0.24, 0.11)),
        curve(p(0.46, 0.49), p(0.43, 0.70), p(0.44, 0.90)),
      ],

    // A premolar has two cusps and one fissure between them, pitted at each
    // end where it runs up onto the marginal ridges. The mandibular ones sit
    // lower and carry a short lingual groove instead of the mesial pit.
    ToothType.premolar when upper => [
        ShapeContour(p(0.80, 0.46), [
          ShapeSegment(p(0.20, 0.46), control: p(0.50, 0.38)),
        ]),
        polyline([p(0.78, 0.43), p(0.85, 0.28)]),
        polyline([p(0.22, 0.43), p(0.15, 0.28)]),
      ],

    ToothType.premolar => [
        ShapeContour(p(0.75, 0.43), [
          ShapeSegment(p(0.27, 0.45), control: p(0.50, 0.37)),
        ]),
        curve(p(0.52, 0.42), p(0.54, 0.62), p(0.53, 0.80)),
      ],

    // A canine is a single cusp: its tip, and the two ridges falling away from
    // it towards the neighbouring teeth.
    ToothType.canine => [
        curve(p(0.18, 0.34), p(0.50, 0.12), p(0.82, 0.34)),
        polyline([p(0.50, 0.16), p(0.50, 0.50)]),
      ],

    // An incisor is scored once, just inside its biting edge.
    ToothType.incisor => [
        curve(p(0.20, 0.30), p(0.50, 0.13), p(0.80, 0.30)),
      ],
  };
}

/// A closed polygon with every corner rounded off, which is how all four
/// crown shapes are built: straight-edged outlines read as machine parts,
/// and real crowns have no corners.
ShapeContour roundedPolygon(List<Pt> vertices, double radius) {
  Pt? start;
  final segments = <ShapeSegment>[];
  for (var i = 0; i < vertices.length; i++) {
    final current = vertices[i];
    final previous = vertices[(i - 1 + vertices.length) % vertices.length];
    final next = vertices[(i + 1) % vertices.length];

    final toPrevious = previous - current;
    final toNext = next - current;
    // Never round away more than half an edge, or neighbouring corners eat
    // into each other and the outline folds over itself.
    final from = current + toPrevious * (math.min(radius, toPrevious.distance / 2) / toPrevious.distance);
    final to = current + toNext * (math.min(radius, toNext.distance / 2) / toNext.distance);

    if (start == null) {
      start = from;
    } else {
      segments.add(ShapeSegment(from));
    }
    segments.add(ShapeSegment(to, control: current));
  }
  return ShapeContour(start!, segments, closed: true);
}

ShapeContour polyline(List<Pt> points) {
  return ShapeContour(
    points.first,
    [for (final point in points.skip(1)) ShapeSegment(point)],
  );
}

ShapeContour curve(Pt from, Pt control, Pt to) {
  return ShapeContour(from, [ShapeSegment(to, control: control)]);
}

// --- Surface partitioning -------------------------------------------------

/// How much of the crown the biting surface takes, measured from the centre
/// out. The remainder is split between the four sides, which is how a chart
/// divides a crown: a central box with four collars around it.
const double _centreShare = 0.44;

/// Which way along the arch a tooth's local +x axis points. Crowns are laid
/// out in Universal order, so +x runs towards the midline in the first half of
/// each arch (#1-8, #17-24) and away from it in the second (#9-16, #25-32).
bool _plusXIsMesial(int tooth) => (tooth <= 8) || (tooth >= 17 && tooth <= 24);

/// Cuts [outline] into its five surfaces. The crown is convex, so the angle
/// of its outline about the crown's centre only ever increases — that is what
/// lets the four sides be cut off at fixed diagonals without any region
/// overlapping another or a sliver being left between them.
Map<ToothSurface, ShapeContour> _surfacesOf(int tooth, ShapeContour outline, double w, double h) {
  final centre = Pt(w / 2, h / 2);
  final points = outline.flatten(perCurve: 7);
  // flatten() repeats nothing, but a closed contour's last point is not its
  // first, so close the ring explicitly before walking it.
  final ring = [...points, outline.start];

  // Measured in the box's own units, so a crown that is wider than it is tall
  // still gets its corners cut at the visual diagonal rather than a skewed one.
  double angleOf(Pt point) => math.atan2((point.y - centre.y) / h, (point.x - centre.x) / w);

  // Unwrap the ring's angles into one monotonic run, then flip it if the
  // outline was wound clockwise, so a sector is always an increasing span.
  final angles = <double>[angleOf(ring.first)];
  for (var i = 1; i < ring.length; i++) {
    var angle = angleOf(ring[i]);
    while (angle - angles.last > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angles.last - angle > math.pi) {
      angle += 2 * math.pi;
    }
    angles.add(angle);
  }
  // A clockwise outline runs the angles downwards; walking it backwards makes
  // every sector an increasing span, which is all the cutting below needs.
  final descending = angles.last < angles.first;
  final wound = descending ? ring.reversed.toList() : ring;
  final woundAngles = descending ? angles.reversed.toList() : angles;

  /// The sides, as the angle spans they cover. 0 is the +x side and -pi/2 the
  /// outer, cheek-facing side, since y grows towards the tongue.
  const quarter = math.pi / 4;
  final sectors = <ToothSurface, (double, double)>{
    ToothSurface.outer: (-3 * quarter, -quarter),
    _plusXIsMesial(tooth) ? ToothSurface.towardMidline : ToothSurface.awayFromMidline: (-quarter, quarter),
    ToothSurface.lingual: (quarter, 3 * quarter),
    _plusXIsMesial(tooth) ? ToothSurface.awayFromMidline : ToothSurface.towardMidline: (3 * quarter, 5 * quarter),
  };

  Pt shrink(Pt point) => centre + (point - centre) * _centreShare;

  final surfaces = <ToothSurface, ShapeContour>{
    // The biting surface: the whole crown pulled in towards its centre.
    ToothSurface.centre: ShapeContour(
      shrink(outline.start),
      [for (final segment in outline.segments) ShapeSegment(shrink(segment.end), control: segment.control == null ? null : shrink(segment.control!))],
      closed: true,
    ),
  };

  for (final entry in sectors.entries) {
    final (from, to) = entry.value;
    // Each collar is the run of outline between two diagonals, closed back
    // along the same run pulled in to the biting surface's edge — so the two
    // regions share that edge exactly and nothing falls between them.
    final arc = _arcBetween(wound, woundAngles, from, to);
    if (arc.length < 2) continue;
    surfaces[entry.key] = polygon([...arc, ...arc.reversed.map(shrink)]);
  }

  return surfaces;
}

/// The run of [ring] between the [from] and [to] diagonals, with a point
/// interpolated onto each end so neighbouring runs meet exactly.
///
/// Angles are re-anchored at [from] before the run is picked out. One sector
/// per tooth straddles the point where the outline happens to start, and
/// selecting its points by ring order instead would take them from both ends
/// of the ring — giving a polygon that jumps across the crown, overlaps its
/// neighbours and hit-tests as a bow tie.
List<Pt> _arcBetween(List<Pt> ring, List<double> angles, double from, double to) {
  final count = ring.length - 1; // the ring's last point repeats its first
  if (count < 2) return const [];

  /// How far past [from] an angle sits, in `[0, 2pi)`.
  double anchored(double angle) {
    final turn = (angle - from) % (2 * math.pi);
    return turn < 0 ? turn + 2 * math.pi : turn;
  }

  // Sorting by the anchored angle is the ring walked from the [from] diagonal
  // round to it again: the outline is convex, so its points only ever advance
  // in angle, and consecutive entries here are still neighbours on the ring.
  final walk = <(double, Pt)>[
    for (var i = 0; i < count; i++) (anchored(angles[i]), ring[i]),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  /// The point [turn] radians past [from], interpolated along whichever edge
  /// of the walk crosses it. The last edge closes the walk, so it is measured
  /// a full turn further on.
  Pt pointAt(double turn) {
    for (var i = 0; i < walk.length; i++) {
      final last = i == walk.length - 1;
      final (startAngle, startPoint) = walk[i];
      final (nextAngle, nextPoint) = walk[last ? 0 : i + 1];
      final endAngle = last ? nextAngle + 2 * math.pi : nextAngle;
      for (final candidate in [turn, turn + 2 * math.pi]) {
        if (candidate < startAngle || candidate > endAngle) continue;
        final width = endAngle - startAngle;
        final t = width == 0 ? 0.0 : (candidate - startAngle) / width;
        return startPoint + (nextPoint - startPoint) * t;
      }
    }
    return walk.first.$2;
  }

  final span = to - from; // always a quarter turn, so never wraps on itself
  return [
    pointAt(0),
    for (final (turn, point) in walk)
      if (turn > 0 && turn < span) point,
    pointAt(span),
  ];
}

/// A closed contour through [points], with no curves.
ShapeContour polygon(List<Pt> points) {
  return ShapeContour(
    points.first,
    [for (final point in points.skip(1)) ShapeSegment(point)],
    closed: true,
  );
}

// --- Arch layout ----------------------------------------------------------

/// Universal numbers in the order they sit along each arch, read left to right
/// across the chart. The patient faces the viewer, so the patient's right is
/// the viewer's left: #1 (upper right third molar) opens the upper arch on the
/// left, and #32 (lower right third molar) closes the lower arch on that same
/// side.
const List<int> kUpperArchTeeth = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
const List<int> kLowerArchTeeth = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];

/// Width over height of the chart, taken off the reference drawing: there each
/// arch measures 545x405 and the pair together spans 545x840.
const double kChartAspect = 0.632;

/// Slack between neighbouring crowns and at the ends of each arch, in cells.
/// Crowns sit flush against each other the way they do in the reference and in
/// a real mouth, so there is nothing between them but their two outlines.
const double kGapUnits = 0.0;
const double kPadUnits = 0.08;

/// Share of the chart's height left empty between the two arches — the wide
/// separation the reference has.
const double kArchGapFraction = 0.065;

/// Outline weight relative to a cell, and the fissure weight as a fraction of
/// that. Taken off the reference, where a crown about 90px across is drawn in
/// a line about 2.5px thick, with the fissures scored a little finer.
///
/// The chart and the exported asset both stroke with these, so the drawing has
/// the same weight of line at the same size in either.
const double kToothStrokeUnits = 0.030;
const double kGrooveStrokeFraction = 0.8;

/// Number height relative to a cell. Small enough to sit between neighbouring
/// numbers at the crowded front of the arch, large enough to read.
const double kNumberFontUnits = 0.32;

/// Room reserved outside each arch for a tooth's number, in cells: the gap
/// between the crown and its number, then the number itself. The arch is
/// pulled in by this much so the outermost numbers are never clipped.
///
/// The box is the *whole* width of a two-digit number, not half of it: the
/// number is centred one half-extent out from the gap, so its far edge lands a
/// full extent beyond the crown.
const double kNumberGapUnits = 0.16;
const double kNumberBoxUnits = kNumberFontUnits * 2.0;

/// Half an ellipse, sampled so crowns can be spaced along it by arc length
/// rather than by angle: even angular steps would crowd the molars at the back
/// and stretch the incisors across the front.
class EllipseArc {
  final double cx, cy, a, b;

  /// True for the maxillary arch, which sweeps over the top of its centre.
  final bool upper;

  final List<double> _u = <double>[];
  final List<double> _s = <double>[];

  EllipseArc(this.cx, this.cy, this.a, this.b, this.upper) {
    const samples = 360;
    var previous = pointAt(0);
    _u.add(0);
    _s.add(0);
    var travelled = 0.0;
    for (var i = 1; i <= samples; i++) {
      final u = i / samples;
      final point = pointAt(u);
      travelled += (point - previous).distance;
      previous = point;
      _u.add(u);
      _s.add(travelled);
    }
  }

  double get length => _s.last;

  /// `u` runs 0 to 1 left to right along the upper arch and right to left
  /// along the lower one — the order the Universal numbers run in.
  double _phi(double u) => upper ? math.pi * (1 - u) : math.pi * u;

  Pt pointAt(double u) {
    final phi = _phi(u);
    final dy = b * math.sin(phi);
    return Pt(cx + a * math.cos(phi), upper ? cy - dy : cy + dy);
  }

  /// Unit vector pointing straight out of the arch at `u` — away from the
  /// tongue, past the cheek. Where a tooth's number goes.
  Pt outwardAt(double u) {
    final phi = _phi(u);
    // Same normal [angleAt] works from, negated: that one wants the inward
    // direction, this one the outward.
    final nx = -b * math.cos(phi);
    final ny = (upper ? 1 : -1) * a * math.sin(phi);
    final length = math.sqrt(nx * nx + ny * ny);
    if (length == 0) return Pt(0, upper ? -1 : 1);
    return Pt(-nx / length, -ny / length);
  }

  /// Turns a crown so the outer, cheek-facing edge of its cell points straight
  /// out of the arch — the orientation every tooth has in the reference.
  double angleAt(double u) {
    final phi = _phi(u);
    // Inward normal: the cell's top edge faces out, so its foot faces in.
    final nx = -b * math.cos(phi);
    final ny = (upper ? 1 : -1) * a * math.sin(phi);
    final length = math.sqrt(nx * nx + ny * ny);
    if (length == 0) return 0;
    return math.atan2(-nx / length, ny / length);
  }

  double uAtDistance(double s) {
    if (s <= 0) return 0;
    if (s >= length) return 1;
    var lo = 0;
    var hi = _s.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_s[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _s[hi] - _s[lo];
    final t = span == 0 ? 0.0 : (s - _s[lo]) / span;
    return _u[lo] + (_u[hi] - _u[lo]) * t;
  }
}

/// Where one tooth ends up on the chart.
class ToothPlacement {
  final Pt center;
  final double angle;
  final double width;
  final double height;

  /// Unit vector away from the arch, used to sit this tooth's number outside
  /// it the way the reference chart does.
  final Pt outward;

  const ToothPlacement(this.center, this.angle, this.width, this.height, this.outward);
}

/// The measured arch: where every crown sits, how big it is and which way it
/// faces, for one canvas size.
class ArchGeometry {
  final double width;
  final double height;
  final double cell;
  final Map<int, ToothPlacement> placements;

  const ArchGeometry({
    required this.width,
    required this.height,
    required this.cell,
    required this.placements,
  });

  static ArchGeometry build(double width, double height) {
    final archH = height * (1 - kArchGapFraction) / 2;
    final centerX = width / 2;

    double demandOf(List<int> arch) =>
        arch.fold<double>(0, (total, n) => total + toothWidthFactor(n)) +
        (arch.length - 1) * kGapUnits +
        2 * kPadUnits;

    // Both arches ride the same ellipse, so the fuller of the two sets the
    // crown size and the other splits its slack between its ends. That keeps
    // upper and lower teeth drawn to one scale, as the reference has them.
    final demand = math.max(demandOf(kUpperArchTeeth), demandOf(kLowerArchTeeth));

    // Crown size decides how far the ellipse must sit in from the canvas edge
    // — a tooth reaches half its own extent past the arc — and that inset in
    // turn decides how much arc there is to fill. A few passes settle it.
    var cell = width * 0.11;
    var a = 0.0;
    var b = 0.0;
    for (var pass = 0; pass < 16; pass++) {
      // Half a crown, plus the strip its number sits in outside that.
      final inset = cell * (maxToothExtent / 2 + kNumberGapUnits + kNumberBoxUnits);
      a = centerX - inset;
      b = archH - inset;
      if (a <= 2 || b <= 2) break;
      cell = (cell + halfEllipsePerimeter(a, b) / demand) / 2;
    }

    final upperArc = EllipseArc(centerX, archH, a, b, true);
    final lowerArc = EllipseArc(centerX, height - archH, a, b, false);

    final placements = <int, ToothPlacement>{};
    void layOut(List<int> arch, EllipseArc arc) {
      final used = arch.fold<double>(0, (total, n) => total + toothWidthFactor(n) * cell) +
          (arch.length - 1) * kGapUnits * cell;
      var cursor = math.max(0.0, (arc.length - used) / 2);
      for (final n in arch) {
        final w = toothWidthFactor(n) * cell;
        cursor += w / 2;
        final u = arc.uAtDistance(cursor);
        placements[n] = ToothPlacement(
          arc.pointAt(u),
          arc.angleAt(u),
          w,
          toothHeightFactor(n) * cell,
          arc.outwardAt(u),
        );
        cursor += w / 2 + kGapUnits * cell;
      }
    }

    layOut(kUpperArchTeeth, upperArc);
    layOut(kLowerArchTeeth, lowerArc);

    return ArchGeometry(width: width, height: height, cell: cell, placements: placements);
  }

  /// Ramanujan's approximation, halved. Accurate to a fraction of a pixel at
  /// these eccentricities and far cheaper than sampling inside the fit loop.
  static double halfEllipsePerimeter(double a, double b) {
    final h = math.pow((a - b) / (a + b), 2).toDouble();
    return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h))) / 2;
  }

  /// Font size for the tooth numbers at this canvas size.
  double get numberFontSize => math.max(9.0, cell * kNumberFontUnits);

  /// Where a tooth's number is centred: straight out of the arch from the
  /// crown, clear of it by [kNumberGapUnits] plus half the text's own extent.
  ///
  /// Measured from the crown's half-height, so a long molar pushes its number
  /// further out than a short incisor and the ring of numbers stays clear of
  /// the teeth all the way round.
  Pt numberCenterFor(int tooth, double textExtent) {
    final placement = placements[tooth]!;
    final distance = placement.height / 2 + cell * kNumberGapUnits + textExtent / 2;
    return placement.center + placement.outward * distance;
  }

  ToothShape shapeFor(int tooth) {
    final placement = placements[tooth]!;
    return buildToothShape(tooth, placement.width, placement.height);
  }

  /// Maps a point in the tooth's own box onto the chart: the same rotation and
  /// offset the painter applies, so exported paths land where taps do.
  Pt toChart(int tooth, Pt point) {
    final placement = placements[tooth]!;
    final cos = math.cos(placement.angle);
    final sin = math.sin(placement.angle);
    final x = point.x - placement.width / 2;
    final y = point.y - placement.height / 2;
    return Pt(
      placement.center.x + x * cos - y * sin,
      placement.center.y + x * sin + y * cos,
    );
  }
}
