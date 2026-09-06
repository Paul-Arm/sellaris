import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { constants } from 'node:fs';

const snapshot = process.argv.includes('--snapshot');
const catalog = JSON.parse(await readFile('src/assets/model-catalog.json', 'utf8'));
const assets = [];
for (const asset of catalog) {
  const path = `public${asset.url}`;
  if (snapshot) {
    const directory = `artifacts/model-remesh/before/${asset.set}`;
    await mkdir(directory, { recursive: true });
    await copyFile(path, `${directory}/${asset.id}.glb`, constants.COPYFILE_EXCL).catch((error) => {
      if (error.code !== 'EEXIST') throw error;
    });
  }
  const bytes = await readFile(
    snapshot ? `artifacts/model-remesh/before/${asset.set}/${asset.id}.glb` : path,
  );
  const json = JSON.parse(bytes.toString('utf8', 20, 20 + bytes.readUInt32LE(12)));
  let triangles = 0,
    vertices = 0,
    draws = 0;
  function visit(index) {
    const node = json.nodes[index];
    if (node.mesh !== undefined)
      for (const primitive of json.meshes[node.mesh].primitives) {
        const count = json.accessors[primitive.attributes.POSITION].count;
        vertices += count;
        triangles += (primitive.indices === undefined ? count : json.accessors[primitive.indices].count) / 3;
        draws++;
      }
    for (const child of node.children ?? []) visit(child);
  }
  for (const root of json.scenes[json.scene ?? 0].nodes) visit(root);
  assets.push({
    set: asset.set,
    id: asset.id,
    bytes: bytes.length,
    triangles,
    vertices,
    draws,
    clips: json.animations?.length ?? 0,
  });
}
const sets = Object.values(Object.groupBy(assets, (a) => a.set)).map((models) => ({
  set: models[0].set,
  models: models.length,
  triangles: models.reduce((n, a) => n + a.triangles, 0),
  vertices: models.reduce((n, a) => n + a.vertices, 0),
  bytes: models.reduce((n, a) => n + a.bytes, 0),
  heaviest: [...models]
    .sort((a, b) => b.triangles - a.triangles)
    .slice(0, 3)
    .map(({ id, triangles }) => ({ id, triangles })),
}));
await mkdir('artifacts/model-remesh', { recursive: true });
await writeFile(
  `artifacts/model-remesh/${snapshot ? 'before' : 'after'}.json`,
  JSON.stringify({ sets, assets }, null, 2),
);
console.log(JSON.stringify({ sets, triangles: assets.reduce((n, a) => n + a.triangles, 0) }, null, 2));
if (!snapshot) {
  const before = await readFile('artifacts/model-remesh/before.json', 'utf8')
    .then(JSON.parse)
    .catch((error) => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
  if (before) {
    const format = (n) => n.toLocaleString('de-DE');
    const decrease = (old, current) => `${((1 - current / old) * 100).toFixed(2).replace('.', ',')} %`;
    const total = (items, key) => items.reduce((n, item) => n + item[key], 0);
    const rows = sets.map((set) => {
      const old = before.sets.find((item) => item.set === set.set);
      return `| ${set.set.toUpperCase()} | ${format(old.triangles)} | ${format(set.triangles)} | ${decrease(old.triangles, set.triangles)} |`;
    });
    const oldTriangles = total(before.assets, 'triangles');
    const newTriangles = total(assets, 'triangles');
    await writeFile(
      'artifacts/model-remesh/RESULTS.md',
      [
        '# Blender-Remesh: gemessener Modellbestand',
        '',
        `${assets.length} Modelle: **${format(oldTriangles)} → ${format(newTriangles)} Dreiecke (${decrease(oldTriangles, newTriangles)} weniger)**.`,
        '',
        '| Shipset | Vorher | Nachher | Reduktion |',
        '|---|---:|---:|---:|',
        ...rows,
        '',
        `GLB-Gesamtgröße: ${format(total(before.assets, 'bytes'))} → ${format(total(assets, 'bytes'))} Bytes.`,
        `Animationsbestand: ${total(before.assets, 'clips')} → ${total(assets, 'clips')} Clips.`,
        '',
        'Gezählt werden alle Dreiecke der Standardszene eines Modells, einschließlich wiederholter Module. Die Gesamtsumme beschreibt den vollständigen Katalog, keine einzelne Spielsituation.',
        '',
        'Blender-Sichtvergleiche und Einzelprüfungen stehen in den sechs Set-Verzeichnissen. Der zentrale Finalizer prüft die unveränderten Nodes und dekodierten Animationssamples sowie Normalen, Indizes, eingebettete PNGs und UVs.',
        '',
        'Der Vite-Vergleich unter `/artifacts/model-remesh/compare.html` verwendet die tatsächliche ModelLibrary und ModelSurfaces des Spiels für vorher/nachher. Er bietet Drahtgitter, vier Ansichten und synchrone Animationsclips.',
        '',
      ].join('\n'),
    );
  }
}
