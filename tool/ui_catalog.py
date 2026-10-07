#!/usr/bin/env python3
"""Refresh the source inventory embedded in ui_catalog.html using the current checkout."""
import argparse
import collections
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tool/ui_catalog.html'
GROUPS = {
    'Buttons': 'AppButton AppIconButton AppDialogAction TextButton FilledButton OutlinedButton ElevatedButton IconButton BackButton CupertinoButton CupertinoDialogAction ExButtonText ExButtonOutline ExButtonElevated ExCloseButton CenterPlayButton',
    'Inputs': 'AppTextField AppTextFormField AppDropdown AppDropdownFormField TextField TextFormField CupertinoTextField CupertinoTextFormFieldRow ExAutoComplate TypeAheadField DropdownButton DropdownButtonFormField DropdownMenuItem DropdownButtonHideUnderline',
    'Selection': 'Switch Checkbox CheckboxListTile ChoiceChip InputChip Slider RangeSlider SliderTheme',
    'Navigation': 'AppBar Drawer TabBar SearchTabBar ListTile MenuAnchor MenuItemButton MenuSeparator PopupMenuButton PopupMenuItem CustomPopup ContextMenuWidget Menu MenuAction',
    'Dialogs & overlays': 'AppDialog AppConfirmDialog Dialog AlertDialog CupertinoAlertDialog ExAlert OverPanel DownloadMethodDialog PageDownloadDialog PageDownloadHistoryDialog SearchHistoryDropdown SearchSuggestionsOverlay OverlayPortal Tooltip',
    'Feedback': 'AppNotification SnackBar ExUiLoading ExUiErrorOrEmpty CircularProgressIndicator LinearProgressIndicator CupertinoActivityIndicator HelperToast ToastificationWrapper DottedBorder',
    'Media & content': 'ExAvatarView Text Icon ExThumbnail CachedNetworkImage Image MediaStack MarkdownBlock SelectionArea SelectableText Table TableRow TableConfig ExChewieCustom Chewie MaterialVideoProgressBar PlayerControls PlayerSeekPreview TimelineTile',
    'Layout': 'AppPanel AppSectionHeading ExDivider Scaffold Expanded Flexible Spacer Center Align Positioned ClipRRect ClipRect AnimatedOpacity AnimatedContainer ColoredBox FractionallySizedBox InteractiveViewer InkWell InkResponse GestureDetector MyLayout Container DecoratedBox Material Card Divider VerticalDivider Padding SizedBox ConstrainedBox Row Column Wrap Stack HStack VStack ZStack ListView GridView FlutterListView SingleChildScrollView GlassContainer ExpansionTile LayoutBuilder',
}
SYMBOLS = {name: group for group, names in GROUPS.items() for name in names.split()}
EXTENSIONS = re.compile(r'\.(text|onInkTap|onTap|cornerRadius|shimmer|tooltip|box)\b')


def inventory():
    records, files, definitions = [], [], []
    symbols = dict(SYMBOLS)
    for path in (ROOT / 'lib').rglob('*.dart'):
        for name in re.findall(r'class\s+(\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|GetView)\b', path.read_text()):
            symbols.setdefault(name, 'Project widgets')
    constructor_pattern = re.compile(r'\b(' + '|'.join(sorted(symbols, key=len, reverse=True)) + r')(\.[A-Za-z_]\w*)?\s*(?:<[^\n()]*>)?\s*\(')
    tokens = {key: collections.defaultdict(list) for key in ['fontSize', 'radius', 'spacing', 'colors', 'icons']}
    for path in sorted((ROOT / 'lib').rglob('*.dart')):
        if path.name.endswith('.g.dart'):
            continue
        source = path.read_text()
        relative = path.relative_to(ROOT).as_posix()
        lines = source.splitlines()
        before = len(records)
        for match in constructor_pattern.finditer(source):
            base, suffix = match.group(1), match.group(2) or ''
            if suffix in {'.styleFrom', '.of', '.fromJson'} or (base == 'AppNotification' and suffix != '.show'):
                continue
            line = source.count('\n', 0, match.start()) + 1
            records.append({'type': base + suffix, 'group': symbols[base], 'file': relative, 'line': line,
                            'snippet': '\n'.join(lines[max(0, line - 2):line + 3])[:550]})
        for match in EXTENSIONS.finditer(source):
            line = source.count('\n', 0, match.start()) + 1
            records.append({'type': 'VelocityX .' + match.group(1), 'group': 'Extensions', 'file': relative,
                            'line': line, 'snippet': lines[line - 1][:900]})
        for match in re.finditer(r'class\s+(\w+)\s+extends\s+(StatelessWidget|StatefulWidget|GetView)(?:<[^>]*>)?', source):
            definitions.append({'name': match.group(1), 'base': match.group(2), 'file': relative,
                                'line': source.count('\n', 0, match.start()) + 1})
        token_patterns = {
            'fontSize': r'(?:fontSize:\s*|\.size\()(\d+(?:\.\d+)?)',
            'radius': r'(?:BorderRadius\.circular\(|cornerRadius\(|radius:\s*)(\d+(?:\.\d+)?)',
            'spacing': r'(?:EdgeInsets\.all\(|spacing:\s*|runSpacing:\s*)(\d+(?:\.\d+)?)',
            'colors': r'((?:AppColor|Colors|CupertinoColors|Vx)\.[A-Za-z_]\w*(?:\.shade\d+)?|Color\(0x[0-9a-fA-F]+\))',
            'icons': r'((?:Icons|CupertinoIcons)\.\w+|UIconsPro\.\w+\.\w+)',
        }
        for key, pattern in token_patterns.items():
            for match in re.finditer(pattern, source):
                if key == 'colors' and match.group(1) == 'AppColor.dependOn':
                    continue
                line = source.count('\n', 0, match.start()) + 1
                tokens[key][match.group(1)].append({'file': relative, 'line': line})
        if len(records) > before:
            files.append({'file': relative, 'matches': len(records) - before,
                          'types': sorted({r['type'] for r in records[before:]})})
    palette_source = (ROOT / 'lib/app/core/app_color.dart').read_text()
    palette = [{'name': m.group(1), 'expression': m.group(2).strip(),
                'line': palette_source.count('\n', 0, m.start()) + 1}
               for m in re.finditer(r'static Color get (\w+) => ([^;]+);', palette_source)]
    assert records and palette and any(r['type'] == 'AppButton' for r in records)
    assert all((ROOT / r['file']).is_file() and r['line'] > 0 for r in records)
    return {'records': records, 'files': files, 'definitions': definitions, 'tokens': tokens,
            'palette': palette, 'scannedFiles': len(list((ROOT / 'lib').rglob('*.dart')))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check that the embedded inventory matches the current source.')
    args = parser.parse_args()
    data = json.dumps(inventory(), ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    html = OUTPUT.read_text()
    pattern = r'(<script id="source-data" type="application/json">)(.*?)(</script>)'
    match = re.search(pattern, html, re.S)
    assert match, 'Missing inventory marker'
    if args.check:
        assert match.group(2) == data, 'Inventory is stale; run python3 tool/ui_catalog.py'
        print('Inventory matches current source; file references and required families checked.')
    else:
        OUTPUT.write_text(html[:match.start(2)] + data + html[match.end(2):])
        print(f'Updated {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
