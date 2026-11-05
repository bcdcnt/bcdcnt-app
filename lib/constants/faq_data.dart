// Câu hỏi thường gặp trong app. Nội dung gốc từ bcdcnt-web/packages/web/lib/faqData.js,
// chỉnh lại những câu chỉ đường cho đúng cách bố trí của app (tab Khám phá /
// Cộng đồng / Thư viện, Góp ý & hỗ trợ, Đã tải về…). Sửa web thì nhớ xem lại đây.

class FaqItem {
  final String q;
  final String a;
  const FaqItem(this.q, this.a);
}

class FaqGroup {
  final String cat;
  final List<FaqItem> items;
  const FaqGroup(this.cat, this.items);
}

const kFaq = [
  FaqGroup('Giới thiệu & nội dung', [
    FaqItem('BCĐCNT (Bài ca đi cùng năm tháng) là gì?',
        'Là thư viện âm nhạc cộng đồng thành lập từ năm 2009, lưu giữ và lan toả các ca khúc cách mạng, tiền chiến, dân ca, nhạc truyền thống Việt Nam cùng tư liệu liên quan. Trang phi lợi nhuận, do cộng đồng yêu nhạc cùng xây dựng. Xem thêm ở trang Giới thiệu.'),
    FaqItem('"BCĐCNT" là viết tắt của gì?',
        'BCĐCNT là viết tắt của "Bài ca đi cùng năm tháng" — lấy cảm hứng từ chương trình ca nhạc cùng tên của Đài Tiếng nói Việt Nam (VOV). Ban đầu trang dùng tên miền baicadicungnamthang.net, sau đó đổi thành bcdcnt.net cho ngắn gọn, dễ nhớ.'),
    FaqItem('BCĐCNT khác gì các ứng dụng nghe nhạc khác?',
        'Khác với các nơi nghe nhạc thiên về mục đích thương mại, hầu hết bài hát ở đây do chính các thành viên yêu nhạc đề cử, được ban quản trị thẩm định và duyệt trước khi đăng. Nhờ vậy, tác phẩm đều có giá trị nghệ thuật cao và có ích cho cộng đồng, thay vì chạy theo lượt nghe hay lợi nhuận.'),
    FaqItem('Vì sao tạo ra BCĐCNT?',
        'Lưu trữ âm nhạc dân tộc là việc rất cần thiết — không chỉ cho hôm nay mà còn cho các thế hệ trẻ mai sau. Nhiều bản thu quý hiếm đã bị thất lạc hoặc mất thông tin (tác giả, năm sáng tác, người thể hiện…); BCĐCNT mong cùng cộng đồng sưu tầm, bổ sung và gìn giữ kho tàng này. Qua những ca khúc cách mạng, truyền thống, BCĐCNT cũng mong góp phần hun đúc lòng yêu nước, niềm tự hào dân tộc và ý thức giữ gìn bản sắc văn hoá — góp phần chống lại âm mưu "diễn biến hoà bình" trên mặt trận tư tưởng, văn hoá.'),
    FaqItem('Có những loại nội dung nào?',
        'Gồm Tân nhạc (ca khúc), Dân ca, Khí nhạc (hoà tấu), Tiếng thơ (ngâm/đọc thơ) và Thành viên hát (bản thu do thành viên tự thể hiện). Ngoài ra có bản nhạc (sheet), tư liệu/bài viết, hình ảnh về tác phẩm và tác giả.'),
    FaqItem('Nghe và tải nhạc có mất phí không?',
        'Hoàn toàn miễn phí. Bạn nghe và tải nhạc thoải mái, không mất phí, không quảng cáo phiền nhiễu.'),
    FaqItem('"Thành viên hát" là gì?',
        'Là các bản thu do chính thành viên tự hát/thể hiện (cover), khác với bản thu chuyên nghiệp. Bạn cũng có thể gửi bản hát của mình qua mục Gửi bài trên website bcdcnt.net.'),
    FaqItem('"Tiếng thơ" là gì?',
        'Là các tác phẩm ngâm thơ, đọc thơ, thơ phổ nhạc — một thể loại đặc trưng được lưu giữ trên BCĐCNT.'),
    FaqItem('Nhạc trên BCĐCNT có bản quyền thế nào?',
        'Phần lớn là nhạc cách mạng, truyền thống được sưu tầm nhằm mục đích lưu giữ, giáo dục và phi lợi nhuận. Nếu bạn là tác giả/chủ sở hữu và có yêu cầu, vui lòng gửi riêng cho ban quản trị qua mục Góp ý & hỗ trợ.'),
    FaqItem('BCĐCNT hoạt động bằng kinh phí nào?',
        'BCĐCNT hoạt động hoàn toàn dựa trên kinh phí cá nhân của người sáng lập cùng sự ủng hộ từ các thành viên yêu nhạc — phi lợi nhuận, không quảng cáo thương mại.'),
  ]),
  FaqGroup('Nghe & tải nhạc', [
    FaqItem('Nghe một bài hát như thế nào?',
        'Chạm vào bài hát bất kỳ để phát. Thanh phát nhỏ ở cuối màn hình cho tạm dừng và chuyển bài; chạm vào thanh đó để mở trình phát đầy đủ: tua, lặp lại, phát ngẫu nhiên, hẹn giờ tắt và xem lời bài hát.'),
    FaqItem('Tải nhạc về máy để nghe khi không có mạng?',
        'Trên trang bài hát bấm Tải về, hoặc bấm nút ⋮ cạnh bài rồi chọn "Tải về để nghe offline". Bài đã tải nằm ở Thư viện → Đã tải về và nghe được cả khi không có mạng.'),
    FaqItem('BCĐCNT có những bản nào?',
        'Bạn đang dùng ứng dụng BCĐCNT. Ngoài ra còn có bản cho máy tính (Windows / macOS / Linux) và website bcdcnt.net — dùng chung một tài khoản.'),
    FaqItem('Vì sao có bài không nghe/tải được hoặc bị gián đoạn?',
        'Thường do kết nối mạng — hãy kiểm tra mạng rồi thử lại. Ngoài ra, một số bài cũ có thể bị mất dữ liệu; nếu gặp, nhờ bạn báo lại qua mục Góp ý & hỗ trợ để chúng tôi khôi phục sớm nhất.'),
    FaqItem('Tạo và quản lý playlist thế nào?',
        'Bấm nút ⋮ cạnh bài hát rồi chọn "Thêm vào playlist" để tạo/lưu playlist riêng. Xem lại tại Playlist của tôi.'),
    FaqItem('Lưu yêu thích và xem lại nghe gần đây ở đâu?',
        'Bấm biểu tượng trái tim để lưu vào Yêu thích; lịch sử nghe nằm ở mục Nghe gần đây. Cả hai đều ở tab Thư viện.'),
  ]),
  FaqGroup('Tài khoản & thành viên', [
    FaqItem('Có bắt buộc đăng ký để nghe nhạc không?',
        'Không. Bạn nghe nhạc mà không cần đăng nhập. Đăng ký giúp lưu yêu thích, playlist, bình luận, gửi bài và tích điểm.'),
    FaqItem('Đăng ký / đăng nhập như thế nào?',
        'Vào tab Thư viện rồi bấm Đăng nhập hoặc Đăng ký. Trên iPhone, iPad và Mac bạn có thể dùng "Tiếp tục với Apple".'),
    FaqItem('Quên mật khẩu thì làm sao?',
        'Bấm "Quên mật khẩu?" trong màn đăng nhập; nếu cần hỗ trợ thêm, gửi yêu cầu riêng qua mục Góp ý & hỗ trợ.'),
    FaqItem('Đổi tên hiển thị (tên tài khoản) như thế nào?',
        'Tên hiển thị của bạn chính là tên tài khoản. Để đổi, vào Cài đặt → mục đổi tên, nhập tên mới kèm lý do rồi gửi yêu cầu. Ban quản trị sẽ xem xét và duyệt (nhằm tránh trùng tên hoặc mạo danh). Bạn theo dõi trạng thái yêu cầu ngay trong Cài đặt: đang chờ, đã duyệt, hoặc bị từ chối kèm lý do. Khi được duyệt, tên mới áp dụng cho toàn bộ hoạt động của bạn.'),
    FaqItem('Đổi ảnh đại diện, ảnh nền và thông tin cá nhân?',
        'Vào Cài đặt để thay ảnh đại diện và ảnh nền — chỉ cần tải ảnh lên là hệ thống áp dụng ngay. Tại đây bạn cũng cập nhật được họ tên, ngày/tháng/năm sinh, giới tính, số điện thoại và địa chỉ. Những thay đổi này có hiệu lực tức thì, không cần chờ duyệt. Lưu ý về quyền riêng tư: trong các thông tin cá nhân, chỉ có tuổi (tính từ năm sinh) được hiển thị công khai trên trang cá nhân; các thông tin còn lại (số điện thoại, địa chỉ, ngày/tháng sinh…) được giữ kín, không công khai.'),
    FaqItem('Điểm thành viên / hoạt động là gì?',
        'Điểm ghi nhận mức độ đóng góp của bạn. Một số mốc điểm tiêu biểu: đăng một tác phẩm mới (bài hát, dân ca, khí nhạc, tiếng thơ, thành viên hát) +5 điểm; gửi bài, đóng góp ảnh minh hoạ, bản nhạc (sheet) hoặc tư liệu +3 điểm; cập nhật lời, thêm/sửa tag, dịch lời +2 điểm; bình luận hoặc được thích bình luận +1 điểm. Bạn theo dõi điểm trong trang cá nhân và mục Hoạt động thành viên.'),
  ]),
  FaqGroup('Đóng góp', [
    FaqItem('Làm sao để gửi / đăng một bài hát?',
        'Đăng nhập trên website bcdcnt.net rồi vào mục Gửi bài. Nếu chưa đủ quyền đăng trực tiếp, bạn có thể gửi qua diễn đàn để ban quản trị xem xét. Bài đã gửi xem lại ở Thư viện → Bài gửi.'),
    FaqItem('Tôi tự thu âm / hát cover, gửi lên được không?',
        'Được. Gửi bản hát của bạn — sau khi duyệt sẽ nằm ở mục Thành viên hát.'),
    FaqItem('Bài gửi được duyệt như thế nào, bao lâu?',
        'Ban quản trị (BQT) sẽ nghe và duyệt bài gửi trước khi đăng công khai, nhằm đảm bảo chất lượng và thông tin chính xác. Thời gian tuỳ số lượng, thường trong vài ngày.'),
    FaqItem('Đóng góp bản nhạc, tư liệu, hình ảnh, lời bài hát?',
        'Rất hoan nghênh. Bạn có thể góp bản nhạc (sheet), tư liệu/bài viết, hình ảnh và lời bài hát; các cập nhật này cũng qua duyệt của ban quản trị.'),
    FaqItem('Phát hiện sai lời / sai thông tin bài hát thì báo ở đâu?',
        'Bình luận ngay dưới bài hát, hoặc gửi cho ban quản trị qua mục Góp ý & hỗ trợ để chỉnh sửa.'),
  ]),
  FaqGroup('Tìm kiếm & khám phá', [
    FaqItem('Tìm bài hát / nghệ sĩ / nhạc sĩ như thế nào?',
        'Dùng tab Khám phá: gõ tên bài, nghệ sĩ, nhạc sĩ, nhà thơ, soạn giả… Nhớ mỗi một câu hát? Chọn bộ lọc "Lời bài hát". Bấm biểu tượng micro để tìm bằng giọng nói.'),
    FaqItem('Duyệt nhạc theo chủ đề và thập niên?',
        'Tab Khám phá có sẵn các ô thể loại, thập niên (1940s–1990s) và chủ đề. Trang chủ cũng có mục Nghe theo thập niên.'),
    FaqItem('Bản nhạc (sheet) dùng để làm gì?',
        'Sheet là bản ký âm/tổng phổ giúp bạn hát và chơi nhạc theo. Xem tại mục Bản nhạc hoặc ngay trên trang bài hát.'),
  ]),
  FaqGroup('Hỗ trợ & liên hệ', [
    FaqItem('Liên hệ, góp ý, yêu cầu bài hát với ban quản trị ở đâu?',
        'Gửi riêng cho ban quản trị (góp ý, báo lỗi, khiếu nại) tại mục Góp ý & hỗ trợ; đề nghị bài hát tại mục Yêu cầu. Bạn cũng có thể gửi email trực tiếp tới contact@bcdcnt.net.'),
    FaqItem('BCĐCNT do ai vận hành?',
        'BCĐCNT do cộng đồng yêu nhạc truyền thống Việt Nam xây dựng và duy trì, phi lợi nhuận. Đội ngũ quản trị viên phần lớn được chọn từ những thành viên gắn bó lâu năm và có đóng góp tích cực. Tất cả đều hoạt động hoàn toàn tình nguyện, không nhận lương — vì tình yêu với âm nhạc dân tộc. Chi tiết ở trang Giới thiệu.'),
    FaqItem('Báo lỗi kỹ thuật ở đâu?',
        'Gửi mô tả lỗi qua mục Góp ý & hỗ trợ (chọn chủ đề "Lỗi kỹ thuật") — ban quản trị sẽ kiểm tra và khắc phục.'),
  ]),
];

/// Words in answers that open an app screen (longest first so "Playlist
/// của tôi" wins over shorter overlaps).
const kFaqLinks = [
  ('Góp ý & hỗ trợ', '/ho-tro'),
  ('Hoạt động thành viên', '/cong-dong/hoat-dong-thanh-vien'),
  ('Playlist của tôi', '/playlist-cua-toi'),
  ('Nghe gần đây', '/nghe-gan-day'),
  ('Đã tải về', '/da-tai-ve'),
  ('Giới thiệu', '/gioi-thieu'),
  ('Yêu thích', '/yeu-thich'),
  ('Yêu cầu', '/yeu-cau'),
  ('Bản nhạc', '/sheet'),
  ('Cài đặt', '/cai-dat'),
];
