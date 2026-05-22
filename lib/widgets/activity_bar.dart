import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/language_service.dart';

enum ActivityBarItem { explorer, search, extensions, settings }

class ActivityBar extends StatelessWidget {
  final ActivityBarItem selected;
  final ValueChanged<ActivityBarItem> onSelect;

  const ActivityBar({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      width: 48,
      color: VscodeTheme.activityBg,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _item(ActivityBarItem.explorer, Icons.folder_outlined, lang.tr('activity.explorer')),
          _item(ActivityBarItem.search, Icons.search, lang.tr('activity.search')),
          _item(ActivityBarItem.extensions, Icons.extension_outlined, lang.tr('activity.extensions')),
          const Spacer(),
          _item(ActivityBarItem.settings, Icons.settings_outlined, lang.tr('activity.settings')),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(ActivityBarItem item, IconData icon, String tooltip) {
    final isSelected = selected == item;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: () => onSelect(item),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? VscodeTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected ? VscodeTheme.fg : VscodeTheme.fgMuted,
          ),
        ),
      ),
    );
  }
}
