import 'dart:async';
import '../core/midi_protocol.dart';

abstract interface class MidiTransport {
  String get name;
  bool get isDemo;
  bool get isOpen;
  int get uploadChunk;
  Stream<List<int>> get frames;
  Stream<String> get disconnectReasons;
  Future<void> send(List<int> bytes);
  Future<void> sendFrame(List<int> frame);
  Future<void> close();
}

class MidiWriter {
  final Future<void> Function(List<int> packet) writePacket;
  final Duration pace;
  final void Function(Object error)? onError;
  Future<void> _tail = Future.value();
  bool _closed = false;
  int _pending = 0;

  MidiWriter(
    this.writePacket, {
    this.pace = const Duration(milliseconds: 6),
    this.onError,
  });

  Future<void> send(List<int> bytes, {bool sysex = false}) {
    if (_closed) return Future.error(StateError('Bluetooth 연결이 끊어졌습니다.'));
    if (_pending >= 128) {
      return Future.error(StateError('전송 대기 중입니다. 잠시 후 다시 조절해 주세요.'));
    }
    final packets = sysex
        ? blePackets(bytes)
        : splitChannelMessages(
            bytes,
          ).expand((message) => blePackets(message)).toList();
    _pending++;
    final operation = _tail.then((_) async {
      for (final packet in packets) {
        if (_closed) throw StateError('Bluetooth 연결이 끊어졌습니다.');
        await writePacket(packet);
        if (pace > Duration.zero) await Future<void>.delayed(pace);
      }
    });
    _tail = operation.then<void>(
      (_) {
        _pending--;
      },
      onError: (Object error, StackTrace trace) {
        _pending--;
        if (!_closed) {
          _closed = true;
          onError?.call(error);
        }
      },
    );
    return operation;
  }

  void close() {
    _closed = true;
  }
}

class MidiRequestQueue {
  final MidiTransport? Function() transport;
  Future<void> _tail = Future.value();
  _PendingReply? _pending;
  int _generation = 0;

  MidiRequestQueue(this.transport);

  Future<List<int>> request(
    int command,
    List<int> payload,
    int replyType, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    final generation = _generation;
    final operation = _tail.then<List<int>>((_) async {
      final link = transport();
      if (generation != _generation || link == null || !link.isOpen) {
        throw StateError('앰프 연결이 끊어졌습니다. 다시 연결해 주세요.');
      }
      final completer = Completer<List<int>>();
      final pending = _PendingReply(replyType, command, payload, completer);
      pending.timer = Timer(timeout, () {
        if (_pending != pending) return;
        _pending = null;
        completer.completeError(
          TimeoutException(
            '앰프가 응답하지 않습니다 (명령 $command). 전원과 Onyx 펌웨어를 확인해 주세요.',
          ),
        );
      });
      _pending = pending;
      // Attach an error consumer before writing so cancellation during an awaited native call is handled.
      final reply = completer.future;
      unawaited(reply.then<void>((_) {}, onError: (Object _) {}));
      unawaited(
        Future<void>.sync(
          () => link.sendFrame(buildFrame(command, payload)),
        ).catchError((Object error, StackTrace trace) {
          if (_pending == pending) {
            _pending = null;
            pending.timer?.cancel();
            completer.completeError(error, trace);
          }
        }),
      );
      return reply;
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  void receive(List<int> frame) {
    final reply = parseFrame(frame), pending = _pending;
    if (reply == null ||
        pending == null ||
        reply.type != pending.type ||
        !pending.accepts(reply.data)) {
      return;
    }
    _pending = null;
    pending.timer?.cancel();
    pending.completer.complete(reply.data);
  }

  void cancel([String message = '앰프 연결이 끊어졌습니다. 다시 연결해 주세요.']) {
    _generation++;
    final pending = _pending;
    _pending = null;
    pending?.timer?.cancel();
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(StateError(message));
    }
  }
}

class _PendingReply {
  final int type;
  final int command;
  final List<int> payload;
  final Completer<List<int>> completer;
  Timer? timer;
  _PendingReply(this.type, this.command, this.payload, this.completer);

  bool accepts(List<int> data) {
    if (command == 81) {
      return data.length >= 5 && data[0] == payload[0] && data[2] == payload[1];
    }
    if (command == 83) return data.length >= 2 && data[0] == payload[0];
    if (command == 82) {
      return data.length >= 4 &&
          data[0] == payload[0] &&
          data[1] == payload[1] &&
          data[2] == payload[2];
    }
    return true;
  }
}
