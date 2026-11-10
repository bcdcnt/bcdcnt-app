import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bcdcnt/widgets/ui.dart' show typingInField;

void main() {
  testWidgets('letter shortcuts stay off while typing in a field', (tester) async {
    final outer = FocusNode();
    final fired = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Focus(
          focusNode: outer,
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && !typingInField() && e.logicalKey == LogicalKeyboardKey.keyA) {
              fired.add('approve');
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: const Column(children: [TextField(key: Key('box'))]),
        ),
      ),
    ));
    await tester.pump();
    // Not typing: A approves.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, ['approve']);
    expect(typingInField(), isFalse);
    // Typing in the box: A is just a letter.
    await tester.tap(find.byKey(const Key('box')));
    await tester.pump();
    expect(typingInField(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, ['approve']);
  });
}
