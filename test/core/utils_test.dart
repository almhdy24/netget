import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/utils.dart';

void main() {
  group('NetGetUtils', () {
    test('formatBytes formats units cleanly', () {
      expect(NetGetUtils.formatBytes(0), '0 B');
      expect(NetGetUtils.formatBytes(512), '512 B');
      expect(NetGetUtils.formatBytes(1024), '1.00 KB');
      expect(NetGetUtils.formatBytes(1536), '1.50 KB');
      expect(NetGetUtils.formatBytes(1048576), '1.00 MB');
      expect(NetGetUtils.formatBytes(15728640), '15.0 MB');
      expect(NetGetUtils.formatBytes(1073741824), '1.00 GB');
    });

    test('formatSpeed formats transfer speed per second', () {
      expect(NetGetUtils.formatSpeed(0), '0 B/s');
      expect(NetGetUtils.formatSpeed(1048576), '1.00 MB/s');
      expect(NetGetUtils.formatSpeed(2621440), '2.50 MB/s');
    });

    test('formatEta formats seconds concisely', () {
      expect(NetGetUtils.formatEta(null), '--');
      expect(NetGetUtils.formatEta(-1), '--');
      expect(NetGetUtils.formatEta(45), '45s');
      expect(NetGetUtils.formatEta(60), '1m');
      expect(NetGetUtils.formatEta(125), '2m 5s');
      expect(NetGetUtils.formatEta(3665), '1h 1m');
    });

    test('extractFileNameFromUrl parses clean file names', () {
      expect(
        NetGetUtils.extractFileNameFromUrl('https://example.com/files/app-v1.apk'),
        'app-v1.apk',
      );
      expect(
        NetGetUtils.extractFileNameFromUrl('https://example.com/download?id=123/sample%20video.mp4'),
        'sample video.mp4',
      );
      expect(
        NetGetUtils.extractFileNameFromUrl('https://example.com/'),
        startsWith('download_'),
      );
    });

    test('sanitizeFileName removes invalid filesystem characters', () {
      expect(
        NetGetUtils.sanitizeFileName('my/invalid:file*name?.zip'),
        'my_invalid_file_name_.zip',
      );
      expect(
        NetGetUtils.sanitizeFileName('   clean_file.tar.gz   '),
        'clean_file.tar.gz',
      );
      expect(
        NetGetUtils.sanitizeFileName(''),
        startsWith('download_'),
      );
    });

    test('getFileTypeIcon returns corresponding icon for extensions', () {
      expect(NetGetUtils.getFileTypeIcon('app.apk'), Icons.android_outlined);
      expect(NetGetUtils.getFileTypeIcon('archive.zip'), Icons.folder_zip_outlined);
      expect(NetGetUtils.getFileTypeIcon('song.mp3'), Icons.audiotrack_outlined);
      expect(NetGetUtils.getFileTypeIcon('movie.mp4'), Icons.movie_outlined);
      expect(NetGetUtils.getFileTypeIcon('doc.pdf'), Icons.picture_as_pdf_outlined);
      expect(NetGetUtils.getFileTypeIcon('data.bin'), Icons.insert_drive_file_outlined);
    });
  });
}
