import { mkdir, writeFile } from "node:fs/promises";
import { inflateRawSync } from "node:zlib";
import { execFileSync } from "node:child_process";
import path from "node:path";

const archiveUrl = "https://godot-releases.nbg1.your-objectstorage.com/4.7-stable/Godot_v4.7-stable_export_templates.tpz";
const outputDir = process.argv[2];
const wanted = [
  "windows_release_x86_64.exe",
  "windows_release_x86_64_console.exe",
  "icudt_godot.dat",
];

if (!outputDir) {
  throw new Error("Usage: node fetch_godot_windows_templates.mjs <output-directory>");
}

async function rangeBytes(start, end) {
  const expected = end - start + 1;
  const bytes = execFileSync("curl.exe", [
    "-sS", "-L", "--fail", "--retry", "5", "--retry-all-errors",
    "--range", `${start}-${end}`, archiveUrl,
  ], { maxBuffer: Math.max(expected + 1024 * 1024, 8 * 1024 * 1024) });
  if (bytes.length !== expected) {
    throw new Error(`Mirror returned ${bytes.length} bytes for range ${start}-${end}; expected ${expected}`);
  }
  return bytes;
}

const headers = execFileSync("curl.exe", [
  "-sS", "-I", "-L", "--retry", "8", "--retry-all-errors", "--retry-delay", "2", archiveUrl,
], {
  encoding: "utf8",
  maxBuffer: 1024 * 1024,
});
const contentLengths = [...headers.matchAll(/^content-length:\s*(\d+)\s*$/gim)];
const archiveSize = Number(contentLengths.at(-1)?.[1]);
if (!Number.isSafeInteger(archiveSize) || archiveSize <= 0) {
  throw new Error("Template archive did not provide a valid content length");
}

const tailStart = Math.max(0, archiveSize - 0x10000);
const tail = await rangeBytes(tailStart, archiveSize - 1);
let eocd = -1;
for (let index = tail.length - 22; index >= 0; index--) {
  if (tail.readUInt32LE(index) === 0x06054b50) {
    eocd = index;
    break;
  }
}
if (eocd < 0) {
  throw new Error("ZIP end-of-central-directory record was not found");
}

const totalEntries = tail.readUInt16LE(eocd + 10);
const directoryOffset = tail.readUInt32LE(eocd + 16);
let cursor = directoryOffset - tailStart;
const entries = new Map();
for (let index = 0; index < totalEntries; index++) {
  if (tail.readUInt32LE(cursor) !== 0x02014b50) break;
  const method = tail.readUInt16LE(cursor + 10);
  const compressedSize = tail.readUInt32LE(cursor + 20);
  const uncompressedSize = tail.readUInt32LE(cursor + 24);
  const nameLength = tail.readUInt16LE(cursor + 28);
  const extraLength = tail.readUInt16LE(cursor + 30);
  const commentLength = tail.readUInt16LE(cursor + 32);
  const localOffset = tail.readUInt32LE(cursor + 42);
  const name = tail.subarray(cursor + 46, cursor + 46 + nameLength).toString("utf8");
  entries.set(name, { method, compressedSize, uncompressedSize, localOffset });
  cursor += 46 + nameLength + extraLength + commentLength;
}

await mkdir(outputDir, { recursive: true });
for (const filename of wanted) {
  const entry = entries.get(`templates/${filename}`);
  if (!entry) throw new Error(`Template not found in archive: ${filename}`);
  const localHeader = await rangeBytes(entry.localOffset, entry.localOffset + 29);
  if (localHeader.readUInt32LE(0) !== 0x04034b50) {
    throw new Error(`Invalid local ZIP header for ${filename}`);
  }
  const localNameLength = localHeader.readUInt16LE(26);
  const localExtraLength = localHeader.readUInt16LE(28);
  const dataStart = entry.localOffset + 30 + localNameLength + localExtraLength;
  const compressed = await rangeBytes(dataStart, dataStart + entry.compressedSize - 1);
  const extracted = entry.method === 0 ? compressed : entry.method === 8 ? inflateRawSync(compressed) : null;
  if (!extracted || extracted.length !== entry.uncompressedSize) {
    throw new Error(`Failed to extract ${filename}`);
  }
  const outputPath = path.join(outputDir, filename);
  await writeFile(outputPath, extracted);
  process.stdout.write(`Installed ${filename} (${extracted.length} bytes)\n`);
}
