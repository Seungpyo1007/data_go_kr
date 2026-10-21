import 'response.dart';

/// When and how long [DataGoKrClient] waits before trying a request again.
///
/// Only failures that can pass on their own are retried: a dropped
/// connection, a timeout (including the portal's own `05`), a server error
/// (HTTP 5xx), and an HTTP 429 rate limit. Key and parameter errors fail at
/// once. The waits grow from [initialDelay] by [multiplier] up to
/// [maxDelay].
///
/// The portal's own `22` (also `rate_limit`) is not retried: it means the
/// daily quota is used up, which no wait fixes.
class RetryPolicy {
  /// Creates a policy.
  ///
  /// [sleep] waits between attempts; it defaults to `Future.delayed`, and
  /// tests can pass a function that records the delays instead.
  const RetryPolicy({
    this.maxRetries = 2,
    this.initialDelay = const Duration(milliseconds: 250),
    this.multiplier = 2,
    this.maxDelay = const Duration(seconds: 5),
    this.sleep,
  }) : assert(maxRetries >= 0),
       assert(multiplier >= 1);

  /// Never retries.
  static const none = RetryPolicy(maxRetries: 0);

  /// Retries after the first attempt; `2` means at most three attempts.
  final int maxRetries;

  /// Wait before the first retry.
  final Duration initialDelay;

  /// Factor each further wait grows by.
  final double multiplier;

  /// Longest wait between two attempts.
  final Duration maxDelay;

  /// Waits for a duration. Defaults to `Future.delayed`.
  final Future<void> Function(Duration delay)? sleep;

  /// Wait before retry number [retry], counting from 0.
  Duration delayFor(int retry) {
    var micros = initialDelay.inMicroseconds.toDouble();
    for (var i = 0; i < retry; i++) {
      micros *= multiplier;
    }
    final capped = micros.clamp(0, maxDelay.inMicroseconds.toDouble());
    return Duration(microseconds: capped.round());
  }

  /// Whether [error] is worth another attempt.
  bool shouldRetry(DataGoKrException error) => switch (error.code) {
    'timeout' => true,
    // HTTP 429 passes; the portal's 22 is a daily quota.
    'rate_limit' => error.statusCode == 429 && error.reasonCode != '22',
    // A transport failure has no status; a server error has 5xx.
    'http_error' => error.statusCode == null || error.statusCode! >= 500,
    _ => false,
  };

  /// Waits before retry number [retry].
  Future<void> wait(int retry) {
    final delay = delayFor(retry);
    return (sleep ?? Future<void>.delayed)(delay);
  }
}
