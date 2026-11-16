import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/library/library_model.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:chai_editor/main.dart';
import 'package:chai_editor/widgets/sidebar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native profile: 100 cached note switches and ten sidebar cycles',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('chai-profile-')))!;
    final service = LibraryService(root);
    final paths = <String>[];
    await tester.runAsync(() async {
      await service.initialize();
      for (var i = 0; i < 5; i++) {
        final path = await service.create(service.root, name: 'Profile $i');
        await service.writeNote(path,
            '# Note $i\n\n${'A paragraph of profile test content. ' * 100}');
        paths.add(path);
      }
    });
    await tester.pumpWidget(ChaiEditorApp(libraryService: service));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(LibrarySidebar).evaluate().isNotEmpty &&
          find.text('Welcome').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(LibrarySidebar), findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join(' | '));
    final model = Provider.of<LibraryModel>(
        tester.element(find.byType(LibrarySidebar)),
        listen: false);
    await tester.runAsync(() async {
      for (final path in paths) {
        await model.preload(path);
      }
    });
    final cold = (await tester.runAsync(() async {
      final path = await service.create(service.root, name: 'Cold 100KB');
      await service.writeNote(path,
          '# Cold note\n\n${'A representative paragraph for a cold load.\n\n' * 2200}');
      return path;
    }))!;
    final coldClock = Stopwatch()..start();
    await tester.runAsync(() => model.open(cold));
    await tester.pump();
    final coldLatency = coldClock.elapsedMicroseconds / 1000;
    await model.open(paths.first);
    await tester.pumpAndSettle();
    final latencies = <int>[];
    final edits = <String, List<String>>{};
    await binding.watchPerformance(() async {
      for (var i = 0; i < 100; i++) {
        final tab = model.current!;
        final token = 'edit-$i ';
        edits.putIfAbsent(tab.filePath!, () => []).add(token);
        await tab.editorState.apply(tab.editorState.transaction
          ..insertText(tab.editorState.document.first!, 0, token));
        final clock = Stopwatch()..start();
        await model.open(paths[i % 5]);
        await tester.pump();
        latencies.add(clock.elapsedMicroseconds);
        expect(find.byType(AppFlowyEditor), findsOneWidget);
      }
    }, reportKey: 'switching');
    latencies.sort();
    binding.reportData!['cold_load_ms'] = coldLatency;
    binding.reportData!['latency_ms'] = {
      'median': latencies[50] / 1000,
      'p95': latencies[95] / 1000,
      'max': latencies.last / 1000
    };
    await tester.runAsync(() async {
      await model.flush();
      await model.saveState();
      for (final entry in edits.entries) {
        final text = await service.readNote(entry.key);
        for (final token in entry.value) {
          expect(text, contains(token));
        }
      }
    });
    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        model.toggle();
        await tester.pumpAndSettle();
      }
    }, reportKey: 'sidebar');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
