import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../learning/domain/learning_session.dart';
import '../../subtitles/domain/subtitle_models.dart';

final class SubtitleSettingsSheet extends StatefulWidget {
  const SubtitleSettingsSheet({
    super.key,
    required this.tracks,
    required this.onSelect,
    required this.onOffsetChanged,
    required this.onImport,
    required this.visibility,
    required this.onVisibilityChanged,
  });

  final List<SubtitleTrack> tracks;
  final ValueChanged<SubtitleTrack> onSelect;
  final Future<void> Function(SubtitleTrack track, int offsetMs)
  onOffsetChanged;
  final Future<void> Function() onImport;
  final SubtitleVisibility visibility;
  final ValueChanged<SubtitleVisibility> onVisibilityChanged;

  @override
  State<SubtitleSettingsSheet> createState() => _SubtitleSettingsSheetState();
}

final class _SubtitleSettingsSheetState extends State<SubtitleSettingsSheet> {
  final Map<String, int> _offsets = {};

  @override
  Widget build(BuildContext context) {
    final english = _selectedTrack('en');
    final chinese = _selectedTrack('zh');
    final groups = _groupTracks(widget.tracks);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字幕設定',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'AI 語音辨識（尚未提供）',
                  onPressed: null,
                  icon: const Icon(Icons.auto_awesome),
                ),
                IconButton(
                  tooltip: '手動匯入 SRT',
                  onPressed: () => unawaited(widget.onImport()),
                  icon: const Icon(Icons.playlist_add),
                ),
                IconButton(
                  tooltip: '字幕樣式（尚未提供）',
                  onPressed: null,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '匯入 SRT 後會自動辨識單語或雙語字幕來源。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  (SubtitleVisibility.bilingual, '雙語'),
                  (SubtitleVisibility.englishOnly, '只顯示英文'),
                  (SubtitleVisibility.chineseOnly, '只顯示中文'),
                  (SubtitleVisibility.hidden, '隱藏'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: widget.visibility == option.$1,
                    onSelected: (_) => widget.onVisibilityChanged(option.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            Text('已匯入字幕來源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('尚未匯入字幕來源'),
              )
            else ...[
              for (final group in groups)
                _sourceGroup(context, group, english, chinese),
              if (english != null || chinese != null) ...[
                const Divider(height: 28),
                if (english != null) _offsetControl(context, english),
                if (chinese != null) _offsetControl(context, chinese),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _sourceGroup(
    BuildContext context,
    _SubtitleSourceGroup group,
    SubtitleTrack? selectedEnglish,
    SubtitleTrack? selectedChinese,
  ) {
    final englishTracks = group.tracks.where(_isEnglish).toList();
    final chineseTracks = group.tracks
        .where((track) => !_isEnglish(track))
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.subtitles_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.sourceName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(group.languageLabel),
                  ),
                ],
              ),
            ),
            if (englishTracks.isNotEmpty)
              _trackOptions(englishTracks, selectedEnglish),
            if (chineseTracks.isNotEmpty)
              _trackOptions(chineseTracks, selectedChinese),
          ],
        ),
      ),
    );
  }

  Widget _trackOptions(
    List<SubtitleTrack> tracks,
    SubtitleTrack? selectedTrack,
  ) {
    return RadioGroup<String>(
      groupValue: selectedTrack?.id,
      onChanged: (selectedId) {
        if (selectedId == null) return;
        for (final track in tracks) {
          if (track.id == selectedId) {
            widget.onSelect(track);
            return;
          }
        }
      },
      child: Column(
        children: [
          for (final track in tracks)
            RadioListTile<String>(
              value: track.id,
              title: Text(_isEnglish(track) ? '英文字幕軌' : '中文字幕軌'),
              subtitle: Text(
                track.selectionMode == SubtitleSelectionMode.manual
                    ? '手動指定'
                    : '自動配對',
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),
        ],
      ),
    );
  }

  List<_SubtitleSourceGroup> _groupTracks(List<SubtitleTrack> tracks) {
    final groups = <_SubtitleSourceGroup>[];
    for (final track in tracks) {
      final sourceName = _sourceName(track.sourceName);
      final index = groups.indexWhere(
        (group) =>
            group.sourceName == sourceName &&
            _sameBytes(group.tracks.first.originalBytes, track.originalBytes),
      );
      if (index < 0) {
        groups.add(_SubtitleSourceGroup(sourceName, [track]));
      } else {
        groups[index].tracks.add(track);
      }
    }
    return groups;
  }

  String _sourceName(String value) => value.replaceFirst(
    RegExp(r'\s+·\s+(?:EN|繁中)$', caseSensitive: false),
    '',
  );

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _isEnglish(SubtitleTrack track) =>
      track.languageTag.toLowerCase().startsWith('en');

  Widget _offsetControl(BuildContext context, SubtitleTrack track) {
    final value = _offsets[track.id] ?? track.offsetMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${track.languageTag} 偏移：$value ms'),
        Slider(
          min: -2000,
          max: 2000,
          divisions: 80,
          value: value.clamp(-2000, 2000).toDouble(),
          label: '$value ms',
          onChanged: (next) =>
              setState(() => _offsets[track.id] = next.round()),
          onChangeEnd: (next) =>
              unawaited(widget.onOffsetChanged(track, next.round())),
        ),
      ],
    );
  }

  SubtitleTrack? _selectedTrack(String language) {
    for (final track in widget.tracks) {
      if (track.isSelected &&
          track.languageTag.toLowerCase().startsWith(language)) {
        return track;
      }
    }
    return null;
  }
}

final class _SubtitleSourceGroup {
  _SubtitleSourceGroup(this.sourceName, List<SubtitleTrack> tracks)
    : tracks = List.of(tracks);

  final String sourceName;
  final List<SubtitleTrack> tracks;

  String get languageLabel {
    final english = tracks
        .where((track) => track.languageTag.toLowerCase().startsWith('en'))
        .toList();
    final chinese = tracks
        .where((track) => track.languageTag.toLowerCase().startsWith('zh'))
        .toList();
    if (english.isNotEmpty && chinese.isNotEmpty) {
      return _hasLanguageOnlyCue(english, han: false) &&
              _hasLanguageOnlyCue(chinese, han: true)
          ? '雙語來源'
          : '多語軌';
    }
    if (english.isNotEmpty) return '英文';
    if (chinese.isNotEmpty) return '中文';
    return '未辨識';
  }

  bool _hasLanguageOnlyCue(
    List<SubtitleTrack> candidates, {
    required bool han,
  }) {
    final expected = RegExp(han ? r'[\u3400-\u9FFF]' : r'[A-Za-z]');
    final other = RegExp(han ? r'[A-Za-z]' : r'[\u3400-\u9FFF]');
    return candidates.any(
      (track) => track.cues.any(
        (cue) => expected.hasMatch(cue.text) && !other.hasMatch(cue.text),
      ),
    );
  }
}
