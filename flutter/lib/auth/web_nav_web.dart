// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void navigateToExternal(String url) {
  html.window.location.assign(url);
}

void replaceBrowserUrl(String url) {
  html.window.history.replaceState(null, '', url);
}
