import test from 'node:test';
import assert from 'node:assert/strict';
import { HudFrame } from '../src/hud-frame';

test('Three.js fallback labels are presented with every camera frame, including 165 Hz', () => {
  const painted: number[] = [],
    scenes: number[] = [];
  let camera = 0;
  const frame = new HudFrame({
    nativePaint: () => assert.fail('native API unavailable'),
    fallbackPaint: () => painted.push(camera),
    onFallback: () => assert.fail('already in fallback'),
  });
  for (let i = 0; i < 165; i++) {
    camera = i;
    frame.present(() => scenes.push(camera));
  }
  assert.equal(painted.length, 165);
  assert.deepEqual(painted, scenes, 'labels must use exactly the rendered camera state');
});

test('native paint couples the newest scene and HTML snapshot without drawing an older camera', () => {
  const order: string[] = [];
  let camera = 1;
  const frame = new HudFrame({
    requestPaint: () => order.push('request'),
    nativePaint: () => order.push(`html:${camera}`),
    fallbackPaint: () => assert.fail('native rendering works'),
    onFallback: () => assert.fail('native rendering works'),
  });
  frame.present(() => order.push('scene:1'));
  camera = 2;
  frame.present(() => order.push('scene:2'));
  assert.deepEqual(order, ['request', 'request']);
  frame.paint();
  assert.deepEqual(order, ['request', 'request', 'scene:2', 'html:2']);
  frame.dispose();
  frame.present(() => assert.fail('disposed scene'));
  frame.paint();
  assert.equal(order.length, 4);
});

test('partial experimental APIs fall back without leaving missing labels or duplicating the scene', () => {
  for (const failure of ['request', 'paint', 'silent']) {
    let scene = 0,
      labels = 0,
      fallback = 0;
    const frame = new HudFrame({
      requestPaint: () => {
        if (failure === 'request') throw new Error('disabled');
      },
      nativePaint: () => {
        throw new Error('unsupported drawable snapshot');
      },
      fallbackPaint: () => labels++,
      onFallback: () => fallback++,
    });
    frame.present(() => scene++);
    if (failure === 'paint') frame.paint();
    if (failure === 'silent') for (let i = 0; i < 4; i++) frame.present(() => scene++);
    assert.equal(frame.native, false, failure);
    assert.equal(scene, 1, failure);
    assert.equal(labels, 1, failure);
    assert.equal(fallback, 1, failure);
    frame.present(() => scene++);
    assert.equal(scene, 2);
    assert.equal(labels, 2);
  }
});
