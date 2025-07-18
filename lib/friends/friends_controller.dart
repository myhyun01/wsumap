// lib/friends/friends_controller.dart - 웹소켓 연동 추가
import 'dart:async';
import 'package:flutter/material.dart';
import 'friend.dart';
import 'friend_repository.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';

class FriendsController extends ChangeNotifier {
  final FriendRepository repository;
  final String myId;
  final WebSocketService _wsService = WebSocketService();

  FriendsController(this.repository, this.myId) {
    _initializeWebSocket();
    _startRealTimeUpdates();
  }

  List<Friend> friends = [];
  List<FriendRequest> friendRequests = [];
  List<SentFriendRequest> sentFriendRequests = [];
  List<String> onlineUsers = [];
  bool isLoading = false;
  String? errorMessage;
  bool isWebSocketConnected = false;

  Timer? _updateTimer;
  StreamSubscription? _wsMessageSubscription;
  StreamSubscription? _wsConnectionSubscription;
  StreamSubscription? _wsOnlineUsersSubscription;

  static const Duration _updateInterval = Duration(seconds: 5);
  DateTime? _lastUpdate;
  bool _isRealTimeEnabled = true;

  bool get isRealTimeEnabled => _isRealTimeEnabled && isWebSocketConnected;

  // 🔌 웹소켓 초기화
  Future<void> _initializeWebSocket() async {
    debugPrint('🔌 웹소켓 서비스 초기화 중...');

    // 알림 서비스 초기화
    await NotificationService.initialize();

    // 웹소켓 연결
    await _wsService.connect(myId);

    // 웹소켓 이벤트 리스너 설정
    _wsMessageSubscription = _wsService.messageStream.listen(
      _handleWebSocketMessage,
    );
    _wsConnectionSubscription = _wsService.connectionStream.listen(
      _handleConnectionChange,
    );
    _wsOnlineUsersSubscription = _wsService.onlineUsersStream.listen(
      _handleOnlineUsersUpdate,
    );

    debugPrint('✅ 웹소켓 서비스 초기화 완료');
  }

  // 📨 웹소켓 메시지 처리
  void _handleWebSocketMessage(Map<String, dynamic> message) {
    debugPrint('📨 친구 컨트롤러에서 웹소켓 메시지 수신: ${message['type']}');

    switch (message['type']) {
      case 'new_friend_request':
      case 'friend_request_accepted':
      case 'friend_request_rejected':
      case 'friend_deleted':
        // 친구 관련 이벤트 발생 시 즉시 데이터 업데이트
        debugPrint('🔄 친구 이벤트로 인한 즉시 업데이트');
        quickUpdate();
        break;

      case 'friend_status_change':
        _handleFriendStatusChange(message);
        break;
    }
  }

  // 🔌 연결 상태 변경 처리
  void _handleConnectionChange(bool isConnected) {
    isWebSocketConnected = isConnected;
    debugPrint('🔌 웹소켓 연결 상태 변경: $isConnected');

    if (isConnected) {
      debugPrint('✅ 웹소켓 연결됨 - 폴링 중지됨');
      // 폴링 타이머는 유지하되, 실제 API 호출은 스킵
      // 한 번만 동기화
      quickUpdate();
    } else {
      debugPrint('❌ 웹소켓 연결 끊어짐 - 폴링 모드로 전환');
      // 폴링이 이미 돌고 있으니 추가 작업 불필요
    }

    notifyListeners();
  }

  // 👥 온라인 사용자 목록 업데이트
  void _handleOnlineUsersUpdate(List<String> users) {
    onlineUsers = users;
    debugPrint('👥 온라인 사용자 업데이트: ${users.length}명');

    // 친구 목록의 온라인 상태 업데이트
    _updateFriendsOnlineStatus();
    notifyListeners();
  }

  // 📶 친구 상태 변경 처리
  void _handleFriendStatusChange(Map<String, dynamic> message) {
    final userId = message['userId'];
    final isOnline = message['isOnline'] ?? false;

    debugPrint('📶 친구 상태 변경: $userId - ${isOnline ? '온라인' : '오프라인'}');

    // 친구 목록에서 해당 사용자의 상태 업데이트
    for (int i = 0; i < friends.length; i++) {
      if (friends[i].userId == userId) {
        friends[i] = Friend(
          userId: friends[i].userId,
          userName: friends[i].userName,
          profileImage: friends[i].profileImage,
          phone: friends[i].phone,
          isLogin: isOnline,
          lastLocation: friends[i].lastLocation,
        );
        break;
      }
    }

    notifyListeners();
  }

  // 👥 친구들의 온라인 상태 업데이트
  void _updateFriendsOnlineStatus() {
    for (int i = 0; i < friends.length; i++) {
      final isOnline = onlineUsers.contains(friends[i].userId);
      if (friends[i].isLogin != isOnline) {
        friends[i] = Friend(
          userId: friends[i].userId,
          userName: friends[i].userName,
          profileImage: friends[i].profileImage,
          phone: friends[i].phone,
          isLogin: isOnline,
          lastLocation: friends[i].lastLocation,
        );
      }
    }
  }

  // 🔄 실시간 업데이트 시작 (웹소켓이 없을 때 폴백)
  void _startRealTimeUpdates() {
    debugPrint('🔄 실시간 업데이트 시작');
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(_updateInterval, (timer) {
      // 웹소켓이 연결되어 있으면 폴링 중지
      if (isWebSocketConnected) {
        debugPrint('📡 웹소켓 연결됨 - 폴링 스킵');
        return; // 폴링하지 않음
      }

      // 웹소켓이 연결되어 있지 않을 때만 폴링
      if (_isRealTimeEnabled) {
        debugPrint('📡 폴링 모드로 업데이트 (웹소켓 비활성)');
        _silentUpdate();
      }
    });
  }

  // 🔄 조용한 업데이트
  Future<void> _silentUpdate() async {
    try {
      debugPrint('🔄 백그라운드 친구 데이터 업데이트 중...');

      final now = DateTime.now();
      final previousFriendsCount = friends.length;
      final previousRequestsCount = friendRequests.length;
      final previousSentRequestsCount = sentFriendRequests.length;

      final newFriends = await repository.getMyFriends(myId);
      final newFriendRequests = await repository.getFriendRequests(myId);
      final newSentFriendRequests = await repository.getSentFriendRequests(
        myId,
      );

      bool hasChanges = false;

      if (newFriends.length != previousFriendsCount ||
          newFriendRequests.length != previousRequestsCount ||
          newSentFriendRequests.length != previousSentRequestsCount) {
        hasChanges = true;
      }

      if (!hasChanges) {
        final newFriendIds = newFriends.map((f) => f.userId).toSet();
        final currentFriendIds = friends.map((f) => f.userId).toSet();

        final newRequestIds = newFriendRequests
            .map((r) => r.fromUserId)
            .toSet();
        final currentRequestIds = friendRequests
            .map((r) => r.fromUserId)
            .toSet();

        final newSentIds = newSentFriendRequests.map((r) => r.toUserId).toSet();
        final currentSentIds = sentFriendRequests
            .map((r) => r.toUserId)
            .toSet();

        if (!newFriendIds.containsAll(currentFriendIds) ||
            !currentFriendIds.containsAll(newFriendIds) ||
            !newRequestIds.containsAll(currentRequestIds) ||
            !currentRequestIds.containsAll(newRequestIds) ||
            !newSentIds.containsAll(currentSentIds) ||
            !currentSentIds.containsAll(newSentIds)) {
          hasChanges = true;
        }
      }

      if (hasChanges) {
        debugPrint('📡 친구 데이터 변경 감지됨! UI 업데이트 중...');

        if (newFriendRequests.length > previousRequestsCount) {
          final newRequests = newFriendRequests.length - previousRequestsCount;
          debugPrint('🔔 새로운 친구 요청 $newRequests개 도착!');
        }

        if (newFriends.length > previousFriendsCount) {
          final newFriendsCount = newFriends.length - previousFriendsCount;
          debugPrint('✅ 새로운 친구 $newFriendsCount명 추가됨!');
        }

        friends = newFriends;
        friendRequests = newFriendRequests;
        sentFriendRequests = newSentFriendRequests;
        errorMessage = null;
        _lastUpdate = now;

        // 온라인 상태 업데이트
        _updateFriendsOnlineStatus();

        notifyListeners();
      } else {
        debugPrint('📊 친구 데이터 변경 없음');
      }
    } catch (e) {
      debugPrint('❌ 백그라운드 업데이트 실패: $e');
    }
  }

  // ⚡ 즉시 업데이트
  Future<void> quickUpdate() async {
    debugPrint('⚡ 빠른 친구 데이터 업데이트');
    await _silentUpdate();
  }

  // 기존 메서드들은 동일하게 유지...
  Future<void> loadAll() async {
    debugPrint('🔄 명시적 친구 데이터 새로고침');
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      friends = await repository.getMyFriends(myId);
      friendRequests = await repository.getFriendRequests(myId);
      sentFriendRequests = await repository.getSentFriendRequests(myId);
      _lastUpdate = DateTime.now();

      // 온라인 상태 업데이트
      _updateFriendsOnlineStatus();

      debugPrint('✅ 친구 데이터 새로고침 완료');
      debugPrint('👥 친구: ${friends.length}명');
      debugPrint('📥 받은 요청: ${friendRequests.length}개');
      debugPrint('📤 보낸 요청: ${sentFriendRequests.length}개');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 데이터 새로고침 실패: $e');
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> addFriend(String addId) async {
    try {
      debugPrint('👤 친구 추가 요청: $addId');
      await repository.requestFriend(myId, addId);
      await quickUpdate();
      debugPrint('✅ 친구 추가 요청 완료');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 추가 실패: $e');
      notifyListeners();
    }
  }

  Future<void> acceptRequest(String addId) async {
    try {
      debugPrint('✅ 친구 요청 수락: $addId');
      await repository.acceptRequest(myId, addId);
      await quickUpdate();
      debugPrint('✅ 친구 요청 수락 완료');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 요청 수락 실패: $e');
      notifyListeners();
    }
  }

  Future<void> rejectRequest(String addId) async {
    try {
      debugPrint('❌ 친구 요청 거절: $addId');
      await repository.rejectRequest(myId, addId);
      await quickUpdate();
      debugPrint('✅ 친구 요청 거절 완료');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 요청 거절 실패: $e');
      notifyListeners();
    }
  }

  Future<void> deleteFriend(String addId) async {
    try {
      debugPrint('🗑️ 친구 삭제: $addId');
      await repository.deleteFriend(myId, addId);
      await quickUpdate();
      debugPrint('✅ 친구 삭제 완료');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 삭제 실패: $e');
      notifyListeners();
    }
  }

  Future<void> cancelSentRequest(String friendId) async {
    try {
      debugPrint('🚫 친구 요청 취소: $friendId');
      await repository.cancelSentRequest(myId, friendId);
      await quickUpdate();
      debugPrint('✅ 친구 요청 취소 완료');
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 요청 취소 실패: $e');
      notifyListeners();
    }
  }

  Future<Friend?> getFriendInfo(String friendId) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      return await repository.getFriendInfo(friendId);
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('❌ 친구 정보 조회 실패: $e');
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void stopRealTimeUpdates() {
    debugPrint('⏸️ 실시간 친구 업데이트 중지');
    _isRealTimeEnabled = false;
    _updateTimer?.cancel();
  }

  void resumeRealTimeUpdates() {
    debugPrint('▶️ 실시간 친구 업데이트 재시작');
    _isRealTimeEnabled = true;
    _startRealTimeUpdates();
    quickUpdate();
  }

  String get lastUpdateTime {
    if (_lastUpdate == null) return '업데이트 없음';

    final now = DateTime.now();
    final diff = now.difference(_lastUpdate!);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}초 전';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else {
      return '${diff.inHours}시간 전';
    }
  }

  // 📶 특정 친구의 온라인 상태 확인
  bool isFriendOnline(String userId) {
    return onlineUsers.contains(userId);
  }

  // 📊 웹소켓 연결 상태 정보
  String get connectionStatus {
    if (isWebSocketConnected) {
      return '실시간 연결됨';
    } else {
      return '폴링 모드';
    }
  }

  @override
  void dispose() {
    debugPrint('🛑 FriendsController 정리 중...');

    _updateTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    _wsOnlineUsersSubscription?.cancel();

    // 웹소켓 연결 해제
    _wsService.disconnect();

    super.dispose();
  }
}
