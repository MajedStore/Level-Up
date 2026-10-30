import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/home_widget_service.dart';

void main() {
  testWidgets('closing the store cancels deferred widget data reads', (
    tester,
  ) async {
    var reads = 0;
    HomeWidgetService.syncSoon(() {
      reads++;
      throw StateError('The backing store is closed');
    });
    HomeWidgetService.cancelPendingSync();

    // Advance the scheduler deterministically past the debounce deadline.
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });
}
