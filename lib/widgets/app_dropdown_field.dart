import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';

/// One choice in an [AppDropdownField].
class AppDropdownOption<T> {
  final T value;
  final String label;

  const AppDropdownOption({required this.value, required this.label});
}

/// A dropdown that reads like the app's text fields and, unlike Material's
/// [DropdownButtonFormField], always opens *underneath* the field.
///
/// Material's dropdown positions its menu over the button so the selected item
/// lands on top of it, which covers the field — and the label — the moment it
/// opens. This one links the menu to the field with a [LayerLink] and anchors
/// it to the field's bottom edge, so the list drops down and the field stays
/// visible above it.
class AppDropdownField<T> extends StatefulWidget {
  final T? value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String labelText;

  /// Shown in place of the value while nothing is selected.
  final String hintText;
  final Widget? prefixIcon;

  const AppDropdownField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.labelText,
    this.hintText = 'Not set',
    this.prefixIcon,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild the open menu so the check mark follows the new selection.
    _overlay?.markNeedsBuild();
  }

  bool get _isOpen => _overlay != null;

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final fieldSize = box.size;
    final fieldTopLeft = box.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    // Room left under the field once the keyboard (if any) is accounted for.
    // The menu is capped to it so a long list scrolls in place instead of
    // running off the bottom of the screen — it never flips above the field.
    const gap = 6.0;
    const minHeight = 96.0;
    final spaceBelow = screenHeight - viewInsets - (fieldTopLeft.dy + fieldSize.height) - gap - 12;
    final maxHeight = spaceBelow.clamp(minHeight, 260.0);

    _overlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.shrink(),
            ),
          ),
          Positioned(
            width: fieldSize.width,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, gap),
              child: _buildMenu(maxHeight),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlay!);
    setState(() {});
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() {});
  }

  Widget _buildMenu(double maxHeight) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: widget.options.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final option = widget.options[index];
              final selected = option.value == widget.value;
              return InkWell(
                onTap: () {
                  _close();
                  widget.onChanged(option.value);
                },
                child: Container(
                  color: selected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            color: selected ? AppColors.primary : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (selected) Icon(CupertinoIcons.check_mark, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String? get _selectedLabel {
    for (final option in widget.options) {
      if (option.value == widget.value) return option.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = _selectedLabel;
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggle,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixIcon: widget.prefixIcon,
          ),
          isEmpty: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label ?? widget.hintText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: label == null ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                ),
              ),
              // Points down when closed, up while the menu is open below.
              Icon(
                _isOpen ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                color: AppColors.primary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
