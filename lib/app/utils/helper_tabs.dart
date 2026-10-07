int moveTab<T>(List<T> tabs, int activeIndex, int oldIndex, int newIndex, bool Function(T) isPinned) {
  if (oldIndex < 0 || oldIndex >= tabs.length || newIndex < 0 || newIndex >= tabs.length) return activeIndex;
  final active = tabs[activeIndex];
  final tab = tabs.removeAt(oldIndex);
  final pinnedCount = tabs.where(isPinned).length;
  final destination = isPinned(tab) ? newIndex.clamp(0, pinnedCount) : newIndex.clamp(pinnedCount, tabs.length);
  tabs.insert(destination, tab);
  return tabs.indexOf(active);
}
