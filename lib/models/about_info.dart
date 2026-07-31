import '../build_info.dart';

/// 关于页面的应用信息
class AboutInfo {
  final String version;
  final String buildTimeString;

  const AboutInfo({
    required this.version,
    required this.buildTimeString,
  });

  factory AboutInfo.load() {
    return AboutInfo(
      version: '',
      buildTimeString: buildTime.isNotEmpty ? buildTime : 'unknown',
    );
  }

  AboutInfo copyWith({String? version, String? buildTimeString}) {
    return AboutInfo(
      version: version ?? this.version,
      buildTimeString: buildTimeString ?? this.buildTimeString,
    );
  }

  bool get hasVersion => version.isNotEmpty;
}
