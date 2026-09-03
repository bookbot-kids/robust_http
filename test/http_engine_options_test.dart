import 'package:flutter_test/flutter_test.dart';
import 'package:robust_http/engine/http_engine.dart';

void main() {
  group('engine selection', () {
    test('defaults to dart:io so no existing caller changes stack', () {
      expect(const HttpEngineOptions().engine, HttpEngine.dartIo);
      expect(HttpEngine.fromString(null), HttpEngine.dartIo);
      expect(HttpEngine.fromString('nonsense'), HttpEngine.dartIo);
    });

    test('reads the names callers actually pass', () {
      expect(HttpEngine.fromString('auto'), HttpEngine.auto);
      expect(HttpEngine.fromString('native'), HttpEngine.native);
      expect(HttpEngine.fromString('dartIo'), HttpEngine.dartIo);
      expect(HttpEngine.fromString(' NATIVE '), HttpEngine.native);
    });
  });

  group('cache mode', () {
    test('an option map without the new keys behaves exactly as before', () {
      final legacy = HttpEngineOptions.fromMap({'httpEngine': 'auto'});
      expect(legacy.effectiveCacheMode, NativeCacheMode.disabled);
      expect(legacy.quicHints, isEmpty);
      expect(legacy.nativeStoragePath, isNull);

      final withBytes = HttpEngineOptions.fromMap({'nativeCacheBytes': 4096});
      expect(withBytes.effectiveCacheMode, NativeCacheMode.memory);
    });

    test('an explicit mode wins over the byte-count derivation', () {
      final options = HttpEngineOptions.fromMap({
        'nativeCacheBytes': 4096,
        'nativeCacheMode': 'diskNoHttp',
      });
      expect(options.effectiveCacheMode, NativeCacheMode.diskNoHttp);
      expect(options.effectiveCacheMode.needsStoragePath, isTrue);
    });

    test('only the disk modes ask for a storage path', () {
      expect(NativeCacheMode.disabled.needsStoragePath, isFalse);
      expect(NativeCacheMode.memory.needsStoragePath, isFalse);
      expect(NativeCacheMode.diskNoHttp.needsStoragePath, isTrue);
      expect(NativeCacheMode.disk.needsStoragePath, isTrue);
    });

    test('an unreadable mode name falls back to the derivation, not a throw',
        () {
      final options = HttpEngineOptions.fromMap({'nativeCacheMode': 'wat'});
      expect(options.nativeCacheMode, isNull);
      expect(options.effectiveCacheMode, NativeCacheMode.disabled);
    });
  });

  group('quic hints', () {
    test('are read from a list and cleaned of blanks', () {
      final options = HttpEngineOptions.fromMap({
        'quicHints': ['books.bookbotkids.com', '  ', 'www.bookbotkids.com'],
      });
      expect(options.quicHints,
          ['books.bookbotkids.com', 'www.bookbotkids.com']);
    });

    test('a value that is not a list is ignored rather than fatal', () {
      expect(
          HttpEngineOptions.fromMap({'quicHints': 'books.bookbotkids.com'})
              .quicHints,
          isEmpty);
    });
  });
}
