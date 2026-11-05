import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/image_upload.dart';
import 'ui.dart' show UserAvatar;

// CTV tools on a song's detail page — the same menu as the web
// (bcdcnt-web components/shared/SongAdminActions.jsx): same actions, same
// permissions, same mutations. Each item shows only to members holding the
// matching permission, so regular listeners never see the button.

const _artistPerms = {'song': 'manage_song', 'folk': 'manage_folk', 'instrumental': 'manage_instrumental', 'poem': 'manage_poem'};
const _typePerms = {'song': 'manage_song', 'folk': 'manage_folk', 'instrumental': 'manage_instrumental', 'poem': 'manage_poem', 'karaoke': 'manage_karaoke'};
const _updateMutation = {'song': 'updateSong', 'folk': 'updateFolk', 'instrumental': 'updateInstrumental', 'poem': 'updatePoem', 'karaoke': 'updateKaraoke'};
const _crudType = {'song': 'Song', 'folk': 'Folk', 'instrumental': 'Instrumental', 'poem': 'Poem', 'karaoke': 'Karaoke'};
const _adminPath = {'song': 'bai-hat', 'folk': 'dan-ca', 'instrumental': 'khi-nhac', 'poem': 'tieng-tho', 'karaoke': 'thanh-vien-hat'};
const _lyricTypes = ['', 'Thơ', 'Lời', 'Lời: phỏng thơ', 'Lời Việt'];
const _subtitlePresets = ['(bản 1)', '(bản 2)', '(bản 3)', '(bản 4)'];

/// Any CTV permission that unlocks at least one item.
bool canUseSongAdmin(AuthProvider auth) => const [
      'manage_sheet', 'update_lyric', 'update_thumbnail', 'manage_thumbnail', 'manage_song', 'mark_hq',
      'manage_folk', 'manage_instrumental', 'manage_poem', 'manage_karaoke', 'use_admin_tool',
    ].any(auth.hasPermission);

class _Action {
  final String key, label;
  final IconData icon;
  final bool danger, toggle, on;
  const _Action(this.key, this.label, this.icon, {this.danger = false, this.toggle = false, this.on = false});
}

/// The CTV menu. [song] is the detail page's normalized map; [onRefresh]
/// reloads the page after a change.
Future<void> showSongAdminSheet(BuildContext context, {required Map<String, dynamic> song, required String type, required Future<void> Function() onRefresh}) async {
  final auth = context.read<AuthProvider>();
  bool can(String? p) => p != null && auth.hasPermission(p);
  final id = '${song['id']}';
  // Folk / poem pages have no sheet on the web either (tags, year, composers live elsewhere).
  final sheetId = (type == 'folk' || type == 'poem') ? null : song['sheet']?['id']?.toString();
  final fileId = song['file']?['id']?.toString();
  final thumb = song['thumbnail'] is Map ? song['thumbnail'] as Map : null;
  final isHq = song['file']?['is_hq'] == 1 || song['file']?['is_hq'] == true;

  int sticky = 0;
  if (type == 'song' && can('manage_song')) {
    try {
      final d = await auth.authedQuery(r'query($id: ID!) { song(id: $id) { id sticky_comment } }', {'id': id});
      sticky = (d['song']?['sticky_comment'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  final actions = <_Action>[
    // API updateThumbnail needs update_thumbnail; replacing an existing picture is for manage_thumbnail.
    if (can('update_thumbnail') && (can('manage_thumbnail') || thumb?['url'] == null)) const _Action('thumb', 'Ảnh minh hoạ', Icons.image_outlined),
    if (type != 'karaoke' && can(_artistPerms[type])) const _Action('artists', 'Sửa trình bày', Icons.mic_none_rounded),
    if (sheetId != null && can('manage_sheet')) ...const [
      _Action('tag', 'Sửa tag', Icons.tag_rounded),
      _Action('year', 'Sửa năm sáng tác', Icons.calendar_today_outlined),
      _Action('composers', 'Sửa sáng tác', Icons.music_note_outlined),
      _Action('poets', 'Sửa nhà thơ', Icons.menu_book_outlined),
    ],
    if (type == 'folk' && can('manage_folk')) ...const [
      _Action('recomposers', 'Sửa soạn giả', Icons.music_note_outlined),
      _Action('melodyFcat', 'Sửa làn điệu – thể loại', Icons.queue_music_rounded),
    ],
    if (can(_typePerms[type])) const _Action('accompanists', 'Sửa đệm nhạc', Icons.piano_outlined),
    if (can('update_thumbnail') && thumb?['id'] != null) const _Action('caption', 'Chú thích ảnh', Icons.short_text_rounded),
    if (sheetId != null && can('manage_sheet')) ...const [
      _Action('editSheet', 'Sửa bản nhạc', Icons.open_in_new_rounded),
      _Action('addRevision', 'Thêm bản nhạc', Icons.add_rounded),
    ],
    if (can(_typePerms[type])) const _Action('subtitle', 'Chú thích bản thu', Icons.edit_outlined),
    if (fileId != null && can('manage_song')) const _Action('source', 'Nguồn bản thu', Icons.album_outlined),
    if (fileId != null && can('mark_hq')) _Action('vov', 'VOV-HQ', Icons.star_outline_rounded, toggle: true, on: isHq),
    if (type == 'song' && can('manage_song')) _Action('sticky', 'Ghim BL nổi bật', Icons.push_pin_outlined, toggle: true, on: sticky == 1),
    // API duplicateSong / emptyFile check use_admin_tool (not manage_song).
    if (can('use_admin_tool')) ...const [
      _Action('duplicate', 'Nhân bản bài hát', Icons.copy_rounded),
      _Action('emptyFile', 'Xoá ruột file nhạc', Icons.delete_outline_rounded, danger: true),
    ],
    if (can(_typePerms[type])) const _Action('edit', 'Sửa trên web', Icons.open_in_new_rounded),
  ];
  if (actions.isEmpty || !context.mounted) return;

  final picked = await showModalBottomSheet<_Action>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Công cụ CTV', style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
          ),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? AppColors.error : AppColors.textSecondary),
              title: Text(a.label, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: a.danger ? AppColors.error : AppColors.text))),
              trailing: a.toggle ? Switch(value: a.on, onChanged: (_) => Navigator.pop(ctx, a), activeColor: AppColors.accent) : null,
              onTap: () => Navigator.pop(ctx, a),
            ),
        ]),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;

  final ctl = _Ctl(context, auth, onRefresh);
  // New names go through addPeopleToSong (approve_topic); new tags through createTags (manage_tag).
  final canCreatePeople = can('approve_topic');
  switch (picked.key) {
    case 'thumb':
      await ctl.run(() async {
        final files = await pickImages();
        if (files.isEmpty) return null;
        ctl.toast('Đang tải ảnh lên…');
        final img = await uploadImage(auth, files.first, context: 'image');
        await auth.authedMutate(r'mutation($id: ID!, $type: String!, $image_id: ID!) { updateThumbnail(id: $id, type: $type, image_id: $image_id) { id } }',
            {'id': id, 'type': type, 'image_id': img.id});
        return 'Đã đổi ảnh minh hoạ';
      });
    case 'artists':
      await _editPeople(ctl,
          title: 'Sửa nghệ sĩ trình bày',
          search: 'artists',
          allowCreate: canCreatePeople,
          load: () async => _people((await auth.authedQuery('query(\$id: ID!) { $type(id: \$id) { artists(first: 100) { data { id title avatar { url } } } } }', {'id': id}))[type]?['artists']),
          save: (list) async {
            final resolved = await _createNew(auth, list, songId: id, songType: type, peopleType: 'artist', search: 'artists');
            await auth.authedMutate('mutation(\$id: ID!, \$v: CRUD${_crudType[type]}Artists) { ${_updateMutation[type]}(input: { id: \$id, artists: \$v }) { id } }',
                {'id': id, 'v': _sync(resolved)});
          });
    case 'composers':
      await _editPeople(ctl,
          title: 'Sửa nhạc sĩ',
          search: 'composers',
          allowCreate: canCreatePeople,
          load: () async => _people((await auth.authedQuery(r'query($id: ID!) { sheet(id: $id) { composers(first: 50) { data { id title avatar { url } } } } }', {'id': sheetId}))['sheet']?['composers']),
          save: (list) async {
            final resolved = await _createNew(auth, list, songId: id, songType: type, peopleType: 'composer', search: 'composers');
            await auth.authedMutate(r'mutation($id: ID!, $v: CRUDSheetComposers) { updateSheet(input: { id: $id, composers: $v }) { id } }', {'id': sheetId, 'v': _sync(resolved)});
          });
    case 'recomposers':
      await _editPeople(ctl,
          title: 'Sửa soạn giả',
          search: 'recomposers',
          allowCreate: canCreatePeople,
          load: () async => _people((await auth.authedQuery(r'query($id: ID!) { folk(id: $id) { recomposers(first: 50) { data { id title avatar { url } } } } }', {'id': id}))['folk']?['recomposers']),
          save: (list) async {
            final resolved = await _createNew(auth, list, songId: id, songType: type, peopleType: 'recomposer', search: 'recomposers');
            await auth.authedMutate(r'mutation($id: ID!, $v: CRUDFolkRecomposers) { updateFolk(input: { id: $id, recomposers: $v }) { id } }', {'id': id, 'v': _sync(resolved)});
          });
    case 'poets':
      String lyricType = '';
      await _editPeople(ctl,
          title: 'Sửa nhà thơ',
          search: 'poets',
          allowCreate: canCreatePeople,
          load: () async {
            final d = (await auth.authedQuery(r'query($id: ID!) { sheet(id: $id) { lyric_type poets(first: 50) { data { id title avatar { url } } } } }', {'id': sheetId}))['sheet'];
            lyricType = (d?['lyric_type'] ?? '').toString().trim();
            return _people(d?['poets']);
          },
          header: (setState) => _Dropdown(
                label: 'Kiểu hiển thị',
                value: _lyricTypes.contains(lyricType) ? lyricType : '',
                items: _lyricTypes,
                onChanged: (v) => setState(() => lyricType = v),
              ),
          save: (list) async {
            final resolved = await _createNew(auth, list, songId: id, songType: type, peopleType: 'poet', search: 'poets');
            await auth.authedMutate(r'mutation($id: ID!, $lt: String, $v: CRUDSheetPoets) { updateSheet(input: { id: $id, lyric_type: $lt, poets: $v }) { id } }',
                {'id': sheetId, 'lt': lyricType, 'v': _sync(resolved)});
          });
    case 'accompanists':
      final instrument = TextEditingController();
      await _editPeople(ctl,
          title: 'Sửa người đệm nhạc',
          search: 'artists',
          allowCreate: false,
          load: () async {
            final d = (await auth.authedQuery('query(\$id: ID!) { $type(id: \$id) { accompaniment_instrument accompanists(first: 50) { data { id title avatar { url } } } } }', {'id': id}))[type];
            instrument.text = (d?['accompaniment_instrument'] ?? '').toString();
            return _people(d?['accompanists']);
          },
          header: (_) => _Field(label: 'Nhạc cụ đệm', controller: instrument, hint: 'VD: piano, guitar, đàn bầu…'),
          save: (list) async {
            await auth.authedMutate('mutation(\$id: ID!, \$v: CRUD${_crudType[type]}Accompanists, \$i: String) { ${_updateMutation[type]}(input: { id: \$id, accompaniment_instrument: \$i, accompanists: \$v }) { id } }',
                {'id': id, 'i': instrument.text.trim().isEmpty ? null : instrument.text.trim(), 'v': _sync(list)});
          });
    case 'tag':
      await _editTags(ctl, sheetId!);
    case 'melodyFcat':
      await _editMelodyFcat(ctl, id);
    case 'year':
      await _editText(ctl, title: 'Sửa năm sáng tác', label: 'Năm sáng tác', initial: '${song['sheet']?['year'] ?? ''}', keyboard: TextInputType.number,
          save: (v) => auth.authedMutate(r'mutation($id: ID!, $year: String) { updateSongYear(sheet_id: $id, year: $year) { id } }', {'id': sheetId, 'year': v.isEmpty ? null : v}));
    case 'caption':
      await _editText(ctl, title: 'Chú thích ảnh minh hoạ', label: 'Hiện khi phóng to ảnh', initial: '${thumb?['caption'] ?? ''}', lines: 3, image: thumb?['url']?.toString(),
          save: (v) => auth.authedMutate(r'mutation($image_id: ID!, $type: String!, $id: ID!, $caption: String) { updateImageCaption(image_id: $image_id, type: $type, id: $id, caption: $caption) { id } }',
              {'image_id': '${thumb!['id']}', 'type': type, 'id': id, 'caption': v.isEmpty ? null : v}));
    case 'subtitle':
      await _editText(ctl, title: 'Chú thích bản thu', label: 'Hiện cạnh tên bài, để phân biệt các bản thu cùng tên', initial: '${song['subtitle'] ?? ''}', presets: _subtitlePresets,
          save: (v) => auth.authedMutate(
              'mutation(\$input: Update${_crudType[type]}Input!) { ${_updateMutation[type]}(input: \$input) { id subtitle } }', {'input': {'id': id, 'subtitle': v.isEmpty ? null : v}}));
    case 'source':
      await _editText(ctl, title: 'Nguồn bản thu', label: 'Nguồn / người sưu tầm (tri ân)', initial: '${song['file']?['source'] ?? ''}', lines: 3,
          save: (v) => auth.authedMutate(r'mutation($file_id: ID!, $source: String) { updateFileSource(file_id: $file_id, source: $source) { id } }', {'file_id': fileId, 'source': v.isEmpty ? null : v}));
    case 'addRevision':
      await _addRevision(ctl, sheetId!);
    case 'vov':
      await ctl.run(() async {
        await auth.authedMutate(isHq ? r'mutation($f: ID!) { unmarkHQ(file_id: $f) { id } }' : r'mutation($f: ID!) { markAsHQ(file_id: $f) { id } }', {'f': fileId});
        return isHq ? 'Đã bỏ VOV-HQ' : 'Đã đánh dấu VOV-HQ';
      });
    case 'sticky':
      await ctl.run(() async {
        final next = sticky == 1 ? 0 : 1;
        await auth.authedMutate(r'mutation($id: ID!, $v: Int) { updateSong(input: { id: $id, sticky_comment: $v }) { id } }', {'id': id, 'v': next});
        return next == 1 ? 'Đã ghim bình luận nổi bật' : 'Đã bỏ ghim bình luận';
      });
    case 'duplicate':
      if (await _confirm(context, 'Nhân bản bài hát', 'Tạo một bản sao của bài này?', 'Nhân bản')) {
        await ctl.run(() async {
          await auth.authedMutate(r'mutation($id: ID!, $type: String!) { duplicateSong(id: $id, type: $type) { id } }', {'id': id, 'type': type});
          return 'Đã nhân bản';
        });
      }
    case 'emptyFile':
      if (await _confirm(context, 'Xoá ruột file nhạc', 'Xoá nội dung file nhạc của bài này? Không thể hoàn tác.', 'Xoá', danger: true)) {
        await ctl.run(() async {
          await auth.authedMutate(r'mutation($id: ID!, $type: String!) { emptyFile(id: $id, type: $type) { id } }', {'id': id, 'type': type});
          return 'Đã xoá ruột file nhạc';
        });
      }
    case 'editSheet':
      await launchUrl(Uri.parse('$siteUrl/admin/sheet/$sheetId'), mode: LaunchMode.externalApplication);
    case 'edit':
      await launchUrl(Uri.parse('$siteUrl/admin/${_adminPath[type]}/$id'), mode: LaunchMode.externalApplication);
  }
}

/// Runs an edit, reports the result and reloads the page.
class _Ctl {
  final BuildContext context;
  final AuthProvider auth;
  final Future<void> Function() refresh;
  _Ctl(this.context, this.auth, this.refresh);

  void toast(String msg, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null));
  }

  /// [job] returns the success message, or null when the user backed out.
  Future<void> run(Future<String?> Function() job) async {
    try {
      final msg = await job();
      if (msg == null) return;
      toast(msg);
      await refresh();
    } catch (e) {
      toast('Lỗi: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    }
  }
}

List<Map<String, dynamic>> _people(dynamic v) =>
    ((v is Map ? v['data'] : v) as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

Map<String, dynamic> _sync(List<Map<String, dynamic>> list) => {
      'sync': [for (var i = 0; i < list.length; i++) {'id': '${list[i]['id']}', 'order': i + 1}],
    };

/// New names (typed, not picked) are created through addPeopleToSong, then
/// looked up to get their id — the same two steps as the web.
Future<List<Map<String, dynamic>>> _createNew(AuthProvider auth, List<Map<String, dynamic>> list,
    {required String songId, required String songType, required String peopleType, required String search}) async {
  final out = <Map<String, dynamic>>[];
  for (final p in list) {
    if (!'${p['id']}'.startsWith('new-')) {
      out.add(p);
      continue;
    }
    await auth.authedMutate(r'mutation($s: ID!, $t: String!, $n: String!, $pt: String!) { addPeopleToSong(song_id: $s, song_type: $t, people_title: $n, people_type: $pt) { __typename } }',
        {'s': songId, 't': songType, 'n': p['title'], 'pt': peopleType});
    final d = await auth.authedQuery('query(\$q: Mixed) { $search(first: 1, where: {AND: [{column: "title", value: \$q}]}) { data { id title } } }', {'q': p['title']});
    final found = _people(d[search]).firstOrNull;
    if (found != null) out.add(found);
  }
  return out;
}

// ── Sheets ───────────────────────────────────────────────────────────

Future<T?> _sheet<T>(BuildContext context, String title, Widget Function(BuildContext, StateSetter) build) => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: display(TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 14),
                  build(ctx, setState),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

Widget _saveRow(BuildContext ctx, {required bool busy, required VoidCallback? onSave, String label = 'Lưu'}) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
            child: Text('Huỷ', style: body(TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onSave,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 13), shape: const StadiumBorder()),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(label, style: body(const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
          ),
        ),
      ]),
    );

Future<void> _editText(_Ctl ctl,
    {required String title, required String label, required String initial, required Future<dynamic> Function(String) save,
    int lines = 1, TextInputType? keyboard, List<String> presets = const [], String? image}) async {
  final c = TextEditingController(text: initial == 'null' ? '' : initial);
  var busy = false;
  final ok = await _sheet<bool>(ctl.context, title, (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (image != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(image, height: 160, fit: BoxFit.cover)),
          ),
        _Field(label: label, controller: c, lines: lines, keyboard: keyboard, autofocus: true),
        if (presets.isNotEmpty)
          Wrap(spacing: 8, children: [for (final p in presets) ActionChip(label: Text(p), onPressed: () => c.text = p)]),
        _saveRow(ctx, busy: busy, onSave: () async {
          setState(() => busy = true);
          try {
            await save(c.text.trim());
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setState(() => busy = false);
            ctl.toast('Lỗi: $e', error: true);
          }
        }),
      ]));
  if (ok == true) {
    ctl.toast('Đã lưu');
    await ctl.refresh();
  }
}

Future<void> _editPeople(_Ctl ctl,
    {required String title,
    required String search,
    required Future<List<Map<String, dynamic>>> Function() load,
    required Future<void> Function(List<Map<String, dynamic>>) save,
    Widget Function(StateSetter)? header,
    bool allowCreate = true}) async {
  List<Map<String, dynamic>> list;
  try {
    list = await load();
  } catch (e) {
    ctl.toast('Không tải được dữ liệu: $e', error: true);
    return;
  }
  var busy = false;
  final ok = await _sheet<bool>(ctl.context, title, (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null) header(setState),
        PeopleField(
          items: list,
          search: search,
          allowCreate: allowCreate,
          onChanged: (v) => setState(() => list = v),
        ),
        _saveRow(ctx, busy: busy, onSave: () async {
          setState(() => busy = true);
          try {
            await save(list);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setState(() => busy = false);
            ctl.toast('Lỗi: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
          }
        }),
      ]));
  if (ok == true) {
    ctl.toast('Đã lưu');
    await ctl.refresh();
  }
}

Future<void> _editTags(_Ctl ctl, String sheetId) async {
  final canCreate = ctl.auth.hasPermission('manage_tag');
  List<Map<String, dynamic>> tags;
  try {
    final d = await ctl.auth.authedQuery(r'query($id: ID!) { sheet(id: $id) { tags { id name } } }', {'id': sheetId});
    tags = ((d['sheet']?['tags'] as List?) ?? const []).map((t) => {'id': t['id'], 'title': t['name']}).toList();
  } catch (e) {
    ctl.toast('Không tải được tag: $e', error: true);
    return;
  }
  var busy = false;
  final ok = await _sheet<bool>(ctl.context, 'Sửa tag', (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PeopleField(
          items: tags,
          search: 'tags',
          allowCreate: canCreate,
          prefix: '#',
          onCreate: (name) async {
            final d = await ctl.auth.authedMutate(r'mutation($t: String!) { createTags(tags: $t) { id name } }', {'t': name});
            return ((d['createTags'] as List?) ?? const []).map((t) => <String, dynamic>{'id': t['id'], 'title': t['name']}).toList();
          },
          onChanged: (v) => setState(() => tags = v),
        ),
        _saveRow(ctx, busy: busy, onSave: () async {
          setState(() => busy = true);
          try {
            await ctl.auth.authedMutate(r'mutation($id: ID!, $ids: [ID]) { updateSheetTag(sheet_id: $id, tag_ids: $ids) { id } }',
                {'id': sheetId, 'ids': tags.map((t) => '${t['id']}').toList()});
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setState(() => busy = false);
            ctl.toast('Lỗi: $e', error: true);
          }
        }),
      ]));
  if (ok == true) {
    ctl.toast('Đã lưu tag');
    await ctl.refresh();
  }
}

Future<void> _editMelodyFcat(_Ctl ctl, String folkId) async {
  List<Map<String, dynamic>> fcats, melodies;
  try {
    final d = (await ctl.auth.authedQuery(r'query($id: ID!) { folk(id: $id) { fcats(first: 50) { data { id title } } melodies(first: 50) { data { id title } } } }', {'id': folkId}))['folk'];
    fcats = _people(d?['fcats']);
    melodies = _people(d?['melodies']);
  } catch (e) {
    ctl.toast('Không tải được dữ liệu: $e', error: true);
    return;
  }
  var busy = false;
  final ok = await _sheet<bool>(ctl.context, 'Sửa làn điệu – thể loại', (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Thể loại dân ca', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
        const SizedBox(height: 6),
        PeopleField(items: fcats, search: 'fcats', allowCreate: false, onChanged: (v) => setState(() => fcats = v)),
        const SizedBox(height: 16),
        Text('Làn điệu', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
        const SizedBox(height: 6),
        PeopleField(
          items: melodies,
          search: 'melodies',
          // Only melodies of the chosen genres, like the web.
          filterFcatIds: fcats.map((f) => '${f['id']}').toList(),
          allowCreate: true,
          onCreate: (name) async {
            final fcatId = fcats.isEmpty ? null : int.tryParse('${fcats.first['id']}');
            final d = await ctl.auth.authedMutate(r'mutation($t: String!, $f: Int) { createMelody(input: { title: $t, fcat_id: $f }) { id title } }', {'t': name, 'f': fcatId});
            final m = d['createMelody'];
            return m == null ? <Map<String, dynamic>>[] : [Map<String, dynamic>.from(m)];
          },
          onChanged: (v) => setState(() => melodies = v),
        ),
        _saveRow(ctx, busy: busy, onSave: () async {
          setState(() => busy = true);
          try {
            await ctl.auth.authedMutate(
                r'mutation($id: ID!, $f: [SyncFolkFcat], $m: [SyncFolkMelody]) { updateFolk(input: { id: $id, fcats: { sync: $f }, melodies: { sync: $m } }) { id } }', {
              'id': folkId,
              'f': fcats.map((f) => {'id': '${f['id']}'}).toList(),
              'm': melodies.map((m) => {'id': '${m['id']}'}).toList(),
            });
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setState(() => busy = false);
            ctl.toast('Lỗi: $e', error: true);
          }
        }),
      ]));
  if (ok == true) {
    ctl.toast('Đã lưu');
    await ctl.refresh();
  }
}

/// "Thêm bản nhạc": pick the score images, upload, then createSheetRevision
/// with them as <img> paragraphs (what the web editor produces).
Future<void> _addRevision(_Ctl ctl, String sheetId) async {
  final title = TextEditingController();
  final images = <UploadedImage>[];
  var busy = false;
  String? status;
  final ok = await _sheet<bool>(ctl.context, 'Thêm bản nhạc', (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Field(label: 'Tiêu đề (tuỳ chọn)', controller: title),
        Text('Ảnh các trang bản nhạc', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final img in images)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.url == null ? const SizedBox(width: 72, height: 96) : Image.network(img.url!, width: 72, height: 96, fit: BoxFit.cover),
            ),
          InkWell(
            onTap: busy
                ? null
                : () async {
                    final files = await pickImages(multiple: true);
                    if (files.isEmpty) return;
                    setState(() => busy = true);
                    try {
                      for (var i = 0; i < files.length; i++) {
                        setState(() => status = 'Đang tải ảnh ${i + 1}/${files.length}…');
                        images.add(await uploadImage(ctl.auth, files[i], context: 'sheet'));
                      }
                      status = null;
                    } catch (e) {
                      status = 'Lỗi tải ảnh: $e';
                    }
                    setState(() => busy = false);
                  },
            child: Container(
              width: 72,
              height: 96,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
              child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary),
            ),
          ),
        ]),
        if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status!, style: body(TextStyle(fontSize: 13, color: AppColors.textMuted)))),
        _saveRow(ctx, busy: busy, label: 'Tạo', onSave: images.isEmpty
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final content = images.where((i) => i.url != null).map((i) => '<p><img src="${i.url}"></p>').join();
                  await ctl.auth.authedMutate(r'mutation($t: String, $c: String, $s: ID!) { createSheetRevision(input: { title: $t, content: $c, sheet_id: $s }) { id } }',
                      {'t': title.text.trim().isEmpty ? null : title.text.trim(), 'c': content, 's': sheetId});
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setState(() => busy = false);
                  ctl.toast('Lỗi: $e', error: true);
                }
              }),
      ]));
  if (ok == true) {
    ctl.toast('Đã thêm bản nhạc');
    await ctl.refresh();
  }
}

Future<bool> _confirm(BuildContext context, String title, String message, String action, {bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: TextStyle(color: danger ? AppColors.error : AppColors.accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ) ==
    true;

// ── Form pieces ──────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int lines;
  final TextInputType? keyboard;
  final bool autofocus;
  const _Field({required this.label, required this.controller, this.hint, this.lines = 1, this.keyboard, this.autofocus = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            autofocus: autofocus,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 3,
            keyboardType: keyboard,
            style: body(TextStyle(fontSize: 16, color: AppColors.text)),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            ),
          ),
        ]),
      );
}

class _Dropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Text('$label: ', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          DropdownButton<String>(
            value: value,
            items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i.isEmpty ? '— Chọn —' : i))],
            onChanged: (v) => onChanged(v ?? ''),
          ),
        ]),
      );
}

/// Chips of the chosen people (tap ✕ to remove, ↑ to move earlier) plus a
/// search box. Typing a name that isn't found offers "Thêm mới".
/// [search] is the GraphQL list to search: artists / composers / poets /
/// recomposers / tags / fcats / melodies.
class PeopleField extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String search;
  final bool allowCreate;
  final String prefix;
  final List<String>? filterFcatIds;
  final Future<List<Map<String, dynamic>>> Function(String name)? onCreate;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  const PeopleField({required this.items, required this.search, required this.onChanged, this.allowCreate = true, this.prefix = '', this.filterFcatIds, this.onCreate});

  @override
  State<PeopleField> createState() => PeopleFieldState();
}

class PeopleFieldState extends State<PeopleField> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  bool get _isTag => widget.search == 'tags';
  String _name(Map m) => '${m['title'] ?? m['name'] ?? ''}';

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    setState(() => _searching = true);
    final col = _isTag ? 'name' : 'title';
    final fields = _isTag ? 'id name' : (const ['artists', 'composers', 'poets', 'recomposers'].contains(widget.search) ? 'id title avatar { url }' : 'id title');
    final order = const ['artists', 'composers', 'poets', 'recomposers'].contains(widget.search) ? 'orderBy: [{column: "views", order: DESC}], ' : '';
    final fc = widget.filterFcatIds;
    final extra = (widget.search == 'melodies' && fc != null && fc.isNotEmpty) ? ', {column: "fcat_id", operator: IN, value: \$ids}' : '';
    // People: prefix match (like the web); tags / genres / melodies: anywhere.
    final like = (_isTag || widget.search == 'fcats' || widget.search == 'melodies') ? '%$q%' : '$q%';
    try {
      final d = await ApiClient.query(
        'query(\$q: Mixed${extra.isEmpty ? '' : ', \$ids: Mixed'}) { ${widget.search}(first: 15, $order where: {AND: [{column: "$col", operator: LIKE, value: \$q}$extra]}) { data { $fields } } }',
        {'q': like, if (extra.isNotEmpty) 'ids': fc!.map(int.tryParse).whereType<int>().toList()},
      );
      final chosen = widget.items.map((e) => '${e['id']}').toSet();
      final list = _people(d[widget.search]).where((m) => !chosen.contains('${m['id']}')).map((m) => {...m, if (_isTag) 'title': m['name']}).toList();
      if (mounted && _q.text.trim() == q) setState(() => _results = list);
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _add(Map<String, dynamic> m) {
    widget.onChanged([...widget.items, m]);
    _q.clear();
    setState(() => _results = []);
  }

  Future<void> _create() async {
    final name = _q.text.trim();
    if (name.isEmpty) return;
    if (widget.onCreate != null) {
      try {
        final created = await widget.onCreate!(name);
        final have = widget.items.map((e) => '${e['id']}').toSet();
        widget.onChanged([...widget.items, ...created.where((c) => !have.contains('${c['id']}'))]);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được: $e')));
      }
    } else {
      // Created for real on Lưu (addPeopleToSong), like the web.
      widget.onChanged([...widget.items, {'id': 'new-${DateTime.now().microsecondsSinceEpoch}', 'title': name}]);
    }
    _q.clear();
    setState(() => _results = []);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final q = _q.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (items.isEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Chưa có ai', style: body(TextStyle(fontSize: 13, color: AppColors.textMuted))))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < items.length; i++)
            InputChip(
              avatar: items[i]['avatar']?['url'] != null ? UserAvatar(url: items[i]['avatar']['url'], name: _name(items[i]), size: 24) : null,
              label: Text('${widget.prefix}${_name(items[i])}${'${items[i]['id']}'.startsWith('new-') ? ' (mới)' : ''}'),
              onDeleted: () => widget.onChanged([...items]..removeAt(i)),
              // Tap to move one place earlier (order = order shown on the page).
              onPressed: i == 0
                  ? null
                  : () {
                      final l = [...items];
                      final m = l.removeAt(i);
                      l.insert(i - 1, m);
                      widget.onChanged(l);
                    },
            ),
        ]),
      if (items.length > 1)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('Chạm vào tên để đưa lên trước', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted)))),
      const SizedBox(height: 10),
      TextField(
        controller: _q,
        onChanged: (v) {
          setState(() {});
          _onQuery(v);
        },
        onSubmitted: (_) => _results.isEmpty && widget.allowCreate ? _create() : null,
        style: body(TextStyle(fontSize: 16, color: AppColors.text)),
        decoration: InputDecoration(
          hintText: widget.allowCreate ? 'Tìm… (không có thì thêm mới)' : 'Tìm…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        ),
      ),
      for (final r in _results)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: r['avatar'] != null || const ['artists', 'composers', 'poets', 'recomposers'].contains(widget.search)
              ? UserAvatar(url: r['avatar']?['url']?.toString(), name: _name(r), size: 32)
              : null,
          title: Text('${widget.prefix}${_name(r)}', style: body(TextStyle(fontSize: 15, color: AppColors.text))),
          onTap: () => _add(r),
        ),
      if (widget.allowCreate && q.isNotEmpty && !_searching && !_results.any((r) => _name(r).toLowerCase() == q.toLowerCase()))
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.add_circle_outline_rounded, color: AppColors.accent),
          title: Text('Thêm mới "$q"', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accent))),
          onTap: _create,
        ),
    ]);
  }
}
