import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeModelPng } from '../scripts/node-model-loader.mjs';

// Two RGB pixels per row; its five scanlines exercise PNG filters 0 through 4.
const image = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAAFCAIAAADg0arLAAAALElEQVR4nGP4z8DA8J+BkYHh////DEw8GimBCneZtdXldOPkWDYY3wzcvRwAvksLdPqbQQMAAAAASUVORK5CYII=',
  'base64',
);

test('offline model validation decodes baked PNG colors and all scanline filters', () => {
  const result = decodeModelPng(image);
  assert.equal(result.width, 2);
  assert.equal(result.height, 5);
  assert.deepEqual(
    Array.from(result.data),
    [
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255, 12, 40, 99, 255, 80, 31, 220, 255,
      49, 59, 79, 255, 109, 139, 179, 255, 225, 110, 40, 255, 50, 70, 90, 255,
    ],
  );
});

test('offline model validation rejects corrupt or truncated baked PNGs', () => {
  const corrupt = Buffer.from(image);
  corrupt[50] ^= 1;
  assert.throws(() => decodeModelPng(corrupt), /PNG checksum/);
  assert.throws(() => decodeModelPng(image.subarray(0, image.length - 4)), /Truncated PNG/);
});

test('transparent field maps preserve straight RGB and alpha independently', () => {
  const rgba = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGPgEpFjODEtpQEAB8MCf1pybS8AAAAASUVORK5CYII=',
    'base64',
  );
  const result = decodeModelPng(rgba);
  assert.equal(result.width, 2);
  assert.equal(result.height, 1);
  assert.deepEqual(Array.from(result.data), [10, 20, 30, 0, 200, 150, 100, 128]);
});
