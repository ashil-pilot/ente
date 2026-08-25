import "package:flutter_test/flutter_test.dart";
import "package:photos/core/configuration.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  test("normal and automatic logout reset Search before other work", () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    for (final autoLogout in [false, true]) {
      final stopAfterReset = StateError("stop after Search reset");
      var resetCount = 0;
      final configuration = Configuration.forTesting(
        preferences: preferences,
        resetSearchForAccountBoundary: () {
          resetCount++;
          throw stopAfterReset;
        },
      );

      await expectLater(
        configuration.logout(autoLogout: autoLogout),
        throwsA(same(stopAfterReset)),
      );
      expect(resetCount, 1, reason: "autoLogout=$autoLogout");
    }
  });

  test("changing account identity resets Search exactly once", () async {
    SharedPreferences.setMockInitialValues({Configuration.userIDKey: 41});
    final preferences = await SharedPreferences.getInstance();
    var resetCount = 0;
    final configuration = Configuration.forTesting(
      preferences: preferences,
      resetSearchForAccountBoundary: () => resetCount++,
    );

    await configuration.setUserID(41);
    expect(resetCount, 0);

    await configuration.setUserID(42);
    expect(resetCount, 1);
    expect(configuration.getUserID(), 42);
  });
}
