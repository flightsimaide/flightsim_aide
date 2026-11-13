import 'app_exception.dart';

/// Outcome of an operation: either an [Ok] value or an [Error] with an [AppException].
sealed class Result<T> {
  const Result();

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// The value if [Ok], otherwise null.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Error() => null,
  };

  /// The error if [Error], otherwise null.
  AppException? get errorOrNull => switch (this) {
    Ok() => null,
    Error(:final error) => error,
  };
}

/// Successful result holding [value].
final class Ok<T> extends Result<T> {
  /// Creates a successful result.
  const Ok(this.value);

  /// The produced value.
  final T value;
}

/// Failed result holding [error].
final class Error<T> extends Result<T> {
  /// Creates a failed result.
  const Error(this.error);

  /// The failure.
  final AppException error;
}
