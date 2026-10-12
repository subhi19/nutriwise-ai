import 'package:flutter/material.dart';

class SelectableChip extends StatelessWidget {
  final String label;
  final String? emoji;
  final bool selected;
  final bool enabled;
  final Color color;
  final ValueChanged<bool> onSelected;

  const SelectableChip({
    super.key,
    required this.label,
    this.emoji,
    required this.selected,
    required this.color,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => onSelected(!selected) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : const Color(0xFFDDD6C9), width: 1.4),
            boxShadow: selected
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF26322E),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle, size: 16, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}