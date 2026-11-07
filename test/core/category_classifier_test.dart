import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/constants.dart';
import 'package:netget/core/utils.dart';

void main() {
  group('Category and Content-Disposition Tests', () {
    test('parses UTF-8 and quoted Content-Disposition filenames', () {
      expect(
        NetGetUtils.parseContentDisposition(
          "attachment; filename*=UTF-8''document%20name.pdf",
        ),
        'document name.pdf',
      );
      expect(
        NetGetUtils.parseContentDisposition(
          'attachment; filename="archive_2026.zip"',
        ),
        'archive_2026.zip',
      );
      expect(
        NetGetUtils.parseContentDisposition('attachment; filename=movie.mp4'),
        'movie.mp4',
      );
      expect(NetGetUtils.parseContentDisposition(null), isNull);
    });

    test('classifies filenames and MIME types into categories correctly', () {
      expect(NetGetUtils.classifyCategory('video.mp4'), DownloadCategory.video);
      expect(
        NetGetUtils.classifyCategory('stream', 'video/mp4'),
        DownloadCategory.video,
      );
      expect(NetGetUtils.classifyCategory('song.mp3'), DownloadCategory.audio);
      expect(
        NetGetUtils.classifyCategory('stream', 'audio/aac'),
        DownloadCategory.audio,
      );
      expect(
        NetGetUtils.classifyCategory('photo.jpg'),
        DownloadCategory.images,
      );
      expect(
        NetGetUtils.classifyCategory('paper.pdf'),
        DownloadCategory.documents,
      );
      expect(
        NetGetUtils.classifyCategory('data.tar.gz'),
        DownloadCategory.archives,
      );
      expect(NetGetUtils.classifyCategory('app.apk'), DownloadCategory.apps);
      expect(
        NetGetUtils.classifyCategory('unknown.xyz'),
        DownloadCategory.other,
      );
    });

    test('formats elapsed seconds into formatted strings', () {
      expect(NetGetUtils.formatElapsed(45), '00:45');
      expect(NetGetUtils.formatElapsed(125), '02:05');
      expect(NetGetUtils.formatElapsed(3665), '01:01:05');
    });
  });
}
