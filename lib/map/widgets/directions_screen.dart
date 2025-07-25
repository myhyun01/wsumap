// lib/map/widgets/directions_screen.dart - 통합 API 적용 버전 (수정됨)

import 'package:flutter/material.dart';
import 'package:flutter_application_1/generated/app_localizations.dart';
import 'package:flutter_application_1/inside/building_map_page.dart';
import 'package:flutter_application_1/models/building.dart';
import 'package:flutter_application_1/models/search_result.dart';
import 'package:flutter_application_1/services/integrated_search_service.dart';
import 'package:flutter_application_1/map/building_data.dart';
import 'package:flutter_application_1/managers/location_manager.dart';
import 'package:flutter_application_1/unified_navigation_stepper_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/services/unified_path_service.dart';

class DirectionsScreen extends StatefulWidget {
  final Building? presetStart;
  final Building? presetEnd;
  final Map<String, dynamic>? roomData;

  const DirectionsScreen({
    super.key,
    this.presetStart,
    this.presetEnd,
    this.roomData,
  });

  @override
  State<DirectionsScreen> createState() => _DirectionsScreenState();
}

class _DirectionsScreenState extends State<DirectionsScreen> {
  Building? _startBuilding;
  Building? _endBuilding;

  // 🔥 호실 정보 추가
  Map<String, dynamic>? _startRoomInfo;
  Map<String, dynamic>? _endRoomInfo;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;
  String? _searchType; // 'start' or 'end'
  List<Building> _recentSearches = [];

  bool _needsCoordinateUpdate = false;

  // 네비게이션 상태 관련
  bool _isNavigationActive = false;
  String _estimatedDistance = '';
  String _estimatedTime = '';

  // 🔥 통합 API 미리보기 정보
  UnifiedPathResponse? _previewResponse;
  bool _isCalculatingPreview = false;

  @override
  void initState() {
    super.initState();

    if (widget.roomData != null) {
      _handleRoomData(widget.roomData!);
    } else {
      // 🔥 preset 건물들도 건물 코드 추출
      if (widget.presetStart != null) {
        final startCode = _extractBuildingCode(widget.presetStart!.name);
        _startBuilding = Building(
          name: startCode,
          info: widget.presetStart!.info,
          lat: widget.presetStart!.lat,
          lng: widget.presetStart!.lng,
          category: widget.presetStart!.category,
          baseStatus: widget.presetStart!.baseStatus,
          hours: widget.presetStart!.hours,
          phone: widget.presetStart!.phone,
          imageUrl: widget.presetStart!.imageUrl,
          description: widget.presetStart!.description,
        );
      }

      if (widget.presetEnd != null) {
        final endCode = _extractBuildingCode(widget.presetEnd!.name);
        _endBuilding = Building(
          name: endCode,
          info: widget.presetEnd!.info,
          lat: widget.presetEnd!.lat,
          lng: widget.presetEnd!.lng,
          category: widget.presetEnd!.category,
          baseStatus: widget.presetEnd!.baseStatus,
          hours: widget.presetEnd!.hours,
          phone: widget.presetEnd!.phone,
          imageUrl: widget.presetEnd!.imageUrl,
          description: widget.presetEnd!.description,
        );
      }
    }

    if (_startBuilding != null) {
      debugPrint('PresetStart 건물: ${_startBuilding!.name}');
      if (_startBuilding!.lat == 0.0 && _startBuilding!.lng == 0.0) {
        debugPrint('경고: 출발지 좌표가 (0,0)입니다');
      }
    }

    if (_endBuilding != null) {
      debugPrint('PresetEnd 건물: ${_endBuilding!.name}');
    }

    _recentSearches = [];

    // 출발지와 도착지가 모두 설정되면 미리보기 계산
    if (_startBuilding != null && _endBuilding != null) {
      _calculateRoutePreview();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationManager = Provider.of<LocationManager>(context, listen: false);
      locationManager.requestLocationQuickly(); // 언어 변경 후에도 위치 강제 갱신
    });
  }

  void _handleRoomData(Map<String, dynamic> roomData) {
    try {
      debugPrint('=== _handleRoomData 시작 ===');
      debugPrint('받은 방 정보: $roomData');

      final String roomName = (roomData['roomName'] ?? '').toString();
      final String buildingNameRaw = (roomData['buildingName'] ?? '')
          .toString();
      final String buildingName = _extractBuildingCode(
        buildingNameRaw,
      ); // 🔥 건물 코드만 사용
      final String type = (roomData['type'] ?? '').toString();

      final String floorNumberStr = (roomData['floorNumber'] ?? '1')
          .toString(); // 🔥 항상 문자열

      final roomInfo = {
        'roomName': roomName,
        'buildingName': buildingName,
        'floorNumber': floorNumberStr,
      };

      final roomBuilding = Building(
        name: buildingName,
        info:
            '${floorNumberStr.isNotEmpty ? "${floorNumberStr}층 " : ""}$roomName호',
        lat: 0.0,
        lng: 0.0,
        category: '강의실',
        baseStatus: '사용가능',
        hours: '',
        phone: '',
        imageUrl: '',
        description:
            '$buildingName ${floorNumberStr.isNotEmpty ? "${floorNumberStr}층 " : ""}$roomName호',
      );

      if (type == 'start') {
        setState(() {
          _startBuilding = roomBuilding;
          _startRoomInfo = roomInfo;
        });
        debugPrint('출발지로 설정: $buildingName ($floorNumberStr층 $roomName호)');
      } else if (type == 'end') {
        setState(() {
          _endBuilding = roomBuilding;
          _endRoomInfo = roomInfo;
        });
        debugPrint('도착지로 설정: $buildingName ($floorNumberStr층 $roomName호)');
      }

      _needsCoordinateUpdate = true;

      debugPrint('=== _handleRoomData 완료 ===');
    } catch (e, stackTrace) {
      debugPrint('❌ _handleRoomData 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('방 정보 처리 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 추가: 건물명에서 건물 코드 추출 헬퍼 메서드

  // 6. _extractBuildingCode 헬퍼 메서드 (이미 제공했지만 다시 포함)
  String _extractBuildingCode(String buildingName) {
    final regex = RegExp(r'\(([^)]+)\)');
    final match = regex.firstMatch(buildingName);
    if (match != null) {
      return match.group(1)!;
    }
    final spaceSplit = buildingName.trim().split(' ');
    if (spaceSplit.isNotEmpty &&
        RegExp(r'^[A-Za-z0-9\-]+$').hasMatch(spaceSplit[0])) {
      return spaceSplit[0];
    }
    return buildingName;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 🔥 좌표 업데이트가 필요한 경우
    if (_needsCoordinateUpdate) {
      _updateBuildingCoordinates();
      _needsCoordinateUpdate = false;
    }
  }

  void _updateBuildingCoordinates() {
    try {
      final buildings = BuildingDataProvider.getBuildingData(context);

      // 출발지 좌표 업데이트
      if (_startBuilding != null && _startBuilding!.lat == 0.0) {
        final matchingBuilding = _findMatchingBuilding(
          buildings,
          _startBuilding!.name,
        );
        if (matchingBuilding != null) {
          setState(() {
            _startBuilding = Building(
              name: _startBuilding!.name,
              info: _startBuilding!.info,
              lat: matchingBuilding.lat,
              lng: matchingBuilding.lng,
              category: _startBuilding!.category,
              baseStatus: _startBuilding!.baseStatus,
              hours: _startBuilding!.hours,
              phone: _startBuilding!.phone,
              imageUrl: _startBuilding!.imageUrl,
              description: _startBuilding!.description,
            );
          });
          debugPrint(
            '✅ 출발지 좌표 업데이트: ${_startBuilding!.name} -> (${matchingBuilding.lat}, ${matchingBuilding.lng})',
          );
        } else {
          debugPrint('⚠️ 출발지 건물 좌표를 찾을 수 없음: ${_startBuilding!.name}');
        }
      }

      // 도착지 좌표 업데이트
      if (_endBuilding != null && _endBuilding!.lat == 0.0) {
        final matchingBuilding = _findMatchingBuilding(
          buildings,
          _endBuilding!.name,
        );
        if (matchingBuilding != null) {
          setState(() {
            _endBuilding = Building(
              name: _endBuilding!.name,
              info: _endBuilding!.info,
              lat: matchingBuilding.lat,
              lng: matchingBuilding.lng,
              category: _endBuilding!.category,
              baseStatus: _endBuilding!.baseStatus,
              hours: _endBuilding!.hours,
              phone: _endBuilding!.phone,
              imageUrl: _endBuilding!.imageUrl,
              description: _endBuilding!.description,
            );
          });
          debugPrint(
            '✅ 도착지 좌표 업데이트: ${_endBuilding!.name} -> (${matchingBuilding.lat}, ${matchingBuilding.lng})',
          );
        } else {
          debugPrint('⚠️ 도착지 건물 좌표를 찾을 수 없음: ${_endBuilding!.name}');
        }
      }

      // 좌표 업데이트 후 미리보기 재계산
      if (_startBuilding != null && _endBuilding != null) {
        _calculateRoutePreview();
      }
    } catch (e) {
      debugPrint('❌ 건물 좌표 업데이트 오류: $e');
    }
  }

  Building? _findMatchingBuilding(
    List<Building> buildings,
    String buildingCode,
  ) {
    try {
      return buildings.firstWhere(
        (building) =>
            building.name.contains(buildingCode) ||
            building.name == buildingCode ||
            _extractBuildingCode(building.name) == buildingCode,
      );
    } catch (e) {
      // firstWhere에서 찾지 못하면 StateError가 발생하므로 null 반환
      return null;
    }
  }

  // 🔥 통합 API를 사용한 경로 미리보기 계산
  // 3. 경로 미리보기 계산 시 (건물 코드/층번호 일치 보장)
Future<void> _calculateRoutePreview() async {
  try {
    if (_startBuilding == null || _endBuilding == null) {
      debugPrint('⚠️ 출발지 또는 도착지가 없어서 경로 계산 불가');
      return;
    }

    setState(() => _isCalculatingPreview = true);
    setState(() => _isCalculatingPreview = true);

    debugPrint('🔍 경로 미리보기 계산 시작');
    debugPrint('   출발지: ${_startBuilding!.name}');
    debugPrint('   도착지: ${_endBuilding!.name}');
    debugPrint('   출발 호실: ${_startRoomInfo?['roomName'] ?? 'None'}');
    debugPrint('   도착 호실: ${_endRoomInfo?['roomName'] ?? 'None'}');

      UnifiedPathResponse? response;

    // 🔥 1. 호실-호실 경로
    if (_startRoomInfo != null && _endRoomInfo != null) {
      response = await _calculateRoomToRoomPath();
    }
    // 🔥 2. 호실-건물 경로  
    else if (_startRoomInfo != null) {
      response = await _calculateRoomToBuildingPath();
    }
    // 🔥 3. 건물-호실 경로 (내 위치 → 호실 포함)
    else if (_endRoomInfo != null) {
      response = await _calculateBuildingToRoomPath();
    }
    // 🔥 4. 건물-건물 경로 (내 위치 → 건물 포함)
    else {
      response = await _calculateBuildingToBuildingPath();
    }

    // 🔥 응답 처리 및 검증
    await _processRouteResponse(response);

  } catch (e) {
    debugPrint('❌ 경로 미리보기 계산 전체 오류: $e');
    await _handleRouteCalculationError(e);
  } finally {
    if (mounted) {
      setState(() => _isCalculatingPreview = false);
    }
  }
}

Future<UnifiedPathResponse?> _calculateRoomToRoomPath() async {
  try {
    debugPrint('🏠 호실-호실 경로 계산');
    
    // 🔥 안전한 호실 정보 추출
    final fromBuilding = _safeExtractRoomData(_startRoomInfo!, 'buildingName');
    final fromFloor = _safeExtractFloorNumber(_startRoomInfo!, 'floorNumber');
    final fromRoom = _safeExtractRoomData(_startRoomInfo!, 'roomName');
    
    final toBuilding = _safeExtractRoomData(_endRoomInfo!, 'buildingName');
    final toFloor = _safeExtractFloorNumber(_endRoomInfo!, 'floorNumber');
    final toRoom = _safeExtractRoomData(_endRoomInfo!, 'roomName');
    
    // 🔥 필수 정보 검증
    if (fromBuilding.isEmpty || fromRoom.isEmpty || 
        toBuilding.isEmpty || toRoom.isEmpty) {
      throw Exception('호실 정보가 불완전합니다: from($fromBuilding-$fromRoom) to($toBuilding-$toRoom)');
    }
    
    if (fromFloor < 1 || toFloor < 1) {
      throw Exception('층 번호가 유효하지 않습니다: from($fromFloor층) to($toFloor층)');
    }
    
    debugPrint('✅ 호실-호실 경로: $fromBuilding $fromFloor층 $fromRoom호 → $toBuilding $toFloor층 $toRoom호');
    
    final response = await UnifiedPathService.getPathBetweenRooms(
      fromBuilding: fromBuilding,
      fromFloor: fromFloor,
      fromRoom: fromRoom,
      toBuilding: toBuilding,
      toFloor: toFloor,
      toRoom: toRoom,
    );
    
    if (response == null) {
      throw Exception('호실 간 경로 API 응답이 null입니다');
    }
    
    return response;
  } catch (e) {
    debugPrint('❌ 호실-호실 경로 계산 오류: $e');
    throw Exception('호실 간 경로 계산 실패: $e');
  }
}

// 🔥 호실-건물 경로 계산
Future<UnifiedPathResponse?> _calculateRoomToBuildingPath() async {
  try {
    debugPrint('🏠 호실-건물 경로 계산');
    
    final fromBuilding = _safeExtractRoomData(_startRoomInfo!, 'buildingName');
    final fromFloor = _safeExtractFloorNumber(_startRoomInfo!, 'floorNumber');
    final fromRoom = _safeExtractRoomData(_startRoomInfo!, 'roomName');
    
    if (fromBuilding.isEmpty || fromRoom.isEmpty) {
      throw Exception('출발 호실 정보가 불완전합니다: $fromBuilding-$fromRoom');
    }
    
    if (fromFloor < 1) {
      throw Exception('출발 층 번호가 유효하지 않습니다: $fromFloor층');
    }
    
    debugPrint('✅ 호실-건물 경로: $fromBuilding $fromFloor층 $fromRoom호 → ${_endBuilding!.name}');
    
    final response = await UnifiedPathService.getPathFromRoom(
      fromBuilding: fromBuilding,
      fromFloor: fromFloor,
      fromRoom: fromRoom,
      toBuilding: _endBuilding!,
    );
    
    if (response == null) {
      throw Exception('호실-건물 경로 API 응답이 null입니다');
    }
    
    return response;
  } catch (e) {
    debugPrint('❌ 호실-건물 경로 계산 오류: $e');
    throw Exception('호실에서 건물로의 경로 계산 실패: $e');
  }
}

// 🔥 건물-호실 경로 계산
// 🔥 _calculateBuildingToRoomPath 간단 수정 - "내 위치" 체크 추가

Future<UnifiedPathResponse?> _calculateBuildingToRoomPath() async {
  try {
    debugPrint('🏠 건물-호실 경로 계산');
    
    final toBuilding = _safeExtractRoomData(_endRoomInfo!, 'buildingName');
    final toFloor = _safeExtractFloorNumber(_endRoomInfo!, 'floorNumber');
    final toRoom = _safeExtractRoomData(_endRoomInfo!, 'roomName');
    
    if (toBuilding.isEmpty || toRoom.isEmpty) {
      throw Exception('도착 호실 정보가 불완전합니다: $toBuilding-$toRoom');
    }
    
    if (toFloor < 1) {
      throw Exception('도착 층 번호가 유효하지 않습니다: $toFloor층');
    }
    
    // 🔥 "내 위치"든 일반 건물이든 동일하게 처리
    debugPrint('✅ 건물-호실 경로: ${_startBuilding!.name} → $toBuilding $toFloor층 $toRoom호');
    
    final response = await UnifiedPathService.getPathToRoom(
      fromBuilding: _startBuilding!,  // "내 위치"도 그대로 전달
      toBuilding: toBuilding,
      toFloor: toFloor,
      toRoom: toRoom,
    );
    
    if (response == null) {
      throw Exception('건물-호실 경로 API 응답이 null입니다');
    }
    
    return response;
  } catch (e) {
    debugPrint('❌ 건물-호실 경로 계산 오류: $e');
    throw Exception('건물에서 호실로의 경로 계산 실패: $e');
  }
}

// 🔥 건물-건물 경로 계산
Future<UnifiedPathResponse?> _calculateBuildingToBuildingPath() async {
  try {
    debugPrint('🏢 건물-건물 경로 계산');
    
    final startName = _startBuilding!.name;
    final endName = _endBuilding!.name;
    
    if (startName.isEmpty || endName.isEmpty) {
      throw Exception('건물 이름이 비어있습니다: start($startName) end($endName)');
    }
    
    // 🔥 "내 위치"든 일반 건물이든 동일하게 처리
    debugPrint('✅ 건물-건물 경로: $startName → $endName');
    
    final response = await UnifiedPathService.getPathBetweenBuildings(
      fromBuilding: _startBuilding!,  // "내 위치"도 그대로 전달
      toBuilding: _endBuilding!,
    );
    
    if (response == null) {
      throw Exception('건물 간 경로 API 응답이 null입니다');
    }
    
    return response;
  } catch (e) {
    debugPrint('❌ 건물-건물 경로 계산 오류: $e');
    throw Exception('건물 간 경로 계산 실패: $e');
  }
}

// 🔥 경로 응답 처리 및 검증
Future<void> _processRouteResponse(UnifiedPathResponse? response) async {
  try {
    if (response == null) {
      throw Exception('경로 계산 API 응답이 null입니다');
    }
    
    if (!mounted) {
      debugPrint('⚠️ 컴포넌트가 unmounted 상태입니다');
      return;
    }
    
    // 🔥 성공적으로 응답 처리
    setState(() {
      _previewResponse = response;
    });
    
    // 🔥 거리/시간 계산
    _calculateEstimatesFromResponse(response);
    
    debugPrint('✅ 경로 미리보기 계산 완료');
    debugPrint('   경로 타입: ${response.type}');
    debugPrint('   예상 거리: $_estimatedDistance');
    debugPrint('   예상 시간: $_estimatedTime');
    
  } catch (e) {
    debugPrint('❌ 경로 응답 처리 오류: $e');
    throw Exception('경로 응답 처리 실패: $e');
  }
}

// 🔥 경로 계산 오류 처리
Future<void> _handleRouteCalculationError(dynamic error) async {
  try {
    if (!mounted) return;
    
    // 🔥 오류 상태 초기화
    setState(() {
      _previewResponse = null;
      _estimatedDistance = '';
      _estimatedTime = '';
    });
    
    final errorMessage = error.toString();
    debugPrint('🚨 경로 계산 오류 처리: $errorMessage');
    
    // 🔥 오류 타입별 사용자 알림
    String userMessage;
    Color messageColor;
    
    if (errorMessage.contains('호실')) {
      userMessage = '호실 경로 계산 중 오류가 발생했습니다. 건물 단위로 검색해보세요.';
      messageColor = Colors.orange;
    } else if (errorMessage.contains('위치')) {
      userMessage = '현재 위치를 확인할 수 없습니다. 다시 시도해주세요.';
      messageColor = Colors.blue;
    } else if (errorMessage.contains('API') || errorMessage.contains('null')) {
      userMessage = '서버 연결에 문제가 있습니다. 잠시 후 다시 시도해주세요.';
      messageColor = Colors.red;
    } else {
      userMessage = '경로 계산 중 오류가 발생했습니다. 다시 시도해주세요.';
      messageColor = Colors.red;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userMessage),
        backgroundColor: messageColor,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '다시 시도',
          textColor: Colors.white,
          onPressed: () {
            _calculateRoutePreview();
          },
        ),
      ),
    );
    
  } catch (e) {
    debugPrint('❌ 오류 처리 중 추가 오류: $e');
  }
}

String _safeExtractRoomData(Map<String, dynamic> roomInfo, String key) {
  try {
    final value = roomInfo[key];
    if (value == null) return '';
    return value.toString().trim();
  } catch (e) {
    debugPrint('❌ 호실 데이터 추출 오류 ($key): $e');
    return '';
  }
}

/// 🔥 안전한 층 번호 추출 헬퍼 메서드
int _safeExtractFloorNumber(Map<String, dynamic> roomInfo, String key) {
  try {
    final value = roomInfo[key];
    if (value == null) return 1;
    
    final floorStr = value.toString().trim();
    if (floorStr.isEmpty) return 1;
    
    final floorNumber = int.tryParse(floorStr);
    return floorNumber ?? 1;
  } catch (e) {
    debugPrint('❌ 층 번호 추출 오류 ($key): $e');
    return 1;
  }
}

  // 🔥 통합 API 응답으로부터 예상 시간과 거리 계산
  void _calculateEstimatesFromResponse(UnifiedPathResponse response) {
  try {
    double totalDistance = 0;
    
    // 🔥 null 체크 강화
    if (response.result.departureIndoor?.path.distance != null) {
      totalDistance += response.result.departureIndoor!.path.distance;
    }
    if (response.result.outdoor?.path.distance != null) {
      totalDistance += response.result.outdoor!.path.distance;
    }
    if (response.result.arrivalIndoor?.path.distance != null) {
      totalDistance += response.result.arrivalIndoor!.path.distance;
    }
    
    // 🔥 거리 포맷팅 - 안전한 계산
    if (totalDistance <= 0) {
      _estimatedDistance = '0m';
      _estimatedTime = '0분';
      return;
    }
    
    if (totalDistance < 1000) {
      _estimatedDistance = '${totalDistance.round()}m';
    } else {
      _estimatedDistance = '${(totalDistance / 1000).toStringAsFixed(1)}km';
    }
    
    // 🔥 예상 시간 계산 - 안전한 계산
    const double walkingSpeedKmh = 4.0;
    final double timeInHours = totalDistance / 1000 / walkingSpeedKmh;
    final int timeInMinutes = (timeInHours * 60).round();
    
    if (timeInMinutes <= 0) {
      _estimatedTime = '1분 이내';
    } else if (timeInMinutes < 60) {
      _estimatedTime = '도보 ${timeInMinutes}분';
    } else {
      final int hours = timeInMinutes ~/ 60;
      final int minutes = timeInMinutes % 60;
      if (minutes == 0) {
        _estimatedTime = '도보 ${hours}시간';
      } else {
        _estimatedTime = '도보 ${hours}시간 ${minutes}분';
      }
    }

    debugPrint('📊 통합 API 기반 예상: 거리 $_estimatedDistance, 시간 $_estimatedTime');
    
  } catch (e) {
    debugPrint('❌ 거리/시간 계산 오류: $e');
    _estimatedDistance = '계산 불가';
    _estimatedTime = '계산 불가';
  }
}

  Future<void> _onSearchChanged() async {
  final query = _searchController.text.trim();
  
  if (query.isEmpty) {
    setState(() {
      _searchResults = [];
      _isSearching = false;
      _isLoading = false;
    });
    return;
  }

  // 🔥 "내 위치" 관련 검색은 건너뛰기
  final lowercaseQuery = query.toLowerCase();
  if (lowercaseQuery.contains('내 위치') || 
      lowercaseQuery.contains('내위치') || 
      lowercaseQuery.contains('현재위치') || 
      lowercaseQuery.contains('현재 위치') ||
      lowercaseQuery.contains('my location') ||
      lowercaseQuery.contains('current location')) {
    setState(() {
      _searchResults = [];
      _isSearching = false;
      _isLoading = false;
    });
    debugPrint('⚠️ "내 위치" 관련 검색은 건너뛰기: $query');
    return;
  }

  setState(() {
    _isSearching = true;
    _isLoading = true;
  });

  try {
    final results = await IntegratedSearchService.search(query, context);
    
    if (mounted) {
      setState(() {
        _searchResults = results ?? []; // null 체크 추가
        _isLoading = false;
      });
    }
  } catch (e) {
    debugPrint('❌ 검색 오류: $e');
    if (mounted) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
    }
  }
}

  void _selectStartLocation() {
    setState(() {
      _searchType = 'start';
      _isSearching = false;
      _isLoading = false;
      _searchResults = [];
      _searchController.clear();
    });
    _focusNode.requestFocus();
  }

  void _selectEndLocation() {
    setState(() {
      _searchType = 'end';
      _isSearching = false;
      _isLoading = false;
      _searchResults = [];
      _searchController.clear();
    });
    _focusNode.requestFocus();
  }

 // 2. 검색 결과 선택 시 (건물/호실 모두 건물 코드만 사용)
void _onSearchResultSelected(SearchResult result) {
  try {
    Building building;
    Map<String, dynamic>? roomInfo;

    if (result.isRoom) {
      building = result.toBuildingWithRoomLocation();
      roomInfo = {
        'roomName': result.roomNumber ?? '',
        'buildingName': _extractBuildingCode(result.building.name),
        'floorNumber': result.floorNumber?.toString() ?? '1',
      };
    } else {
      final buildingCode = _extractBuildingCode(result.building.name);
      building = Building(
        name: buildingCode,
        info: result.building.info,
        lat: result.building.lat,
        lng: result.building.lng,
        category: result.building.category,
        baseStatus: result.building.baseStatus,
        hours: result.building.hours,
        phone: result.building.phone,
        imageUrl: result.building.imageUrl,
        description: result.building.description,
      );
    }

    // 🔥 안전한 리스트 업데이트
    setState(() {
      try {
        _recentSearches.removeWhere((b) => b.name == building.name);
        _recentSearches.insert(0, building);
        if (_recentSearches.length > 5) {
          _recentSearches = _recentSearches.take(5).toList();
        }
      } catch (e) {
        debugPrint('❌ 최근 검색 목록 업데이트 오류: $e');
        _recentSearches = [building]; // 안전하게 초기화
      }
    });

    if (_searchType == 'start') {
      setState(() {
        _startBuilding = building;
        _startRoomInfo = roomInfo;
        _searchType = null;
        _isSearching = false;
        _isLoading = false;
        _searchResults = [];
        _searchController.clear();
      });
      debugPrint('✅ 출발지 설정: ${building.name}');
    } else if (_searchType == 'end') {
      setState(() {
        _endBuilding = building;
        _endRoomInfo = roomInfo;
        _searchType = null;
        _isSearching = false;
        _isLoading = false;
        _searchResults = [];
        _searchController.clear();
      });
      debugPrint('✅ 도착지 설정: ${building.name}');
    }

    _focusNode.unfocus();
    _focusNode.unfocus();

    // 🔥 안전한 경로 미리보기 계산
    if (_startBuilding != null && _endBuilding != null) {
      Future.microtask(() => _calculateRoutePreview());
    }
    
  } catch (e) {
    debugPrint('❌ 검색 결과 선택 오류: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('선택 중 오류가 발생했습니다. 다시 시도해주세요.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

  void _onBuildingSelected(Building building) {
  try {
    final buildingCode = _extractBuildingCode(building.name);
    final cleanBuilding = Building(
      name: buildingCode,
      info: building.info,
      lat: building.lat,
      lng: building.lng,
      category: building.category,
      baseStatus: building.baseStatus,
      hours: building.hours,
      phone: building.phone,
      imageUrl: building.imageUrl,
      description: building.description,
    );

    // 🔥 안전한 리스트 업데이트
    setState(() {
      try {
        _recentSearches.removeWhere((b) => b.name == cleanBuilding.name);
        _recentSearches.insert(0, cleanBuilding);
        if (_recentSearches.length > 5) {
          _recentSearches = _recentSearches.take(5).toList();
        }
      } catch (e) {
        debugPrint('❌ 최근 검색 목록 업데이트 오류: $e');
        _recentSearches = [cleanBuilding]; // 안전하게 초기화
      }
    });

    if (_searchType == 'start') {
      setState(() {
        _startBuilding = cleanBuilding;
        _startRoomInfo = null;
        _searchType = null;
        _isSearching = false;
        _isLoading = false;
        _searchResults = [];
        _searchController.clear();
      });
      debugPrint('✅ 출발지 건물 설정: ${cleanBuilding.name}');
    } else if (_searchType == 'end') {
      setState(() {
        _endBuilding = cleanBuilding;
        _endRoomInfo = null;
        _searchType = null;
        _isSearching = false;
        _isLoading = false;
        _searchResults = [];
        _searchController.clear();
      });
      debugPrint('✅ 도착지 건물 설정: ${cleanBuilding.name}');
    }
    
    _focusNode.unfocus();

    // 🔥 안전한 경로 미리보기 계산
    if (_startBuilding != null && _endBuilding != null) {
      Future.microtask(() => _calculateRoutePreview());
    }
    
  } catch (e) {
    debugPrint('❌ 건물 선택 오류: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('건물 선택 중 오류가 발생했습니다. 다시 시도해주세요.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

  void _swapLocations() {
    if (_startBuilding != null && _endBuilding != null) {
      setState(() {
        final tempBuilding = _startBuilding;
        final tempRoomInfo = _startRoomInfo;

        _startBuilding = _endBuilding;
        _startRoomInfo = _endRoomInfo;

        _endBuilding = tempBuilding;
        _endRoomInfo = tempRoomInfo;
      });

      // 🔥 교환 후 미리보기 재계산
      _calculateRoutePreview();
    }
  }

  // 🔥 통합 네비게이션 시작 (기존 _startNavigation 대체)
void _startUnifiedNavigation() {
  try {
    debugPrint('=== 통합 네비게이션 시작 ===');
    debugPrint('출발지: ${_startBuilding?.name} (호실: ${_startRoomInfo?['roomName'] ?? 'None'})');
    debugPrint('도착지: ${_endBuilding?.name} (호실: ${_endRoomInfo?['roomName'] ?? 'None'})');
    debugPrint('PathResponse 상태: ${_previewResponse != null ? '있음' : 'null'}');

    if (_startBuilding == null || _endBuilding == null) {
      debugPrint('❌ 출발지 또는 도착지가 설정되지 않음');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('출발지와 도착지를 모두 설정해주세요'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 🔥 pathResponse null 체크 및 재계산
    if (_previewResponse == null) {
      debugPrint('⚠️ pathResponse가 null입니다. 경로를 다시 계산합니다...');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('경로를 계산하는 중...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );

      // 경로 재계산 후 네비게이션 시작
      _calculateRoutePreview().then((_) {
        if (_previewResponse != null) {
          _proceedWithNavigation();
        } else {
          _handleNavigationFailure();
        }
      }).catchError((error) {
        debugPrint('❌ 경로 재계산 실패: $error');
        _handleNavigationFailure();
      });
      
      return;
    }

    // pathResponse가 있으면 바로 진행
    _proceedWithNavigation();

  } catch (e) {
    debugPrint('❌ _startUnifiedNavigation 전체 오류: $e');
    _handleNavigationFailure();
  }
}

void _proceedWithNavigation() {
  try {
    debugPrint('✅ 경로 데이터로 네비게이션 시작');

    // 🔥 통합 네비게이션 데이터 구성
    final unifiedNavigationData = {
      'type': 'unified_navigation',
      'start': _startBuilding,
      'end': _endBuilding,
      'startRoomInfo': _startRoomInfo,
      'endRoomInfo': _endRoomInfo,
      'useCurrentLocation': _startBuilding!.name == '내 위치',
      'estimatedDistance': _estimatedDistance,
      'estimatedTime': _estimatedTime,
      'pathResponse': _previewResponse,
      'showNavigationStatus': true,
    };

    debugPrint('✅ 통합 네비게이션 데이터 구성 완료');

    // === 안전한 단계별 네비게이션 데이터 추출 ===
    final departureIndoor = _previewResponse?.result?.departureIndoor;
    final outdoor = _previewResponse?.result?.outdoor;
    final arrivalIndoor = _previewResponse?.result?.arrivalIndoor;

    // 🔥 안전한 출발 실내 노드 리스트
    final List<String> departureNodeIds = [];
    if (departureIndoor?.path?.path != null) {
      try {
        departureNodeIds.addAll(
          (departureIndoor!.path.path).map((e) => e.toString()).toList()
        );
      } catch (e) {
        debugPrint('❌ 출발 실내 노드 추출 오류: $e');
      }
    }

    // 🔥 안전한 실외 경로 좌표 리스트
    final List<Map<String, dynamic>> outdoorPath = [];
    if (outdoor?.path?.path != null) {
      try {
        final pathData = outdoor!.path.path;
        if (pathData is List) {
          for (final item in pathData) {
            if (item is Map<String, dynamic>) {
              outdoorPath.add(item);
            }
          }
        }
      } catch (e) {
        debugPrint('❌ 실외 경로 추출 오류: $e');
      }
    }

    // 🔥 안전한 실외 거리
    final double outdoorDistance = outdoor?.path?.distance ?? 0.0;

    // 🔥 안전한 도착 실내 노드 리스트
    final List<String> arrivalNodeIds = [];
    if (arrivalIndoor?.path?.path != null) {
      try {
        arrivalNodeIds.addAll(
          (arrivalIndoor!.path.path).map((e) => e.toString()).toList()
        );
      } catch (e) {
        debugPrint('❌ 도착 실내 노드 추출 오류: $e');
      }
    }

    // 🔥 안전한 건물 코드 추출
    final String departureBuilding = _extractBuildingCode(_startBuilding?.name ?? '');
    final String arrivalBuilding = _extractBuildingCode(_endBuilding?.name ?? '');

    debugPrint('📊 네비게이션 데이터 요약:');
    debugPrint('   출발 노드: ${departureNodeIds.length}개');
    debugPrint('   실외 경로: ${outdoorPath.length}개 좌표');
    debugPrint('   실외 거리: ${outdoorDistance}m');
    debugPrint('   도착 노드: ${arrivalNodeIds.length}개');

    // 🔥 최소한의 데이터 검증
    if (departureBuilding.isEmpty || arrivalBuilding.isEmpty) {
      throw Exception('건물 정보가 불완전합니다');
    }

    // 단계별 네비게이션 Wrapper로 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UnifiedNavigationStepperPage(
          departureBuilding: departureBuilding,
          departureNodeIds: departureNodeIds,
          outdoorPath: outdoorPath,
          outdoorDistance: outdoorDistance,
          arrivalBuilding: arrivalBuilding,
          arrivalNodeIds: arrivalNodeIds,
        ),
      ),
    );

  } catch (e) {
    debugPrint('❌ 네비게이션 진행 오류: $e');
    _handleNavigationFailure();
  }
}

void _handleNavigationFailure() {
  if (mounted) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('네비게이션을 시작할 수 없습니다. 경로를 다시 확인해주세요.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }
}

  void _cancelSearch() {
    setState(() {
      _searchType = null;
      _isSearching = false;
      _isLoading = false;
      _searchResults = [];
      _searchController.clear();
    });
    _focusNode.unfocus();
  }

  void _stopNavigation() {
    setState(() {
      _isNavigationActive = false;
      _estimatedDistance = '';
      _estimatedTime = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('길찾기가 종료되었습니다'),
        backgroundColor: Colors.grey,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final locationManager = Provider.of<LocationManager>(context); // 항상 최신 상태 구독
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: _searchType != null ? _buildSearchView() : _buildDirectionsView(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = AppLocalizations.of(context)!;

    if (_searchType != null) {
      return AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: _cancelSearch,
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: (_) => _onSearchChanged(),
            decoration: InputDecoration(
              hintText: _searchType == 'start'
                  ? l10n.search_start_location
                  : l10n.search_end_location,
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.search,
                  color: Colors.indigo.shade400,
                  size: 20,
                ),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged();
                      },
                      icon: Icon(
                        Icons.clear,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      );
    } else {
      return AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
        ),
        title: Text(
          _isNavigationActive
              ? l10n.unified_navigation_in_progress
              : l10n.unified_navigation,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: _isNavigationActive
            ? [
                IconButton(
                  onPressed: _stopNavigation,
                  icon: const Icon(Icons.close, color: Colors.black87),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      );
    }
  }

  Widget _buildSearchView() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recentSearches.isNotEmpty && !_isSearching) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.recent_searches,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _recentSearches.clear();
                    });
                  },
                  child: Text(
                    l10n.clear_all,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(child: _buildSearchContent()),
      ],
    );
  }

  Widget _buildSearchContent() {
    if (!_isSearching) {
      return _buildRecentSearches();
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_searchResults.isEmpty) {
      return _buildNoResults();
    }

    return _buildSearchResults();
  }

  Widget _buildLoadingState() {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.indigo),
          const SizedBox(height: 16),
          Text(
            l10n.searching,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return Container();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _recentSearches.length,
      itemBuilder: (context, index) {
        final building = _recentSearches[index];
        return _buildBuildingResultItem(building, isRecent: true);
      },
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return _buildSearchResultItem(result);
      },
    );
  }

  // 🔥 수정된 _buildSearchResultItem 메서드 - 강의실 직접 이동 기능 추가

  // directions_screen.dart에서 _buildSearchResultItem의 onTap 부분을 다음과 같이 수정

  // directions_screen.dart에서 _buildSearchResultItem의 onTap 부분을 다음과 같이 수정

Widget _buildSearchResultItem(SearchResult result) {
  return Container(
    margin: const EdgeInsets.only(bottom: 1),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.zero,
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: result.isBuilding
              ? const Color(0xFF3B82F6).withOpacity(0.1)
              : const Color(0xFF10B981).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          result.isBuilding ? Icons.business : Icons.room,
          color: result.isBuilding
              ? const Color(0xFF3B82F6)
              : const Color(0xFF10B981),
          size: 18,
        ),
      ),
      title: Text(
        result.displayName ?? '이름 없음', // 🔥 null 체크 추가
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        _buildSafeSubtitle(result), // 🔥 안전한 subtitle 생성
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey.shade400,
        size: 20,
      ),
      onTap: () => _handleSearchResultTap(result), // 🔥 안전한 탭 처리
    ),
  );
}

String _buildSafeSubtitle(SearchResult result) {
  try {
    if (result.isRoom) {
      return result.roomDescription?.isNotEmpty == true 
          ? result.roomDescription! 
          : '강의실';
    } else {
      return result.building.info.isNotEmpty 
          ? result.building.info 
          : result.building.category.isNotEmpty 
              ? result.building.category 
              : '건물';
    }
  } catch (e) {
    debugPrint('❌ subtitle 생성 오류: $e');
    return '정보 없음';
  }
}

void _handleSearchResultTap(SearchResult result) {
  try {
    if (_searchType != null) {
      // 길찾기 모드: 출발지/도착지 설정
      _onSearchResultSelected(result);
    } else {
      // 🔥 단독 검색 모드: 강의실이면 바로 이동
      if (result.isRoom) {
        _navigateToRoomDirectly(result);
      } else {
        // 건물이면 길찾기 모드로 설정
        _onSearchResultSelected(result);
      }
    }
  } catch (e) {
    debugPrint('❌ 검색 결과 탭 처리 오류: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('항목 선택 중 오류가 발생했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


// 🔥 강의실로 바로 이동하는 메서드 추가
void _navigateToRoomDirectly(SearchResult result) {
  try {
    if (!result.isRoom || result.building == null) {
      debugPrint('❌ 유효하지 않은 강의실 정보');
      return;
    }

    final buildingCode = _extractBuildingCode(result.building.name);
    final roomNumber = result.roomNumber ?? '';
    final floorNumber = result.floorNumber ?? 1;

    if (buildingCode.isEmpty || roomNumber.isEmpty) {
      debugPrint('❌ 필수 정보 누락: 건물($buildingCode), 호실($roomNumber)');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('강의실 정보가 불완전합니다'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    debugPrint('🎯 강의실로 바로 이동: ${result.displayName}');
    debugPrint('   건물: $buildingCode');
    debugPrint('   층: $floorNumber');
    debugPrint('   호실: $roomNumber');

    // 사용자에게 이동 중임을 알림
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.displayName ?? roomNumber}로 이동 중...'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );

    // BuildingMapPage로 직접 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BuildingMapPage(
          buildingName: buildingCode,
          targetRoomId: roomNumber,
          targetFloorNumber: floorNumber,
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ 강의실 직접 이동 오류: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('강의실 이동 중 오류가 발생했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


  Widget _buildBuildingResultItem(Building building, {bool isRecent = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isRecent
                ? Colors.grey.shade100
                : const Color(0xFFFF6B6B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            isRecent ? Icons.history : Icons.location_on,
            color: isRecent ? Colors.grey.shade600 : const Color(0xFFFF6B6B),
            size: 18,
          ),
        ),
        title: Text(
          building.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          building.info.isNotEmpty ? building.info : building.category,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isRecent
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _recentSearches.removeWhere((b) => b.name == building.name);
                  });
                },
                icon: Icon(Icons.close, color: Colors.grey.shade400, size: 18),
              )
            : null,
        onTap: () => _onBuildingSelected(building),
      ),
    );
  }

  Widget _buildNoResults() {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, color: Colors.grey.shade400, size: 64),
          const SizedBox(height: 16),
          Text(
            l10n.no_search_results,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.try_different_keyword,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionsView() {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 16),
            // preset 및 호실 알림 메시지
            if (widget.presetStart != null ||
                widget.presetEnd != null ||
                widget.roomData != null) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getPresetMessage(),
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 출발지 입력
            _buildLocationInput(
              isStartLocation: true,
              icon: Icons.my_location,
              iconColor: const Color(0xFF10B981),
              hint: l10n.enter_start_location,
              selectedBuilding: _startBuilding,
              roomInfo: _startRoomInfo,
              onTap: _selectStartLocation,
            ),

            // 교환 버튼 (기존 그대로)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 56),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _swapLocations,
                        child: Icon(
                          Icons.swap_vert,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 도착지 입력
            _buildLocationInput(
              isStartLocation: false,
              icon: Icons.location_on,
              iconColor: const Color(0xFFEF4444),
              hint: l10n.enter_end_location,
              selectedBuilding: _endBuilding,
              roomInfo: _endRoomInfo,
              onTap: _selectEndLocation,
            ),

            const Spacer(),

            // 통합 API 경로 미리보기 정보
            if (_previewResponse != null && !_isCalculatingPreview) ...[
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.route,
                          color: Colors.blue.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.route_preview,
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRoutePreview(),
                  ],
                ),
              ),
            ],

            // 로딩 중이거나 기본 안내 메시지
            if (_isCalculatingPreview) ...[
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.calculating_optimal_route,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ] else if (_previewResponse == null &&
                _startBuilding == null &&
                _endBuilding == null) ...[
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.set_departure_and_destination,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
          ],
        ),

        // 하단 고정 버튼
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          child: ElevatedButton(
            onPressed: (_startBuilding != null && _endBuilding != null)
                ? _startUnifiedNavigation
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              disabledBackgroundColor: Colors.grey.shade300,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.grey.shade500,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.navigation,
                  size: 20,
                  color: (_startBuilding != null && _endBuilding != null)
                      ? Colors.white
                      : Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.start_unified_navigation,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: (_startBuilding != null && _endBuilding != null)
                        ? Colors.white
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🔥 경로 미리보기 위젯
  Widget _buildRoutePreview() {
    final l10n = AppLocalizations.of(context)!;

    if (_previewResponse == null) return Container();

    final result = _previewResponse!.result;
    final steps = <Widget>[];

    // 출발지 실내 구간
    if (result.departureIndoor != null) {
      steps.add(
        _buildRouteStep(
          icon: Icons.home,
          title: l10n.departure_indoor,
          distance:
              '${result.departureIndoor!.path.distance.toStringAsFixed(0)}m',
          description: l10n.to_building_exit,
          color: Colors.green,
        ),
      );
    }

    // 실외 구간
    if (result.outdoor != null) {
      steps.add(
        _buildRouteStep(
          icon: Icons.directions_walk,
          title: l10n.outdoor_movement,
          distance: '${result.outdoor!.path.distance.toStringAsFixed(0)}m',
          description: l10n.to_destination_building,
          color: Colors.blue,
        ),
      );
    }

    // 도착지 실내 구간
    if (result.arrivalIndoor != null) {
      steps.add(
        _buildRouteStep(
          icon: Icons.location_on,
          title: l10n.arrival_indoor,
          distance:
              '${result.arrivalIndoor!.path.distance.toStringAsFixed(0)}m',
          description: l10n.to_final_destination,
          color: Colors.orange,
        ),
      );
    }

    return Column(
      children: [
        // 전체 요약
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryItem(l10n.total_distance, _estimatedDistance),
            _buildSummaryItem(l10n.estimated_time, _estimatedTime),
            _buildSummaryItem(l10n.route_type, _getRouteTypeDescription()),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),

        // 단계별 경로
        ...steps,
      ],
    );
  }

  Widget _buildRouteStep({
    required IconData icon,
    required String title,
    required String distance,
    required String description,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Text(
            distance,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  String _getRouteTypeDescription() {
    final l10n = AppLocalizations.of(context)!;

    if (_previewResponse == null) return '';

    switch (_previewResponse!.type) {
      case 'building-building':
        return l10n.building_to_building;
      case 'room-building':
        return l10n.room_to_building;
      case 'building-room':
        return l10n.building_to_room;
      case 'room-room':
        return l10n.room_to_room;
      case 'location-building':
        return l10n.location_to_building;
      default:
        return l10n.unified_route;
    }
  }

  String _getPresetMessage() {
    if (widget.roomData != null) {
      final type = widget.roomData!['type'] ?? '';
      final roomName = widget.roomData!['roomName'] ?? '';
      final buildingName = widget.roomData!['buildingName'] ?? '';

      if (type == 'start') {
        return '$buildingName $roomName호가 출발지로 설정되었습니다';
      } else {
        return '$buildingName $roomName호가 도착지로 설정되었습니다';
      }
    } else if (widget.presetStart != null) {
      return '${widget.presetStart!.name}이 출발지로 설정되었습니다';
    } else if (widget.presetEnd != null) {
      return '${widget.presetEnd!.name}이 도착지로 설정되었습니다';
    }
    return '';
  }

  Widget _buildLocationInput({
    required bool isStartLocation,
    required IconData icon,
    required Color iconColor,
    required String hint,
    required Building? selectedBuilding,
    required Map<String, dynamic>? roomInfo,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 기본 위치 입력
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selectedBuilding != null) ...[
                            Text(
                              selectedBuilding.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            // 🔥 호실 정보 표시
                            if (roomInfo != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${roomInfo['floorNumber'] ?? ''}층 ${roomInfo['roomName'] ?? ''}호',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ] else if (selectedBuilding
                                .category
                                .isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                selectedBuilding.category,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ] else ...[
                            Text(
                              hint,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 출발지인 경우 "내 위치" 옵션 항상 추가
          if (isStartLocation) ...[
            const Divider(height: 1),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  try {
                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('현재 위치를 가져오는 중...'),
                          ],
                        ),
                        backgroundColor: Color(0xFF2196F3),
                        duration: Duration(seconds: 5),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                      ),
                    );

                    final locationManager = Provider.of<LocationManager>(
                      context,
                      listen: false,
                    );

                    if (locationManager.hasValidLocation &&
                        locationManager.currentLocation != null) {
                      final myLocationBuilding = Building(
                        name: '내 위치',
                        info: '현재 위치에서 출발',
                        lat: locationManager.currentLocation!.latitude!,
                        lng: locationManager.currentLocation!.longitude!,
                        category: '현재위치',
                        baseStatus: '사용가능',
                        hours: '',
                        phone: '',
                        imageUrl: '',
                        description: '현재 위치에서 길찾기를 시작합니다',
                      );

                      setState(() {
                        _startBuilding = myLocationBuilding;
                        _startRoomInfo = null; // 현재 위치는 호실 정보 없음
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                const Text('현재 위치가 출발지로 설정되었습니다'),
                              ],
                            ),
                            backgroundColor: const Color(0xFF10B981),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );

                        // 🔥 현재 위치 설정 후 미리보기 계산
                        if (_endBuilding != null) {
                          _calculateRoutePreview();
                        }
                      }
                    } else {
                      await locationManager.requestLocation();
                      await Future.delayed(const Duration(milliseconds: 500));

                      if (locationManager.hasValidLocation &&
                          locationManager.currentLocation != null) {
                        final myLocationBuilding = Building(
                          name: '내 위치',
                          info: '현재 위치에서 출발',
                          lat: locationManager.currentLocation!.latitude!,
                          lng: locationManager.currentLocation!.longitude!,
                          category: '현재위치',
                          baseStatus: '사용가능',
                          hours: '',
                          phone: '',
                          imageUrl: '',
                          description: '현재 위치에서 길찾기를 시작합니다',
                        );

                        if (mounted) {
                          setState(() {
                            _startBuilding = myLocationBuilding;
                            _startRoomInfo = null;
                          });

                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(
                                    Icons.my_location,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('현재 위치가 출발지로 설정되었습니다'),
                                ],
                              ),
                              backgroundColor: const Color(0xFF10B981),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          // 🔥 현재 위치 설정 후 미리보기 계산
                          if (_endBuilding != null) {
                            _calculateRoutePreview();
                          }
                        }
                      } else {
                        throw Exception('위치를 가져올 수 없습니다');
                      }
                    }
                  } catch (e) {
                    final myLocationBuilding = Building(
                      name: '내 위치',
                      info: '현재 위치에서 출발 (기본 위치)',
                      lat: 36.338133,
                      lng: 127.446423,
                      category: '현재위치',
                      baseStatus: '사용가능',
                      hours: '',
                      phone: '',
                      imageUrl: '',
                      description: '현재 위치에서 길찾기를 시작합니다',
                    );

                    setState(() {
                      _startBuilding = myLocationBuilding;
                      _startRoomInfo = null;
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.warning,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text('기본 위치를 사용합니다'),
                            ],
                          ),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 2),
                        ),
                      );

                      // 🔥 기본 위치 설정 후 미리보기 계산
                      if (_endBuilding != null) {
                        _calculateRoutePreview();
                      }
                    }
                  }
                },
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Color(0xFF2196F3),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '내 위치',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '현재 위치에서 출발',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.gps_fixed,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
