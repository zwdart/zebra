import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/feedback_service.dart';

/// 反馈页面状态管理
class FeedbackProvider extends ChangeNotifier {
  bool _isSubmitting = false;

  bool get isSubmitting => _isSubmitting;

  /// 提交反馈
  Future<bool> submitFeedback({
    required String email,
    required String subject,
    required String description,
    required BuildContext context,
  }) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    notifyListeners();

    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Theme.of(context).platform.name;

      final result = await FeedbackService.submitFeedback(
        email: email,
        subject: subject,
        description: description,
        platform: platform,
        appVersion: info.version,
      );

      if (result['success'] == true) {
        _isSubmitting = false;
        notifyListeners();
        return true;
      } else {
        final error = result['error'] as String? ?? 'Unknown error';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.feedbackSubmitFailed}: $e')),
        );
      }
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
    return false;
  }
}
