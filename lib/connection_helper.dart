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

  static final _stateSubscriptions =
      <StreamSubscription<List<ConnectivityResult>>>[];
  static final _internetSubscriptions =
      <StreamSubscription<InternetStatus>>[];
  static final _internetCheckers = <InternetConnection>[];

  /// The default endpoints used by `internet_connection_checker_plus`,
  /// rebuilt with a custom [timeout] because the package keeps its own
  /// default option list private.
  static List<InternetCheckOption> _checkOptions(Duration timeout) => [
        InternetCheckOption(
            uri: Uri.parse('https://one.one.one.one'), timeout: timeout),
        InternetCheckOption(
            uri: Uri.parse('https://icanhazip.com'), timeout: timeout),
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
    return (await Connectivity().checkConnectivity())
        .any((status) => status == ConnectivityResult.wifi);
  }

  Future<bool> hasMobileConnection() async {
    return (await Connectivity().checkConnectivity())
        .any((status) => status == ConnectivityResult.mobile);
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
  void listenStateChanged(void Function(bool) listener) {
    final subscription =
        Connectivity().onConnectivityChanged.listen((statuses) {
      final isConnected = statuses.any((status) {
        return status == ConnectivityResult.wifi ||
            status == ConnectivityResult.mobile ||
            status == ConnectivityResult.ethernet;
      });

      listener(isConnected);
    });
    _stateSubscriptions.add(subscription);
  }

  /// Unlisten to the connection status changes
  void unlistenStateChanged() {
    _stateSubscriptions.forEach((sub) {
      sub.cancel();
    });
  }

  /// Listen to the internet connection status changes
  void listenInternetChanged(void Function(bool) listener,
      {int delayedInSeconds = 60, int timeoutInSeconds = 10}) {
    if (kIsWeb) return;
    final checker = InternetConnection.createInstance(
      checkInterval: Duration(seconds: delayedInSeconds),
      useDefaultOptions: false,
      customCheckOptions: _checkOptions(Duration(seconds: timeoutInSeconds)),
    );
    final subscription = checker.onStatusChange.listen((event) {
      listener(event == InternetStatus.connected);
    });
    _internetCheckers.add(checker);
    _internetSubscriptions.add(subscription);
  }

  /// Unlisten to the internet connection status changes
  void unlistenInternetChanged() {
    _internetSubscriptions.forEach((sub) {
      sub.cancel();
    });
    _internetCheckers.forEach((checker) {
      checker.dispose();
    });
  }

  /// Clear all the state subscriptions
  void clearStateSubscriptions() {
    _stateSubscriptions.clear();
  }

  /// Clear all the internet subscriptions
  void clearInternetSubscriptions() {
    _internetSubscriptions.clear();
    _internetCheckers.clear();
  }
}
