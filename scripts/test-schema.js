#!/usr/bin/env node
'use strict';

const assert = require('assert');
const { validateCrashPayload, computeFingerprint } = require('../api/schema');

function testDartCrash() {
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'Bad state: test',
    stackTrace: '#0      main (package:app/main.dart:10:5)',
    errorType: 'StateError',
    errorSource: 'dart',
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.crash.errorSource, 'dart');
}

function testNativeManagedCrash() {
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'Object reference not set',
    stackTrace: 'at Runner.App.OnCreate() in App.cs:line 20',
    errorType: 'System.NullReferenceException',
    errorSource: 'native_managed',
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.crash.errorSource, 'native_managed');
  assert.ok(result.crash.fingerprint.length === 16);
}

function testNativeCppCrash() {
  const stackTrace = '#0 0x12345678\\n#1 0x87654321';
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'Native crash: SIGSEGV',
    stackTrace,
    errorType: 'SIGSEGV',
    errorSource: 'native_cpp',
    customKeys: { signal: 'SIGSEGV', nativeCrashId: '1700000000_12345' },
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.crash.errorSource, 'native_cpp');

  const fingerprint = computeFingerprint({
    errorType: 'SIGSEGV',
    message: 'Native crash: SIGSEGV',
    stackTrace,
    errorSource: 'native_cpp',
  });

  assert.strictEqual(fingerprint.length, 16);
}

function testNativeCppCrashWithoutTimestamp() {
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'Native crash: SIGSEGV',
    stackTrace: '#0 0xdeadbeef',
    errorType: 'SIGSEGV',
    errorSource: 'native_cpp',
  });

  assert.strictEqual(result.ok, true);
  assert.ok(result.crash.timestamp);
}

function testDeviceId() {
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'test',
    deviceId: 'tizen-abc-123',
    errorSource: 'dart',
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.crash.deviceId, 'tizen-abc-123');
}

function testInvalidErrorSource() {
  const result = validateCrashPayload({
    platform: 'tizen',
    appId: 'np.com.nettv',
    appVersion: '1.2.18',
    message: 'bad source',
    errorSource: 'invalid',
  });

  assert.strictEqual(result.ok, false);
}

testDartCrash();
testNativeManagedCrash();
testNativeCppCrash();
testNativeCppCrashWithoutTimestamp();
testDeviceId();
testInvalidErrorSource();

console.log('schema tests passed');
