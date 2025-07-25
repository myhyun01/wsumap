// lib/repositories/building_repository.dart - 완전 수정된 버전
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/building.dart';
import '../services/building_api_service.dart';
import '../services/building_data_service.dart';
import '../core/result.dart';
import '../core/app_logger.dart';

/// 건물 데이터의 단일 진실 공급원 (Single Source of Truth)
class BuildingRepository extends ChangeNotifier {
  static BuildingRepository? _instance;

  factory BuildingRepository() {
    // dispose된 인스턴스면 새로 생성
    if (_instance == null || _instance!._isDisposed) {
      _instance = BuildingRepository._internal();
    }
    return _instance!;
  }

  BuildingRepository._internal();

  // 🔥 단일 데이터 저장소
  List<Building> _allBuildings = [];
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _lastError;
  DateTime? _lastLoadTime;
  bool _isDisposed = false;

  // 🔥 서비스 인스턴스들
  final BuildingDataService _buildingDataService = BuildingDataService();

  // 🔥 콜백 관리
  final List<Function(List<Building>)> _dataChangeListeners = [];

  // Getters
  List<Building> get allBuildings => List.unmodifiable(_allBuildings);
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get hasData => _allBuildings.isNotEmpty;
  String? get lastError => _lastError;
  DateTime? get lastLoadTime => _lastLoadTime;
  int get buildingCount => _allBuildings.length;
  bool get isDisposed => _isDisposed;

  /// 🔥 안전한 notifyListeners 호출
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// 🔥 Repository 재초기화
  void _reinitialize() {
    if (_isDisposed) {
      AppLogger.info('BuildingRepository 재초기화', tag: 'REPO');
      _allBuildings.clear();
      _isLoaded = false;
      _isLoading = false;
      _lastError = null;
      _lastLoadTime = null;
      _dataChangeListeners.clear();
      _isDisposed = false;
    }
  }

  /// 🔥 새 세션을 위한 완전한 리셋
  void resetForNewSession() {
    debugPrint('🔄 BuildingRepository 새 세션 리셋');

    if (_isDisposed) {
      _reinitialize();
    }

    // 데이터 상태 완전 리셋
    _allBuildings.clear();
    _isLoaded = false;
    _isLoading = false;
    _lastError = null;
    _lastLoadTime = null;

    // 리스너들은 유지하되 알림
    _safeNotifyListeners();

    debugPrint('✅ BuildingRepository 리셋 완료');
  }

  /// 🔥 메인 데이터 로딩 메서드 - Result 패턴 완전 적용
  Future<Result<List<Building>>> getAllBuildings({
    bool forceRefresh = false,
  }) async {
    return await ResultHelper.runSafelyAsync(() async {
      // dispose 상태 확인 및 재초기화
      if (_isDisposed) {
        _reinitialize();
      }

      // 이미 로딩된 데이터가 있고 강제 새로고침이 아니면 캐시 반환
      if (_isLoaded && _allBuildings.isNotEmpty && !forceRefresh) {
        AppLogger.info(
          'BuildingRepository: 캐시된 데이터 반환 (${_allBuildings.length}개)',
          tag: 'REPO',
        );
        return _getCurrentBuildingsWithOperatingStatus();
      }

      // 현재 로딩 중이면 기다리기
      if (_isLoading) {
        AppLogger.debug('BuildingRepository: 이미 로딩 중, 대기...', tag: 'REPO');
        return await _waitForLoadingComplete();
      }

      return await _loadBuildingsFromServer();
    }, 'BuildingRepository.getAllBuildings');
  }

  /// 🔥 동기식 건물 데이터 반환 (기존 호환성 유지)
  List<Building> getAllBuildingsSync() {
    if (_isDisposed) {
      _reinitialize();
    }

    if (_isLoaded && _allBuildings.isNotEmpty) {
      return _getCurrentBuildingsWithOperatingStatus();
    }

    // 데이터가 없으면 fallback 반환
    return _getFallbackBuildings().map((building) {
      final autoStatus = _getAutoOperatingStatusWithoutContext(
        building.baseStatus,
      );
      return building.copyWith(baseStatus: autoStatus);
    }).toList();
  }

  /// 🔥 서버에서 건물 데이터 로딩 - Result 패턴 적용
  Future<List<Building>> _loadBuildingsFromServer() async {
    _isLoading = true;
    _lastError = null;
    _safeNotifyListeners();

    try {
      List<Building> buildings = [];

      // 1단계: 일반 API 시도
      final apiResult = await ResultHelper.runSafelyAsync(() async {
        return await BuildingApiService.getAllBuildings();
      }, 'BuildingApiService.getAllBuildings');

      if (apiResult.isSuccess) {
        buildings = apiResult.data!;
        debugPrint('✅ 일반 API 성공: ${buildings.length}개');
        debugPrint(
          '🔍 API 응답 건물 목록: ${buildings.map((b) => b.name).join(', ')}',
        );
      } else {
        debugPrint('❌ 일반 API 실패: ${apiResult.error}');

        // 2단계: BuildingDataService 시도
        final dataServiceResult = await ResultHelper.runSafelyAsync(() async {
          await _buildingDataService.loadBuildings();
          return _buildingDataService.buildings;
        }, 'BuildingDataService.loadBuildings');

        if (dataServiceResult.isSuccess) {
          buildings = dataServiceResult.data!;
          debugPrint('✅ DataService 성공: ${buildings.length}개');
          debugPrint(
            '🔍 DataService 응답 건물 목록: ${buildings.map((b) => b.name).join(', ')}',
          );
        } else {
          debugPrint('❌ DataService 실패: ${dataServiceResult.error}');
        }
      }

      // 3단계: 데이터 검증 및 저장
      if (buildings.isNotEmpty) {
        _allBuildings = buildings;
        _isLoaded = true;
        _lastLoadTime = DateTime.now();
        debugPrint('✅ 서버 데이터 저장 완료: ${buildings.length}개');
      } else {
        // 4단계: 확장된 Fallback 데이터 사용
        _allBuildings = _getFallbackBuildings();
        _isLoaded = true;
        _lastLoadTime = DateTime.now();
        _lastError = '서버 데이터 없음, 확장된 Fallback 사용';
        debugPrint('⚠️ 확장된 Fallback 데이터 사용: ${_allBuildings.length}개');
        debugPrint(
          '🔍 Fallback 건물 목록: ${_allBuildings.map((b) => b.name).join(', ')}',
        );
      }

      // 🔥 수정: 올바른 메서드 호출 (언더스코어 제거)
      notifyDataChangeListeners();
    } catch (e) {
      _lastError = e.toString();
      _allBuildings = _getFallbackBuildings();
      _isLoaded = true;
      debugPrint('❌ 로딩 실패, 확장된 Fallback 사용: ${_allBuildings.length}개');
      debugPrint('🔍 오류 내용: $e');

      // 🔥 수정: 올바른 메서드 호출 (언더스코어 제거)
      notifyDataChangeListeners();
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }

    return _getCurrentBuildingsWithOperatingStatus();
  }

  /// 🔥 현재 시간 기준 운영상태가 적용된 건물 목록 반환
  List<Building> _getCurrentBuildingsWithOperatingStatus() {
    return _allBuildings.map((building) {
      final autoStatus = _getAutoOperatingStatusWithoutContext(
        building.baseStatus,
      );
      return building.copyWith(baseStatus: autoStatus);
    }).toList();
  }

  /// 🔥 확장된 Fallback 건물 데이터 (23개 건물)
  List<Building> _getFallbackBuildings() {
    return [
      Building(
        name: '우송도서관(W1)',
        info: '도서관 및 학습 공간',
        lat: 36.338076,
        lng: 127.446452,
        category: '학습시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5601',
        imageUrl: null,
        description: '메인 도서관',
      ),
      Building(
        name: '산학혁신관(W2)',
        info: '산학협력 관련 시설',
        lat: 36.339589,
        lng: 127.447295,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5602',
        imageUrl: null,
        description: '산학혁신관',
      ),
      Building(
        name: '학군단(W2-1)',
        info: '학군단 시설',
        lat: 36.339537,
        lng: 127.447746,
        category: '행정시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5603',
        imageUrl: null,
        description: '학군단',
      ),
      Building(
        name: '유학생기숙사(W3)',
        info: '유학생 기숙사',
        lat: 36.339464,
        lng: 127.446453,
        category: '기숙사',
        baseStatus: '24시간',
        hours: '24시간',
        phone: '042-821-5604',
        imageUrl: null,
        description: '유학생기숙사',
      ),
      Building(
        name: '철도물류관(W4)',
        info: '철도물류 관련 강의실',
        lat: 36.33876,
        lng: 127.445511,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5605',
        imageUrl: null,
        description: '철도물류관',
      ),
      Building(
        name: '보건의료과학관(W5)',
        info: '보건의료 관련 강의실',
        lat: 36.338067,
        lng: 127.444903,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5606',
        imageUrl: null,
        description: '보건의료과학관',
      ),
      Building(
        name: '교양교육관(W6)',
        info: '교양교육 관련 강의실',
        lat: 36.337507,
        lng: 127.445761,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5607',
        imageUrl: null,
        description: '교양교육관',
      ),
      Building(
        name: '우송관(W7)',
        info: '우송관 강의실',
        lat: 36.337149,
        lng: 127.44507,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5608',
        imageUrl: null,
        description: '우송관',
      ),
      Building(
        name: '우송유치원(W8)',
        info: '우송유치원',
        lat: 36.33749,
        lng: 127.444353,
        category: '교육시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5609',
        imageUrl: null,
        description: '우송유치원',
      ),
      Building(
        name: '정례원(W9)',
        info: '정례원 강의실',
        lat: 36.3371,
        lng: 127.444062,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5610',
        imageUrl: null,
        description: '정례원',
      ),
      Building(
        name: '사회복지융합관(W10)',
        info: '사회복지 관련 강의실',
        lat: 36.336656,
        lng: 127.443852,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5611',
        imageUrl: null,
        description: '사회복지융합관',
      ),
      Building(
        name: '체육관(W11)',
        info: '체육관 시설',
        lat: 36.335822,
        lng: 127.443289,
        category: '체육시설',
        baseStatus: '운영중',
        hours: '06:00-22:00',
        phone: '042-821-5612',
        imageUrl: null,
        description: '체육관(서캠)',
      ),
      Building(
        name: 'SICA(W12)',
        info: 'SICA 시설',
        lat: 36.335513,
        lng: 127.443778,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5613',
        imageUrl: null,
        description: 'SICA',
      ),
      Building(
        name: '우송타워(W13)',
        info: '우송타워',
        lat: 36.335634,
        lng: 127.444357,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5614',
        imageUrl: null,
        description: '우송타워',
      ),
      Building(
        name: 'Culinary Center(W14)',
        info: '요리 관련 시설',
        lat: 36.335419,
        lng: 127.444638,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5615',
        imageUrl: null,
        description: 'Culinary Center',
      ),
      Building(
        name: '식품건축관(W15)',
        info: '식품 및 건축 관련 강의실',
        lat: 36.335441,
        lng: 127.445383,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5616',
        imageUrl: null,
        description: '식품건축관',
      ),
      Building(
        name: '학생회관(W16)',
        info: '학생회관 및 편의시설',
        lat: 36.33604,
        lng: 127.44497,
        category: '학생시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5617',
        imageUrl: null,
        description: '학생회관',
      ),
      Building(
        name: 'W17 동관(W17-동관)',
        info: 'W17 동관 시설',
        lat: 36.3358485,
        lng: 127.4456995,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5618',
        imageUrl: null,
        description: 'W17 동관',
      ),
      Building(
        name: '미디어융합관(W17-서관)',
        info: '미디어융합관 시설',
        lat: 36.3359085,
        lng: 127.4455097,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5619',
        imageUrl: null,
        description: '미디어융합관',
      ),
      Building(
        name: '우송예술회관(W18)',
        info: '예술 관련 시설',
        lat: 36.336346,
        lng: 127.446151,
        category: '문화시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5620',
        imageUrl: null,
        description: '우송예술회관',
      ),
      Building(
        name: '앤디cut 아저씨 빌딩(W19)',
        info: '강의실 및 실습실',
        lat: 36.3365,
        lng: 127.4455372,
        category: '강의시설',
        baseStatus: '운영중',
        hours: '09:00-18:00',
        phone: '042-821-5621',
        imageUrl: null,
        description: '앤디cut 아저씨 빌딩',
      ),
      Building(
        name: '청운2숙',
        info: '기숙사 시설',
        lat: 36.3398982,
        lng: 127.4470519,
        category: '기숙사',
        baseStatus: '24시간',
        hours: '24시간',
        phone: '042-821-5622',
        imageUrl: null,
        description: '기숙사',
      ),
      Building(
        name: '24시간 편의점',
        info: '24시간 운영하는 편의점',
        lat: 36.337500,
        lng: 127.446000,
        category: '편의시설',
        baseStatus: '24시간',
        hours: '24시간',
        phone: '042-821-5678',
        imageUrl: null,
        description: '24시간 편의점',
      ),
    ];
  }

  /// 🔥 강제 데이터 새로고침 개선
  Future<void> forceRefresh() async {
    debugPrint('🔄 BuildingRepository 강제 새로고침');

    // 완전한 상태 리셋
    resetForNewSession();

    // 새로운 데이터 로딩
    await getAllBuildings(forceRefresh: true);

    if (_isLoaded && _allBuildings.isNotEmpty) {
      debugPrint('✅ 강제 새로고침 성공: ${_allBuildings.length}개 건물');
      notifyDataChangeListeners();
    } else {
      debugPrint('❌ 강제 새로고침 실패');
    }
  }

  /// 🔥 로딩 완료까지 대기
  Future<List<Building>> _waitForLoadingComplete() async {
    int attempts = 0;
    const maxAttempts = 50; // 최대 5초 대기

    while (_isLoading && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    return _getCurrentBuildingsWithOperatingStatus();
  }

  /// 🔥 데이터 새로고침 - Result 패턴 적용 (MapService에서 호출)
  Future<Result<void>> refresh() async {
    return await ResultHelper.runSafelyAsync(() async {
      AppLogger.info('BuildingRepository: 강제 새로고침', tag: 'REPO');
      await forceRefresh();
    }, 'BuildingRepository.refresh');
  }

  /// 🔥 검색 기능 - Result 패턴 적용
  Result<List<Building>> searchBuildings(String query) {
    return ResultHelper.runSafely(() {
      if (query.isEmpty) {
        return _getCurrentBuildingsWithOperatingStatus();
      }

      final filtered = _allBuildings.where((building) {
        final q = query.toLowerCase();
        return building.name.toLowerCase().contains(q) ||
            building.info.toLowerCase().contains(q) ||
            building.category.toLowerCase().contains(q);
      }).toList();

      return filtered.map((b) {
        final autoStatus = _getAutoOperatingStatusWithoutContext(b.baseStatus);
        return b.copyWith(baseStatus: autoStatus);
      }).toList();
    }, 'BuildingRepository.searchBuildings');
  }

  /// 🔥 카테고리별 건물 필터링 - Result 패턴 적용
  Result<List<Building>> getBuildingsByCategory(String category) {
    return ResultHelper.runSafely(() {
      final filtered = _allBuildings.where((building) {
        return building.category == category;
      }).toList();

      return filtered.map((building) {
        final autoStatus = _getAutoOperatingStatusWithoutContext(
          building.baseStatus,
        );
        return building.copyWith(baseStatus: autoStatus);
      }).toList();
    }, 'BuildingRepository.getBuildingsByCategory');
  }

  /// 🔥 운영 상태별 건물 가져오기 - Result 패턴 적용
  Result<List<Building>> getOperatingBuildings() {
    return ResultHelper.runSafely(() {
      final current = _getCurrentBuildingsWithOperatingStatus();
      return current
          .where(
            (building) =>
                building.baseStatus == '운영중' || building.baseStatus == '24시간',
          )
          .toList();
    }, 'BuildingRepository.getOperatingBuildings');
  }

  Result<List<Building>> getClosedBuildings() {
    return ResultHelper.runSafely(() {
      final current = _getCurrentBuildingsWithOperatingStatus();
      return current
          .where(
            (building) =>
                building.baseStatus == '운영종료' || building.baseStatus == '임시휴무',
          )
          .toList();
    }, 'BuildingRepository.getClosedBuildings');
  }

  /// 🔥 특정 건물 찾기 - Result 패턴 적용
  Result<Building?> findBuildingByName(String name) {
    return ResultHelper.runSafely(() {
      try {
        final current = _getCurrentBuildingsWithOperatingStatus();
        return current.firstWhere(
          (building) =>
              building.name.toLowerCase().contains(name.toLowerCase()),
        );
      } catch (e) {
        return null;
      }
    }, 'BuildingRepository.findBuildingByName');
  }

  /// 🔥 거리 계산 (하버사인 공식)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // 지구 반지름 (km)

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// 🔥 도를 라디안으로 변환
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// 🔥 근처 건물 찾기
  Result<List<Building>> getNearbyBuildings(
    double lat,
    double lng,
    double radiusKm,
  ) {
    return ResultHelper.runSafely(() {
      final current = _getCurrentBuildingsWithOperatingStatus();

      final nearby = current.where((building) {
        final distance = _calculateDistance(
          lat,
          lng,
          building.lat,
          building.lng,
        );
        return distance <= radiusKm;
      }).toList();

      // 거리순으로 정렬
      nearby.sort((a, b) {
        final distanceA = _calculateDistance(lat, lng, a.lat, a.lng);
        final distanceB = _calculateDistance(lat, lng, b.lat, b.lng);
        return distanceA.compareTo(distanceB);
      });

      return nearby;
    }, 'BuildingRepository.getNearbyBuildings');
  }

  /// 🔥 데이터 변경 리스너 관리
  void addDataChangeListener(Function(List<Building>) listener) {
    if (_isDisposed) return;

    _dataChangeListeners.add(listener);
    AppLogger.debug(
      '데이터 변경 리스너 추가 (총 ${_dataChangeListeners.length}개)',
      tag: 'REPO',
    );
  }

  void removeDataChangeListener(Function(List<Building>) listener) {
    if (_isDisposed) return;

    _dataChangeListeners.remove(listener);
    AppLogger.debug(
      '데이터 변경 리스너 제거 (총 ${_dataChangeListeners.length}개)',
      tag: 'REPO',
    );
  }

  /// 🔥 데이터 변경 리스너 알림 (public 메서드)
  void notifyDataChangeListeners() {
    if (_isDisposed) return;

    final currentBuildings = _getCurrentBuildingsWithOperatingStatus();
    AppLogger.debug(
      '데이터 변경 리스너들에게 알림 (${_dataChangeListeners.length}개)',
      tag: 'REPO',
    );

    for (final listener in _dataChangeListeners) {
      try {
        listener(currentBuildings);
      } catch (e) {
        AppLogger.info('데이터 변경 리스너 오류: $e', tag: 'REPO');
      }
    }
  }

  /// 🔥 캐시 무효화 - Result 패턴 적용
  Result<void> invalidateCache() {
    return ResultHelper.runSafely(() {
      AppLogger.info('BuildingRepository: 캐시 무효화', tag: 'REPO');
      _allBuildings.clear();
      _isLoaded = false;
      _lastLoadTime = null;
      _lastError = null;
      _safeNotifyListeners();
    }, 'BuildingRepository.invalidateCache');
  }

  /// 🔥 통계 정보 - Result 패턴 적용
  Result<Map<String, int>> getCategoryStats() {
    return ResultHelper.runSafely(() {
      final current = _getCurrentBuildingsWithOperatingStatus();
      final stats = <String, int>{};

      for (final building in current) {
        stats[building.category] = (stats[building.category] ?? 0) + 1;
      }

      AppLogger.debug('카테고리 통계: $stats', tag: 'REPO');
      return stats;
    }, 'BuildingRepository.getCategoryStats');
  }

  Result<Map<String, int>> getOperatingStats() {
    return ResultHelper.runSafely(() {
      final current = _getCurrentBuildingsWithOperatingStatus();
      final stats = <String, int>{};

      for (final building in current) {
        stats[building.baseStatus] = (stats[building.baseStatus] ?? 0) + 1;
      }

      AppLogger.debug('운영 상태 통계: $stats', tag: 'REPO');
      return stats;
    }, 'BuildingRepository.getOperatingStats');
  }

  /// 🔥 Repository 상태 정보
  Map<String, dynamic> getRepositoryStatus() {
    return {
      'isLoaded': _isLoaded,
      'isLoading': _isLoading,
      'buildingCount': _allBuildings.length,
      'lastError': _lastError,
      'lastLoadTime': _lastLoadTime?.toIso8601String(),
      'hasData': _allBuildings.isNotEmpty,
      'isDisposed': _isDisposed,
      'listenersCount': _dataChangeListeners.length,
    };
  }

  /// 🔥 Context 없이 운영상태 평가 (fallback 용)
  String _getAutoOperatingStatusWithoutContext(String baseStatus) {
    if (baseStatus == '24시간' || baseStatus == '임시휴무' || baseStatus == '휴무') {
      return baseStatus;
    }

    final now = DateTime.now().hour;
    return (now >= 9 && now < 18) ? '운영중' : '운영종료';
  }

  /// 🔥 Repository 정리 - 안전한 dispose
  @override
  void dispose() {
    if (_isDisposed) return;

    AppLogger.info('BuildingRepository 정리', tag: 'REPO');
    _isDisposed = true;
    _dataChangeListeners.clear();
    _allBuildings.clear();
    _buildingDataService.dispose();
    super.dispose();
  }
}
