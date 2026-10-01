// HydroCap dev tool — passive BLE scan via Android's Java scanner, run inside
// a throwaway host process with Frida (root device). Logs LARQ-family caps.
// No writes, no connections. Prints JSON lines to the Frida console.
'use strict';

Java.perform(function () {
  var app = Java.use('android.app.ActivityThread').currentApplication();
  if (app === null) {
    // Spawned process: Application not created yet. Retry shortly.
    setTimeout(function () { Java.perform(main); }, 500);
    return;
  }
  main();
});

function main() {
  var app = Java.use('android.app.ActivityThread').currentApplication();
  if (app === null) { setTimeout(function () { Java.perform(main); }, 500); return; }
  var ctx = app.getApplicationContext();
  var BluetoothManager = Java.use('android.bluetooth.BluetoothManager');
  var mgr = Java.cast(ctx.getSystemService('bluetooth'), BluetoothManager);
  var adapter = mgr.getAdapter();
  var scanner = adapter.getBluetoothLeScanner();
  var ScanSettings = Java.use('android.bluetooth.le.ScanSettings');
  var Builder = Java.use('android.bluetooth.le.ScanSettings$Builder');
  var settings = Builder.$new().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY.value).build();
  var ArrayList = Java.use('java.util.ArrayList');
  var filters = ArrayList.$new();
  // Android blocks unfiltered scans while the screen is off; filter on the
  // Device Information service the LARQ cap advertises (protocol doc §1).
  var ParcelUuid = Java.use('android.os.ParcelUuid');
  var FilterBuilder = Java.use('android.bluetooth.le.ScanFilter$Builder');
  filters.add(FilterBuilder.$new().setServiceUuid(ParcelUuid.fromString('0000180a-0000-1000-8000-00805f9b34fb')).build());
  filters.add(FilterBuilder.$new().setManufacturerData(0x0059, Java.array('byte', [0x43, 0x41, 0x50])).build());

  function hex(bytes) {
    if (bytes === null) return null;
    var s = '';
    for (var i = 0; i < bytes.length; i++) {
      var b = bytes[i] & 0xff; s += (b < 16 ? '0' : '') + b.toString(16);
    }
    return s;
  }

  var seen = {};
  var Callback = Java.registerClass({
    name: 'dev.hydrocap.tools.ScanCb',
    superClass: Java.use('android.bluetooth.le.ScanCallback'),
    methods: {
      onScanResult: [{
        returnType: 'void', argumentTypes: ['int', 'android.bluetooth.le.ScanResult'],
        implementation: function (cbType, result) {
          try {
            var dev = result.getDevice();
            var rec = result.getScanRecord();
            var name = rec !== null ? rec.getDeviceName() : null;
            var addr = dev.getAddress();
            var rssi = result.getRssi();
            var raw = rec !== null ? hex(rec.getBytes()) : null;
            var uuids = rec !== null && rec.getServiceUuids() !== null ? rec.getServiceUuids().toString() : null;
            var mfg = null;
            if (rec !== null) {
              var sa = rec.getManufacturerSpecificData();
              if (sa !== null && sa.size() > 0) {
                mfg = {};
                for (var i = 0; i < sa.size(); i++) mfg[sa.keyAt(i)] = hex(sa.valueAt(i));
              }
            }
            var interesting = (name !== null && name.toLowerCase().indexOf('larq') >= 0) ||
              (uuids !== null && uuids.toLowerCase().indexOf('0000180a') >= 0) ||
              (mfg !== null && mfg[89] !== undefined && mfg[89].indexOf('434150') === 0);
            var key = addr + '|' + name;
            var n = (seen[key] || 0) + 1; seen[key] = n;
            if (interesting || n === 1) {
              console.log(JSON.stringify({ t: Date.now(), name: name, addr: addr, rssi: rssi,
                uuids: uuids, mfg: mfg, raw: interesting ? raw : undefined, n: n, hit: interesting }));
            }
          } catch (e) { console.log('ERR ' + e); }
        }
      }],
      onScanFailed: [{ returnType: 'void', argumentTypes: ['int'],
        implementation: function (code) { console.log('SCAN_FAILED ' + code); } }]
    }
  });
  var cb = Callback.$new();
  scanner.startScan(filters, settings, cb);
  console.log('SCAN_STARTED');
  setTimeout(function () { try { scanner.stopScan(cb); } catch (e) {} console.log('SCAN_STOPPED'); }, 25000);
}

