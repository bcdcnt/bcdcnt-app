# BCĐCNT app — Ứng dụng nghe nhạc đa nền tảng

Ứng dụng nghe nhạc **chính thức** của **[bcdcnt.net](https://bcdcnt.net)** — viết bằng **Flutter** (iOS · Android · macOS · Windows · Web).

## 📸 Giao diện

> **12 chủ đề màu**, gồm cả **tối** lẫn **sáng**. Ảnh ngay dưới là chủ đề **tối**; xem chủ đề **sáng** ở [mục bên dưới](#-giao-diện-sáng).

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

### 🌞 Giao diện sáng

Cùng các màn hình trên ở chủ đề **sáng** — bật trong **Phối màu** (Cài đặt) hoặc nút **Giao diện** ở thanh bên.

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/light/01-home.png" alt="Trang chủ — sáng"/><br/><sub><b>🏠 Trang chủ</b></sub></td>
    <td width="50%"><img src="docs/screenshots/light/04-song-detail.png" alt="Chi tiết bài hát — sáng"/><br/><sub><b>🎵 Chi tiết bài hát</b></sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/light/10-player.png" alt="Trình phát — sáng"/><br/><sub><b>▶️ Trình phát</b></sub></td>
    <td><img src="docs/screenshots/light/09-library.png" alt="Thư viện — sáng"/><br/><sub><b>📚 Thư viện</b></sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/light/16-search-results.png" alt="Kết quả tìm kiếm — sáng"/><br/><sub><b>🔎 Tìm kiếm — kết quả</b></sub></td>
    <td><img src="docs/screenshots/light/14-settings.png" alt="Cài đặt — sáng"/><br/><sub><b>⚙️ Cài đặt</b></sub></td>
  </tr>
</table>

## ✨ Tính năng

- 🎵 **Nghe nhạc** cách mạng & trữ tình — hàng nghìn bài hát, kèm **lời** và **bản nhạc**
- 🔎 **Tìm kiếm & duyệt** theo nghệ sĩ · nhạc sĩ · nhà thơ · soạn giả, thể loại, thập niên, tư liệu
- 👤 **Trang chi tiết** nghệ sĩ / bài hát: tiểu sử, tác phẩm, lời, bản nhạc, gợi ý, thống kê
- ❤️ **Cá nhân hoá**: yêu thích, playlist, nghe gần đây, bài gửi, thống kê nghe
- 💬 **Cộng đồng**: bình luận, thảo luận, dòng hoạt động & thông báo **realtime**
- ⬇️ **Tải về** bài hát, tư liệu
- 📱 **Đa nền tảng** — một mã nguồn chạy trên iOS · Android · macOS · Windows · Web

## 🛠 Công nghệ

| Thành phần | Dùng |
|---|---|
| UI đa nền tảng | **Flutter / Dart** |
| Giao tiếp backend | **GraphQL** (đăng nhập, dữ liệu nhạc, bình luận) |
| Xác thực | **JWT** (access / refresh token) |

## 📥 Tải & cài đặt

Tải bản mới nhất cho nền tảng của bạn tại **[trang Releases](https://github.com/bcdcnt/bcdcnt-app/releases/latest)**, rồi làm theo hướng dẫn bên dưới.

### 🍎 macOS
1. Tải `bcdcnt-macos.dmg` (hoặc `.zip`).
2. Mở file, kéo **Bài ca đi cùng năm tháng** vào thư mục **Applications**.
3. Lần đầu mở: app chưa ký Apple nên macOS sẽ chặn → **chuột phải vào app → Open → Open**. (Hoặc chạy `xattr -dr com.apple.quarantine "/Applications/Bài ca đi cùng năm tháng.app"` rồi mở lại.)

> Yêu cầu: macOS 11 (Big Sur) trở lên.

### 🪟 Windows
1. Tải `bcdcnt-windows.zip`.
2. Giải nén vào một thư mục bất kỳ (vd `C:\Program Files\BCDCNT`).
3. Chạy **`bcdcnt.exe`**. Nếu SmartScreen cảnh báo → **More info → Run anyway**.

> Yêu cầu: Windows 10 trở lên (64-bit).

### 🐧 Linux
1. Tải `bcdcnt-linux.tar.gz`.
2. Giải nén và cấp quyền chạy:
   ```bash
   tar -xzf bcdcnt-linux.tar.gz && cd bcdcnt
   chmod +x bcdcnt && ./bcdcnt
   ```
3. Cần **libmpv** cho phát nhạc (backend âm thanh trên Linux):
   ```bash
   sudo apt install libmpv2     # Debian/Ubuntu  (hoặc: libmpv-dev / mpv)
   ```

### 🤖 Android
1. Tải file **`bcdcnt.apk`**.
2. Mở file → nếu được hỏi, bật **"Cài ứng dụng không rõ nguồn gốc"** cho trình duyệt/trình quản lý file.
3. Nhấn **Cài đặt**.

> Yêu cầu: Android 6.0 trở lên.

### 🍏 iOS
- **TestFlight** (khuyến nghị): mở link mời TestFlight, cài **TestFlight** từ App Store rồi nhấn **Install**.
- Hoặc cài file `.ipa` qua công cụ sideload (AltStore / Sideloadly) nếu không dùng TestFlight.

> Yêu cầu: iOS 13 trở lên.

---

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
