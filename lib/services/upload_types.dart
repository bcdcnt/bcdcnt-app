/// Names of upload types (`upload.type`) as members read them.
const kUploadTypeLabels = {
  'song': 'Tân nhạc',
  'folk': 'Dân ca',
  'instrumental': 'Khí nhạc',
  'karaoke': 'Bản thu',
  'poem': 'Tiếng thơ',
  'replace': 'Bổ sung bản ghi',
  'document_audio': 'Tư liệu âm thanh',
  'document_image': 'Tư liệu hình ảnh',
  'document_video': 'Tư liệu video',
  'document_news': 'Bài viết',
  'sheet': 'Bản nhạc',
  'beat': 'Beat',
  'discussion': 'Thảo luận',
};

String uploadTypeLabel(dynamic type) => kUploadTypeLabels['$type'] ?? '${type ?? ''}';
