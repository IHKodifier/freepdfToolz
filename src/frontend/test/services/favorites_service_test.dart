import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freepdftoolz_frontend/services/favorites_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FavoritesService.init();
  });

  test('FavoritesService initial state is empty', () {
    expect(FavoritesService.getFavorites(), isEmpty);
    expect(FavoritesService.isFavorite('merge'), isFalse);
  });

  test(
    'FavoritesService toggles favorite and persists to SharedPreferences',
    () async {
      expect(FavoritesService.isFavorite('merge'), isFalse);

      await FavoritesService.toggleFavorite('merge');
      expect(FavoritesService.isFavorite('merge'), isTrue);
      expect(FavoritesService.getFavorites(), contains('merge'));

      // Toggle off
      await FavoritesService.toggleFavorite('merge');
      expect(FavoritesService.isFavorite('merge'), isFalse);
      expect(FavoritesService.getFavorites(), isNot(contains('merge')));
    },
  );

  test('FavoritesService notifies listeners when favorites change', () async {
    final notifications = <Set<String>>[];
    FavoritesService.favoritesNotifier.addListener(() {
      notifications.add(
        Set<String>.from(FavoritesService.favoritesNotifier.value),
      );
    });

    await FavoritesService.toggleFavorite('split');
    await FavoritesService.toggleFavorite('compress');

    expect(notifications.length, 2);
    expect(notifications.last, containsAll(['split', 'compress']));
  });

  test('FavoritesService loads existing persisted values', () async {
    SharedPreferences.setMockInitialValues({
      FavoritesService.prefsKey: ['rotate', 'watermark'],
    });

    await FavoritesService.init();

    expect(FavoritesService.isFavorite('rotate'), isTrue);
    expect(FavoritesService.isFavorite('watermark'), isTrue);
    expect(FavoritesService.isFavorite('merge'), isFalse);
  });
}
