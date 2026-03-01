import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/models/a2ui_models.dart';

void main() {
  group('A2UISurface', () {
    group('getPath / setPath', () {
      test('sets and gets top-level key', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.setPath('name', 'Alice');
        expect(surface.getPath('name'), 'Alice');
      });

      test('sets and gets nested path', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.setPath('/user/name', 'Bob');
        expect(surface.getPath('/user/name'), 'Bob');
      });

      test('creates intermediate maps', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.setPath('/a/b/c', 42);
        expect(surface.getPath('/a/b/c'), 42);
        expect(surface.getPath('/a/b'), isA<Map<String, dynamic>>());
      });

      test('returns null for missing path', () {
        final surface = A2UISurface(surfaceId: 'main');
        expect(surface.getPath('/nonexistent'), isNull);
      });

      test('handles empty path gracefully', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.setPath('', 'value'); // Should be a no-op
        expect(surface.dataModel, isEmpty);
      });
    });

    group('mergeContents', () {
      test('merges at root', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.mergeContents(null, [
          {'key': 'name', 'valueString': 'Alice'},
          {'key': 'age', 'valueNumber': 30},
        ]);
        expect(surface.dataModel['name'], 'Alice');
        expect(surface.dataModel['age'], 30);
      });

      test('merges at path', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.mergeContents('user', [
          {'key': 'name', 'valueString': 'Bob'},
        ]);
        expect(surface.getPath('/user/name'), 'Bob');
      });

      test('merges nested valueMap', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.mergeContents(null, [
          {
            'key': 'user',
            'valueMap': [
              {'key': 'name', 'valueString': 'Carol'},
              {'key': 'active', 'valueBoolean': true},
            ]
          },
        ]);
        expect(surface.getPath('/user/name'), 'Carol');
        expect(surface.getPath('/user/active'), true);
      });

      test('merges valueArray', () {
        final surface = A2UISurface(surfaceId: 'main');
        surface.mergeContents(null, [
          {'key': 'tags', 'valueArray': ['a', 'b', 'c']},
        ]);
        expect(surface.dataModel['tags'], ['a', 'b', 'c']);
      });
    });
  });

  group('A2UIComponent', () {
    test('parses from JSON', () {
      final comp = A2UIComponent.fromJson({
        'id': 'title',
        'component': {
          'Text': {'text': {'literalString': 'Hello'}, 'usageHint': 'h1'}
        },
      });
      expect(comp.id, 'title');
      expect(comp.type, 'Text');
      expect(comp.props['usageHint'], 'h1');
    });

    test('parses weight', () {
      final comp = A2UIComponent.fromJson({
        'id': 'col',
        'weight': 3,
        'component': {'Column': {'children': {'explicitList': []}}},
      });
      expect(comp.weight, 3);
    });

    test('handles missing component gracefully', () {
      final comp = A2UIComponent.fromJson({'id': 'broken'});
      expect(comp.type, 'Unknown');
      expect(comp.props, isEmpty);
    });

    test('handles empty component map', () {
      final comp = A2UIComponent.fromJson({'id': 'empty', 'component': {}});
      expect(comp.type, 'Unknown');
    });
  });

  group('SurfaceUpdate', () {
    test('parses from JSON', () {
      final update = SurfaceUpdate.fromJson({
        'surfaceId': 'main',
        'components': [
          {'id': 'root', 'component': {'Column': {'children': {'explicitList': ['a']}}}},
          {'id': 'a', 'component': {'Text': {'text': {'literalString': 'hi'}}}},
        ],
      });
      expect(update.surfaceId, 'main');
      expect(update.components.length, 2);
      expect(update.components[0].id, 'root');
      expect(update.components[1].type, 'Text');
    });

    test('defaults surfaceId to main', () {
      final update = SurfaceUpdate.fromJson({'components': []});
      expect(update.surfaceId, 'main');
    });
  });

  group('BeginRendering', () {
    test('parses from JSON', () {
      final br = BeginRendering.fromJson({
        'surfaceId': 'dash',
        'root': 'root-comp',
        'catalogId': 'weather',
      });
      expect(br.surfaceId, 'dash');
      expect(br.root, 'root-comp');
      expect(br.catalogId, 'weather');
    });
  });

  group('DataModelUpdate', () {
    test('parses with path', () {
      final dmu = DataModelUpdate.fromJson({
        'surfaceId': 'main',
        'path': 'user',
        'contents': [{'key': 'name', 'valueString': 'Test'}],
      });
      expect(dmu.surfaceId, 'main');
      expect(dmu.path, 'user');
      expect(dmu.contents.length, 1);
    });

    test('parses without path', () {
      final dmu = DataModelUpdate.fromJson({
        'surfaceId': 'main',
        'contents': [],
      });
      expect(dmu.path, isNull);
    });
  });

  group('DeleteSurface', () {
    test('parses from JSON', () {
      final ds = DeleteSurface.fromJson({'surfaceId': 'temp'});
      expect(ds.surfaceId, 'temp');
    });
  });

  group('BoundValue resolution', () {
    test('resolves literal string', () {
      expect(resolveBoundString({'literalString': 'hello'}, null), 'hello');
    });

    test('resolves literal number', () {
      expect(resolveBoundNum({'literalNumber': 42}, null), 42);
    });

    test('resolves literal boolean', () {
      expect(resolveBoundBool({'literalBoolean': true}, null), true);
    });

    test('resolves path from data model', () {
      final surface = A2UISurface(surfaceId: 'main');
      surface.setPath('/user/name', 'Alice');
      expect(resolveBoundString({'path': '/user/name'}, surface), 'Alice');
    });

    test('resolves initialization shorthand (path + literal)', () {
      final surface = A2UISurface(surfaceId: 'main');
      // First resolution should initialize the path
      final result = resolveBoundString(
        {'path': '/form/name', 'literalString': 'Default'},
        surface,
      );
      expect(result, 'Default');
      expect(surface.getPath('/form/name'), 'Default');
    });

    test('initialization shorthand does not overwrite existing value', () {
      final surface = A2UISurface(surfaceId: 'main');
      surface.setPath('/form/name', 'Existing');
      final result = resolveBoundString(
        {'path': '/form/name', 'literalString': 'Default'},
        surface,
      );
      expect(result, 'Existing');
    });

    test('resolves plain string', () {
      expect(resolveBoundString('hello', null), 'hello');
    });

    test('resolves null to empty string', () {
      expect(resolveBoundString(null, null), '');
    });

    test('resolves bool false for missing path', () {
      final surface = A2UISurface(surfaceId: 'main');
      expect(resolveBoundBool({'path': '/missing'}, surface), false);
    });

    test('resolves legacy value key', () {
      expect(resolveBoundString({'value': 'legacy'}, null), 'legacy');
    });
  });

  group('UserAction', () {
    test('serializes to JSON', () {
      final action = UserAction(
        name: 'submit',
        surfaceId: 'main',
        sourceComponentId: 'btn-1',
        timestamp: '2026-01-01T00:00:00Z',
        context: {'name': 'Alice'},
      );
      final json = action.toJson();
      expect(json['userAction']['name'], 'submit');
      expect(json['userAction']['surfaceId'], 'main');
      expect(json['userAction']['context']['name'], 'Alice');
    });
  });
}
