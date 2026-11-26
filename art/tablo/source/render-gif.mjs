import { closeSync, existsSync, openSync, readFileSync, readdirSync, renameSync, writeFileSync, writeSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = dirname(fileURLToPath(import.meta.url));
const project = dirname(source);
const template = readFileSync(join(project, 'FastRevers-Tablo-FR.svg'), 'utf8');
const settings = JSON.parse(readFileSync(join(source, 'animation.json'), 'utf8'));
const { captions, size, holdMs, flipMs, staggerMs, frameMs } = settings;
if (!Array.isArray(captions) || captions.length < 2 || captions.some(pair => !/^[A-Z]{2}$/.test(pair))) {
  throw Error('Укажите как минимум две пары латинских букв A–Z в animation.json.');
}
if (!Number.isInteger(size) || size < 32 || size > 1254 ||
    [holdMs, flipMs, frameMs].some(v => !Number.isFinite(v) || v <= 0) ||
    !Number.isFinite(staggerMs) || staggerMs < 0 || frameMs < 20) {
  throw Error('Проверьте размер и интервалы времени в animation.json.');
}

const cells = [
  { left: 112, right: 600, top: 407, bottom: 898, hinge: 655 },
  { left: 646, right: 1136, top: 407, bottom: 898, hinge: 655 }
];
const scale = size / 1254;
const [step, work, outputPath] = process.argv.slice(2);

function xml(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

function prepareCaption(pair) {
  // The desktop renderer loads the matching TTF supplied beside this script.
  let svg = template.replace(/<style\b[^>]*>\s*@font-face[\s\S]*?<\/style>/, '');
  for (const [index, side] of ['left', 'right'].entries()) {
    const matcher = new RegExp('(<text\\b[^>]*\\bid="text-' + side + '"[^>]*>)[\\s\\S]*?(</text>)');
    if (!matcher.test(svg)) throw Error('В SVG отсутствует text-' + side);
    svg = svg.replace(matcher, '$1' + pair[index] + '$2');
  }
  const svgPath = join(work, pair + '.svg');
  writeFileSync(svgPath, svg);
}

function roundedPanel(x, y, cell) {
  const r = 35;
  const dx = Math.max(cell.left + r - x, 0, x - cell.right + r);
  const dy = Math.max(cell.top + r - y, 0, y - cell.bottom + r);
  return dx * dx + dy * dy < r * r;
}

function drawCell(frame, before, after, cell, elapsed, side) {
  const t = Math.max(0, Math.min(1, elapsed / flipMs));
  const angle = Math.PI * t * t * (3 - 2 * t);
  const cosine = Math.cos(angle);
  const sine = Math.sin(angle);
  const upper = cosine > 0;
  const halfHeight = upper ? cell.hinge - cell.top : cell.bottom - cell.hinge;
  const focal = 2950;
  const lip = halfHeight * cosine / (1 - halfHeight * sine / focal);
  const center = (cell.left + cell.right) / 2;
  const minX = Math.floor((cell.left - 28) * scale);
  const maxX = Math.ceil((cell.right + 28) * scale);
  const movingFace = upper ? before : after;

  for (let py = Math.floor(cell.top * scale); py < Math.ceil(cell.bottom * scale); ++py) {
    const y = (py + 0.5) / scale;
    const dy = y - cell.hinge;
    // Inverse pinhole projection of the hinged leaf onto its source texture.
    const sy = Math.abs(cosine) > 0.002 && dy * cosine < 0
      ? Math.abs(dy) / (Math.abs(cosine) + Math.abs(dy) * sine / focal) : Infinity;
    const widthScale = 1 - sy * sine / focal;
    const fromY = cell.hinge + (upper ? -sy : sy);
    const bg = t === 0 ? before : (t === 1 || dy < 0 ? after : before);
    for (let px = minX; px < maxX; ++px) {
      const x = (px + 0.5) / scale;
      const p = 4 * (py * size + px);
      // Use each complete face at rest. Their surrounding hardware is identical.
      frame[p] = bg[p]; frame[p+1] = bg[p+1]; frame[p+2] = bg[p+2];
      if (t === 0 || t === 1 || !roundedPanel(x, y, cell)) continue;
      const pinInset = side === 0 ? 27 : 26;
      if (Math.abs(dy) < 49 && (x < cell.left + pinInset || x > cell.right - pinInset)) continue;
      const fromX = center + (x - center) * widthScale;
      if (!(sy <= halfHeight && roundedPanel(fromX, fromY, cell))) {
        // Soft shadow from the free edge, projected onto the fixed faces.
        const underEdge = dy + lip;
        const strength = underEdge > 0 ? Math.exp(-underEdge / 17) : Math.exp(underEdge / 8);
        const shade = 1 - 0.37 * sine * strength;
        for (let c = 0; c < 3; ++c) frame[p+c] = bg[p+c] * shade;
        continue;
      }
      const ix = fromX * scale - 0.5, iy = fromY * scale - 0.5;
      const bx = Math.floor(ix), by = Math.floor(iy);
      const fx = ix - bx, fy = iy - by;
      const sample = 4 * (by * size + bx);
      const nearEdge = (halfHeight - sy) * Math.abs(cosine);
      const bevel = nearEdge < 3.5 ? 10 * sine * (1 - nearEdge / 3.5) : 0;
      const light = 1 - (upper ? 0.22 : 0.38) * sine;
      for (let c = 0; c < 3; ++c) {
        const a = sample + c, b = a + size * 4;
        const top = movingFace[a] * (1-fx) + movingFace[a+4] * fx;
        const bottom = movingFace[b] * (1-fx) + movingFace[b+4] * fx;
        frame[p+c] = Math.min(255, ((1-fy)*top + fy*bottom)*light + bevel);
      }
    }
  }
}

// GIF delays are stored in hundredths of a second in each graphics control extension.
// Assign the holds after palette encoding, without repeating hundreds of identical frames.
function setDelays(gif, delays) {
  let pos = 13, frame = 0;
  if (gif[10] & 128) pos += 3 * (1 << ((gif[10] & 7) + 1));
  function blocks() {
    while (gif[pos] > 0) pos += gif[pos] + 1;
    ++pos;
  }
  while (pos < gif.length && gif[pos] !== 0x3b) {
    const marker = gif[pos++];
    if (marker === 0x21) {
      const label = gif[pos++];
      if (label === 0xf9) gif.writeUInt16LE(Math.max(2, Math.round(delays[frame] / 10)), pos + 2);
      blocks();
    } else if (marker === 0x2c) {
      const flags = gif[pos+8];
      pos += 9;
      if (flags & 128) pos += 3 * (1 << ((flags & 7) + 1));
      ++pos;
      blocks();
      ++frame;
    } else throw Error('Некорректный блок GIF.');
  }
  if (frame !== delays.length) throw Error('Число кадров в GIF не совпадает с монтажом.');
  return gif;
}

if (step === 'prepare') {
  const fonts = [source, join(source, 'fonts')].filter(p => existsSync(p));
  const bundledFonts = fonts.filter(p => readdirSync(p).some(f => /\.(ttf|otf)$/i.test(f)));
  if (process.platform !== 'win32' && bundledFonts.length) {
    const fontConfig = join(work, 'fonts.conf');
    writeFileSync(fontConfig, '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig>' +
      bundledFonts.map(p => '<dir>' + xml(p) + '</dir>').join('') +
      '<include ignore_missing="yes">/etc/fonts/fonts.conf</include><cachedir>' + xml(work) + '</cachedir></fontconfig>');
  }
  const pairs = [...new Set(captions)];
  pairs.forEach(prepareCaption);
  writeFileSync(join(work, 'pairs.txt'), pairs.join('\n') + '\n');
  writeFileSync(join(work, 'size.txt'), String(size));
} else if (step === 'frames') {
  const states = new Map([...new Set(captions)].map(pair => [pair, readFileSync(join(work, pair + '.rgba'))]));
  const rawPath = join(work, 'frames.rgba');
  const fd = openSync(rawPath, 'w');
  const delays = [];
  function add(frame, delay) {
    writeSync(fd, frame);
    delays.push(delay);
  }
  try {
    for (let i=0; i<captions.length; ++i) {
      const before = states.get(captions[i]), after = states.get(captions[(i+1) % captions.length]);
      add(before, holdMs);
      for (let ms=frameMs; ms<flipMs + staggerMs; ms+=frameMs) {
        const frame = Buffer.from(before);
        cells.forEach((cell, side) => drawCell(frame, before, after, cell, ms - side * staggerMs, side));
        add(frame, frameMs);
      }
    }
  } finally { closeSync(fd); }
  writeFileSync(join(work, 'delays.json'), JSON.stringify(delays));
} else if (step === 'finish') {
  const delays = JSON.parse(readFileSync(join(work, 'delays.json'), 'utf8'));
  const target = resolve(outputPath);
  const output = target + '.tmp-' + process.pid;
  writeFileSync(output, setDelays(readFileSync(join(work, 'animation.gif')), delays));
  renameSync(output, target);
  console.log(target + ' — ' + delays.length + ' кадров, ' + delays.reduce((a,b)=>a+b,0) / 1000 + ' с');
} else throw Error('Запустите сборку через render-gif.sh.');
