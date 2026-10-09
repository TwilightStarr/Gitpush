import 'package:flutter/material.dart';

class QuickCommandChips extends StatelessWidget {
  final List<String> shortcuts;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddShortcut;

  const QuickCommandChips({
    super.key,
    required this.shortcuts,
    required this.onSelect,
    required this.onAddShortcut,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ...shortcuts.map((shortcut) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(shortcut),
                onPressed: () => onSelect(shortcut),
                avatar: const Icon(Icons.bolt, size: 14),
              ),
            );
          }),
          ActionChip(
            label: const Text('+ Kısayol'),
            onPressed: onAddShortcut,
            avatar: const Icon(Icons.add, size: 14),
          ),
        ],
      ),
    );
  }
}
