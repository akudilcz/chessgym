import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/rating_tier.dart';

/// Horizontal rainbow bar spanning the rating range with a marker for the
/// player's current rating. Tier labels sit under each segment.
class TierBar extends StatelessWidget {
  final int displayedRating;
  final int rangeMin;
  final int rangeMax;
  final double height;

  const TierBar({
    super.key,
    required this.displayedRating,
    this.rangeMin = 400,
    this.rangeMax = 2500,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final tiers = RatingTier.values;
    final rating = displayedRating.clamp(rangeMin, rangeMax);
    final span = rangeMax - rangeMin;

    return LayoutBuilder(builder: (ctx, cons) {
      final width = cons.maxWidth;
      final markerX = (rating - rangeMin) / span * width;

      // Compute per-tier segment widths in pixels.
      final segWidths = <double>[];
      for (var i = 0; i < tiers.length; i++) {
        final from = tiers[i].floor.clamp(rangeMin, rangeMax);
        final to = i + 1 < tiers.length
            ? tiers[i + 1].floor.clamp(rangeMin, rangeMax)
            : rangeMax;
        segWidths.add((to - from) / span * width);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Marker + rating number above the bar.
          SizedBox(
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  // clamp() throws when its upper bound is below its lower
                  // one, so a bar narrower than the 48px label crashes
                  // layout outright. Reachable by resizing the desktop
                  // window; math.max keeps the range valid.
                  left: (markerX - 24)
                      .clamp(0.0, math.max(0.0, width - 48)),
                  top: 0,
                  child: SizedBox(
                    width: 48,
                    child: Text(
                      '$displayedRating',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (markerX - 6).clamp(-6, width - 6),
                  bottom: -2,
                  child: const Icon(Icons.arrow_drop_down, size: 16),
                ),
              ],
            ),
          ),
          // The rainbow bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: [
                for (var i = 0; i < tiers.length; i++)
                  SizedBox(
                    width: segWidths[i],
                    height: height,
                    child: Container(color: tiers[i].color),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Tier abbreviations under each segment.
          Row(
            children: [
              for (var i = 0; i < tiers.length; i++)
                SizedBox(
                  width: segWidths[i],
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _abbrev(tiers[i]),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: tiers[i].color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }

  static String _abbrev(RatingTier t) => switch (t) {
        RatingTier.beginner => 'BEG',
        RatingTier.novice => 'NOV',
        RatingTier.intermediate => 'INT',
        RatingTier.advanced => 'ADV',
        RatingTier.expert => 'EXP',
        RatingTier.master => 'MST',
        RatingTier.grandmaster => 'GM',
      };
}
