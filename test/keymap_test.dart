import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/input/daw_input.dart';
import 'package:sridaw/input/keymap.dart';

void main() {
  group('character keymap (soft keyboard path)', () {
    test('vim motions resolve to the same actions as hardware keys', () {
      expect(Keymap.resolveChar('h'), DawAction.moveLeft);
      expect(Keymap.resolveChar('j'), DawAction.moveDown);
      expect(Keymap.resolveChar('k'), DawAction.moveUp);
      expect(Keymap.resolveChar('l'), DawAction.moveRight);
      expect(Keymap.resolveChar('w'), DawAction.nextNote);
      expect(Keymap.resolveChar('b'), DawAction.prevNote);
    });

    test('case is preserved so V is line-select, not visual', () {
      expect(Keymap.resolveChar('v'), DawAction.visualToggle);
      expect(Keymap.resolveChar('V'), DawAction.visualLineToggle);
      expect(Keymap.resolveChar('G'), DawAction.gotoLastLine);
    });

    test('mode keys and command key resolve', () {
      expect(Keymap.resolveChar('i'), DawAction.drawToggle);
      expect(Keymap.resolveChar('x'), DawAction.eraseToggle);
      expect(Keymap.resolveChar(':'), DawAction.enterCommand);
      expect(Keymap.resolveChar('u'), DawAction.undo);
    });

    test('unbound characters return null', () {
      expect(Keymap.resolveChar('z'), isNull);
      expect(Keymap.resolveChar('#'), isNull);
    });
  });

  group('input mode labels', () {
    test('cover the spec modes', () {
      expect(InputMode.values.map((m) => m.label).toSet(), {
        'NORMAL',
        'INSERT',
        'DRAW',
        'ERASE',
        'VISUAL',
        'V-LINE',
        'COMMAND',
        'PIANO',
        'REPLACE',
      });
    });
  });
}
