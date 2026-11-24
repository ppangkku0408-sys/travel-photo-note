import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

// 공공데이터포털 일반 인증키(Decoding)를 한 줄로 붙여넣으세요.
const serviceKey = '8fd6ccc3ec510b319f553c80067885d7edd9baa4f340a5047e316b7805615709';

Future<List<Map<String, dynamic>>> fetchPhotos() async {
  final uri = Uri.https(
    'apis.data.go.kr',
    '/B551011/PhotoGalleryService1/galleryList1',
    {
      'serviceKey': serviceKey,
      'numOfRows': '5',
      'pageNo': '1',
      'MobileOS': 'ETC',
      'MobileApp': 'Rehearsal',
      'arrange': 'A',
      '_type': 'json',
    },
  );
  final res = await http.get(uri);
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  final item = data['response']['body']['items']['item'];
  final list = item is List ? item : [item];
  return list.map((e) => Map<String, dynamic>.from(e)).toList();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 여행 사진 한 컷',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _photosFuture;
  Map<String, dynamic>? _selected;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _photosFuture = fetchPhotos();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _login() async {
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } catch (e) {
      _snack('로그인 실패: $e');
    }
  }

  Future<void> _logout() => FirebaseAuth.instance.signOut();

  Future<void> _save(User user) async {
    final note = _noteCtrl.text.trim();
    if (_selected == null) {
      _snack('먼저 사진을 선택하세요');
      return;
    }
    if (note.isEmpty) {
      _snack('한 줄 감상을 입력하세요');
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('photoNotes').add({
        'uid': user.uid,
        'photoTitle': _selected!['galTitle'] ?? '',
        'imageUrl': _selected!['galWebImageUrl'] ?? '',
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _noteCtrl.clear();
      _snack('저장했어요');
    } catch (e) {
      _snack('저장 실패: $e');
    }
  }

  String _https(String url) => url.replaceFirst('http://', 'https://');

  Widget _photoCard(Map<String, dynamic> p) {
    final title = (p['galTitle'] ?? '').toString();
    final place = (p['galPhotographyLocation'] ?? '').toString();
    final url = _https((p['galWebImageUrl'] ?? '').toString());
    final isSelected = identical(_selected, p);
    return Card(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => setState(() => _selected = p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (url.isNotEmpty)
              Image.network(
                url,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(child: Text('이미지를 불러오지 못했어요')),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (place.isNotEmpty) Text(place),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesList(User user) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('photoNotes')
          .where('uid', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('조회 오류: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs.toList();
        docs.sort((a, b) {
          final ta = a.data()['createdAt'] as Timestamp?;
          final tb = b.data()['createdAt'] as Timestamp?;
          if (ta == null) return -1;
          if (tb == null) return 1;
          return tb.compareTo(ta);
        });
        if (docs.isEmpty) return const Text('아직 저장한 감상이 없어요');
        return Column(
          children: docs.map((d) {
            final m = d.data();
            return ListTile(
              title: Text((m['note'] ?? '').toString()),
              subtitle: Text((m['photoTitle'] ?? '').toString()),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('오늘의 여행 사진 한 컷'),
            actions: [
              if (user != null) ...[
                Center(child: Text(user.displayName ?? user.email ?? '')),
                TextButton(onPressed: _logout, child: const Text('로그아웃')),
              ] else
                TextButton(onPressed: _login, child: const Text('Google 로그인')),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _photosFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Text('API 오류: ${snap.error}');
                      }
                      return Column(
                        children: snap.data!.map(_photoCard).toList(),
                      );
                    },
                  ),
                  const Divider(height: 32),
                  if (user == null)
                    const Text('로그인하면 마음에 드는 사진에 한 줄 감상을 남길 수 있어요.')
                  else ...[
                    Text(
                      _selected == null
                          ? '사진을 선택해 주세요'
                          : '선택한 사진: ${_selected!['galTitle']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '한 줄 감상을 적어 보세요',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => _save(user),
                      child: const Text('저장'),
                    ),
                    const Divider(height: 32),
                    Text('내 감상', style: Theme.of(context).textTheme.titleMedium),
                    _notesList(user),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}