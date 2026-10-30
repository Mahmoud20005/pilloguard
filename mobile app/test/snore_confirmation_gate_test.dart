import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snoring/snore_confirmation_gate.dart';

void main() {
  final start = DateTime(2026, 1, 1);

  SnoreAcousticEvent event(int id, int onsetMs, int endMs) =>
      SnoreAcousticEvent(
        id: id,
        onset: start.add(Duration(milliseconds: onsetMs)),
        end: start.add(Duration(milliseconds: endMs)),
      );

  test('seven completed events confirm exactly once', () async {
    var writes = 0;
    final gate = SnoreConfirmationGate(
      writeConfirmedCommand: () async => writes++,
    );
    for (var i = 0; i < 7; i++) {
      expect(
        await gate.addCompletedEvent(event(i, i * 1000, i * 1000 + 300)),
        i == 6,
      );
    }
    expect(writes, 1);
  });

  test('exactly seven seconds resets the sequence', () async {
    final gate = SnoreConfirmationGate(writeConfirmedCommand: () async {});
    for (var i = 0; i < 6; i++) {
      await gate.addCompletedEvent(event(i, i * 1000, i * 1000 + 200));
    }
    await gate.addCompletedEvent(event(6, 13200, 13400));
    expect(gate.consecutivePositiveWindows, 1);
  });

  test('a gap greater than seven seconds resets the sequence', () async {
    final gate = SnoreConfirmationGate(writeConfirmedCommand: () async {});
    for (var i = 0; i < 6; i++) {
      await gate.addCompletedEvent(event(i, i * 1000, i * 1000 + 200));
    }
    await gate.addCompletedEvent(event(6, 14000, 14200));
    expect(gate.consecutivePositiveWindows, 1);
  });

  test('six events do not confirm and a second group can confirm', () async {
    var writes = 0;
    final gate = SnoreConfirmationGate(
      writeConfirmedCommand: () async => writes++,
    );
    for (var i = 0; i < 6; i++) {
      await gate.addCompletedEvent(event(i, i * 500, i * 500 + 200));
    }
    expect(writes, 0);
    for (var i = 0; i < 7; i++) {
      await gate.addCompletedEvent(
        event(10 + i, 10000 + i * 500, 10200 + i * 500),
      );
    }
    expect(writes, 1);
  });

  test('duplicate event cannot increment the sequence twice', () async {
    final gate = SnoreConfirmationGate(writeConfirmedCommand: () async {});
    final first = event(1, 0, 300);
    await gate.addCompletedEvent(first);
    await gate.addCompletedEvent(first);
    expect(gate.consecutivePositiveWindows, 1);
  });

  test('PCM silence closes an event and separates the next event', () async {
    final segmenter = SnorePcmEventSegmenter();
    final active = _pcmWindow(activeFrames: {0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    final silence = _pcmWindow(activeFrames: {});
    final first = segmenter.processWindow(
      pcm16: active,
      windowStart: start,
      candidate: true,
      audioIsValid: true,
      impulseRejected: false,
    );
    expect(first, isEmpty);
    final second = segmenter.processWindow(
      pcm16: silence,
      windowStart: start.add(const Duration(seconds: 1)),
      candidate: true,
      audioIsValid: true,
      impulseRejected: false,
    );
    expect(second, hasLength(1));
    expect(second.single.end, start.add(const Duration(seconds: 1)));
  });

  test('a sustained snore across windows is one event', () {
    final segmenter = SnorePcmEventSegmenter();
    segmenter.processWindow(
      pcm16: _pcmWindow(activeFrames: {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}),
      windowStart: start,
      candidate: true,
      audioIsValid: true,
      impulseRejected: false,
    );
    segmenter.processWindow(
      pcm16: _pcmWindow(activeFrames: {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}),
      windowStart: start.add(const Duration(seconds: 1)),
      candidate: true,
      audioIsValid: true,
      impulseRejected: false,
    );
    expect(segmenter.flush(), hasLength(1));
  });

  test('invalid and rejected windows do not create events', () {
    final segmenter = SnorePcmEventSegmenter();
    final events = segmenter.processWindow(
      pcm16: _pcmWindow(activeFrames: {0, 1}),
      windowStart: start,
      candidate: true,
      audioIsValid: false,
      impulseRejected: true,
    );
    expect(events, isEmpty);
    expect(segmenter.flush(), isEmpty);
  });

  test('seven events can span more than fifty seconds', () async {
    var writes = 0;
    final gate = SnoreConfirmationGate(
      writeConfirmedCommand: () async => writes++,
    );
    for (var i = 0; i < 7; i++) {
      await gate.addCompletedEvent(event(i, i * 6900, i * 6900 + 100));
    }
    expect(writes, 1);
  });
}

Uint8List _pcmWindow({required Set<int> activeFrames}) {
  final bytes = Uint8List(32000);
  for (final frame in activeFrames) {
    for (var sample = 0; sample < 1600; sample++) {
      final value = (math.sin(sample / 10) * 8000).round();
      final offset = frame * 3200 + sample * 2;
      bytes[offset] = value & 0xff;
      bytes[offset + 1] = (value >> 8) & 0xff;
    }
  }
  return bytes;
}
