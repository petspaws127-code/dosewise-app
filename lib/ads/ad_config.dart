/// AdMob configuration — GOOGLE'S OFFICIAL TEST IDs ONLY.
///
/// ⚠️ DO NOT SHIP REAL AD UNIT IDs FROM A DEV MACHINE BY ACCIDENT.
/// The founder creates their own AdMob account later and pastes the real
/// IDs here before the Play Store release build.
///
/// TODO(PLAY-RELEASE): replace the four IDs below with the real IDs from the
///   founder's AdMob console (Apps → Ad units → banner / interstitial /
///   rewarded), set [useTestIds] = false, and update the APPLICATION_ID
///   meta-data in android/app/src/main/AndroidManifest.xml to the real App ID.
///   Then rebuild. Test ads show a "Test Ad" label; real ads must NEVER be
///   clicked by the developers/testers (policy violation).
class AdConfig {
  /// Google's official sample App ID (Android). Test only.
  static const String androidAppId =
      'ca-app-pub-3940256099942544~3347511713';

  /// Google's official sample banner unit. Test only.
  static const String bannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  /// Google's official sample interstitial unit. Test only.
  static const String interstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  /// Google's official sample rewarded unit. Test only.
  static const String rewardedUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// Must be true until the PLAY-RELEASE TODO above is done.
  static const bool useTestIds = true;

  /// Safety net: refuse to build release artifacts with test IDs once the
  /// founder flips this file to production.
  static void assertConsistent() {
    assert(
      !useTestIds ||
          androidAppId.contains('3940256099942544'),
      'AdConfig: useTestIds=true but IDs do not look like Google test IDs',
    );
  }
}
