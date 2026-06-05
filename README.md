# BCĐCNT — Bài ca đi cùng năm tháng

Ứng dụng nghe nhạc **chính thức** của **[bcdcnt.net](https://bcdcnt.net)** — viết bằng **Flutter** (iOS · Android · macOS · Windows · Web).

## 📸 Giao diện

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/01-home.png" alt="Trang chủ"/><br/><sub><b>🏠 Trang chủ</b> — feed nhạc, gợi ý, bình luận realtime</sub></td>
    <td width="50%"><img src="docs/screenshots/05-search.png" alt="Tìm kiếm"/><br/><sub><b>🔍 Tìm kiếm</b> — chưa gõ: lịch sử & xu hướng</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/02-artists.png" alt="Nghệ sĩ"/><br/><sub><b>🎤 Danh bạ nghệ sĩ</b> — 5.000+ nghệ sĩ, lọc A–Z</sub></td>
    <td><img src="docs/screenshots/03-artist-detail.png" alt="Chi tiết nghệ sĩ"/><br/><sub><b>👤 Chi tiết nghệ sĩ</b> — tiểu sử, bài hát, thống kê</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/04-song-detail.png" alt="Chi tiết bài hát"/><br/><sub><b>🎵 Chi tiết bài hát</b> — lời, bản nhạc, gợi ý</sub></td>
    <td><img src="docs/screenshots/10-player.png" alt="Trình phát"/><br/><sub><b>▶️ Trình phát</b> — now playing, lời, hàng đợi</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/08-category.png" alt="Thể loại"/><br/><sub><b>🗂️ Thể loại</b> — danh sách bài + sắp xếp</sub></td>
    <td><img src="docs/screenshots/09-library.png" alt="Thư viện"/><br/><sub><b>📚 Thư viện</b> — yêu thích, nghe gần đây, playlist</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/06-activity.png" alt="Hoạt động"/><br/><sub><b>📈 Hoạt động</b> — dòng thời gian toàn site</sub></td>
    <td><img src="docs/screenshots/07-comments.png" alt="Bình luận"/><br/><sub><b>💬 Bình luận</b> — mới nhất, có bộ lọc</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/16-search-results.png" alt="Kết quả tìm kiếm"/><br/><sub><b>🔎 Tìm kiếm — kết quả</b> — 28 kết quả «Tình ca», lọc theo loại</sub></td>
    <td><img src="docs/screenshots/17-composers.png" alt="Nhạc sĩ"/><br/><sub><b>🎼 Nhạc sĩ</b> — danh bạ nhạc sĩ, lọc A–Z</sub></td>
  </tr>
</table>

### 🎯 Cá nhân hoá

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/11-favorites.png" alt="Yêu thích"/><br/><sub><b>❤️ Yêu thích</b> — danh sách bài đã thích</sub></td>
    <td width="50%"><img src="docs/screenshots/12-playlists.png" alt="Playlist của tôi"/><br/><sub><b>🎶 Playlist của tôi</b> — danh sách phát tự tạo</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/13-my-uploads.png" alt="Bài tôi gửi"/><br/><sub><b>⬆️ Bài tôi gửi</b> — đóng góp của thành viên</sub></td>
    <td><img src="docs/screenshots/15-stats.png" alt="Thống kê"/><br/><sub><b>📊 Thống kê</b> — lượt nghe, streak, phân loại</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/14-settings.png" alt="Cài đặt"/><br/><sub><b>⚙️ Cài đặt</b> — hồ sơ, ảnh đại diện, tuỳ chọn</sub></td>
    <td><img src="docs/screenshots/18-recent.png" alt="Nghe gần đây"/><br/><sub><b>🕘 Nghe gần đây</b> — lịch sử nghe</sub></td>
  </tr>
</table>

## ✨ Tính năng

- 🎵 Nghe nhạc cách mạng & trữ tình — hàng nghìn bài hát, kèm **lời** và **bản nhạc**
- 🔎 Tìm kiếm toàn diện: bài hát, nghệ sĩ, nhạc sĩ, nhà thơ, tư liệu…
- 🎤 Danh bạ nghệ sĩ / nhạc sĩ / nhà thơ + trang chi tiết (tiểu sử, tác phẩm, thống kê)
- 🎙️ Karaoke & ngâm thơ (tiếng thơ)
- ❤️ Cá nhân hoá: yêu thích, playlist, nghe gần đây, bài gửi, thống kê nghe
- 💬 Bình luận & dòng hoạt động cộng đồng (realtime)
- 📱 Một mã nguồn — chạy trên iOS · Android · macOS · Windows · Web

## 🛠 Công nghệ

| Thành phần | Dùng |
|---|---|
| UI đa nền tảng | **Flutter / Dart** |
| Giao tiếp backend | **GraphQL** (đăng nhập, dữ liệu nhạc, bình luận) |
| Xác thực | **JWT** (access / refresh token) |

## 🚀 Chạy dự án

```bash
flutter pub get               # cài dependency

flutter run -d macos          # desktop macOS
flutter run -d chrome         # web
flutter run -d <device-id>    # iOS / Android  (liệt kê: flutter devices)
```

Build bản phát hành: `flutter build apk` · `ios` · `macos` · `web`.

## 📁 Cấu trúc

```text
lib/
├── screens/     # màn hình (home, song_detail, profile, …)
├── widgets/     # thành phần tái dùng (full_player, comment_section, …)
├── services/    # api.dart (GraphQL), auth.dart, player.dart
└── constants/   # theme.dart (màu, font, apiBase, siteUrl)
```
