# Accessibility

Accessibility is not a toggle; it is baseline behavior. Settings extend defaults, they do not enable features that should have always worked.

## Visual

- **Contrast**: the default board palette meets WCAG 2.1 AA contrast (≥ 4.5:1) between light and dark squares, and between any piece and the square it sits on.
- **Colorblind-safe**: the default palette is designed for deuteranopia and protanopia; a "high contrast" setting swaps in a black/white palette with additional outline on pieces for achromatopsia and low vision.
- **Text scale**: all UI text respects the OS's dynamic type / font-scale setting up to the platform maximum (200% on iOS, 130% on Android). No fixed pixel sizes anywhere.
- **Reduced motion**: when the OS signals reduced motion, piece-move animations collapse to instant state changes; pulse/glow affordances are replaced with static outlines.

## Input

- **Touch targets**: all interactive targets meet the 44×44 logical-pixel minimum (iOS HIG) and 48×48 dp (Material).
- **One-handed use**: all primary actions reachable in the lower 2/3 of the screen on phone form factor.
- **Keyboard (iPad + Android with hardware keyboard)**: arrow keys step through moves in analyze; letters + digits enter SAN in a future version.
- **Drag or tap**: moves can always be made by dragging OR by tap-tap (tap piece, tap destination). The player never has to choose.

## Screen reader

- The board is announced as a grid; each square announces "file rank, piece or empty", e.g. "e4, white pawn".
- A move is announced in SAN: "Knight takes f7 check".
- Puzzle prompt is announced ("White to move. Find the best move.").
- Theme names are announced after resolution, not before.
- The constellation map announces each theme node with (name, mastery level, locked/unlocked state).

## Sound

Sounds are not shipped in the current build. The app is silent on moves, captures, checks, and mates; all feedback is visual and haptic. When sounds do ship they must follow the rule "visual feedback never depends on sound; sound never depends on visual feedback", and Settings will regain a Sound toggle defaulting to on.

## Haptics

Haptics are on by default (configurable in Settings → Feedback). Short medium-impact pulse on puzzle resolve (solve or fail); lighter selection-click on each accepted move.

## Piece set

The default piece set is high-contrast and recognizable at thumbnail scale. Alternative sets may be selected in Settings but never override the default without the player's choice.
