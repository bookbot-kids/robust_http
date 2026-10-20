import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:singleton/singleton.dart';

class ConnectionHelper {
  factory ConnectionHelper() =>
      Singleton.lazy(() => ConnectionHelper._privateConstructor());
  ConnectionHelper._privateConstructor();
  static ConnectionHelper shared = ConnectionHelper();

  /// Stream injection keeps listener ownership testable without platform I/O.
  @visibleForTesting
  ConnectionHelper.forTesting({
    required Stream<List<ConnectivityResult>> stateChanges,
    required Stream<InternetStatus> internetChanges,
  }) : _testStateChanges = stateChanges,
       _testInternetChanges = internetChanges;

  Stream<List<ConnectivityResult>>? _testStateChanges;
  Stream<InternetStatus>? _testInternetChanges;
  final _stateSubscriptions =
      <Object?, List<StreamSubscription<List<ConnectivityResult>>>>{};
  final _internetSubscriptions =
      <Object?, List<StreamSubscription<InternetStatus>>>{};
  final _internetCheckers = <Object?, List<InternetConnection>>{};

  /// The default endpoints used by `internet_connection_checker_plus`,
  /// rebuilt with a custom [timeout] because the package keeps its own
  /// default option list private.
  static List<InternetCheckOption> _checkOptions(Duration timeout) => [
    InternetCheckOption(
      uri: Uri.parse('https://one.one.one.one'),
      timeout: timeout,
    ),
    InternetCheckOption(
      uri: Uri.parse('https://icanhazip.com'),
      timeout: timeout,
    ),
    InternetCheckOption(
      uri: Uri.parse(
        'https://ajax.googleapis.com/ajax/libs/jquery/3.7.1/jquery.min.js',
      ),
      timeout: timeout,
    ),
    InternetCheckOption(
      uri: Uri.parse('https://captive.apple.com/internet-check'),
      timeout: timeout,
    ),
  ];

  /// Whether the device has any connection status. By default does not include bluetooth in the check
  Future<bool> hasConnection({bool includeBluetooth = false}) async {
    final statuses = await Connectivity().checkConnectivity();
    return statuses.any((status) {
      return status == ConnectivityResult.wifi ||
          status == ConnectivityResult.mobile ||
          status == ConnectivityResult.ethernet ||
          (includeBluetooth && status == ConnectivityResult.bluetooth);
    });
  }

  Future<bool> hasWifiConnection() async {
    return (await Connectivity().checkConnectivity()).any(
      (status) => status == ConnectivityResult.wifi,
    );
  }

  /// Pack downloads are allowed on Wi-Fi and wired desktop connections.
  Future<bool> hasWifiOrEthernetConnection() async =>
      allowsPackDownloads(await Connectivity().checkConnectivity());

  static bool allowsPackDownloads(List<ConnectivityResult> statuses) =>
      statuses.contains(ConnectivityResult.wifi) ||
      statuses.contains(ConnectivityResult.ethernet);

  Future<bool> hasMobileConnection() async {
    return (await Connectivity().checkConnectivity()).any(
      (status) => status == ConnectivityResult.mobile,
    );
  }

  /// Whether the device has any internet connection
  Future<bool> hasInternetConnection({int? timeoutInSeconds}) async {
    if (kIsWeb) return true;
    if (timeoutInSeconds == null) {
      return await InternetConnection().hasInternetAccess;
    }

    final checker = InternetConnection.createInstance(
      useDefaultOptions: false,
      customCheckOptions: _checkOptions(Duration(seconds: timeoutInSeconds)),
    );
    try {
      return await checker.hasInternetAccess;
    } finally {
      await checker.dispose();
    }
  }

  /// Listen to the connection status changes
  void listenStateChanged(void Function(bool) listener, {Object? owner}) {
    final subscription =
        (_testStateChanges ?? Connectivity().onConnectivityChanged).listen((
          statuses,
        ) {
          final isConnected = statuses.any((status) {
            return status == ConnectivityResult.wifi ||
                status == ConnectivityResult.mobile ||
                status == ConnectivityResult.ethernet;
          });

          listener(isConnected);
        });
    _stateSubscriptions.putIfAbsent(owner, () => []).add(subscription);
  }

  /// Cancels only this owner's listeners. Legacy callers use the null owner;
  /// they cannot remove explicitly owned download or other feature listeners.
  void unlistenStateChanged({Object? owner}) {
    for (final sub in _stateSubscriptions.remove(owner) ?? []) {
      unawaited(sub.cancel());
    }
  }

  /// Each caller supplies its own owner token and cancels only that token.
  void listenInternetChanged(
    void Function(bool) listener, {
    int delayedInSeconds = 60,
    int timeoutInSeconds = 10,
    Object? owner,
  }) {
    if (kIsWeb && _testInternetChanges == null) return;
    final checker = _testInternetChanges == null
        ? InternetConnection.createInstance(
            checkInterval: Duration(seconds: delayedInSeconds),
            useDefaultOptions: false,
            customCheckOptions: _checkOptions(
              Duration(seconds: timeoutInSeconds),
            ),
          )
        : null;
    final subscription = (_testInternetChanges ?? checker!.onStatusChange)
        .listen((event) {
          listener(event == InternetStatus.connected);
        });
    if (checker != null) {
      _internetCheckers.putIfAbsent(owner, () => []).add(checker);
    }
    _internetSubscriptions.putIfAbsent(owner, () => []).add(subscription);
  }

  void unlistenInternetChanged({Object? owner}) {
    for (final sub in _internetSubscriptions.remove(owner) ?? []) {
      unawaited(sub.cancel());
    }
    for (final checker in _internetCheckers.remove(owner) ?? []) {
      unawaited(checker.dispose());
    }
  }

  /// Clearing also releases resources, rather than orphaning live listeners.
  void clearStateSubscriptions({Object? owner}) =>
      unlistenStateChanged(owner: owner);
  void clearInternetSubscriptions({Object? owner}) =>
      unlistenInternetChanged(owner: owner);
}
