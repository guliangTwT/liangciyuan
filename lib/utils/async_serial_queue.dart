import 'dart:async';

/// Runs asynchronous operations one at a time in submission order.
class AsyncSerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<T>();
    _tail = (() async {
      try {
        await previous;
      } catch (_) {}
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    })();
    return completer.future;
  }
}

/// Runs [action] for every item with at most [concurrency] in flight and
/// returns the results in the input order.
///
/// 用于把「一次一个远端文件」的串行下载改成有上限的并发：每个文件的
/// RTT 都在几百毫秒量级，串行等待会直接累加成用户看到的同步耗时。
/// 任一项失败会立即抛出，其余任务不再启动。
Future<List<TResult>> mapBounded<T, TResult>(
  List<T> items,
  Future<TResult> Function(T item) action, {
  int concurrency = 4,
}) async {
  if (items.isEmpty) return const [];
  final results = List<TResult?>.filled(items.length, null);
  var next = 0;
  Object? failure;
  StackTrace? failureStack;

  Future<void> worker() async {
    while (true) {
      if (failure != null) return;
      final index = next++;
      if (index >= items.length) return;
      try {
        results[index] = await action(items[index]);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
        return;
      }
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < concurrency.clamp(1, items.length); i++) worker(),
  ];
  await Future.wait(workers);
  final error = failure;
  if (error != null) {
    Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
  }
  return [for (final result in results) result as TResult];
}
