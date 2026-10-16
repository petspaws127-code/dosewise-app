import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../db/database.dart';
import '../db/models.dart';
import 'ad_config.dart';

/// Where an interstitial is allowed to appear (spec §5, locked):
/// a positive moment, max once per calendar day.
enum InterstitialTrigger { allDone, medAdded }

/// Central AdMob manager. Implements the founder's locked ad-UX bar:
/// - Banner: Today tab ONLY (see [DoseWiseBanner]).
/// - Interstitial: max 1/day, only at a positive moment.
/// - Rewarded: opt-in only; the promised action ALWAYS runs, even if the
///   ad fails to load or is dismissed (never punish the user).
class AdService {
  AdService._(this._db);
  final AppDatabase _db;

  static AdService? _instance;
  static AdService get instance => _instance!;

  bool _rewardedLoading = false;

  static Future<void> init(AppDatabase db) async {
    AdConfig.assertConsistent();
    _instance = AdService._(db);
    await MobileAds.instance.initialize();
  }

  // ---------- interstitial ----------

  /// Shows an interstitial only if today's cap hasn't been hit.
  /// Returns true when an ad was actually shown.
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger) async {
    final today = dateKey(DateTime.now());
    final shown = await _db.metaGet(AppDatabase.kInterstitialShownDate);
    if (shown == today) return false; // cap: 1/day, already shown

    final ad = await _loadInterstitial();
    if (ad == null) return false;

    var shownOk = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => shownOk = true,
      onAdDismissedFullScreenContent: (a) => a.dispose(),
      onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
    );
    await ad.show();
    // Stamp the cap even if show failed — one attempt per day is the
    // annoyance budget, and a failed show must not retry-bomb the user.
    await _db.metaSet(AppDatabase.kInterstitialShownDate, today);
    debugPrint('interstitial trigger: ${trigger.name}');
    return shownOk;
  }

  Future<InterstitialAd?> _loadInterstitial() {
    final done = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => done.complete(ad),
        onAdFailedToLoad: (error) {
          debugPrint('interstitial load failed: $error');
          done.complete(null);
        },
      ),
    );
    return done.future;
  }

  // ---------- rewarded (opt-in) ----------

  /// Shows a rewarded ad; [proceed] ALWAYS runs — on reward earned, on
  /// dismiss, and on load failure. The user is never punished for ad
  /// failure (spec §5). [proceed] is awaited; callers wrap their body in
  /// try/finally so their busy flags always reset.
  Future<void> showRewardedOrElse(
      Future<void> Function() proceed) async {
    final ad = await _loadRewarded();
    if (ad == null) {
      await proceed(); // ad failed to load → generate anyway
      return;
    }
    var proceeded = false;
    Future<void> done() async {
      if (!proceeded) {
        proceeded = true;
        await proceed();
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        done(); // dismissed early → still generate
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        done();
      },
    );
    ad.show(
      onUserEarnedReward: (ad, reward) => done(),
    );
    // Safety: if neither callback fires (shouldn't happen), don't hang.
    Future.delayed(const Duration(seconds: 90), done);
  }

  Future<RewardedAd?> _loadRewarded() {
    if (_rewardedLoading) return Future.value(null);
    _rewardedLoading = true;
    final done = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          done.complete(ad);
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          debugPrint('rewarded load failed: $error');
          done.complete(null);
        },
      ),
    );
    return done.future;
  }
}

/// Anchored adaptive banner for the Today tab ONLY (spec §5).
/// Hidden by the caller when the med list is empty / onboarding, and
/// behind dialogs/sheets via [visible]. Reserves its slot while loading
/// so the list doesn't jump when the ad arrives.
class DoseWiseBanner extends StatefulWidget {
  const DoseWiseBanner({super.key, this.visible = true});
  final bool visible;

  @override
  State<DoseWiseBanner> createState() => _DoseWiseBannerState();
}

class _DoseWiseBannerState extends State<DoseWiseBanner> {
  BannerAd? _ad;
  AdSize? _size;
  bool _loading = true;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad != null) return;
    _load();
  }

  Future<void> _load() async {
    final width = MediaQuery.of(context).size.width.truncate();
    final orientation = MediaQuery.of(context).orientation;
    final size =
        await AdSize.getAnchoredAdaptiveBannerAdSize(orientation, width);
    if (size == null || !mounted) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    setState(() => _size = size);
    _ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('banner load failed: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _failed = true;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || _failed) return const SizedBox.shrink();
    final size = _size;
    final ad = _ad;
    if (_loading || size == null || ad == null) {
      // Reserved slot while loading — no content jump on arrival.
      return const SizedBox(height: 64);
    }
    return SizedBox(
      width: size.width.toDouble(),
      height: size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
