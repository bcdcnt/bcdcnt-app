import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/auth_dialogs.dart';

/// Turns any exception into a short Vietnamese sentence an older listener
/// can act on — never "ClientException: Failed host lookup…".
/// Messages the server already wrote in Vietnamese are passed through.
String friendlyError(Object e, {String fallback = 'Có lỗi xảy ra, vui lòng thử lại.'}) {
  if (e is TimeoutException) return 'Mạng chậm quá, vui lòng thử lại.';
  if (e is SocketException || e is HandshakeException) {
    return 'Không có kết nối mạng, kiểm tra rồi thử lại.';
  }
  var msg = e.toString().replaceFirst(RegExp(r'^(Exception|ClientException|HttpException):\s*'), '').trim();
  final low = msg.toLowerCase();
  if (low.contains('failed host lookup') || low.contains('socket') || low.contains('connection') || low.contains('network')) {
    return 'Không có kết nối mạng, kiểm tra rồi thử lại.';
  }
  if (low.contains('unauthenticated')) return 'Phiên đăng nhập đã hết, vui lòng đăng nhập lại.';
  if (low.contains('unauthorized') || low.contains('forbidden')) return 'Bạn không có quyền thực hiện thao tác này.';
  // Keep server messages that are already Vietnamese (have diacritics) and short.
  final looksVietnamese = RegExp(r'[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]', caseSensitive: false).hasMatch(msg);
  if (looksVietnamese && msg.length <= 160) return msg;
  return fallback;
}

/// One way to ask a guest to log in: opens the login dialog directly instead
/// of a snackbar that leaves them nowhere to go.
Future<void> askLogin(BuildContext context) =>
    showDialog(context: context, useRootNavigator: true, builder: (_) => const LoginDialog());
