import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/firebase_sync_hash.dart';

void main() {
  test(
    'sync digests ignore map insertion order and integral double spelling',
    () {
      expect(
        firebaseSyncHash({
          'state': {'b': 2.0, 'a': 1},
          'items': [
            3.0,
            {'y': true, 'x': 'v'},
          ],
        }),
        firebaseSyncHash({
          'items': [
            3,
            {'x': 'v', 'y': true},
          ],
          'state': {'a': 1.0, 'b': 2},
        }),
      );
    },
  );

  test('sync digests change when any mutation data changes', () {
    expect(
      firebaseSyncHash({
        'revision': 4,
        'state': {'xp': 12},
      }),
      isNot(
        firebaseSyncHash({
          'revision': 4,
          'state': {'xp': 13},
        }),
      ),
    );
  });
}
