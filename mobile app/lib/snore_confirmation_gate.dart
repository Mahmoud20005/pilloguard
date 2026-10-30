import 'dart:math' as math;
import 'dart:typed_data';

typedef SnoreCommandWriter = Future<void> Function();

class SnoreAcousticEvent {
  const SnoreAcousticEvent({
    required this.id,
    required this.onset,
    required this.end,
  });

  final int id;
  final DateTime onset;
  final DateTime end;
}

/// Segments candidate model windows using the PCM envelope, not timestamps
/// supplied by the model.
class SnorePcmEventSegmenter {
  SnorePcmEventSegmenter({
    this.activityRms = 0.005,
    this.boundarySilence = const Duration(milliseconds: 200),
  });

  final double activityRms;
  final Duration boundarySilence;
  DateTime? _onset;
  DateTime? _end;
  int _nextId = 1;

  List<SnoreAcousticEvent> processWindow({
    required Uint8List pcm16,
    required DateTime windowStart,
    required bool candidate,
    required bool audioIsValid,
    required bool impulseRejected,
  }) {
    if (!candidate || !audioIsValid || impulseRejected) return _close();
    const frameBytes = 3200; // 100 ms at 16 kHz, mono, PCM16.
    final silenceFrames = math.max(1, boundarySilence.inMilliseconds ~/ 100);
    final completed = <SnoreAcousticEvent>[];
    var trailingSilence = 0;
    for (
      var offset = 0;
      offset + frameBytes <= pcm16.length;
      offset += frameBytes
    ) {
      if (_rms(pcm16, offset, frameBytes) < activityRms) {
        trailingSilence++;
        if (trailingSilence >= silenceFrames) completed.addAll(_close());
        continue;
      }
      trailingSilence = 0;
      final frameStart = windowStart.add(
        Duration(milliseconds: (offset ~/ frameBytes) * 100),
      );
      _onset ??= frameStart;
      _end = frameStart.add(const Duration(milliseconds: 100));
    }
    return completed;
  }

  List<SnoreAcousticEvent> flush() => _close();

  List<SnoreAcousticEvent> _close() {
    if (_onset == null || _end == null) return const [];
    final event = SnoreAcousticEvent(id: _nextId++, onset: _onset!, end: _end!);
    _onset = null;
    _end = null;
    return [event];
  }

  double _rms(Uint8List bytes, int offset, int length) {
    var sum = 0.0;
    for (var index = offset; index < offset + length; index += 2) {
      var sample = bytes[index] | (bytes[index + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final normalized = sample / 32768.0;
      sum += normalized * normalized;
    }
    return math.sqrt(sum / (length ~/ 2));
  }
}

class SnoreConfirmationGate {
  SnoreConfirmationGate({
    required this.writeConfirmedCommand,
    this.requiredPositiveWindows = 7,
  }) : assert(requiredPositiveWindows > 0);

  final SnoreCommandWriter writeConfirmedCommand;
  final int requiredPositiveWindows;

  int _consecutivePositiveWindows = 0;
  final Set<int> _processedEventIds = <int>{};
  SnoreAcousticEvent? _lastEvent;
  bool _commandSentForEpisode = false;

  int get consecutivePositiveWindows => _consecutivePositiveWindows;
  bool get commandSentForEpisode => _commandSentForEpisode;

  Future<bool> addInferenceResult({
    required bool? isPositive,
    required bool audioIsValid,
    required bool impulseRejected,
  }) async {
    if (!audioIsValid || impulseRejected || isPositive == null || !isPositive) {
      return false;
    }
    // Legacy callers do not have PCM event boundaries. They can still submit
    // explicit events through addCompletedEvent; this method remains a
    // compatibility adapter and does not claim each window is an event.
    return false;
  }

  Future<bool> addCompletedEvent(SnoreAcousticEvent event) async {
    if (!_processedEventIds.add(event.id)) return false;
    final previous = _lastEvent;
    if (previous != null) {
      final gap = event.onset.difference(previous.end);
      if (gap.isNegative || gap >= const Duration(seconds: 7)) {
        _consecutivePositiveWindows = 0;
      }
    }
    _lastEvent = event;
    _consecutivePositiveWindows++;
    if (_consecutivePositiveWindows < requiredPositiveWindows) return false;
    await writeConfirmedCommand();
    _commandSentForEpisode = true;
    _consecutivePositiveWindows = 0;
    _lastEvent = null;
    _processedEventIds.clear();
    return true;
  }

  void resetEpisode() {
    _consecutivePositiveWindows = 0;
    _lastEvent = null;
    _processedEventIds.clear();
    _commandSentForEpisode = false;
  }
}
