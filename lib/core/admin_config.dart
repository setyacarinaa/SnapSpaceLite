class AdminConfig {
  // System admin credentials used for bootstrapping only.
  // For production, consider moving these to secure storage or remote config.
  static const String systemAdminEmail = 'adminsnapspacelite29@gmail.com';
  static const String systemAdminPassword = 'adminku290925';
  // Base URL for Cloud Functions HTTP endpoints (no trailing slash).
  // e.g. https://us-central1-YOUR_PROJECT.cloudfunctions.net
  // Set this after you deploy functions, or leave empty to use direct client deletes (may fail if rules deny).
  static const String functionBaseUrl = '';
}
