import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

Map<String, dynamic> bleOkPayload([Map<String, dynamic>? extra]) {
  return <String, dynamic>{
    'errcode': 0,
    'errmsg': 'SUCCESS',
    'errCode': 0,
    'errMsg': 'SUCCESS',
    ...?extra,
  };
}

Map<String, dynamic> bleFailPayload(int code, String message) {
  return <String, dynamic>{
    'errcode': code,
    'errmsg': message,
    'errCode': code,
    'errMsg': message,
  };
}

class HybridBleBridge {
  HybridBleBridge() {
    _statusSubscription = _ble.statusStream.listen((status) {
      _status = status;
    });
    _status = _ble.status;
  }

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, DiscoveredDevice> _discoveredDevices =
      <String, DiscoveredDevice>{};
  final Map<String, List<DiscoveredService>> _discoveredServices =
      <String, List<DiscoveredService>>{};
  final Map<String, StreamSubscription<List<int>>> _notifySubscriptions =
      <String, StreamSubscription<List<int>>>{};

  StreamSubscription<BleStatus>? _statusSubscription;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  BleStatus _status = BleStatus.unknown;
  String? _connectedDeviceId;

  Future<({bool ok, Object payload})> handleMethod({
    required String method,
    required Map<String, dynamic> opts,
    required Future<void> Function(String key, Map<String, dynamic> payload)
    emitEvent,
  }) async {
    try {
      switch (method) {
        case 'openbluetoothadapter':
          return await _openBluetoothAdapter();
        case 'closebluetoothadapter':
          return await _closeBluetoothAdapter();
        case 'getbluetoothadapterstate':
          return (ok: true, payload: bleOkPayload(_adapterStatePayload()));
        case 'onbluetoothadapterstatechange':
          await emitEvent(
            'campus.onBluetoothAdapterStateChange',
            bleOkPayload(_adapterStatePayload()),
          );
          await emitEvent(
            'JCpdaily.onBluetoothAdapterStateChange',
            bleOkPayload(_adapterStatePayload()),
          );
          return (ok: true, payload: bleOkPayload());
        case 'offbluetoothadapterstatechange':
          return (ok: true, payload: bleOkPayload());
        case 'startbluetoothdevicesdiscovery':
          return await _startDiscovery(emitEvent);
        case 'stopbluetoothdevicesdiscovery':
          await _stopDiscovery();
          return (ok: true, payload: bleOkPayload());
        case 'getbluetoothdevices':
          return (
            ok: true,
            payload: bleOkPayload(<String, dynamic>{
              'devices': _discoveredDevices.values.map(_mapDiscoveredDevice).toList(),
              'code': 0,
              'msg': 'SUCCESS',
            }),
          );
        case 'getconnectedbluetoothdevices':
          return (
            ok: true,
            payload: bleOkPayload(<String, dynamic>{
              'devices': _currentConnectedDevices(),
              'connected': _connectedDeviceId != null,
              'isConnected': _connectedDeviceId != null,
              'code': 0,
              'msg': 'SUCCESS',
            }),
          );
        case 'onbluetoothdevicefound':
        case 'offbluetoothdevicefound':
          return (ok: true, payload: bleOkPayload());
        case 'connectbledevice':
          return await _connectBleDevice(opts, emitEvent);
        case 'disconnectbledevice':
          return await _disconnectBleDevice(opts, emitEvent);
        case 'onbleconnectionstatechanged':
        case 'offbleconnectionstatechanged':
          return (ok: true, payload: bleOkPayload());
        case 'getbledeviceservices':
          return await _getBleDeviceServices(opts);
        case 'getbledevicecharacteristics':
          return await _getBleDeviceCharacteristics(opts);
        case 'notifyblecharacteristicvaluechange':
          return await _notifyBleCharacteristicValueChange(opts, emitEvent);
        case 'onblecharacteristicvaluechange':
        case 'offblecharacteristicvaluechange':
          return (ok: true, payload: bleOkPayload());
        case 'writeblecharacteristicvalue':
          return await _writeBleCharacteristicValue(opts);
        case 'readblecharacteristicvalue':
          return await _readBleCharacteristicValue(opts);
      }
    } catch (error) {
      return (ok: false, payload: bleFailPayload(51099, error.toString()));
    }

    return (ok: true, payload: bleOkPayload());
  }

  Future<void> dispose() async {
    await _stopDiscovery();
    await _connectionSubscription?.cancel();
    for (final subscription in _notifySubscriptions.values) {
      await subscription.cancel();
    }
    _notifySubscriptions.clear();
    await _statusSubscription?.cancel();
  }

  Future<({bool ok, Object payload})> _openBluetoothAdapter() async {
    if (!await _ensureBlePermissions()) {
      return (ok: false, payload: bleFailPayload(51001, '蓝牙权限未授予'));
    }
    await _waitForBleReady();
    if (_status != BleStatus.ready) {
      return (ok: false, payload: bleFailPayload(51003, '蓝牙未打开'));
    }
    return (
      ok: true,
      payload: bleOkPayload(<String, dynamic>{
        ..._adapterStatePayload(),
        'autoClose': true,
        'open': true,
        'opened': true,
        'enabled': true,
        'result': true,
        'success': true,
        'code': 0,
        'msg': 'SUCCESS',
      }),
    );
  }

  Future<void> _waitForBleReady() async {
    if (_status == BleStatus.ready) return;

    final timeout = Platform.isIOS
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 600);
    final deadline = DateTime.now().add(timeout);

    while (_status != BleStatus.ready && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<({bool ok, Object payload})> _closeBluetoothAdapter() async {
    await _stopDiscovery();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDeviceId = null;
    for (final subscription in _notifySubscriptions.values) {
      await subscription.cancel();
    }
    _notifySubscriptions.clear();
    if (Platform.isIOS) {
      return (
        ok: true,
        payload: bleOkPayload(<String, dynamic>{
          ..._adapterStatePayload(),
          'closed': true,
          'result': true,
          'success': true,
          'code': 0,
          'msg': 'SUCCESS',
        }),
      );
    }
    return (
      ok: false,
      payload: bleFailPayload(
        51015,
        "Attempt to invoke interface method 'java.lang.Object java.util.Map.get(java.lang.Object)' on a null object reference",
      ),
    );
  }

  Future<({bool ok, Object payload})> _startDiscovery(
    Future<void> Function(String key, Map<String, dynamic> payload) emitEvent,
  ) async {
    final open = await _openBluetoothAdapter();
    if (!open.ok) return open;

    await _stopDiscovery();
    _discoveredDevices.clear();
    _scanSubscription = _ble
        .scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen((device) async {
          _discoveredDevices[device.id] = device;
          final payload = bleOkPayload(<String, dynamic>{
            'devices': <Map<String, dynamic>>[_mapDiscoveredDevice(device)],
          });
          await emitEvent('campus.onBluetoothDeviceFound', payload);
          await emitEvent('JCpdaily.onBluetoothDeviceFound', payload);
        });
    return (ok: true, payload: bleOkPayload());
  }

  Future<void> _stopDiscovery() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<({bool ok, Object payload})> _connectBleDevice(
    Map<String, dynamic> opts,
    Future<void> Function(String key, Map<String, dynamic> payload) emitEvent,
  ) async {
    final deviceId = (opts['deviceId'] ?? '').toString();
    if (deviceId.isEmpty) {
      return (ok: false, payload: bleFailPayload(10001, 'deviceId 不能为空'));
    }
    await _stopDiscovery();
    await _connectionSubscription?.cancel();

    final completer = Completer<({bool ok, Object payload})>();
    _connectionSubscription = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 8),
        )
        .listen(
          (update) async {
            final connected =
                update.connectionState == DeviceConnectionState.connected;
            if (connected) {
              _connectedDeviceId = deviceId;
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                _connectedDeviceId == deviceId) {
              _connectedDeviceId = null;
            }

            final eventPayload = bleOkPayload(<String, dynamic>{
              'deviceId': deviceId,
              'connected': connected,
            });
            await emitEvent('campus.onBLEConnectionStateChanged', eventPayload);
            await emitEvent('JCpdaily.onBLEConnectionStateChanged', eventPayload);

            if (!completer.isCompleted &&
                update.connectionState == DeviceConnectionState.connected) {
              completer.complete((ok: true, payload: bleOkPayload()));
            }
          },
          onError: (Object error) {
            if (!completer.isCompleted) {
              completer.complete((
                ok: false,
                payload: bleFailPayload(10003, error.toString()),
              ));
            }
          },
        );

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => (
        ok: false,
        payload: bleFailPayload(10004, '连接蓝牙设备超时'),
      ),
    );
  }

  Future<({bool ok, Object payload})> _disconnectBleDevice(
    Map<String, dynamic> opts,
    Future<void> Function(String key, Map<String, dynamic> payload) emitEvent,
  ) async {
    final deviceId = (opts['deviceId'] ?? _connectedDeviceId ?? '').toString();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDeviceId = null;
    final payload = bleOkPayload(<String, dynamic>{
      'deviceId': deviceId,
      'connected': false,
    });
    await emitEvent('campus.onBLEConnectionStateChanged', payload);
    await emitEvent('JCpdaily.onBLEConnectionStateChanged', payload);
    return (ok: true, payload: bleOkPayload());
  }

  Future<({bool ok, Object payload})> _getBleDeviceServices(
    Map<String, dynamic> opts,
  ) async {
    final deviceId = (opts['deviceId'] ?? _connectedDeviceId ?? '').toString();
    if (deviceId.isEmpty) {
      return (ok: false, payload: bleFailPayload(10005, 'deviceId 不能为空'));
    }
    // ignore: deprecated_member_use
    final services = await _ble.discoverServices(deviceId);
    _discoveredServices[deviceId] = services;
    return (ok: true, payload: services.map(_mapService).toList());
  }

  Future<({bool ok, Object payload})> _getBleDeviceCharacteristics(
    Map<String, dynamic> opts,
  ) async {
    final deviceId = (opts['deviceId'] ?? _connectedDeviceId ?? '').toString();
    final serviceId = (opts['serviceId'] ?? '').toString().toLowerCase();
    if (deviceId.isEmpty || serviceId.isEmpty) {
      return (
        ok: false,
        payload: bleFailPayload(10006, 'deviceId 或 serviceId 不能为空'),
      );
    }
    final expandedServiceId = _expandShortUuid(serviceId).toLowerCase();
    final shortLower = _toShortUuid(expandedServiceId).toLowerCase();

    var services = _discoveredServices[deviceId];
    if (services == null || services.isEmpty) {
      // ignore: deprecated_member_use
      services = await _ble.discoverServices(deviceId);
      _discoveredServices[deviceId] = services;
    }

    debugPrint(
      '[BLE.chars] looking for serviceId=$serviceId '
      'expanded=$expandedServiceId short=$shortLower '
      'discovered=${services.map((s) => s.serviceId.toString()).toList()}',
    );

    DiscoveredService? service;
    for (final s in services) {
      final sid = s.serviceId.toString().toLowerCase();
      if (sid == expandedServiceId ||
          sid.contains(shortLower) ||
          _toShortUuid(sid).toLowerCase() == shortLower) {
        service = s;
        break;
      }
    }

    if (service == null) {
      debugPrint(
        '[BLE.chars] service not found, retrying after 500ms... '
        'requested=$serviceId discovered=${services.map((s) => s.serviceId.toString()).toList()}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // ignore: deprecated_member_use
      services = await _ble.discoverServices(deviceId);
      _discoveredServices[deviceId] = services;
      for (final s in services) {
        final sid = s.serviceId.toString().toLowerCase();
        if (sid == expandedServiceId ||
            sid.contains(shortLower) ||
            _toShortUuid(sid).toLowerCase() == shortLower) {
          service = s;
          break;
        }
      }
    }

    if (service == null) {
      return (
        ok: false,
        payload: bleFailPayload(
          10007,
          '未找到蓝牙服务 (requested=$serviceId, '
          'discovered=${services.map((s) => s.serviceId.toString()).toList()})',
        ),
      );
    }
    final foundService = service;
    final charsList = foundService.characteristics
        .map((item) => _mapCharacteristic(item, foundService.serviceId.toString()))
        .toList();
    debugPrint(
      '[BLE.chars] returning ${charsList.length} characteristics: '
      '${charsList.map((c) => '${c['characteristicId']}(w=${c['properties']?['write']},n=${c['properties']?['notify']})').toList()}',
    );
    return (
      ok: true,
      payload: bleOkPayload(<String, dynamic>{
        'characteristics': charsList,
      }),
    );
  }

  Future<({bool ok, Object payload})> _notifyBleCharacteristicValueChange(
    Map<String, dynamic> opts,
    Future<void> Function(String key, Map<String, dynamic> payload) emitEvent,
  ) async {
    final deviceId = (opts['deviceId'] ?? '').toString();
    final serviceId = (opts['serviceId'] ?? '').toString();
    final characteristicId = (opts['characteristicId'] ?? '').toString();
    final state = opts['state'] != false;
    if (deviceId.isEmpty || serviceId.isEmpty || characteristicId.isEmpty) {
      return (ok: false, payload: bleFailPayload(10008, 'notify 参数不完整'));
    }

    final key = '$deviceId|$serviceId|$characteristicId';
    await _notifySubscriptions.remove(key)?.cancel();
    if (!state) {
      return (ok: true, payload: bleOkPayload());
    }

    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(_expandShortUuid(serviceId)),
      characteristicId: Uuid.parse(_expandShortUuid(characteristicId)),
    );
    _notifySubscriptions[key] = _ble
        .subscribeToCharacteristic(characteristic)
        .listen((data) async {
          final payload = bleOkPayload(<String, dynamic>{
            'deviceId': deviceId,
            'serviceId': _toShortUuid(serviceId),
            'characteristicId': _toShortUuid(characteristicId),
            'value': _bytesToHex(data),
          });
          await emitEvent('campus.onBLECharacteristicValueChange', payload);
          await emitEvent('JCpdaily.onBLECharacteristicValueChange', payload);
        });
    return (ok: true, payload: bleOkPayload());
  }

  Future<({bool ok, Object payload})> _writeBleCharacteristicValue(
    Map<String, dynamic> opts,
  ) async {
    final deviceId = (opts['deviceId'] ?? '').toString();
    final serviceId = (opts['serviceId'] ?? '').toString();
    final characteristicId = (opts['characteristicId'] ?? '').toString();
    final value = _normalizeWriteValue(opts['value']);
    if (deviceId.isEmpty || serviceId.isEmpty || characteristicId.isEmpty) {
      return (ok: false, payload: bleFailPayload(10009, '写入参数不完整'));
    }
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(_expandShortUuid(serviceId)),
      characteristicId: Uuid.parse(_expandShortUuid(characteristicId)),
    );
    try {
      await _ble.writeCharacteristicWithoutResponse(characteristic, value: value);
    } catch (_) {
      await _ble.writeCharacteristicWithResponse(characteristic, value: value);
    }
    return (ok: true, payload: bleOkPayload());
  }

  Future<({bool ok, Object payload})> _readBleCharacteristicValue(
    Map<String, dynamic> opts,
  ) async {
    final deviceId = (opts['deviceId'] ?? '').toString();
    final serviceId = (opts['serviceId'] ?? '').toString();
    final characteristicId = (opts['characteristicId'] ?? '').toString();
    if (deviceId.isEmpty || serviceId.isEmpty || characteristicId.isEmpty) {
      return (ok: false, payload: bleFailPayload(10010, '读取参数不完整'));
    }
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(_expandShortUuid(serviceId)),
      characteristicId: Uuid.parse(_expandShortUuid(characteristicId)),
    );
    final value = await _ble.readCharacteristic(characteristic);
    return (
      ok: true,
      payload: bleOkPayload(<String, dynamic>{
        'value': _bytesToHex(value),
      }),
    );
  }

  Future<bool> _ensureBlePermissions() async {
    if (Platform.isIOS) {
      await _waitForBleReady();
      if (_status == BleStatus.unauthorized || _status == BleStatus.unsupported) {
        return false;
      }
      return true;
    }
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  List<Map<String, dynamic>> _currentConnectedDevices() {
    if (_connectedDeviceId == null) return const <Map<String, dynamic>>[];
    final device = _discoveredDevices[_connectedDeviceId!];
    if (device == null) {
      final fallbackName = _normalizeDeviceLocalName(_connectedDeviceId!);
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'deviceId': _connectedDeviceId,
          'name': fallbackName,
          'localName': fallbackName,
          'RSSI': 0,
        },
      ];
    }
    return <Map<String, dynamic>>[_mapDiscoveredDevice(device)];
  }

  Map<String, dynamic> _adapterStatePayload() {
    final available = _status == BleStatus.ready;
    final discovering = _scanSubscription != null;
    final connected = _connectedDeviceId != null;
    return <String, dynamic>{
      'available': available,
      'isAvailable': available,
      'bluetoothEnabled': available,
      'discovering': discovering,
      'isDiscovering': discovering,
      'connected': connected,
      'isConnected': connected,
      'adapterState': available ? 'on' : 'off',
      'state': available ? 'on' : 'off',
    };
  }

  static Map<String, dynamic> _mapDiscoveredDevice(DiscoveredDevice device) {
    final displayName = device.name.trim().isNotEmpty ? device.name.trim() : device.id;
    final localName = _normalizeDeviceLocalName(displayName);
    return <String, dynamic>{
      'deviceId': device.id,
      'name': displayName,
      'localName': localName,
      'RSSI': device.rssi,
    };
  }

  static String _normalizeDeviceLocalName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;

    final exactMatch =
        RegExp(r'^([A-Za-z]{2})[_-]?([A-Za-z0-9]{12})$').firstMatch(trimmed);
    if (exactMatch != null) {
      return '${exactMatch.group(1)!.toUpperCase()}_${exactMatch.group(2)!}';
    }

    final serialMatch = RegExp(r'([A-Za-z0-9]{12})').firstMatch(trimmed);
    if (serialMatch != null) {
      final serial = serialMatch.group(1)!;
      final prefixMatch = RegExp(r'^([A-Za-z]{2})').firstMatch(trimmed);
      final prefix = (prefixMatch?.group(1) ?? 'ZY').toUpperCase();
      return '${prefix}_$serial';
    }

    return trimmed;
  }

  static const String _bleSigBaseSuffix = '-0000-1000-8000-00805f9b34fb';

  static String _toShortUuid(String full) {
    final lower = full.toLowerCase().trim();
    if (RegExp(r'^[0-9a-f]{4}$').hasMatch(lower)) {
      return lower.toUpperCase();
    }
    final m = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$')
        .firstMatch(lower);
    if (m != null) return m.group(1)!.toUpperCase();
    return full;
  }

  static String _expandShortUuid(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return clean;
    if (clean.contains('-') || clean.length == 32) return clean;
    final hex = clean.toLowerCase();
    if (RegExp(r'^[0-9a-f]{4}$').hasMatch(hex)) {
      return '0000$hex$_bleSigBaseSuffix';
    }
    if (RegExp(r'^[0-9a-f]{8}$').hasMatch(hex)) {
      return '$hex$_bleSigBaseSuffix';
    }
    return clean;
  }

  static Map<String, dynamic> _mapService(DiscoveredService service) {
    final fullUuid = service.serviceId.toString();
    final shortUuid = _toShortUuid(fullUuid);
    return <String, dynamic>{
      'serviceId': shortUuid,
      'isPrimary': true,
    };
  }

  static Map<String, dynamic> _mapCharacteristic(
    DiscoveredCharacteristic characteristic,
    String serviceId,
  ) {
    final fullUuid = characteristic.characteristicId.toString();
    final shortUuid = _toShortUuid(fullUuid);
    final shortServiceId = _toShortUuid(serviceId);
    final isWritable = characteristic.isWritableWithResponse ||
        characteristic.isWritableWithoutResponse;
    return <String, dynamic>{
      'characteristicId': shortUuid,
      'serviceId': shortServiceId,
      'value': '',
      'properties': <String, bool>{
        'notify': characteristic.isNotifiable,
        'write': isWritable,
        'indicate': characteristic.isIndicatable,
        'read': characteristic.isReadable,
      },
    };
  }

  static List<int> _normalizeWriteValue(Object? rawValue) {
    if (rawValue is List) {
      return rawValue.map((item) => int.tryParse(item.toString()) ?? 0).toList();
    }
    final text = rawValue?.toString() ?? '';
    final normalized = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (normalized.isEmpty) return const <int>[];
    final buffer = StringBuffer(normalized);
    if (buffer.length.isOdd) {
      buffer.write('0');
    }
    final result = <int>[];
    final hex = buffer.toString();
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
