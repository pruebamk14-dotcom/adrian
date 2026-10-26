#!/usr/bin/env node
/*
 * Descarga las fotos de la página de Facebook de la iglesia a assets/img/fb/
 * y genera assets/img/fb/gallery.json, que la galería del sitio carga sola.
 *
 * Requisitos: Node 18+ y un token de acceso de la PÁGINA (lo obtiene un
 * administrador de la página; ver README → "Fotos automáticas de Facebook").
 *
 * Uso:
 *   FB_TOKEN="EAAG..." node tools/facebook-fotos.mjs [pagina] [cantidad]
 *   FB_TOKEN="EAAG..." node tools/facebook-fotos.mjs vidaencristotexas 24
 *
 * El token NO se guarda en ningún archivo: solo se usa mientras corre el script.
 */
import { mkdir, writeFile, readdir, unlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const token = process.env.FB_TOKEN;
const page = process.argv[2] || "vidaencristotexas";
const limit = Math.min(Number(process.argv[3]) || 24, 100);
const API = "https://graph.facebook.com/v21.0";

if (!token) {
  console.error("Falta el token. Ejemplo:\n  FB_TOKEN=\"EAAG...\" node tools/facebook-fotos.mjs");
  process.exit(1);
}

const outDir = join(dirname(fileURLToPath(import.meta.url)), "..", "assets", "img", "fb");

const graph = async (url) => {
  const r = await fetch(url);
  const j = await r.json();
  if (j.error) throw new Error(`Facebook respondió: ${j.error.message}`);
  return j;
};

const photos = [];
let next = `${API}/${encodeURIComponent(page)}/photos?type=uploaded&fields=id,name,images,created_time,link&limit=${Math.min(limit, 50)}&access_token=${encodeURIComponent(token)}`;
while (next && photos.length < limit) {
  const j = await graph(next);
  photos.push(...(j.data || []));
  next = j.paging?.next;
}
if (!photos.length) { console.log("La página no devolvió fotos."); process.exit(0); }

await mkdir(outDir, { recursive: true });
for (const f of await readdir(outDir)) if (f.endsWith(".jpg") || f === "gallery.json") await unlink(join(outDir, f));

const gallery = [];
for (const p of photos.slice(0, limit)) {
  // images viene ordenado de mayor a menor; usamos la primera ≤ 1600px de ancho
  const img = (p.images || []).find(i => i.width <= 1600) || p.images?.[0];
  if (!img) continue;
  const file = `${p.id}.jpg`;
  const r = await fetch(img.source);
  if (!r.ok) { console.warn(`No se pudo bajar ${p.id}`); continue; }
  await writeFile(join(outDir, file), Buffer.from(await r.arrayBuffer()));
  const caption = (p.name || "").split("\n")[0].trim().slice(0, 80) || "Vida en Cristo";
  gallery.push({ src: `assets/img/fb/${file}`, caption, link: p.link, date: p.created_time });
  process.stdout.write(`✓ ${file}\n`);
}

await writeFile(join(outDir, "gallery.json"), JSON.stringify(gallery, null, 2));
console.log(`\nListo: ${gallery.length} fotos en assets/img/fb/ y gallery.json actualizado.`);
