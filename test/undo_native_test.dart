import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:chai_editor/main.dart';
import 'package:chai_editor/toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'both text input clients dispatch native undo/redo even without text state',
      () {
    var undo = 0;
    var redo = 0;
    final delta = DeltaTextInputService(
        onUndo: () => undo++,
        onRedo: () => redo++,
        onInsert: (_) async => true,
        onDelete: (_) async => true,
        onReplace: (_) async => true,
        onNonTextUpdate: (_) async => true,
        onPerformAction: (_) async {});
    final nonDelta = NonDeltaTextInputService(
        onUndo: () => undo++,
        onRedo: () => redo++,
        onInsert: (_) async => true,
        onDelete: (_) async => true,
        onReplace: (_) async => true,
        onNonTextUpdate: (_) async => true,
        onPerformAction: (_) async {});
    delta.performSelector('undo:');
    delta.performSelector('redo:');
    nonDelta.performSelector('undo:');
    nonDelta.performSelector('redo:');
    expect(undo, 2);
    expect(redo, 2);
  });

  testWidgets(
      'macOS native Edit menu actions reach the active document history',
      (tester) async {
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final state =
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    await state.apply(
        state.transaction..insertText(state.document.first!, 0, 'Native undo'));
    await tester.pumpAndSettle();
    // Attach the actual editor's text-input client by focusing its document.
    tester.widget<EditorToolbar>(find.byType(EditorToolbar)).onSelectTab(0);
    await tester.pumpAndSettle();
    final clients = tester.testTextInput.log
        .where((call) => call.method == 'TextInput.setClient');
    expect(clients, isNotEmpty);
    final client = (clients.last.arguments as List).first;
    Future<void> selector(String command) async {
      await tester.runAsync(() => tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
              'flutter/textinput',
              const JSONMethodCodec().encodeMethodCall(
                  MethodCall('TextInputClient.performSelectors', [
                client,
                [command]
              ])),
              (_) {}));
      await tester.pumpAndSettle();
    }

    await selector('undo:');
    expect(state.document.first!.delta!.toPlainText(), '');
    await selector('redo:');
    expect(state.document.first!.delta!.toPlainText(), 'Native undo');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
