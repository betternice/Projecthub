/// Public Application (client) ID for Niceflix / Projecthub.
/// Safe to ship in the app (public client). Do not put client secrets here.
const String kAzureClientId = '8948bc77-ce24-441c-bd55-d1f5fec140b4';

/// Shown in errors when SPA redirect URI is missing in Azure.
const String kAzureSpaRedirectHint =
    'http://localhost:8080/ และ https://niceflix-ten.vercel.app/ (Platform: Single-page application)';

/// Exact redirect URI for the current web origin (must match Azure SPA entry).
String webRedirectUri() {
  final base = Uri.base;
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/',
  ).toString();
}
