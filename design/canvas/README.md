# Canvas giao diện app

Bản lưu trong git của Design canvas **"BCĐCNT App — Giao diện"**:
https://claude.ai/artifact/8f5arw19K5UGMwv5bDkHDU (riêng tư, chỉ chủ sở hữu mở được).

Quy trình: mọi thay đổi giao diện app vẽ trên canvas trước → duyệt → mới sửa
Flutter → lưu bản canvas mới vào đây cùng commit (hoặc ngay trước commit) sửa code.

## Cấu trúc

| Đường dẫn | Nội dung |
|---|---|
| `project/canvas.json` | Chỉ mục canvas: vị trí, kích thước, tên các artboard, ghi chú |
| `project/*.dc.html` | Mã nguồn từng artboard (12 màn + `TabBar`, `MiniPlayer` dùng chung) |
| `assets/<id>.jpg\|svg` | Ảnh đã tải lên canvas; artboard trỏ tới bằng `/_blob/<id>` |
| `preview/*.png` | Ảnh chụp từng artboard để xem nhanh trên GitHub (tạo bằng `render.py`) |
| `render.py` | Chụp lại `preview/` từ `project/` + `assets/` |

File `.dc.html` cần runtime của canvas nên mở trực tiếp trong trình duyệt sẽ
không đúng; xem `preview/` hoặc mở link canvas.

## Lấy bản mới từ canvas về

Canvas là riêng tư nên chỉ đọc được qua Claude Code (công cụ Artifact). Bảo Claude:
"lưu canvas vào git". Claude sẽ:

1. Đọc `project/canvas.json` và các `project/*.dc.html` từ canvas, ghi đè vào `project/`.
2. Tải ảnh mới (id `/_blob/…` chưa có trong `assets/`) vào `assets/`.
3. Chạy `python3 design/canvas/render.py` để cập nhật `preview/`.
4. Commit riêng thư mục `design/canvas/`.

## Khôi phục lên canvas

- **Canvas còn:** đăng lại `project/*` lên đúng link trên (root = `design/canvas`).
  Các id ảnh vẫn dùng được.
- **Canvas mất:** tạo canvas mới từ loại "Design", tải từng file trong `assets/` lên
  làm asset, thay `/_blob/<id cũ>` bằng url mới trong `project/*.dc.html`, rồi đăng
  `project/*`. Cập nhật link ở đầu file này.
