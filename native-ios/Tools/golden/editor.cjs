// Loads the original editor's JavaScript core (reference/Onyx_Web_Editor.html) so a generator can run the
// ORIGINAL code and write golden vectors that the Swift port is tested against byte for byte.
const fs = require("fs"), os = require("os"), path = require("path");
const ROOT = path.resolve(__dirname, "..", "..");
function loadEditor() {
  const html = fs.readFileSync(path.join(ROOT, "reference", "Onyx_Web_Editor.html"), "utf8");
  const m = /<script>([\s\S]*?)<\/script>/.exec(html);
  if (!m) throw new Error("no script in the editor html");
  const tmp = path.join(os.tmpdir(), "onyx_editor_core.cjs");
  fs.writeFileSync(tmp, m[1]);
  return require(tmp);      // the page ends with `if (typeof module !== "undefined") module.exports = {...}`; its DOM half is skipped (no document)
}
function rng(seed) {        // mulberry32: the same sequence on every run
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const hex = (a) => Array.from(a, (b) => (b & 0xFF).toString(16).padStart(2, "0")).join("");
function writeFixture(name, obj) {
  const dir = path.join(ROOT, "Packages", "OnyxKit", "Tests", "OnyxKitTests", "Fixtures");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name + ".json"), JSON.stringify(obj));
  console.log("wrote", name + ".json", fs.statSync(path.join(dir, name + ".json")).size, "bytes");
}
module.exports = { loadEditor, rng, hex, writeFixture, ROOT };
