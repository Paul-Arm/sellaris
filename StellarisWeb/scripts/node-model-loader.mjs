import assert from 'node:assert/strict';
import { inflateSync, crc32 } from 'node:zlib';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

/** Decode the embedded 8-bit RGB/RGBA PNGs produced by Blender, without a DOM.
 * Browser rendering still uses Three's native image loader. These real pixels
 * let the offline validator check baked models instead of skipping textures.
 */
export function decodeModelPng(input) {
  const bytes = Buffer.from(input);
  assert(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])));
  let width,
    height,
    channels,
    ended = false;
  const compressed = [];
  for (let offset = 8; offset < bytes.length;) {
    assert(offset + 12 <= bytes.length, 'Truncated PNG chunk');
    const length = bytes.readUInt32BE(offset);
    assert(offset + 12 + length <= bytes.length, 'Truncated PNG payload');
    const kind = bytes.toString('ascii', offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    assert.equal(
      crc32(bytes.subarray(offset + 4, offset + 8 + length)),
      bytes.readUInt32BE(offset + 8 + length),
      'PNG checksum',
    );
    if (kind === 'IHDR') {
      assert.equal(length, 13);
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      assert(width > 0 && width <= 2048 && height > 0 && height <= 2048, 'PNG size budget');
      assert.equal(data[8], 8, 'PNG must use eight-bit channels');
      assert(data[9] === 2 || data[9] === 6, 'PNG must be RGB or RGBA');
      channels = data[9] === 6 ? 4 : 3;
      assert.equal(data[10] + data[11] + data[12], 0, 'Unsupported PNG encoding');
    } else if (kind === 'IDAT') compressed.push(data);
    else if (kind === 'IEND') {
      ended = true;
      break;
    }
    offset += length + 12;
  }
  assert(ended && width && height && channels && compressed.length, 'Incomplete PNG');
  const stride = width * channels;
  const raw = inflateSync(Buffer.concat(compressed), { maxOutputLength: (stride + 1) * height });
  assert.equal(raw.length, (stride + 1) * height, 'PNG scanline length');
  const unfiltered = new Uint8Array(stride * height);
  const paeth = (a, b, c) => {
    const p = a + b - c;
    const pa = Math.abs(p - a),
      pb = Math.abs(p - b),
      pc = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
  };
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    assert(filter <= 4, 'Unknown PNG filter');
    for (let x = 0; x < stride; x++) {
      const at = y * stride + x;
      const a = x >= channels ? unfiltered[at - channels] : 0;
      const b = y > 0 ? unfiltered[at - stride] : 0;
      const c = y > 0 && x >= channels ? unfiltered[at - stride - channels] : 0;
      const prediction = [0, a, b, Math.floor((a + b) / 2), paeth(a, b, c)][filter];
      unfiltered[at] = (raw[y * (stride + 1) + x + 1] + prediction) & 255;
    }
  }
  const data = new Uint8Array(width * height * 4);
  for (let p = 0; p < width * height; p++) {
    data.set(unfiltered.subarray(p * channels, p * channels + 3), p * 4);
    data[p * 4 + 3] = channels === 4 ? unfiltered[p * channels + 3] : 255;
  }
  return { width, height, data };
}

export function createNodeModelLoader() {
  const loader = new GLTFLoader();
  loader.register((parser) => ({
    name: 'NODE_embedded_model_png',
    async loadTexture(index) {
      const definition = parser.json.textures[index];
      const source = parser.json.images[definition.source];
      assert(
        source?.bufferView !== undefined && source.mimeType === 'image/png',
        'Model textures must be embedded PNGs',
      );
      const image = decodeModelPng(await parser.getDependency('bufferView', source.bufferView));
      const texture = new THREE.DataTexture(
        image.data,
        image.width,
        image.height,
        THREE.RGBAFormat,
        THREE.UnsignedByteType,
      );
      texture.name = definition.name ?? source.name ?? '';
      texture.flipY = false;
      const sampler = parser.json.samplers?.[definition.sampler] ?? {};
      const filters = {
        9728: THREE.NearestFilter,
        9729: THREE.LinearFilter,
        9984: THREE.NearestMipmapNearestFilter,
        9985: THREE.LinearMipmapNearestFilter,
        9986: THREE.NearestMipmapLinearFilter,
        9987: THREE.LinearMipmapLinearFilter,
      };
      const wraps = {
        33071: THREE.ClampToEdgeWrapping,
        33648: THREE.MirroredRepeatWrapping,
        10497: THREE.RepeatWrapping,
      };
      texture.magFilter = filters[sampler.magFilter] ?? THREE.LinearFilter;
      texture.minFilter = filters[sampler.minFilter] ?? THREE.LinearMipmapLinearFilter;
      texture.wrapS = wraps[sampler.wrapS] ?? THREE.RepeatWrapping;
      texture.wrapT = wraps[sampler.wrapT] ?? THREE.RepeatWrapping;
      texture.generateMipmaps = true;
      texture.needsUpdate = true;
      parser.associations.set(texture, { textures: index });
      return texture;
    },
  }));
  return loader;
}
