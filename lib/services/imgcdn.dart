import 'dart:convert';

// Resized WebP images through imgcdn.bcdcnt.net (self-hosted imgproxy), the
// same helper the website uses (bcdcnt-web/packages/core/imgcdn.js) — keep
// the two in sync so app and web share Cloudflare cache entries.
//
// cdnImg(url, 160) → image fit inside 160px, WebP. Only archive images on
// img.bcdcnt.net (or the same Vultr bucket) are rewritten; anything else is
// returned untouched. Full-screen viewers (sheet music, photo zoom) keep
// the original file.

const _imgcdn = 'https://imgcdn.bcdcnt.net';
const _src = 'https://img.bcdcnt.net/';
const _vultr = 'https://sgp1.vultrobjects.com/img-bcdcnt-net/';

/// Fixed widths so each image only has a few cached variants (same list as web).
const _buckets = [48, 96, 160, 240, 320, 480, 640, 960, 1280];

int _bucket(num w) {
  final n = w.round();
  for (final b in _buckets) {
    if (n <= b) return b;
  }
  return _buckets.last;
}

/// [width] is the size to fetch in *pixels*; pass logical size × ~2.5 for a
/// crisp image on phone screens (see [cdnImgFor]).
String cdnImg(String url, num width, {num height = 0}) {
  if (url.isEmpty || url.startsWith(_imgcdn)) return url;
  final src = url.startsWith(_vultr) ? _src + url.substring(_vultr.length) : url;
  if (!src.startsWith(_src)) return url;
  final w = _bucket(width);
  final h = height > 0 ? _bucket(height) : 0;
  final b64 = base64Url.encode(utf8.encode(src)).replaceAll('=', '');
  return '$_imgcdn/insecure/rs:fit:$w:$h/$b64.webp';
}

/// cdnImg for an image drawn [logicalWidth] points wide (retina-ready).
String cdnImgFor(String url, num logicalWidth) => cdnImg(url, logicalWidth * 2.5);
