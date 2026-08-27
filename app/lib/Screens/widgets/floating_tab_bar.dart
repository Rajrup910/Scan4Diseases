import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'emerald_waves.dart';

/// One entry in the floating bar.
class NeuroTab {
  final IconData icon;
  final int index;
  final String label;
  const NeuroTab(this.icon, this.index, this.label);
}

/// A floating, frosted-glass bottom bar: a rounded pill of icon tabs plus a
/// separate glowing accent action button.
class FloatingTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<NeuroTab> tabs;
  final NeuroTab action;

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.tabs,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    // Light theme mirrors the website's dock: a near-clear glass
                    // fill (definition comes from the blur + a hairline edge, not
                    // a milky white sheet), a soft top-to-bottom sheen, and a
                    // single gentle drop shadow — NO bright white halo, so the
                    // pill reads as smooth frosted glass rather than a glossy,
                    // glowing panel.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: dark
                          ? [
                              Themes.darkSurface.withValues(alpha: 0.85),
                              Themes.darkSurface.withValues(alpha: 0.70),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.32),
                              Colors.white.withValues(alpha: 0.18),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? 0.25 : 0.55),
                      width: 1.0,
                    ),
                    boxShadow: [
                      // Depth only — the earlier white glow (alpha .55) was the
                      // source of the "glossy" look in light mode; it is gone.
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final t in tabs)
                        _TabButton(
                          tab: t,
                          selected: currentIndex == t.index,
                          dark: dark,
                          onTap: () => onSelect(t.index),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            action: action,
            selected: currentIndex == action.index,
            onTap: () => onSelect(action.index),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final NeuroTab tab;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeInk = dark ? Colors.white : Themes.ink;
    final idleInk = dark ? Themes.darkInkSoft : Themes.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: selected
                ? (dark ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.58))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: dark ? 0.30 : 0.60), width: 1)
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            // A small bump as the tab becomes active gives the selection a
            // tactile "pop" without touching the layout.
            scale: selected ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: Icon(tab.icon, size: 23, color: selected ? activeInk : idleInk),
          ),
        ),
      ),
    );
  }
}

/// Standout action button for "+" New Screening.
/// Clean, unified rounded squircle with dynamic emerald waves and gentle depth shadow.
class _ActionButton extends StatelessWidget {
  final NeuroTab action;
  final bool selected;
  final VoidCallback onTap;

  const _ActionButton({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 66.0;
    final borderRadius = BorderRadius.circular(26);

    return Semantics(
      button: true,
      selected: selected,
      label: action.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: [
                // Subtle, gentle depth shadow
                BoxShadow(
                  color: Themes.brand.withValues(alpha: selected ? 0.30 : 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: EmeraldWaves(
                  borderRadius: borderRadius,
                  height: size,
                  width: size,
                  child: const Icon(
                    Icons.add_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
