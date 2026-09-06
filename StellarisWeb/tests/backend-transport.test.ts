import test from 'node:test';
import assert from 'node:assert/strict';
import { gzipSync } from 'node:zlib';
import { OrderedReceiver } from '../backend/transport';

const plain = (value: string) => new Uint8Array([0, ...new TextEncoder().encode(value)]);
const compressed = (value: string) => new Uint8Array([2, ...gzipSync(value)]);
test('compressed snapshots and subsequent plain transactions reach the cache in wire order', async () => {
  const received: string[] = [];
  const receiver = new OrderedReceiver((data) => received.push(new TextDecoder().decode(data)), assert.fail);
  await Promise.all([
    receiver.push(compressed('initial'.repeat(10000))),
    receiver.push(plain('update')),
    receiver.push(compressed('next transaction')),
    receiver.push(plain('delete')),
  ]);
  assert.deepEqual(received, ['initial'.repeat(10000), 'update', 'next transaction', 'delete']);
  assert.equal(receiver.stats.compressedFrames, 2);
  assert.equal(receiver.stats.decodedBytes, 70000 + 6 + 16 + 6);
  assert.equal(receiver.stats.pendingBytes, 0);
});
test('corrupt compression closes the stream and never applies later transactions', async () => {
  const received: Uint8Array[] = [],
    errors: Error[] = [];
  const receiver = new OrderedReceiver(
    (data) => received.push(data),
    (error) => errors.push(error),
  );
  await Promise.all([receiver.push(new Uint8Array([2, 1, 2, 3])), receiver.push(plain('must not apply'))]);
  assert.equal(received.length, 0);
  assert.equal(errors.length, 1);
  assert.equal(receiver.stats.pendingBytes, 0);
});
test('disconnect discards queued decompression and overload requests a fresh snapshot', async () => {
  const received: Uint8Array[] = [],
    errors: Error[] = [];
  const receiver = new OrderedReceiver(
    (data) => received.push(data),
    (error) => errors.push(error),
  );
  const pending = receiver.push(compressed('old connection'));
  receiver.close();
  await pending;
  assert.equal(received.length, 0);
  const limited = new OrderedReceiver(
    (data) => received.push(data),
    (error) => errors.push(error),
    undefined,
    128,
  );
  await limited.push(compressed('compressed expansion'.repeat(1000)));
  assert.equal(received.length, 0);
  assert.match(errors[0].message, /Decoded frame/);
  const backlogged = new OrderedReceiver(
    (data) => received.push(data),
    (error) => errors.push(error),
    undefined,
    16,
  );
  await Promise.all([backlogged.push(plain('123456789')), backlogged.push(plain('123456789'))]);
  assert.equal(received.length, 0);
  assert.match(errors[1].message, /backlog/);
  assert.equal(backlogged.stats.pendingBytes, 0);
});
