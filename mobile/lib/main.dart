import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() => runApp(const TransferApp());

const cream = Color(0xFFF7F3EB);
const blue = Color(0xFF5779E8);
const pink = Color(0xFFE66A91);
const ink = Color(0xFF242A3C);
const muted = Color(0xFF747887);

class TransferApp extends StatelessWidget {
  const TransferApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Android Transfer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: cream),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: ink),
      ),
    ),
    home: const TransferHome(),
  );
}

class RemoteEntry {
  final String name;
  final bool isDirectory;
  final bool isHidden;
  const RemoteEntry(this.name, this.isDirectory, this.isHidden);
  factory RemoteEntry.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    return RemoteEntry(
      name,
      json['isDirectory'] as bool,
      json['isHidden'] as bool? ?? name.startsWith('.'),
    );
  }
}

class RemoteLocation {
  final String id;
  final String name;
  const RemoteLocation(this.id, this.name);
  factory RemoteLocation.fromJson(Map<String, dynamic> json) =>
      RemoteLocation(json['id'] as String, json['name'] as String);
}

class TransferItem {
  final String name;
  String detail = 'Sırada';
  double progress = 0;
  bool finished = false;
  bool failed = false;
  TransferItem(this.name);
}

class TransferHome extends StatefulWidget {
  const TransferHome({super.key});
  @override
  State<TransferHome> createState() => _TransferHomeState();
}

class _TransferHomeState extends State<TransferHome> {
  static const storage = MethodChannel('android_transfer/storage');
  final token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final roots = <String, String>{'storage': '/storage/emulated/0'};
  HttpServer? server;
  String localAddress = '';
  String remoteBase = '';
  String remoteToken = '';
  List<RemoteLocation> locations = [];
  String location = '';
  String path = '';
  List<RemoteEntry> entries = [];
  final selected = <String>{};
  bool access = false;
  bool working = false;
  bool showHidden = false;
  bool showTransferSummary = false;
  List<TransferItem> transferItems = [];
  int transferBatch = 0;
  int page = 0;
  String status = 'Paylaşım için dosya erişimi verin.';

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  @override
  void dispose() {
    server?.close(force: true);
    super.dispose();
  }

  Future<void> _checkAccess() async {
    final granted = await storage.invokeMethod<bool>('hasAccess') ?? false;
    if (!mounted) return;
    setState(() => access = granted);
  }

  Future<void> _requestAccess() async {
    await storage.invokeMethod('requestAccess');
    if (mounted) {
      setState(
        () =>
            status = 'Ayarlar ekranında dosya erişimini açıp uygulamaya dönün.',
      );
    }
  }

  Future<String?> _ip() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final item in interfaces) {
      if (item.name == 'wlan0' || item.name == 'ap0' || item.name == 'swlan0') {
        final candidate = item.addresses
            .where((a) => !a.isLoopback)
            .firstOrNull;
        if (candidate != null) return candidate.address;
      }
    }
    for (final item in interfaces) {
      final candidate = item.addresses.where((a) => !a.isLoopback).firstOrNull;
      if (candidate != null) return candidate.address;
    }
    return null;
  }

  Future<void> _start() async {
    await _checkAccess();
    if (!access) {
      await _requestAccess();
      return;
    }
    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        46733,
        shared: false,
      );
      server!.listen(_handle);
      localAddress = await _ip() ?? '';
      setState(
        () => status = localAddress.isEmpty
            ? 'Yerel IP bulunamadı.'
            : 'Paylaşım hazır: $localAddress:46733',
      );
    } catch (error) {
      setState(() => status = 'Paylaşım açılamadı: $error');
    }
  }

  Future<void> _stop() async {
    await server?.close(force: true);
    setState(() {
      server = null;
      localAddress = '';
      status = 'Paylaşım durduruldu.';
    });
  }

  String get qr => localAddress.isEmpty
      ? ''
      : 'androidtransfer://pair?host=$localAddress&port=46733&token=$token';

  FileSystemEntity? _resolve(String root, String relative) {
    final base = roots[root];
    if (base == null || relative.startsWith('/')) return null;
    final parts = relative.split('/');
    if (parts.any((p) => p == '..' || p == '.')) return null;
    final full = relative.isEmpty ? base : '$base/$relative';
    if (full != base && !full.startsWith('$base/')) return null;
    if (FileSystemEntity.isLinkSync(full)) return null;
    if (relative.isNotEmpty) {
      final parent = Directory(full).parent;
      if (!parent.existsSync()) return null;
      final resolvedParent = parent.resolveSymbolicLinksSync();
      if (resolvedParent != base && !resolvedParent.startsWith('$base/')) {
        return null;
      }
    }
    return FileSystemEntity.typeSync(full) == FileSystemEntityType.directory
        ? Directory(full)
        : File(full);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final address = request.connectionInfo?.remoteAddress;
      if (address == null || !_isPrivate(address)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.headers.value('x-transfer-token') != token || !access) {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      final uri = request.uri;
      response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && uri.path == '/roots') {
        response.write(
          jsonEncode([
            {'id': 'storage', 'name': '/storage/emulated/0'},
          ]),
        );
        return;
      }
      final root = uri.queryParameters['root'] ?? '';
      final relative = uri.queryParameters['path'] ?? '';
      final entity = _resolve(root, relative);
      if (entity == null) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      if (request.method == 'GET' &&
          uri.path == '/list' &&
          entity is Directory) {
        final items = await entity
            .list(followLinks: false)
            .where((e) => e is! Link)
            .toList();
        response.write(
          jsonEncode({
            'entries': items.map((e) {
              final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
              return {
                'name': name,
                'isDirectory': e is Directory,
                'isHidden': name.startsWith('.'),
              };
            }).toList(),
          }),
        );
        return;
      }
      if (request.method == 'GET' &&
          uri.path == '/file' &&
          entity is File &&
          await entity.exists()) {
        final length = await entity.length();
        if (length > 64 * 1024 * 1024) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        response.headers.contentType = ContentType.binary;
        response.contentLength = length;
        await response.addStream(entity.openRead());
        return;
      }
      if (request.method == 'PUT' &&
          uri.path == '/file' &&
          entity is File &&
          !await entity.exists()) {
        final parent = entity.parent;
        if (!await parent.exists()) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        final temporary = File(
          '${entity.path}.${DateTime.now().microsecondsSinceEpoch}.transfer-part',
        );
        try {
          final sink = temporary.openWrite();
          await sink.addStream(request);
          await sink.close();
          await temporary.rename(entity.path);
        } catch (_) {
          if (await temporary.exists()) await temporary.delete();
          rethrow;
        }
        try {
          await storage.invokeMethod('scanFile', {'path': entity.path});
        } catch (_) {
          // The file is already saved; media indexing must not turn a successful upload into an error.
        }
        response.write('{}');
        return;
      }
      response.statusCode = HttpStatus.notFound;
    } catch (error) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': '$error'}));
    } finally {
      await response.close();
    }
  }

  bool _isPrivate(InternetAddress address) {
    if (address.isLoopback) return true;
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  Future<void> _connect(String raw) async {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'androidtransfer' || uri.host != 'pair') {
        throw const FormatException('Geçersiz QR kodu');
      }
      final host = uri.queryParameters['host'] ?? '';
      final port = int.parse(uri.queryParameters['port'] ?? '0');
      final key = uri.queryParameters['token'] ?? '';
      if (host.isEmpty || port < 1 || key.isEmpty) {
        throw const FormatException('Eksik bağlantı bilgisi');
      }
      setState(() {
        remoteBase = 'http://$host:$port';
        remoteToken = key;
        path = '';
        entries = [];
        selected.clear();
        page = 1;
      });
      await _loadRoots();
    } catch (error) {
      if (mounted) setState(() => status = 'Bağlanılamadı: $error');
    }
  }

  Future<HttpClientResponse> _request(
    String action, {
    String method = 'GET',
    String? item,
    File? upload,
    void Function(int, int)? onProgress,
  }) async {
    final query = action == '/roots'
        ? ''
        : '?root=${Uri.encodeQueryComponent(location)}&path=${Uri.encodeQueryComponent(item ?? path)}';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('$remoteBase$action$query'),
      );
      request.headers.set('x-transfer-token', remoteToken);
      if (upload != null) {
        final length = await upload.length();
        request.contentLength = length;
        var sent = 0;
        await for (final chunk in upload.openRead()) {
          request.add(chunk);
          await request.flush();
          sent += chunk.length;
          onProgress?.call(sent, length);
        }
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        final responseText = await utf8.decoder.bind(response).join();
        String detail = 'İstek reddedildi';
        try {
          detail =
              (jsonDecode(responseText) as Map<String, dynamic>)['error']
                  as String? ??
              detail;
        } catch (_) {}
        throw HttpException('$detail (${response.statusCode})');
      }
      return response;
    } finally {
      client.close(force: false);
    }
  }

  void _transferProgress(int index, int done, int total) {
    if (!mounted ||
        index >= transferItems.length ||
        transferItems[index].finished) {
      return;
    }
    setState(() {
      final item = transferItems[index];
      item.progress = total > 0 ? (done / total).clamp(0.0, .98) : 0;
      item.detail = total > 0
          ? done >= total
                ? 'Karşı cihazda kaydediliyor'
                : '${_size(done)} / ${_size(total)}'
          : '${_size(done)} aktarıldı';
    });
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _finishTransfer(int index, [Object? error]) {
    if (!mounted) return;
    setState(() {
      final item = transferItems[index];
      item.finished = true;
      item.failed = error != null;
      item.progress = 1;
      item.detail = error?.toString() ?? 'Tamamlandı';
    });
  }

  Future<void> _loadRoots() async {
    try {
      final response = await _request('/roots');
      final data = jsonDecode(await utf8.decoder.bind(response).join()) as List;
      if (!mounted) return;
      setState(() {
        locations = data
            .map((e) => RemoteLocation.fromJson(e as Map<String, dynamic>))
            .toList();
        location = locations.isEmpty ? '' : locations.first.id;
      });
      await _loadDirectory();
    } catch (error) {
      if (mounted) {
        setState(() {
          locations = [];
          entries = [];
          status = 'Bağlantı kesildi: $error';
        });
      }
    }
  }

  Future<void> _loadDirectory() async {
    if (location.isEmpty) return;
    try {
      final response = await _request('/list');
      final data = jsonDecode(
        await utf8.decoder.bind(response).join(),
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        entries = (data['entries'] as List)
            .map((e) => RemoteEntry.fromJson(e as Map<String, dynamic>))
            .where((e) => showHidden || !e.isHidden)
            .toList();
        entries.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        selected.clear();
        status = '${entries.length} öğe listelendi.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          entries = [];
          selected.clear();
          status = 'Bağlantı kesildi: $error';
        });
      }
    }
  }

  void _open(RemoteEntry entry) {
    if (!entry.isDirectory) return;
    setState(() => path = path.isEmpty ? entry.name : '$path/${entry.name}');
    _loadDirectory();
  }

  void _up() {
    if (path.isEmpty) return;
    final parts = path.split('/')..removeLast();
    setState(() => path = parts.join('/'));
    _loadDirectory();
  }

  void _hideTransferSummary(int batch) {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !working && batch == transferBatch) {
        setState(() => showTransferSummary = false);
      }
    });
  }

  Future<void> _download() async {
    if (selected.isEmpty) return;
    final names = selected.toList()..sort();
    transferBatch++;
    final batch = transferBatch;
    setState(() {
      working = true;
      transferItems = names.map(TransferItem.new).toList();
      showTransferSummary = true;
    });
    for (var index = 0; index < names.length; index++) {
      final name = names[index];
      try {
        if (entries.firstWhere((e) => e.name == name).isDirectory) {
          throw const FileSystemException(
            'Klasör aktarımı henüz desteklenmiyor',
          );
        }
        final destination = File('/storage/emulated/0/Download/$name');
        if (await destination.exists()) {
          throw FileSystemException('İndirilenler içinde aynı ad var', name);
        }
        final relative = path.isEmpty ? name : '$path/$name';
        final temporary = File(
          '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.transfer-part',
        );
        try {
          setState(() => transferItems[index].detail = 'İndiriliyor');
          final response = await _request('/file', item: relative);
          final sink = temporary.openWrite();
          var received = 0;
          try {
            await for (final chunk in response) {
              sink.add(chunk);
              received += chunk.length;
              _transferProgress(index, received, response.contentLength);
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          await temporary.rename(destination.path);
          try {
            await storage.invokeMethod('scanFile', {'path': destination.path});
          } catch (_) {}
        } catch (_) {
          if (await temporary.exists()) await temporary.delete();
          rethrow;
        }
        _finishTransfer(index);
      } catch (error) {
        _finishTransfer(index, error);
      }
    }
    if (mounted) {
      setState(() {
        working = false;
        final failed = transferItems.where((item) => item.failed).length;
        status =
            'Telefona indirme: ${names.length - failed} tamamlandı, $failed hata. Hedef: /storage/emulated/0/Download';
      });
      _hideTransferSummary(batch);
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    transferBatch++;
    final batch = transferBatch;
    setState(() {
      working = true;
      transferItems = result.map((item) => TransferItem(item.name)).toList();
      showTransferSummary = true;
    });
    for (var index = 0; index < result.length; index++) {
      final item = result[index];
      try {
        if (item.path == null) {
          throw const FileSystemException('Seçilen dosya okunamadı');
        }
        final relative = path.isEmpty ? item.name : '$path/${item.name}';
        setState(() => transferItems[index].detail = 'Gönderiliyor');
        final response = await _request(
          '/file',
          method: 'PUT',
          item: relative,
          upload: File(item.path!),
          onProgress: (done, total) => _transferProgress(index, done, total),
        );
        await response.drain<void>();
        _finishTransfer(index);
      } catch (error) {
        _finishTransfer(index, error);
      }
    }
    await _loadDirectory();
    if (mounted) {
      setState(() {
        working = false;
        final failed = transferItems.where((item) => item.failed).length;
        status =
            'Mac’e gönderme: ${result.length - failed} tamamlandı, $failed hata.';
      });
      _hideTransferSummary(batch);
    }
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (value != null) await _connect(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'Android Transfer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Telefonum'),
                    icon: Icon(Icons.smartphone_rounded),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Mac dosyaları'),
                    icon: Icon(Icons.computer_rounded),
                  ),
                ],
                selected: {page},
                onSelectionChanged: (value) =>
                    setState(() => page = value.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? blue.withValues(alpha: .16)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
            Expanded(child: page == 0 ? _phonePanel() : _macPanel()),
            if (showTransferSummary && transferItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _transferSummary(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: Row(
                children: [
                  Icon(
                    working ? Icons.sync_rounded : Icons.circle,
                    size: 9,
                    color: working ? pink : blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: const TextStyle(color: muted, fontSize: 11),
                      maxLines: 2,
                    ),
                  ),
                  if (transferItems.isNotEmpty && !working)
                    TextButton(
                      onPressed: () => setState(
                        () => showTransferSummary = !showTransferSummary,
                      ),
                      child: Text(
                        showTransferSummary ? 'Gizle' : 'Ayrıntılar',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferSummary() {
    final completed = transferItems.where((item) => item.finished).length;
    return SizedBox(
      height: 168,
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Aktarım durumu',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
                const Spacer(),
                Text(
                  '$completed / ${transferItems.length}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value:
                  transferItems.fold<double>(
                    0,
                    (sum, item) => sum + item.progress,
                  ) /
                  transferItems.length,
              color: blue,
              backgroundColor: blue.withValues(alpha: .12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: transferItems.length,
                itemBuilder: (context, index) {
                  final item = transferItems[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Tooltip(
                      message: '${item.name}: ${item.detail}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                item.failed
                                    ? Icons.error_rounded
                                    : item.finished
                                    ? Icons.check_circle_rounded
                                    : Icons.sync_rounded,
                                size: 16,
                                color: item.failed ? pink : blue,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 23, top: 2),
                            child: Text(
                              item.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                          ),
                          if (!item.finished)
                            Padding(
                              padding: const EdgeInsets.only(left: 23, top: 4),
                              child: LinearProgressIndicator(
                                value: item.progress,
                                color: pink,
                                backgroundColor: pink.withValues(alpha: .12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phonePanel() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Telefonun hazır.',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: ink),
      ),
      const SizedBox(height: 6),
      const Text(
        'Mac uygulaması bu QR kodunu okutarak telefon dosyalarına bağlanır.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 24),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: pink),
                SizedBox(width: 8),
                Text(
                  'Bağlantı kodu',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (server != null && qr.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(data: qr, size: 206),
                ),
              )
            else
              const SizedBox(
                height: 218,
                child: Center(
                  child: Icon(Icons.wifi_rounded, size: 60, color: blue),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              server == null
                  ? 'İzin verip paylaşımı başlatın.'
                  : 'Mac kamerasıyla tara veya kodu kopyala.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: server == null ? _start : _stop,
              style: FilledButton.styleFrom(
                backgroundColor: blue,
                minimumSize: const Size.fromHeight(46),
              ),
              child: Text(
                server == null ? 'Paylaşımı başlat' : 'Paylaşımı durdur',
              ),
            ),
            if (server != null)
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: qr)),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Kodu kopyala'),
              ),
            if (!access)
              TextButton(
                onPressed: _requestAccess,
                child: const Text('Dosya erişimi ver'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _card(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paylaşılan depolama',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 12),
            Text(
              '/storage/emulated/0 içindeki gerçek klasör adları',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _macPanel() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Mac dosyaları.',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: ink),
      ),
      const SizedBox(height: 6),
      const Text(
        'Mac QR kodunu tara ve iki yönlü aktar.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('QR tara'),
              style: FilledButton.styleFrom(
                backgroundColor: blue,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () async {
              final controller = TextEditingController();
              final value = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Bağlantı kodu'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'androidtransfer://pair?...',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Bağlan'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (value != null) await _connect(value);
            },
            child: const Text('Kod gir'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (locations.isNotEmpty) ...[
        _card(
          Row(
            children: [
              if (locations.length == 1)
                Flexible(
                  child: Text(
                    locations.first.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                )
              else
                DropdownButton<String>(
                  value: location,
                  underline: const SizedBox(),
                  items: locations
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      location = value;
                      path = '';
                    });
                    _loadDirectory();
                  },
                ),
              const Spacer(),
              IconButton(
                onPressed: path.isEmpty ? null : _up,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(
                tooltip: showHidden ? 'Gizlileri gizle' : 'Gizlileri göster',
                onPressed: () {
                  setState(() {
                    showHidden = !showHidden;
                    if (!showHidden &&
                        path.split('/').any((part) => part.startsWith('.'))) {
                      path = '';
                    }
                  });
                  _loadDirectory();
                },
                icon: Icon(
                  showHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
              IconButton(
                onPressed: _loadDirectory,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${locations.first.name}${path.isEmpty ? '' : '/$path'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: muted,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        _card(
          Column(
            children: entries
                .map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.isDirectory
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded,
                      color: entry.isDirectory ? blue : pink,
                    ),
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: entry.isDirectory
                        ? const Icon(Icons.chevron_right_rounded)
                        : Checkbox(
                            value: selected.contains(entry.name),
                            onChanged: (_) => setState(() {
                              selected.contains(entry.name)
                                  ? selected.remove(entry.name)
                                  : selected.add(entry.name);
                            }),
                          ),
                    onTap: () => entry.isDirectory
                        ? _open(entry)
                        : setState(() {
                            selected.contains(entry.name)
                                ? selected.remove(entry.name)
                                : selected.add(entry.name);
                          }),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: selected.isEmpty || working ? null : _download,
                style: FilledButton.styleFrom(backgroundColor: pink),
                child: const Text('Telefona indir'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: working ? null : _upload,
                style: FilledButton.styleFrom(backgroundColor: blue),
                child: const Text('Mac’e gönder'),
              ),
            ),
          ],
        ),
      ] else
        _card(
          const SizedBox(
            height: 210,
            child: Center(
              child: Text(
                'Mac ile eşleştirince klasörler burada görünür.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFE8E3DD)),
    ),
    child: child,
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool scanned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mac QR kodunu tara')),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (!scanned &&
            value != null &&
            value.startsWith('androidtransfer://pair?') &&
            context.mounted) {
          scanned = true;
          Navigator.of(context).pop(value);
        }
      },
    ),
  );
}
