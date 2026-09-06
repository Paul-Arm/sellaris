import type { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
export function createNodeModelLoader(): GLTFLoader;
export function decodeModelPng(input: ArrayBuffer | Uint8Array): {
  width: number;
  height: number;
  data: Uint8Array;
};
