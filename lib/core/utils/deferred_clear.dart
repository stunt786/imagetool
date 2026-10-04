/// Runs a clean-up [action] just after the current teardown.
///
/// Tool screens release the byte buffers held by their Riverpod notifier when
/// they are popped. Two constraints shape the implementation:
///
/// * `ref` cannot be read from `State.dispose`, so the caller captures the
///   notifier while it is still mounted and hands it to this helper.
/// * Notifying listeners while the element tree is being torn down can reach
///   widgets that are already gone, so the action is deferred to a microtask.
///
/// Failures are swallowed: the provider may already have been disposed (the
/// root `ProviderScope` going away, for instance), in which case its memory is
/// being released anyway and there is nothing left to free.
void runDeferredClear(void Function() action) {
  Future.microtask(() {
    try {
      action();
    } catch (_) {
      // Best-effort clean-up only.
    }
  });
}
