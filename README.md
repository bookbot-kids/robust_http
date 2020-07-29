# robust_http

A robust http Flutter package base on [dio](https://pub.dev/packages/dio).

## Getting Started

This project is a starting point for a Dart
[package](https://flutter.dev/developing-packages/),
a library module containing code that can be shared easily across
multiple Flutter or Dart projects.

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Usage
```
var http = HTTP('https://httpstat.us/',
          {"connectTimeout": 3000, "receiveTimeout": 3000});
var response = await http.get('200'); // success response
```