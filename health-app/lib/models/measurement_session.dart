enum MeasurementState {
  waitingForFinger,
  fingerDetected,
  stabilizing,
  measuring,
  complete,
  removeFinger,
  error,
  ready,
  unknown,
}

MeasurementState parseMeasurementState(String? raw) {
  final normalized = (raw ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'WAITINGFORFINGER':
    case 'WAITING_FOR_FINGER':
      return MeasurementState.waitingForFinger;
    case 'FINGERDETECTED':
    case 'FINGER_DETECTED':
      return MeasurementState.fingerDetected;
    case 'STABILIZING':
      return MeasurementState.stabilizing;
    case 'MEASURING':
      return MeasurementState.measuring;
    case 'COMPLETE':
      return MeasurementState.complete;
    case 'REMOVEFINGER':
    case 'REMOVE_FINGER':
      return MeasurementState.removeFinger;
    case 'READY':
      return MeasurementState.ready;
    case 'ERROR':
      return MeasurementState.error;
    case 'COOLDOWN':
      return MeasurementState.removeFinger;
    default:
      return MeasurementState.unknown;
  }
}

extension MeasurementStateX on MeasurementState {
  String get label {
    switch (this) {
      case MeasurementState.waitingForFinger:
        return 'Waiting for Finger';
      case MeasurementState.fingerDetected:
        return 'Finger Detected';
      case MeasurementState.stabilizing:
        return 'Stabilizing';
      case MeasurementState.measuring:
        return 'Measuring';
      case MeasurementState.complete:
        return 'Complete';
      case MeasurementState.removeFinger:
        return 'Remove Finger';
      case MeasurementState.error:
        return 'Error';
      case MeasurementState.ready:
        return 'Ready';
      case MeasurementState.unknown:
        return 'Idle';
    }
  }

  bool get showsProgress => this == MeasurementState.measuring;

  bool get showsPulse =>
      this == MeasurementState.fingerDetected ||
      this == MeasurementState.stabilizing ||
      this == MeasurementState.measuring;

  bool get isComplete => this == MeasurementState.complete;

  bool get isError => this == MeasurementState.error;
}
