import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/theme.dart';
import '../services/update_check.dart';

/// Top-of-app banner that surfaces a new desktop release when GitHub has
/// one. Mounted once at the root via main.dart's MaterialApp builder so
/// it survives navigation (otherwise it would flash in and out as routes
/// remount).
///
/// Behaviour:
///   - Polls UpdateCheck.check() once on first frame.
///   - Idle when no update / not on desktop / user already dismissed
///     this specific version → renders nothing, takes no layout space.
///   - When an update is found, slides a slim accent-tinted bar above
///     the route content with "Tải về" and "Đóng" actions.
class UpdateBanner extends StatefulWidget {
  final Widget child;
  const UpdateBanner({super.key, required this.child});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  UpdateInfo? _info;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    final info = await UpdateCheck.check();
    if (!mounted || info == null) return;
    setState(() => _info = info);
  }

  Future<void> _onDownload() async {
    final info = _info;
    if (info == null) return;
    final uri = Uri.parse(info.downloadUrl);
    // externalApplication makes the browser handle the .zip download
    // instead of trying to render it inside a webview surface, which
    // some platforms otherwise default to.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onDismiss() async {
    final info = _info;
    if (info != null) await UpdateCheck.dismiss(info.latestVersion);
    if (!mounted) return;
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final showBanner = info != null && !_hidden;

    return Column(
      children: [
        if (showBanner)
          Material(
            color: AppColors.accent,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Phiên bản ${info.latestVersion} đã có. Bấm Tải về để cập nhật.",
                        style: body(const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
                        )),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _onDownload,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text("Tải về", style: body(const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: "Đóng",
                      icon: const Icon(Icons.close, size: 18, color: Colors.white),
                      onPressed: _onDismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
