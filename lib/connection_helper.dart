import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:singleton/singleton.dart';

class ConnectionHelper {
  factory ConnectionHelper() =>
      Singleton.lazy(() => ConnectionHelper._privateConstructor());
  ConnectionHelper._privateConstructor();
  static ConnectionHelper shared = ConnectionHelper();

  static final _stateSubscriptions =
      <StreamSubscription<List<ConnectivityResult>>>[];
  static final _internetSubscriptions =
      <StreamSubscription<InternetConnectionStatus>>[];

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
    return await (InternetConnectionChecker.createInstance(
      checkTimeout: timeoutInSeconds != null
          ? Duration(seconds: timeoutInSeconds)
          : InternetConnectionCheckerConstants.DEFAULT_TIMEOUT,
    )).hasConnection;
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
    final subscription = InternetConnectionChecker.createInstance(
      checkInterval: Duration(seconds: delayedInSeconds),
      checkTimeout: Duration(seconds: timeoutInSeconds),
    ).onStatusChange.listen((event) {
      listener(event == InternetConnectionStatus.connected);
    });
    _internetSubscriptions.add(subscription);
  }

  /// Unlisten to the internet connection status changes
  void unlistenInternetChanged() {
    _internetSubscriptions.forEach((sub) {
      sub.cancel();
    });
  }

  /// Clear all the state subscriptions
  void clearStateSubscriptions() {
    _stateSubscriptions.clear();
  }

  /// Clear all the internet subscriptions
  void clearInternetSubscriptions() {
    _internetSubscriptions.clear();
  }
}
