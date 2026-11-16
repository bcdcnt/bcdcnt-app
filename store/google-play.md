# Google Play — nội dung để dán vào Play Console

App: **net.bcdcnt.music** · tài khoản nhà phát triển BCĐCNT (cá nhân)

---

## 1. Trang thông tin chính trên Store (Grow → Store presence → Main store listing)

**Tên ứng dụng** (≤30)
```
Bài ca đi cùng năm tháng
```

**Mô tả ngắn** (≤80)
```
Kho nhạc Việt Nam xưa: nghe, tải, karaoke, lời bài hát và cộng đồng yêu nhạc
```

**Mô tả đầy đủ** (≤4000)
```
BCĐCNT – Bài ca đi cùng năm tháng là kho lưu trữ những bài hát Việt Nam qua các thời kỳ, gắn bó với cộng đồng người yêu nhạc từ nhiều năm nay.

• Hơn 14.000 bản thu, thông tin hơn 1.300 nhạc sĩ, 3.000 nghệ sĩ và nhiều nhà thơ
• Lời bài hát, bản nhạc, tư liệu, câu chuyện quanh từng ca khúc
• Trình phát nhạc chạy nền, điều khiển trên màn hình khoá, hàng đợi, phát ngẫu nhiên, lặp lại
• Đài phát 24/7 – mở là nghe, không cần chọn bài
• Tìm kiếm nhanh theo tên bài, nhạc sĩ, nghệ sĩ, câu hát – kể cả tìm bằng giọng nói
• Bảng xếp hạng bài hát, nghệ sĩ, thành viên
• Yêu thích, playlist cá nhân, tải bài hát về máy
• Karaoke, bình luận, chia sẻ cảm nhận cùng cộng đồng
• Thông báo khi có bình luận trả lời, bài mới
• Giao diện sáng/tối, chữ dễ đọc

Ứng dụng miễn phí, không quảng cáo.

Website: https://bcdcnt.net
Góp ý: contact@bcdcnt.net
```

**Đồ hoạ**
- Biểu tượng 512×512 PNG
- Hình ảnh nổi bật 1024×500
- Ảnh chụp màn hình điện thoại: 2–8 ảnh (dọc 9:16)

## 2. Cài đặt cửa hàng (Store settings)
- Danh mục: **Ứng dụng → Âm nhạc và âm thanh**
- Thẻ: Âm nhạc, Trình phát nhạc
- Email: `contact@bcdcnt.net` · Trang web: `https://bcdcnt.net`

---

## 3. Nội dung ứng dụng (Policy → App content)

### Chính sách quyền riêng tư
```
https://bcdcnt.net/bao-mat
```

### Quyền truy cập vào ứng dụng
Chọn **"Tất cả hoặc một số chức năng bị hạn chế"** → Thêm hướng dẫn:
- Tên: `Tài khoản thành viên`
- Tên người dùng / mật khẩu: *(tài khoản test thường, KHÔNG dùng tài khoản BQT)*
- Hướng dẫn:
```
Mở tab "Cá nhân" → "Đăng nhập" → nhập email và mật khẩu ở trên. Nghe nhạc, tìm kiếm không cần đăng nhập; đăng nhập để bình luận, yêu thích, tạo playlist.
```

### Quảng cáo
**Không**, ứng dụng không chứa quảng cáo.

### Mức phân loại nội dung (bảng câu hỏi IARC)
- Email: `contact@bcdcnt.net` · Danh mục: **Tất cả các loại khác** (không phải trò chơi / mạng xã hội thuần)
- Bạo lực / tình dục / ngôn từ tục tĩu / chất cấm / cờ bạc: **Không** cho tất cả
- Người dùng có tương tác với nhau không (bình luận, chia sẻ nội dung do người dùng tạo)? **Có**
  - Có kiểm duyệt nội dung? **Có** (BQT duyệt bài gửi, ẩn/xoá bình luận)
  - Có chặn/báo cáo người dùng? **Có**
- Chia sẻ vị trí người dùng? **Không**
- Mua hàng kỹ thuật số? **Không**
- Ứng dụng có phải trình duyệt web / công cụ tìm kiếm? **Không**

### Đối tượng mục tiêu
- Nhóm tuổi: **18 trở lên** (có thể thêm 16–17). KHÔNG chọn dưới 13.
- Ứng dụng có thể vô tình thu hút trẻ em? **Không**

### Ứng dụng tin tức: **Không**
### Ứng dụng phòng chống COVID / chính phủ / tài chính / sức khoẻ: **Không**
### ID quảng cáo (Advertising ID): **Không** dùng

### Quyền dịch vụ trên nền trước (Foreground service)
Loại: **Phát nội dung đa phương tiện (mediaPlayback)**
```
Ứng dụng phát nhạc. Khi người dùng bấm phát một bài hát hoặc đài 24/7 rồi chuyển sang ứng dụng khác hoặc tắt màn hình, nhạc vẫn tiếp tục phát và có thông báo điều khiển (phát/tạm dừng/bài tiếp) trên thanh thông báo và màn hình khoá. Dịch vụ chỉ chạy khi người dùng chủ động phát nhạc và dừng khi người dùng tạm dừng/đóng trình phát.
```
Video minh hoạ (YouTube không công khai): mở app → phát bài → về màn hình chính → nhạc vẫn chạy, kéo thanh thông báo bấm tạm dừng.

---

## 4. An toàn dữ liệu (Data safety)

- Ứng dụng có thu thập/chia sẻ dữ liệu người dùng? **Có**
- Mọi dữ liệu đều được mã hoá khi truyền? **Có** (HTTPS)
- Người dùng có thể yêu cầu xoá dữ liệu? **Có**, link: `https://bcdcnt.net/bao-mat` *(hoặc email contact@bcdcnt.net)*
- Tạo tài khoản: **Tên người dùng + mật khẩu**, **Đăng nhập Google / Apple**

| Loại dữ liệu | Thu thập | Chia sẻ bên thứ 3 | Bắt buộc? | Mục đích |
|---|---|---|---|---|
| Thông tin cá nhân → **Tên** | Có | Không | Không bắt buộc (chỉ khi đăng ký) | Chức năng ứng dụng, Quản lý tài khoản |
| Thông tin cá nhân → **Địa chỉ email** | Có | Không | Không bắt buộc | Chức năng ứng dụng, Quản lý tài khoản, Liên lạc |
| Thông tin cá nhân → **ID người dùng** | Có | Không | Không bắt buộc | Chức năng ứng dụng, Quản lý tài khoản |
| Tin nhắn → **Tin nhắn khác trong ứng dụng** (bình luận) | Có | Không | Không bắt buộc | Chức năng ứng dụng |
| Ảnh và video → **Ảnh** (ảnh đại diện, ảnh đính kèm) | Có | Không | Không bắt buộc | Chức năng ứng dụng |
| Âm thanh → **Tệp nhạc** (bài gửi / karaoke tải lên) | Có | Không | Không bắt buộc | Chức năng ứng dụng |
| Hoạt động trong ứng dụng → **Tương tác với ứng dụng** | Có | Không | Bắt buộc | Thống kê (Analytics) |
| Hoạt động trong ứng dụng → **Lịch sử tìm kiếm** | Có | Không | Bắt buộc | Chức năng ứng dụng, Thống kê |
| Hoạt động trong ứng dụng → **Nội dung khác do người dùng tạo** (playlist, yêu thích) | Có | Không | Không bắt buộc | Chức năng ứng dụng |
| Thông tin và hiệu năng ứng dụng → **Nhật ký sự cố / chẩn đoán** | Không | – | – | – |
| Mã nhận dạng thiết bị hoặc mã khác (FCM push token, GA4 client id) | Có | Không | Bắt buộc | Chức năng ứng dụng (thông báo), Thống kê |

Không thu thập: vị trí, danh bạ, tài chính, sức khoẻ, SMS, lịch, tệp/tài liệu khác.
**Ghi âm giọng nói** (tìm kiếm bằng giọng nói) xử lý bởi dịch vụ nhận dạng của hệ thống, ứng dụng không lưu/gửi bản ghi → **không** khai "Âm thanh → Ghi âm giọng nói".

> Ghi chú: "Chia sẻ" theo định nghĩa của Google không tính nhà cung cấp dịch vụ xử lý thay mình (Google Analytics, Firebase, Cloudflare) → khai **Không chia sẻ**.

---

## 5. Thử nghiệm kín (bắt buộc trước Production)
- ≥ **12 người** đã chấp nhận tham gia, liên tục **14 ngày**.
- Testing → Closed testing → tạo kênh "Alpha" → Testers: danh sách email "BQT" → copy **link tham gia** gửi mọi người.
- Mỗi người: mở link bằng đúng gmail trên máy Android → "Trở thành người thử nghiệm" → cài app từ Play.
- Hết 14 ngày: Dashboard → **Áp dụng quyền truy cập bản phát hành chính thức** (trả lời vài câu về đợt thử).
