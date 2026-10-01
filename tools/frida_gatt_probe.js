// HydroCap dev tool — READ-ONLY GATT probe of a LARQ-family cap, run inside a
// spawned host process with Frida on the rooted phone.
//
// Does: connect, requestMtu(247), discover services, read Device Information
// strings, read Battery Level, enable notifications on NUS TX, then
// disconnect. Sends NOTHING on the NUS RX characteristic.
'use strict';

// Supply with Frida CLI: -P '{"target":"<current BLE address>"}'.
// Caller must select the current address; this probe has no device default.
var TARGET = null;
var NUS_TX = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
var CCCD = '00002902-0000-1000-8000-00805f9b34fb';
var DIS = { '00002a24-0000-1000-8000-00805f9b34fb': 'model', '00002a25-0000-1000-8000-00805f9b34fb': 'serial',
            '00002a26-0000-1000-8000-00805f9b34fb': 'firmware', '00002a27-0000-1000-8000-00805f9b34fb': 'hardware',
            '00002a28-0000-1000-8000-00805f9b34fb': 'software', '00002a29-0000-1000-8000-00805f9b34fb': 'manufacturer' };
var BATT = '00002a19-0000-1000-8000-00805f9b34fb';

function hex(bytes) {
  if (bytes === null) return null;
  var s = ''; for (var i = 0; i < bytes.length; i++) { var b = bytes[i] & 0xff; s += (b < 16 ? '0' : '') + b.toString(16); } return s;
}
function str(bytes) { var s = ''; for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i] & 0xff); return s; }
function log(o) { console.log(JSON.stringify(Object.assign({ t: Date.now() }, o))); }

rpc.exports = {
  init: function (stage, parameters) {
    var target = parameters && parameters.target;
    if (typeof target !== 'string' || !/^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(target)) {
      throw new Error('explicit target BLE address required via Frida -P');
    }
    TARGET = target;
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
  var BluetoothDevice = Java.use('android.bluetooth.BluetoothDevice');
  var BluetoothGatt = Java.use('android.bluetooth.BluetoothGatt');
  var BluetoothGattDescriptor = Java.use('android.bluetooth.BluetoothGattDescriptor');
  var mgr = Java.cast(ctx.getSystemService('bluetooth'), BluetoothManager);
  var adapter = mgr.getAdapter();
  var device = adapter.getRemoteDevice(TARGET);

  var readQueue = [];      // characteristics to read sequentially
  var gattRef = null;
  var notifyChar = null;
  var finished = false;

  function next(gatt) {
    if (readQueue.length > 0) {
      var c = readQueue.shift();
      var ok = gatt.readCharacteristic(c);
      log({ ev: 'read_issued', uuid: c.getUuid().toString(), ok: ok });
      return;
    }
    if (notifyChar !== null) {
      var c2 = notifyChar; notifyChar = null;
      var okN = gatt.setCharacteristicNotification(c2, true);
      var d = c2.getDescriptor(Java.use('java.util.UUID').fromString(CCCD));
      var okD = false;
      if (d !== null) {
        okD = gatt.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.value);
      }
      log({ ev: 'notify_enable', setNotification: okN, cccdWrite: okD, hasCccd: d !== null });
      return;
    }
    if (!finished) {
      finished = true;
      log({ ev: 'done_disconnecting' });
      gatt.disconnect();
    }
  }

  var Cb = Java.registerClass({
    name: 'dev.hydrocap.tools.GattCb',
    superClass: Java.use('android.bluetooth.BluetoothGattCallback'),
    methods: {
      onConnectionStateChange: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int', 'int'],
        implementation: function (gatt, status, newState) {
          log({ ev: 'conn', status: status, newState: newState });
          if (status === 0 && newState === 2) {
            gattRef = gatt;
            var ok = gatt.requestMtu(247);
            log({ ev: 'mtu_requested', ok: ok });
          } else if (newState === 0) {
            try { gatt.close(); } catch (e) {}
            log({ ev: 'closed' });
            console.log('PROBE_DONE');
          }
        } }],
      onMtuChanged: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int', 'int'],
        implementation: function (gatt, mtu, status) {
          log({ ev: 'mtu', mtu: mtu, status: status });
          var ok = gatt.discoverServices();
          log({ ev: 'discover_issued', ok: ok });
        } }],
      onServicesDiscovered: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'int'],
        implementation: function (gatt, status) {
          log({ ev: 'services', status: status });
          var services = gatt.getServices();
          for (var i = 0; i < services.size(); i++) {
            var s = Java.cast(services.get(i), Java.use('android.bluetooth.BluetoothGattService'));
            var chars = s.getCharacteristics();
            var list = [];
            for (var j = 0; j < chars.size(); j++) {
              var c = Java.cast(chars.get(j), Java.use('android.bluetooth.BluetoothGattCharacteristic'));
              var u = c.getUuid().toString();
              list.push({ uuid: u, props: c.getProperties(), descriptors: c.getDescriptors().size() });
              if (DIS[u] !== undefined || u === BATT) readQueue.push(c);
              if (u === NUS_TX) notifyChar = c;
            }
            log({ ev: 'service', uuid: s.getUuid().toString(), chars: list });
          }
          next(gatt);
        } }],
      onCharacteristicRead: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattCharacteristic', 'int'],
        implementation: function (gatt, c, status) {
          var u = c.getUuid().toString();
          var v = c.getValue();
          var out = { ev: 'read', uuid: u, name: DIS[u] || (u === BATT ? 'battery' : u), status: status, hex: v === null ? null : hex(v) };
          if (v !== null && DIS[u] !== undefined) out.text = str(v);
          if (v !== null && u === BATT) out.percent = v[0] & 0xff;
          log(out);
          next(gatt);
        } }],
      onDescriptorWrite: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattDescriptor', 'int'],
        implementation: function (gatt, d, status) {
          log({ ev: 'cccd_written', status: status });
          // Listen a few seconds for unsolicited notifications, then finish.
          setTimeout(function () { Java.perform(function () { next(gatt); }); }, 4000);
        } }],
      onCharacteristicChanged: [{ returnType: 'void', argumentTypes: ['android.bluetooth.BluetoothGatt', 'android.bluetooth.BluetoothGattCharacteristic'],
        implementation: function (gatt, c) {
          var v = c.getValue();
          log({ ev: 'notify', uuid: c.getUuid().toString(), len: v === null ? 0 : v.length, hex: hex(v) });
        } }]
    }
  });

  var cb = Cb.$new();
  log({ ev: 'connecting', addr: TARGET, bond: device.getBondState() });
  // TRANSPORT_LE = 2, autoConnect=false
  device.connectGatt(ctx, false, cb, 2);
  setTimeout(function () { Java.perform(function () {
    if (!finished && gattRef !== null) { log({ ev: 'timeout_disconnect' }); finished = true; gattRef.disconnect(); }
    else if (gattRef === null) { log({ ev: 'timeout_no_connection' }); console.log('PROBE_DONE'); }
  }); }, 40000);
}
