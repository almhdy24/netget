import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';

/// Category selector supporting both desktop sidebar rail and mobile compact chip bar.
class CategorySidebar extends StatelessWidget {
  final DownloadCategory selectedCategory;
  final ValueChanged<DownloadCategory> onCategorySelected;
  final Map<DownloadCategory, int> categoryCounts;
  final bool isRail;

  const CategorySidebar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.categoryCounts = const {},
    this.isRail = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isRail) {
      return _buildRail(context);
    }
    return _buildMobileChips(context);
  }

  Widget _buildRail(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 6),
            child: Text(
              'CATEGORIES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (final cat in DownloadCategory.values)
            _buildRailItem(context, cat),
        ],
      ),
    );
  }

  Widget _buildRailItem(BuildContext context, DownloadCategory cat) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selectedCategory == cat;
    final count = categoryCounts[cat] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => onCategorySelected(cat),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
            child: Row(
              children: [
                Icon(
                  NetGetUtils.getCategoryIcon(cat),
                  size: 16,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.2)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: NetGetUtils.tabularStyle(
                        TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileChips(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
        itemCount: DownloadCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = DownloadCategory.values[index];
          final isSelected = selectedCategory == cat;
          final count = categoryCounts[cat];

          return Center(
            child: ChoiceChip(
              visualDensity: VisualDensity.compact,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              avatar: Icon(
                NetGetUtils.getCategoryIcon(cat),
                size: 14,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
                      style: NetGetUtils.tabularStyle(
                        TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? colorScheme.onPrimary.withValues(alpha: 0.8)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              selected: isSelected,
              onSelected: (_) => onCategorySelected(cat),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
    );
  }
}
