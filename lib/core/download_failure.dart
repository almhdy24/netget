import 'dart:async';
import 'dart:io';

sealed class DownloadFailure {
  final int? statusCode;
  final int? errorCode;
  final String? rawDetail;

  const DownloadFailure({this.statusCode, this.errorCode, this.rawDetail});

  DownloadFailureCode get code;
}

class TimeoutFailure extends DownloadFailure {
  const TimeoutFailure({super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.timeout;
}

class NetworkFailure extends DownloadFailure {
  const NetworkFailure({super.errorCode, super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.noConnection;
}

class ServerRefusedFailure extends DownloadFailure {
  const ServerRefusedFailure({super.errorCode, super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.serverRefused;
}

class StorageFullFailure extends DownloadFailure {
  const StorageFullFailure({super.errorCode, super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.storageFull;
}

class HttpFailure extends DownloadFailure {
  const HttpFailure({required int statusCode, super.rawDetail})
    : super(statusCode: statusCode);

  @override
  DownloadFailureCode get code {
    if (statusCode == 403) {
      return DownloadFailureCode.http403;
    }
    if (statusCode == 404) {
      return DownloadFailureCode.http404;
    }
    if (statusCode != null && statusCode! >= 500) {
      return DownloadFailureCode.serverError;
    }
    return DownloadFailureCode.unknown;
  }
}

class FileChangedOnServerFailure extends DownloadFailure {
  const FileChangedOnServerFailure({super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.fileChangedOnServer;
}

class UnknownFailure extends DownloadFailure {
  const UnknownFailure({super.rawDetail});
  @override
  DownloadFailureCode get code => DownloadFailureCode.unknown;
}

enum DownloadFailureCode {
  timeout,
  noConnection,
  serverRefused,
  fileChangedOnServer,
  storageFull,
  http403,
  http404,
  serverError,
  unknown;

  String localizedMessage({bool isArabic = false}) {
    if (isArabic) {
      switch (this) {
        case DownloadFailureCode.timeout:
          return 'انتهت مهلة الاتصال';
        case DownloadFailureCode.noConnection:
          return 'لا يوجد اتصال بالإنترنت (في انتظار الشبكة...)';
        case DownloadFailureCode.serverRefused:
          return 'رفض الخادم الاتصال';
        case DownloadFailureCode.fileChangedOnServer:
          return 'تغير الملف على الخادم';
        case DownloadFailureCode.storageFull:
          return 'مساحة التخزين ممتلئة';
        case DownloadFailureCode.http403:
          return 'الوصول محظور من الخادم (403)';
        case DownloadFailureCode.http404:
          return 'الملف غير موجود على الخادم (404)';
        case DownloadFailureCode.serverError:
          return 'خطأ في خادم الملف';
        case DownloadFailureCode.unknown:
          return 'فشل التنزيل';
      }
    } else {
      switch (this) {
        case DownloadFailureCode.timeout:
          return 'Connection timed out';
        case DownloadFailureCode.noConnection:
          return 'No connection (waiting for network...)';
        case DownloadFailureCode.serverRefused:
          return 'Server refused connection';
        case DownloadFailureCode.fileChangedOnServer:
          return 'File changed on server';
        case DownloadFailureCode.storageFull:
          return 'Storage is full';
        case DownloadFailureCode.http403:
          return 'Access forbidden (403)';
        case DownloadFailureCode.http404:
          return 'File not found (404)';
        case DownloadFailureCode.serverError:
          return 'Server error';
        case DownloadFailureCode.unknown:
          return 'Download failed';
      }
    }
  }
}

class DownloadFailureMapper {
  static DownloadFailure fromException(Object? error) {
    if (error == null) return const UnknownFailure();

    if (error is FileSystemException) {
      if (error.osError?.errorCode == 28 ||
          error.message.toLowerCase().contains('no space') ||
          error.message.toLowerCase().contains('enospc')) {
        return StorageFullFailure(
          errorCode: error.osError?.errorCode,
          rawDetail: error.message,
        );
      }
      return UnknownFailure(rawDetail: error.message);
    }

    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      final osMsg = error.osError?.message.toLowerCase() ?? '';
      if (error.osError?.errorCode == 111 ||
          msg.contains('refused') ||
          osMsg.contains('refused')) {
        return ServerRefusedFailure(
          errorCode: error.osError?.errorCode,
          rawDetail: error.message,
        );
      }
      return NetworkFailure(
        errorCode: error.osError?.errorCode,
        rawDetail: error.message,
      );
    }

    if (error is TimeoutException) {
      return TimeoutFailure(rawDetail: error.message);
    }

    if (error is HttpException) {
      final msg = error.message;
      if (msg.contains('403')) {
        return HttpFailure(statusCode: 403, rawDetail: msg);
      }
      if (msg.contains('404')) {
        return HttpFailure(statusCode: 404, rawDetail: msg);
      }
      final match = RegExp(r'\b(5\d\d)\b').firstMatch(msg);
      if (match != null) {
        return HttpFailure(
          statusCode: int.parse(match.group(1)!),
          rawDetail: msg,
        );
      }
      if (msg.contains('Server file changed') || msg.contains('ETag')) {
        return FileChangedOnServerFailure(rawDetail: msg);
      }
      return UnknownFailure(rawDetail: msg);
    }

    final str = error.toString().toLowerCase();
    if (str.contains('diskspace') ||
        str.contains('no space') ||
        str.contains('enospc') ||
        str.contains('storage space')) {
      return StorageFullFailure(rawDetail: error.toString());
    }

    if (str.contains('etag') || str.contains('server file changed')) {
      return FileChangedOnServerFailure(rawDetail: error.toString());
    }

    return UnknownFailure(rawDetail: error.toString());
  }

  static DownloadFailureCode mapException(Object? error) {
    return fromException(error).code;
  }

  static String cleanErrorMessage(Object? error, {bool isArabic = false}) {
    return mapException(error).localizedMessage(isArabic: isArabic);
  }
}
