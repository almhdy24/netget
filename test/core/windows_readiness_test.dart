import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/utils.dart';
import 'package:netget/services/multi_connection_downloader.dart';

void main() {
  group('Windows Readiness - File Name Sanitization', () {
    test('sanitizes Windows reserved DOS device names (CON, PRN, AUX, NUL, COM1..9, LPT1..9)', () {
      expect(NetGetUtils.sanitizeFileName('CON'), '_CON');
      expect(NetGetUtils.sanitizeFileName('con.txt'), '_con.txt');
      expect(NetGetUtils.sanitizeFileName('AUX.tar.gz'), '_AUX.tar.gz');
      expect(NetGetUtils.sanitizeFileName('nul.zip'), '_nul.zip');
      expect(NetGetUtils.sanitizeFileName('COM1.log'), '_COM1.log');
      expect(NetGetUtils.sanitizeFileName('COM9'), '_COM9');
      expect(NetGetUtils.sanitizeFileName('LPT1.pdf'), '_LPT1.pdf');
      expect(NetGetUtils.sanitizeFileName('prn'), '_prn');

      // Non-reserved names containing reserved letters should not be prefixed
      expect(NetGetUtils.sanitizeFileName('console.log'), 'console.log');
      expect(NetGetUtils.sanitizeFileName('auxiliary.mp4'), 'auxiliary.mp4');
      expect(NetGetUtils.sanitizeFileName('null_pointer.dart'), 'null_pointer.dart');
    });

    test('strips trailing dots and spaces forbidden on Windows filesystems', () {
      expect(NetGetUtils.sanitizeFileName('document.pdf. . .'), 'document.pdf');
      expect(NetGetUtils.sanitizeFileName('archive.zip   '), 'archive.zip');
      expect(NetGetUtils.sanitizeFileName('spaces and dots ...  '), 'spaces and dots');
    });

    test('replaces Windows illegal characters with underscores', () {
      expect(
        NetGetUtils.sanitizeFileName('bad<name>:file"with|pipes?and*stars.iso'),
        'bad_name__file_with_pipes_and_stars.iso',
      );
      expect(
        NetGetUtils.sanitizeFileName('windows\\slash/separator.dat'),
        'windows_slash_separator.dat',
      );
    });

    test('enforces max file name length respecting MAX_PATH (260)', () {
      final longBase = 'A' * 300;
      final sanitized = NetGetUtils.sanitizeFileName('$longBase.zip', maxFileNameLength: 240);
      expect(sanitized.length, lessThanOrEqualTo(240));
      expect(sanitized.endsWith('.zip'), isTrue);

      final veryLongWithoutExt = 'B' * 300;
      final sanitizedNoExt = NetGetUtils.sanitizeFileName(veryLongWithoutExt, maxFileNameLength: 240);
      expect(sanitizedNoExt.length, 240);
    });
  });

  group('Windows Readiness - safeRenameFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('netget_win_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('renames source to target when target does not exist', () async {
      final source = File('${tempDir.path}/temp_file.tmp');
      final target = File('${tempDir.path}/final_file.txt');

      await source.writeAsString('hello world');
      expect(await source.exists(), isTrue);
      expect(await target.exists(), isFalse);

      final result = await NetGetUtils.safeRenameFile(source, target);
      expect(result.path, target.path);
      expect(await source.exists(), isFalse);
      expect(await target.exists(), isTrue);
      expect(await target.readAsString(), 'hello world');
    });

    test('atomically overwrites target when target already exists (Windows safe)', () async {
      final source = File('${tempDir.path}/new_version.tmp');
      final target = File('${tempDir.path}/existing_target.txt');

      await target.writeAsString('old content');
      await source.writeAsString('new updated content');

      expect(await target.exists(), isTrue);
      expect(await source.exists(), isTrue);

      final result = await NetGetUtils.safeRenameFile(source, target);
      expect(result.path, target.path);
      expect(await source.exists(), isFalse);
      expect(await target.exists(), isTrue);
      expect(await target.readAsString(), 'new updated content');
    });
  });

  group('Windows Readiness - defaultDiskSpaceChecker', () {
    test('returns null without throwing when running on Windows platform', () async {
      if (Platform.isWindows) {
        final result = await defaultDiskSpaceChecker(Directory.current.path);
        expect(result, isNull);
      }
    });
  });
}
