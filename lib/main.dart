import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const FootprintApp());
}

class FootprintApp extends StatelessWidget {
  const FootprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Footprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12151C),
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentPosition;
  bool _isLoading = true;
  String? _errorMessage;

  // 🔥 서버에서 불러온 편지들을 담을 리스트
  List<QueryDocumentSnapshot> _letterDocs = [];

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    _determinePosition();
    _listenToLetters(); // 앱 켜질 때 DB 감시 시작!
  }

  // 🔥 핵심: 파이어베이스 DB 실시간 감시 (Read)
  void _listenToLetters() {
    FirebaseFirestore.instance.collection('letters').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _letterDocs = snapshot.docs; // 서버 데이터가 바뀔 때마다 리스트 갱신
        });
      }
    });
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _errorMessage = '위치 서비스(GPS)가 꺼져있습니다.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _errorMessage = '위치 권한이 거부되었습니다.');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
      ).listen((Position newPosition) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(newPosition.latitude, newPosition.longitude);
          });
        }
      });
    } catch (e) {
      setState(() => _errorMessage = '위치를 가져오는 중 문제 발생: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFECA869)))));
    }

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFECA869)))
          : Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _currentPosition!,
              initialZoom: 17.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.footprint_app',
              ),
              MarkerLayer(
                markers: [
                  // 1. 내 위치 마커
                  Marker(
                    point: _currentPosition!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFECA869),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0xFFECA869), blurRadius: 10)],
                      ),
                    ),
                  ),
                  // 2. 🔥 서버에서 받아온 진짜 편지 마커들 뿌리기
                  ..._letterDocs.map((doc) {
                    final lat = doc['latitude'] as double;
                    final lng = doc['longitude'] as double;
                    final content = doc['content'] as String;

                    final markerPosition = LatLng(lat, lng);
                    final distance = Geolocator.distanceBetween(
                      _currentPosition!.latitude, _currentPosition!.longitude, lat, lng,
                    );
                    final isUnlocked = distance <= 50.0; // 50m 이내인지 계산

                    return Marker(
                      point: markerPosition,
                      width: 100,
                      height: 80,
                      child: GestureDetector(
                        onTap: () {
                          if (isUnlocked) {
                            // 잠금 해제되면 '읽기' 화면으로 이동!
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ReadLetterScreen(content: content)),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('아직 거리가 멉니다. 50m 안으로 다가가세요!')),
                            );
                          }
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isUnlocked ? Icons.mail_outline : Icons.lock_outline,
                              color: isUnlocked ? const Color(0xFFECA869) : Colors.grey,
                              size: 35,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isUnlocked ? '열어보기' : '${distance.toStringAsFixed(0)}m 앞',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  }).toList(), // 리스트로 변환해서 뿌려줌
                ],
              ),
            ],
          ),
          // 상단 헤더
          Positioned(
            top: 60, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF12151C).withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFECA869).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('주변에 남겨진 감정 : ${_letterDocs.length}개', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Icon(Icons.radar, color: const Color(0xFFECA869).withOpacity(0.8), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),

      // 🔥 여기에 남기기 (쓰기) 플로팅 버튼 추가
      floatingActionButton: _isLoading ? null : FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => LetterScreen(currentPosition: _currentPosition!)),
          );
        },
        backgroundColor: const Color(0xFFECA869),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text('여기에 남기기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// --- 편지 작성 (쓰기) 화면 ---
class LetterScreen extends StatefulWidget {
  final LatLng currentPosition;
  const LetterScreen({super.key, required this.currentPosition});
  @override
  State<LetterScreen> createState() => _LetterScreenState();
}

class _LetterScreenState extends State<LetterScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _saveDraft();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _controller.text = prefs.getString('letter_draft') ?? '');
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('letter_draft', _controller.text);
  }

  Future<void> _uploadLetterToDB() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _isUploading = true);
    try {
      await FirebaseFirestore.instance.collection('letters').add({
        'content': _controller.text,
        'latitude': widget.currentPosition.latitude,
        'longitude': widget.currentPosition.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('letter_draft');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('감정을 성공적으로 남겼습니다.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('전송 실패: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      appBar: AppBar(
        title: const Text('발자국 남기기', style: TextStyle(color: Color(0xFFECA869), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFECA869)),
        actions: [
          _isUploading
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFECA869), strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.send_rounded), onPressed: _uploadLetterToDB),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: TextField(
          controller: _controller,
          maxLines: null, expands: true,
          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.8),
          decoration: InputDecoration(
            hintText: '이 공간에 남기고 싶은 감정을 적어주세요...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

// --- 📖 새롭게 추가된 편지 읽기 화면 ---
class ReadLetterScreen extends StatelessWidget {
  final String content;

  const ReadLetterScreen({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      appBar: AppBar(
        title: const Text('누군가의 발자국', style: TextStyle(color: Color(0xFFECA869), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFECA869)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/splash_logo.png', width: 60, opacity: const AlwaysStoppedAnimation(0.5)),
              const SizedBox(height: 40),
              Text(
                content,
                style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.8, letterSpacing: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}