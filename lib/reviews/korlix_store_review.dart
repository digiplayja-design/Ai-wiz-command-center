import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Matches applicationId in android/app/build.gradle.kts. A public listing may
/// be unavailable until the app is released in the visitor's region.
const korlixGooglePlayListingUrl =
    'https://play.google.com/store/apps/details?id=com.korlixdeveloper.korlixai';

// No App Store product URL is exposed until its numeric product ID is verified.
// The native StoreKit API uses the installed app's identity and needs no URL.
const _reviewChannel = MethodChannel('korlix/store_review');
bool _requestPending = false;

/// Requests the store's own review UI at an automatic, neutral stopping point.
///
/// A true result means the native API accepted the request, never that a prompt
/// was displayed or that the member submitted a review. Store quotas, account
/// eligibility and TestFlight can suppress it. Unsupported platforms, older
/// builds without this bridge, native errors and unconfirmed timeouts return
/// false without opening a browser or interrupting the user's normal flow.
Future<bool> requestKorlixStoreReview() async {
  if (kIsWeb ||
      _requestPending ||
      ![
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform)) {
    return false;
  }
  _requestPending = true;
  try {
    return await _reviewChannel
            .invokeMethod<bool>('requestReview')
            .timeout(const Duration(minutes: 2), onTimeout: () => false) ==
        true;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  } catch (_) {
    // A malformed response from an older bridge is unavailable, not success.
    return false;
  } finally {
    _requestPending = false;
  }
}

/// Invalidates an Android request still preparing when the home screen becomes
/// unsafe. Never removes a review card already displayed by the store.
Future<void> cancelKorlixStoreReviewRequest() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _reviewChannel.invokeMethod<void>('cancelPendingReview');
  } catch (_) {
    // Older app versions and unavailable native services need no cleanup.
  }
}
