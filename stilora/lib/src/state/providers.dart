import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/http_repository.dart';
import '../data/mock_data.dart';
import '../data/repositories.dart';
import '../models/models.dart';

/// ── Repository binding ──────────────────────────────────────────
/// Release builds pass `--dart-define=API_BASE_URL=https://…` and talk
/// to the live Bun/Hono backend; debug/test builds (no define) run the
/// in-memory mock repository so suites stay hermetic.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
final bool kLiveBackend = apiBaseUrl.isNotEmpty;

final workspaceRepositoryProvider = Provider<WorkspaceRepository>(
  (ref) => kLiveBackend
      ? HttpWorkspaceRepository(apiBaseUrl)
      : MockWorkspaceRepository(),
);

/// Global connection status — drives the offline banner.
final connectionProvider =
    StateProvider<AppConnection>((ref) => AppConnection.online);

/// Auth session — Phase 4 swaps this for the Better Auth session lookup
/// (POST /api/auth/sign-in/email against our own API).
final signedInProvider = StateProvider<bool>((ref) => false);

/// Onboarding: workspace created during signup flow.
final onboardedWorkspaceProvider = StateProvider<String?>((ref) => null);

/// Theme mode — follows system by default, user-overridable in Settings.
final themeModeProvider = StateProvider<String>((ref) => 'system');

/// ── Async data (each failure here renders the error state) ──────
final workspaceProvider = FutureProvider<Workspace>(
  (ref) => ref.watch(workspaceRepositoryProvider).currentWorkspace(),
);

/// Channel list with optimistic read-state (AsyncNotifier so we can
/// mutate after fetch — FutureProvider notifiers are read-only).
class ChannelsNotifier extends AsyncNotifier<List<Channel>> {
  @override
  Future<List<Channel>> build() =>
      ref.watch(workspaceRepositoryProvider).channels();

  /// Marks a channel read (optimistic, server-confirmed in Phase 4).
  void markRead(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final c in current) c.id == id ? c.copyWith(unreadCount: 0) : c,
    ]);
  }
}

final channelsProvider =
    AsyncNotifierProvider<ChannelsNotifier, List<Channel>>(
        ChannelsNotifier.new);

final conversationsProvider = FutureProvider<List<DmConversation>>(
  (ref) => ref.watch(workspaceRepositoryProvider).conversations(),
);

final membersProvider = FutureProvider<List<UserProfile>>(
  (ref) => ref.watch(workspaceRepositoryProvider).members(),
);

final activityProvider = FutureProvider<List<ActivityItem>>(
  (ref) => ref.watch(workspaceRepositoryProvider).activity(),
);

/// Currently opened channel (null = workspace root).
final activeChannelProvider = StateProvider<Channel?>((ref) => null);

/// Currently opened DM conversation.
final activeDmProvider = StateProvider<DmConversation?>((ref) => null);

/// Messages for the active channel — mutable notifier so reactions and
/// sent messages update optimistically (server-confirmed in Phase 4).
class MessagesNotifier extends AsyncNotifier<List<Message>> {
  @override
  Future<List<Message>> build() async {
    final channel = ref.watch(activeChannelProvider);
    if (channel == null) return const [];
    return ref.watch(workspaceRepositoryProvider).messages(channel.id);
  }

  Future<void> append(Message m) async {
    state = AsyncData([...?state.valueOrNull, m]);
  }

  void toggleReaction(String id, String emoji) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncData([
      for (final m in list)
        m.id == id
            ? m.copyWith(reactions: _toggleReaction(m.reactions, emoji))
            : m,
    ]);
  }

  static List<Reaction> _toggleReaction(List<Reaction> rs, String emoji) {
    final i = rs.indexWhere((r) => r.emoji == emoji);
    if (i == -1) return [...rs, Reaction(emoji: emoji, count: 1, mine: true)];
    final toggled = rs[i].toggled();
    if (toggled.count <= 0) {
      return [...rs]..removeAt(i);
    }
    return [...rs]..[i] = toggled;
  }
}

final messagesProvider =
    AsyncNotifierProvider<MessagesNotifier, List<Message>>(
        MessagesNotifier.new);

/// Thread replies for the opened thread.
final threadProvider = FutureProvider.autoDispose.family<List<Message>, String>(
  (ref, messageId) =>
      ref.watch(workspaceRepositoryProvider).thread(messageId),
);

/// Search query + results (⌘K).
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchResultsProvider = FutureProvider.autoDispose
    .family<List<(String, String, String)>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(workspaceRepositoryProvider).search(query);
});

/// Voice room state (ephemeral — Ably/LiveKit-backed in Phase 4).
final voiceRoomProvider =
    StateProvider<VoiceRoom>((ref) => MockData.voiceRoom);

/// Unread total for the mobile bottom-nav badge.
final unreadTotalProvider = Provider<int>((ref) {
  final channels = ref.watch(channelsProvider).valueOrNull ?? [];
  return channels.fold(0, (sum, c) => sum + c.unreadCount);
});
