import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/models/ws_frame.dart';

void main() {
  group('WsFrame.parse', () {
    test('parses event frame', () {
      final raw = jsonEncode({
        'type': 'event',
        'event': 'chat',
        'payload': {'state': 'delta', 'message': 'hello'},
        'seq': 1,
      });
      final frame = WsFrame.parse(raw);
      expect(frame.type, FrameType.event);
      expect(frame.event, isNotNull);
      expect(frame.event!.event, 'chat');
      expect(frame.event!.payload['state'], 'delta');
      expect(frame.event!.seq, 1);
    });

    test('parses response frame', () {
      final raw = jsonEncode({
        'type': 'res',
        'id': 'abc-123',
        'ok': true,
        'payload': {'type': 'hello-ok'},
      });
      final frame = WsFrame.parse(raw);
      expect(frame.type, FrameType.res);
      expect(frame.response, isNotNull);
      expect(frame.response!.id, 'abc-123');
      expect(frame.response!.ok, true);
      expect(frame.response!.payload?['type'], 'hello-ok');
    });

    test('parses request frame', () {
      final raw = jsonEncode({
        'type': 'req',
        'id': 'req-1',
        'method': 'chat.send',
        'params': {'message': 'test'},
      });
      final frame = WsFrame.parse(raw);
      expect(frame.type, FrameType.req);
      expect(frame.request, isNotNull);
      expect(frame.request!.method, 'chat.send');
      expect(frame.request!.params['message'], 'test');
    });

    test('throws on unknown frame type', () {
      final raw = jsonEncode({'type': 'unknown'});
      expect(() => WsFrame.parse(raw), throwsA(isA<FormatException>()));
    });

    test('throws on non-object JSON', () {
      expect(() => WsFrame.parse('"hello"'), throwsA(isA<FormatException>()));
    });
  });

  group('WsRequest', () {
    test('encodes to JSON string', () {
      final req = WsRequest(id: '1', method: 'chat.send', params: {'message': 'hi'});
      final json = jsonDecode(req.encode()) as Map<String, dynamic>;
      expect(json['type'], 'req');
      expect(json['id'], '1');
      expect(json['method'], 'chat.send');
      expect(json['params']['message'], 'hi');
    });
  });

  group('WsResponse', () {
    test('fromJson with error', () {
      final res = WsResponse.fromJson({
        'id': '2',
        'ok': false,
        'error': {'code': 'unauthorized', 'message': 'bad token'},
      });
      expect(res.ok, false);
      expect(res.error?['code'], 'unauthorized');
    });

    test('fromJson with missing fields defaults gracefully', () {
      final res = WsResponse.fromJson({});
      expect(res.id, '');
      expect(res.ok, false);
      expect(res.payload, isNull);
    });
  });

  group('WsEvent', () {
    test('fromJson with optional fields', () {
      final event = WsEvent.fromJson({
        'event': 'agent',
        'payload': {'stream': 'lifecycle'},
        'seq': 5,
        'stateVersion': 42,
      });
      expect(event.event, 'agent');
      expect(event.seq, 5);
      expect(event.stateVersion, 42);
    });

    test('fromJson without optional fields', () {
      final event = WsEvent.fromJson({
        'event': 'tick',
        'payload': {},
      });
      expect(event.seq, isNull);
      expect(event.stateVersion, isNull);
    });
  });
}
