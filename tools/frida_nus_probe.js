// HydroCap dev tool — NUS request/response probe, GET-only.
// Connects to the cap, enables NUS TX notifications, then sends a fixed
// list of read-only requests one at a time (waiting for each response),
// logging raw bytes. No setters, no SetTime, no DFU.
'use strict';

// Supply with Frida CLI: -P '{"targetName":"<advertised cap name>"}'.
// Resolve the caller-selected name on each scan (the cap rotates addresses).
var TARGET_NAME = null;
var NUS_RX = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
var NUS_TX = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
var CCCD = '00002902-0000-1000-8000-00805f9b34fb';
var WRITE_TYPE = 2; // 2 = WRITE_TYPE_DEFAULT (with response), 1 = NO_RESPONSE

// Pre-encoded CapBleRequest bytes (protoc, vendor-compatible schema). GET only.
var REQUESTS = [
  ['GetCapUiState',              '0d01000000122a0a28747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617055695374617465'],
  ['GetCapTofSettings',          '0d02000000122e0a2c747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f6653657474696e6773'],
  ['GetCapLowBatterySettings',   '0d0300000012350a33747970652e676f6f676c65617069732e636f6d2f526571756573744765744361704c6f774261747465727953657474696e6773'],
  ['GetCapHydroReminderSettings','0d0400000012380a36747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170487964726f52656d696e64657253657474696e6773'],
  ['GetCapDoNotDisturbSettings', '0d0500000012370a35747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170446f4e6f744469737475726253657474696e6773'],
  ['GetCapTofState',             '0d06000000122b0a29747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f665374617465'],
  ['GetCapTimeSettings',         '0d07000000122f0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617054696d6553657474696e6773'],
  ['GetCapTofLog(from=0,limit=5)','0d0800000012320a27747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f664c6f6712070a051505000000'],
  ['GetCapActivationLog(from=0,limit=5)','0d0900000012390a2e747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617041637469766174696f6e4c6f6712070a051505000000']
];

function hex(bytes) { if (bytes === null) return null; var s = ''; for (var i = 0; i < bytes.length; i++) { var b = bytes[i] & 0xff; s += (b < 16 ? '0' : '') + b.toString(16); } return s; }
function unhex(h) { var a = []; for (var i = 0; i < h.length; i += 2) { var v = parseInt(h.substr(i, 2), 16); a.push(v > 127 ? v - 256 : v); } return Java.array('byte', a); }
function log(o) { console.log(JSON.stringify(Object.assign({ t: Date.now() }, o))); }

rpc.exports = {
  init: function (stage, parameters) {
    var targetName = parameters && parameters.targetName;
    if (typeof targetName !== 'string' || !/^LARQ_[0-9A-Za-z]{11}$/.test(targetName)) {
      throw new Error('explicit advertised targetName required via Frida -P');
    }
    TARGET_NAME = targetName;
    Java.perform(function () { waitApp(); });
  }
};
function waitApp() {
  var app = Java.use('android.app.ActivityThread').currentApplication();
  if (app === null) { setTimeout(function () { Java.perform(waitApp); }, 300); return; }
  main(app.getApplicationContext());
}

function main(ctx) {
  var BluetoothManager = Java.use('android.bluetooth.BluetoothManager');
  var BluetoothGattDescriptor = Java.use('android.bluetooth.BluetoothGattDescriptor');
  var UUID = Java.use('java.util.UUID');
  var mgr = Java.cast(ctx.getSystemService('bluetooth'), BluetoothManager);
  var adapter = mgr.getAdapter();

  var G = null, rx = null, tx = null;
  var idx = -1, pending = null, timer = null, finished = false;

  function finish(reason) {
    if (finished) return; finished = true;
    log({ ev: 'finish', reason: reason });
    try { G.disconnect(); } catch (e) { log({ ev: 'disconnect_err', e: '' + e }); }
  }
  function sendNext() {
    idx++;
    if (idx >= REQUESTS.length) { finish('all_done'); return; }
    pending = REQUESTS[idx];
    var bytes = unhex(pending[1]);
    var rc = G.writeCharacteristic(rx, bytes, WRITE_TYPE);
    log({ ev: 'tx', name: pending[0], len: bytes.length, hex: pending[1], writeType: WRITE_TYPE, rc: rc });
    timer = setTimeout(function () { Java.perform(function () { log({ ev: 'timeout', name: pending[0] }); sendNext(); }); }, 5000);
  }

  var Cb = Java.registerClass({
    name: 'dev.hydrocap.tools.NusCb',
    superClass: Java.use('android.bluetooth.BluetoothGattCallback'),
    methods: {
      onConnectionStateChange: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int', 'int'],
        implementation: function (gatt, status, newState) {
          log({ ev: 'conn', status: status, newState: newState });
          if (status === 0 && newState === 2) { G = Java.retain(gatt); G.requestMtu(247); }
          else if (newState === 0) { try { gatt.close(); } catch (e) {} console.log('PROBE_DONE'); }
        } }],
      onMtuChanged: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int', 'int'],
        implementation: function (gatt, mtu, status) { log({ ev: 'mtu', mtu: mtu, status: status }); G.discoverServices(); } }],
      onServicesDiscovered: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int'],
        implementation: function (gatt, status) {
          var svc = G.getService(UUID.fromString('6e400001-b5a3-f393-e0a9-e50e24dcca9e'));
          if (svc === null) { log({ ev: 'no_nus' }); finish('no_nus'); return; }
          rx = Java.retain(svc.getCharacteristic(UUID.fromString(NUS_RX)));
          tx = Java.retain(svc.getCharacteristic(UUID.fromString(NUS_TX)));
          G.setCharacteristicNotification(tx, true);
          var d = tx.getDescriptor(UUID.fromString(CCCD));
          var rc = G.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.value);
          log({ ev: 'cccd_write_issued', rc: rc });
        } }],
      onDescriptorWrite: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattDescriptor', 'int'],
        implementation: function (gatt, d, status) { log({ ev: 'cccd_written', status: status }); sendNext(); } }],
      onCharacteristicWrite: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattCharacteristic', 'int'],
        implementation: function (gatt, c, status) { log({ ev: 'write_ack', status: status }); } }],
      onCharacteristicChanged: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattCharacteristic'],
        implementation: function (gatt, c) {
          var v = c.getValue();
          log({ ev: 'rx', uuid: c.getUuid().toString(), len: v === null ? 0 : v.length, hex: hex(v), forReq: pending ? pending[0] : null });
          if (timer !== null) { clearTimeout(timer); timer = null; }
          setTimeout(function () { Java.perform(sendNext); }, 150);
        } }]
    }
  });

  var cb = Cb.$new();

  // --- scan for the cap by name, then connect to the address it currently uses ---
  var scanner = adapter.getBluetoothLeScanner();
  var ScanSettings = Java.use('android.bluetooth.le.ScanSettings');
  var SBuilder = Java.use('android.bluetooth.le.ScanSettings$Builder');
  var FBuilder = Java.use('android.bluetooth.le.ScanFilter$Builder');
  var ArrayList = Java.use('java.util.ArrayList');
  var filters = ArrayList.$new();
  filters.add(FBuilder.$new().setDeviceName(TARGET_NAME).build());
  var settings = SBuilder.$new().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY.value).build();
  var scanCb = null, found = false;
  var ScanCb = Java.registerClass({
    name: 'dev.hydrocap.tools.NusScanCb',
    superClass: Java.use('android.bluetooth.le.ScanCallback'),
    methods: {
      onScanResult: [{ returnType: 'void', argumentTypes: ['int', 'android.bluetooth.le.ScanResult'],
        implementation: function (cbType, result) {
          if (found) return; found = true;
          var dev = result.getDevice();
          var addr = dev.getAddress();
          log({ ev: 'found', name: result.getScanRecord().getDeviceName(), addr: addr, rssi: result.getRssi() });
          try { scanner.stopScan(scanCb); } catch (e) {}
          var device = adapter.getRemoteDevice(addr);
          log({ ev: 'connecting', addr: addr });
          device.connectGatt(ctx, false, cb, 2);
        } }],
      onScanFailed: [{ returnType: 'void', argumentTypes: ['int'], implementation: function (code) { log({ ev: 'scan_failed', code: code }); } }]
    }
  });
  scanCb = ScanCb.$new();
  scanner.startScan(filters, settings, scanCb);
  log({ ev: 'scanning', name: TARGET_NAME });
  setTimeout(function () { Java.perform(function () {
    if (!found) { try { scanner.stopScan(scanCb); } catch (e) {} log({ ev: 'scan_timeout' }); console.log('PROBE_DONE'); }
  }); }, 30000);
  setTimeout(function () { Java.perform(function () { if (!finished && G !== null) finish('global_timeout'); }); }, 75000);
}
