import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/auth.dart';
import '../services/friendly_error.dart' show askLogin, friendlyError;
import '../services/offline_store.dart';
import 'list_search.dart' show RoundIconButton;

// "Tải tất cả" (canvas NgheSi_TaiTatCa / NgheSi_DangTai / Playlist_TaiTatCa,
// 22/11): a round ⬇ next to 🔍. Tap → bottom sheet "Tải N bài …?" (songs
// already saved are skipped) → songs download one at a time; the button
// becomes a progress ring (tap = stop) and a snackbar says "Đang tải x/N".

/// One running "tải tất cả" of a list.
class BulkJob {
  final String title;
  final int total;
  int done = 0;
  int failed = 0;
  bool running = true;
  bool stop = false;
  String? error;
  BulkJob(this.title, this.total);
  double get progress => total == 0 ? 0 : (done + failed) / total;
}

/// Bulk downloads by list key ("person-songs-pham-tuyen", "playlist-12"), so
/// the ring survives leaving and reopening the page.
class BulkDownload extends ChangeNotifier {
  BulkDownload._();
  static final BulkDownload instance = BulkDownload._();
  final Map<String, BulkJob> _jobs = {};

  BulkJob? job(String key) => _jobs[key];
  bool isRunning(String key) => _jobs[key]?.running ?? false;

  void stop(String key) {
    _jobs[key]?.stop = true;
    notifyListeners();
  }

  /// Downloads [songs] one by one; resolves when done or stopped. Stops early
  /// when the server says the daily download quota is used up.
  Future<BulkJob> run(String key, String title, List<Map<String, dynamic>> songs, AuthProvider auth) async {
    final job = BulkJob(title, songs.length);
    _jobs[key] = job;
    notifyListeners();
    for (final s in songs) {
      if (job.stop) break;
      final err = await OfflineStore.instance.download(s, auth);
      if (err == null) {
        job.done++;
      } else {
        job.failed++;
        if (err.contains('quá nhiều')) {
          job.error = err;
          break;
        }
      }
      notifyListeners();
    }
    job.running = false;
    _jobs.remove(key);
    notifyListeners();
    return job;
  }
}

bool _playable(Map s) => (s['file']?['audio_url'] ?? s['audioUrl']) != null;

/// The round ⬇ / progress ring. [fetch] returns every song of the list (all
/// pages, as currently filtered) when the reader confirms.
class DownloadAllButton extends StatelessWidget {
  final String jobKey;
  /// "Phạm Tuyên", "playlist “Chiến thắng Điện Biên”".
  final String title;
  final int count;
  final Future<List<Map<String, dynamic>>> Function() fetch;
  const DownloadAllButton({super.key, required this.jobKey, required this.title, required this.count, required this.fetch});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BulkDownload.instance,
      builder: (context, _) {
        final job = BulkDownload.instance.job(jobKey);
        if (job != null && job.running) {
          return RoundIconButton(
            icon: Icons.stop_rounded,
            tooltip: 'Đang tải ${job.done + job.failed}/${job.total} bài, bấm để dừng',
            background: AppColors.accentSoft,
            onTap: () => BulkDownload.instance.stop(jobKey),
            child: Stack(alignment: Alignment.center, children: [
              Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: job.progress == 0 ? null : job.progress,
                    strokeWidth: 3,
                    color: AppColors.accentFg,
                    backgroundColor: AppColors.border,
                  ),
                ),
              ),
              Icon(Icons.stop_rounded, size: 18, color: AppColors.accentFg),
            ]),
          );
        }
        return RoundIconButton(
          icon: Icons.download_rounded,
          tooltip: count > 0 ? 'Tải tất cả $count bài về máy' : 'Tải tất cả về máy',
          color: AppColors.accentFg,
          onTap: count > 0 ? () => confirmDownloadAll(context, jobKey: jobKey, title: title, fetch: fetch) : null,
        );
      },
    );
  }
}

/// Bottom sheet "Tải N bài của …?" then the download run with snackbars.
Future<void> confirmDownloadAll(BuildContext context, {required String jobKey, required String title, required Future<List<Map<String, dynamic>>> Function() fetch}) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isAuthenticated) {
    askLogin(context);
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  await OfflineStore.instance.load();
  if (!context.mounted) return;
  final todo = await showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _ConfirmSheet(title: title, fetch: fetch),
  );
  if (todo == null || todo.isEmpty) return;
  void open() => router.push('/da-tai-ve');
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text('Đang tải ${todo.length} bài · $title'),
    duration: const Duration(seconds: 3),
    action: SnackBarAction(label: 'Xem', textColor: const Color(0xFFE0AEAC), onPressed: open),
  ));
  final job = await BulkDownload.instance.run(jobKey, title, todo, auth);
  final parts = <String>[
    if (job.stop) 'Đã dừng: tải được ${job.done}/${job.total} bài' else 'Đã tải xong ${job.done} bài',
    if (job.failed > 0 && job.error == null) '${job.failed} bài lỗi',
    if (job.error != null) job.error!,
  ];
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(parts.join(' · ')),
    duration: const Duration(seconds: 5),
    action: job.done > 0 ? SnackBarAction(label: 'Mở Đã tải về', textColor: const Color(0xFFE0AEAC), onPressed: open) : null,
  ));
}

class _ConfirmSheet extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() fetch;
  const _ConfirmSheet({required this.title, required this.fetch});

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late Future<List<Map<String, dynamic>>> _songs = widget.fetch();

  @override
  Widget build(BuildContext context) {
    final muted = body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _songs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return SizedBox(
                height: 160,
                child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accentFg)),
                  const SizedBox(width: 12),
                  Text('Đang đếm bài…', style: muted),
                ])),
              );
            }
            if (snap.hasError) {
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 8),
                Text(friendlyError(snap.error!, fallback: 'Chưa lấy được danh sách bài'), style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
                const SizedBox(height: 16),
                _buttons(context, primary: 'Thử lại', onPrimary: () => setState(() => _songs = widget.fetch())),
              ]);
            }
            final store = OfflineStore.instance;
            final all = snap.data!.where(_playable).toList();
            final saved = all.where(store.isSaved).length;
            final todo = all.where((s) => !store.isSaved(s)).toList();
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                  child: Icon(Icons.download_rounded, size: 24, color: AppColors.accentFg),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(todo.isEmpty ? 'Đã tải hết rồi' : 'Tải ${todo.length} bài của ${widget.title}?', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 2),
                  Text(todo.isEmpty ? 'Cả ${all.length} bài đã có trong Đã tải về' : 'Nghe được khi không có mạng', style: muted),
                ])),
              ]),
              if (todo.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      [
                        if (saved > 0) 'Đã tải $saved bài từ trước — sẽ bỏ qua.',
                        'Bài tải lần lượt, bấm vòng tiến độ để dừng. Nên dùng Wi‑Fi.',
                      ].join(' '),
                      style: body(TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    )),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              todo.isEmpty
                  ? _buttons(context, primary: 'Mở Đã tải về', onPrimary: () {
                      Navigator.pop(context);
                      GoRouter.of(context).push('/da-tai-ve');
                    })
                  : _buttons(context, primary: 'Tải ${todo.length} bài', icon: Icons.download_rounded, onPrimary: () => Navigator.pop(context, todo)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context, {required String primary, IconData? icon, required VoidCallback onPrimary}) {
    return Row(children: [
      Expanded(
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.text, minimumSize: const Size(48, 50), shape: const StadiumBorder()),
          child: Text('Huỷ', style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 3,
        child: TextButton.icon(
          onPressed: onPrimary,
          style: TextButton.styleFrom(backgroundColor: AppColors.wine, foregroundColor: Colors.white, minimumSize: const Size(48, 50), shape: const StadiumBorder()),
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
          label: Text(primary, style: body(const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        ),
      ),
    ]);
  }
}
