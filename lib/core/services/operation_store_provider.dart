import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'operation_store.dart';

/// Single [OperationStore] instance for the app session.
///
/// Lives in core so any tool can record its output without depending on the
/// Files feature.
final operationStoreProvider = Provider<OperationStore>((ref) {
  return OperationStore();
});
