import 'package:intl/intl.dart';

// The text in these exceptions are for public facing modals.
class UnknownException implements Exception {
  String devDescription;
  UnknownException(this.devDescription);
  String toString() => devDescription.isNotEmpty == true
      ? 'Error $devDescription'
      : Intl.message("We're unsure what happened, but we're looking into it.",
          name: 'unknownException');
}

class ConnectivityException implements Exception {
  final String? message;
  final bool hasConnectionStatus;

  ConnectivityException(this.message, {this.hasConnectionStatus = false});

  String toString() =>
      message ??
      Intl.message('You are not connected to the internet at this time.',
          name: 'notConnected');
}

class RetryFailureException implements Exception {
  String toString() => Intl.message(
      'There is a problem with the internet connection, please retry later.',
      name: 'retryFailure');
}

class UnexpectedResponseException implements Exception {
  String url;
  int statusCode;
  String errorMessage;
  dynamic data;

  UnexpectedResponseException(this.url, this.statusCode, this.errorMessage,
      {this.data});
  String toString() =>
      'Request error [$statusCode] at $url, message: $errorMessage, data: $data';
}

class SyncDataException implements Exception {
  dynamic response;
  SyncDataException(this.response);
  String toString() => Intl.message(
      'There was an error while syncing data. Please try again later.',
      name: 'syncDataFailure');
}

class NetworkTimeoutException implements Exception {
  String errorMessage;
  NetworkTimeoutException(this.errorMessage);
  String toString() => errorMessage.isNotEmpty
      ? errorMessage
      : Intl.message('The request timed out, please try again later.',
          name: 'networkTimeout');
}
