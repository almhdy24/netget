import 'dart:async';
import 'dart:io';

/// Standard failure codes for download operations.
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

  /// Plain, localized, human-friendly explanation of the failure.
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

/// Centralized mapper that converts runtime exceptions into [DownloadFailureCode].
class DownloadFailureMapper {
  static DownloadFailureCode mapException(dynamic error) {
    if (error == null) return DownloadFailureCode.unknown;

    // Check FileSystemException / disk full
    if (error is FileSystemException) {
      if (error.osError?.errorCode == 28 ||
          error.message.toLowerCase().contains('no space') ||
          (error.osError?.message.toLowerCase().contains('no space') ?? false)) {
        return DownloadFailureCode.storageFull;
      }
    }

    if (error is TimeoutException) {
      return DownloadFailureCode.timeout;
    }

    if (error is SocketException) {
      final msg = (error.osError?.message ?? error.message).toLowerCase();
      if (msg.contains('refused') || error.osError?.errorCode == 111) {
        return DownloadFailureCode.serverRefused;
      }
      return DownloadFailureCode.noConnection;
    }

    if (error is HttpException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('403')) return DownloadFailureCode.http403;
      if (msg.contains('404')) return DownloadFailureCode.http404;
      if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
        return DownloadFailureCode.serverError;
      }
    }

    // Inspect string pattern for custom exceptions, e.g. DiskSpaceException
    final str = error.toString().toLowerCase();
    if (str.contains('diskspaceexception') ||
        str.contains('no space') ||
        str.contains('enospc') ||
        str.contains('storage is full') ||
        str.contains('disk is full')) {
      return DownloadFailureCode.storageFull;
    }

    if (str.contains('etag mutated') ||
        str.contains('file changed') ||
        str.contains('range not satisfiable') ||
        str.contains('416')) {
      return DownloadFailureCode.fileChangedOnServer;
    }

    if (str.contains('refused') || str.contains('connection refused')) {
      return DownloadFailureCode.serverRefused;
    }

    if (str.contains('timed out') || str.contains('timeout')) {
      return DownloadFailureCode.timeout;
    }

    if (str.contains('403') || str.contains('forbidden')) {
      return DownloadFailureCode.http403;
    }

    if (str.contains('404') || str.contains('not found')) {
      return DownloadFailureCode.http404;
    }

    if (str.contains('network is unreachable') ||
        str.contains('no route to host') ||
        str.contains('failed host lookup') ||
        str.contains('no connection')) {
      return DownloadFailureCode.noConnection;
    }

    if (str.contains('500') ||
        str.contains('502') ||
        str.contains('503') ||
        str.contains('server error')) {
      return DownloadFailureCode.serverError;
    }

    return DownloadFailureCode.unknown;
  }

  /// Formats a user-friendly error string based on the detected code.
  static String cleanErrorMessage(dynamic error, {bool isArabic = false}) {
    final code = mapException(error);
    return code.localizedMessage(isArabic: isArabic);
  }
}
