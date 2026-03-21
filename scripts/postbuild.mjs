import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const roots = [
  process.env.ELECTROBUN_BUILD_DIR,
  process.env.ELECTROBUN_ARTIFACT_DIR,
  process.argv[2],
  "build",
  "dist",
].filter((value) => typeof value === "string" && value.length > 0);

async function findInfoPlists(rootDir) {
  const results = [];

  async function walk(dir) {
    let entries = [];
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      const fullPath = join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (entry.isFile() && entry.name === "Info.plist" && fullPath.includes(".app/Contents/")) {
        results.push(fullPath);
      }
    }
  }

  await walk(rootDir);
  return results;
}

async function patchInfoPlist(path) {
  const original = await readFile(path, "utf8");
  if (original.includes("<key>LSUIElement</key>")) {
    console.log(`[postbuild] already patched: ${path}`);
    return;
  }

  const patched = original.replace(
    /<\/dict>/,
    "  <key>LSUIElement</key>\n  <true/>\n</dict>",
  );

  if (patched === original) {
    console.warn(`[postbuild] no <dict> tag found in ${path}`);
    return;
  }

  await writeFile(path, patched, "utf8");
  console.log(`[postbuild] patched ${path}`);
}

const seen = new Set();
const plists = [];

for (const rootDir of roots) {
  for (const plist of await findInfoPlists(rootDir)) {
    if (seen.has(plist)) {
      continue;
    }
    seen.add(plist);
    plists.push(plist);
  }
}

if (plists.length === 0) {
  console.log(`[postbuild] no Info.plist files found under known build roots`);
} else {
  for (const plist of plists) {
    await patchInfoPlist(plist);
  }
}
