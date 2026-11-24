String? formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  final gigabytes = bytes / gb;
  if (gigabytes >= 1) {
    return '${gigabytes >= 10 ? gigabytes.toStringAsFixed(0) : gigabytes.toStringAsFixed(1)} GB';
  }
  final megabytes = (bytes / mb).round();
  return '${megabytes < 1 ? 1 : megabytes} MB';
}

String? formatClock(int? milliseconds) {
  if (milliseconds == null || milliseconds < 1000) return null;
  return formatRuntime((milliseconds / 1000).round() ~/ 60);
}

String? formatRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return hours > 0 ? '$hours ชม. $rest นาที' : '$rest นาที';
}
