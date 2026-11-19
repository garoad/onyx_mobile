// Golden vectors for Files/ (NAM, cabinet WAV/raw, preset bank JSON and .abkx), made by running the ORIGINAL editor JavaScript.
// node Tools/golden/gen_files.cjs   ->   Packages/OnyxKit/Tests/OnyxKitTests/Fixtures/files.json
const crypto = require("crypto");
const { loadEditor, rng, hex, writeFixture } = require("./editor.cjs");
const E = loadEditor();
const sha = (u8) => crypto.createHash("sha256").update(Buffer.from(u8)).digest("hex");
const R = rng(0x0A11CE);
const ri = (n) => Math.floor(R() * n);
const pick = (a) => a[ri(a.length)];
const utf8 = (s) => new TextEncoder().encode(s);
const MAXHEX = 4200;                  // outputs up to this many bytes are stored in full, bigger ones as length + SHA-256 + first 64 bytes

function outBytes(u8) {
  if (!u8) return {};
  return u8.length <= MAXHEX ? { bytesHex: hex(u8) } : { bytesLen: u8.length, bytesSha: sha(u8), bytesHead: hex(u8.slice(0, 64)) };
}
function run(fn) { try { return fn(); } catch (e) { return { threw: String(e.message) }; } }

// ---------------------------------------------------------------- NAM
function weights(n, mode) {
  const w = [];
  for (let i = 0; i < n; i++) {
    if (mode === "cheap") w.push((i % 7 - 3) / 4);
    else if (mode === "round") w.push(Math.round((R() - 0.5) * 2e5) / 1e5);
    else w.push((R() - 0.5) * Math.exp((R() - 0.5) * 8));          // full-precision doubles: Float32 rounding matters
  }
  return w;
}
function wavenet(w, extra) { return Object.assign({ version: "0.5.4", architecture: "WaveNet", config: { head_scale: 0.8, layers: [] }, weights: w }, extra || {}); }
function container(subs, extra) { return Object.assign({ version: "0.6.0", architecture: "SlimmableContainer", config: { submodels: subs } }, extra || {}); }
const lite = (w, o) => Object.assign({ max_value: 1.0, model: wavenet(w) }, o || {});
const namCases = [];
function addNam(id, filename, text, bytes) {
  const input = bytes || utf8(text), r = run(() => E.stripNam(input, filename));
  const c = { id, filename, input: hex(input) };
  if (text !== undefined && text.length > 400 && !bytes) {      // the two shared weight lists are stored as tokens
    delete c.input;
    c.text = text.split(JSON.stringify(W1870)).join("$W1870").split(JSON.stringify(W1871)).join("$W1871");
  }
  c.out = r.threw ? { threw: r.threw } : { error: r.error, how: r.how, name: r.name, makeup_db: r.makeup_db, cab: r.cab, ...outBytes(r.bytes) };
  namCases.push(c);
}
const W1870 = weights(1870, "cheap"), W1871 = weights(1871, "cheap");
addNam("lite1870-meta", "Fender Deluxe.nam", JSON.stringify(container([{ model: wavenet(weights(5, "cheap")) }, lite(weights(1870, "round"), {})].map((s, i) => { if (i === 1) s.model.metadata = { name: "Deluxe Reverb", gear_type: "amp", loudness: -18.3, input_level_dbu: 12.5 }; if (i === 1) s.model.config.head_scale = 0.7; return s; }))));
addNam("lite1870-full-precision-1", "x.nam", JSON.stringify(container([lite(weights(1870, "full"))], { metadata: { name: "FullPrec A", loudness: -21.123456789, input_level_dbu: 9.87654321 } })));
addNam("lite1870-full-precision-2", "y.nam", JSON.stringify(wavenet(weights(1870, "full"), { metadata: { name: "FullPrec B CAB", loudness: -12.7777, input_level: 3.1415926 } })));
addNam("lite1871-no-head", "y.nam", JSON.stringify(container([lite(weights(1871, "full"))])));
addNam("lite1871-config-missing", "z.nam", JSON.stringify(container([{ model: { architecture: "WaveNet", weights: W1871 } }])));
addNam("plain-wavenet-1870", "Plain Amp.nam", JSON.stringify(wavenet(W1870, { metadata: { gear_model: "Gear Model Name" } })));
addNam("plain-wavenet-1871", "Plain Amp.nam", JSON.stringify(wavenet(W1871)));
addNam("bom-and-whitespace", "bom.nam", "﻿ \n\t" + JSON.stringify(wavenet(W1870, { metadata: { name: "BOM test" } })));
addNam("bom-bytes", "bombytes.nam", undefined, Uint8Array.from([0xEF, 0xBB, 0xBF, ...utf8(JSON.stringify(wavenet(W1870)))]));
addNam("no-lite", "nolite.nam", JSON.stringify(container([{ model: wavenet(weights(12146, "cheap").slice(0, 300)) }])));
addNam("container-no-config", "c.nam", JSON.stringify({ architecture: "SlimmableContainer" }));
addNam("wrong-architecture", "w.nam", JSON.stringify({ architecture: "LSTM", weights: W1870 }));
addNam("wavenet-wrong-count", "w.nam", JSON.stringify(wavenet(weights(1869, "cheap"))));
addNam("empty-object", "e.nam", "{}");
addNam("bad-json", "bad.nam", "{ not json");
addNam("trailing-garbage", "bad.nam", JSON.stringify(wavenet(W1870)) + " x");
addNam("weights-with-null-and-strings", "ws.nam", JSON.stringify(wavenet(W1870.map((v, i) => (i === 3 ? null : i === 4 ? "0.25" : i === 5 ? true : v)))));
addNam("weights-not-a-number", "ws.nam", JSON.stringify(wavenet(W1870.map((v, i) => (i === 3 ? "abc" : v)))));
addNam("weights-infinity", "ws.nam", JSON.stringify(wavenet(W1870)).replace("0.75", "1e999"));
addNam("head-scale-string", "hs.nam", JSON.stringify(wavenet(W1870, { config: { head_scale: "1.5" } })));
addNam("head-scale-null", "hs.nam", JSON.stringify(wavenet(W1870, { config: { head_scale: null } })));
addNam("head-scale-nan-1871", "hs.nam", JSON.stringify(wavenet(W1871, { config: { head_scale: "x" } })));
addNam("head-scale-inf-1871", "hs.nam", JSON.stringify(wavenet(W1871, { config: { head_scale: "Infinity" } })));
addNam("config-false", "hs.nam", JSON.stringify(wavenet(W1871, { config: false })));
addNam("config-false-1870", "hs.nam", JSON.stringify(wavenet(W1870, { config: 0 })));
addNam("config-null-throws", "hs.nam", JSON.stringify(wavenet(W1870, { config: null })));
addNam("config-string", "hs.nam", JSON.stringify(wavenet(W1870, { config: "abc" })));
addNam("name-from-filename", "My File.nam", JSON.stringify(wavenet(W1870)));
addNam("name-empty-filename", "", JSON.stringify(wavenet(W1870)));
addNam("name-number", "n.nam", JSON.stringify(wavenet(W1870, { metadata: { name: 12.50 } })));
addNam("name-object", "n.nam", JSON.stringify(wavenet(W1870, { metadata: { name: { a: 1 } } })));
addNam("name-unicode", "n.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "Röhre \u{1F3B8} ŝ" } })));
addNam("meta-in-model-and-data", "m.nam", JSON.stringify(container([lite(W1870)].map((s) => { s.model.metadata = { name: "inner", loudness: -10 }; return s; }), { metadata: { name: "outer", loudness: -30 } })));
addNam("meta-outer-only", "m.nam", JSON.stringify(container([lite(W1870)], { metadata: { name: "outer", loudness: -30, gear_type: "Preamp CAB sim" } })));
addNam("meta-is-string", "m.nam", JSON.stringify(wavenet(W1870, { metadata: "text" })));
// cabinet detection: name, gear_type and filename
const cabNames = ["Marshall CAB", "Fender cab free", "No Cab Amp", "cab-free", "without cab", "w/o cab", "CABLESS", "Cab Less", "amp only", "AMP_ONLY", "DI Out", "direct-out", "Full Rig", "Full_Rig 2", "fullrig", "FR Plexi", "fr_plexi", "Afr", "SM57 close", "SM 58", "SM59", "sm570", "MD421", "md 421", "E609", "e 609", "R121 ribbon", "U87 room", "u 87", "mic'd up", "miced", "mic", "microphone", "Mickey", "dynamic", "Tweed", "Plain amp", "cabinet", "ABCAB", "e6090", "Ré121"];
cabNames.forEach((nm, i) => addNam("cab-name-" + i, "f.nam", JSON.stringify(wavenet(W1870, { metadata: { name: nm, loudness: -17 } }))));
["Cab sim", "amp", "CAB", "", "cabinet only", "Amp+Cab"].forEach((g, i) => addNam("cab-gear-" + i, "plain.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "x", gear_type: g } }))));
["Marshall_CAB.nam", "amp_cab_free.nam", "SM57.nam", "FR_JCM.nam", "fullrig.nam", "my mic.nam", "x.nam"].forEach((fn, i) => addNam("cab-file-" + i, fn, JSON.stringify(wavenet(W1870, { metadata: { name: "x" } }))));
addNam("cab-gear-number", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "x", gear_type: 5 } })));
// loudness: makeup, clamps, quarter-dB rounding, flags
[[-20, "amp"], [-3, "amp"], [-40, "amp"], [20, "amp"], [-15.5, "amp"], [-15.5, "cab"], [-11.8, "cab"], [-16.3, "amp"], [-15.375, "amp"], [-15.625, "amp"], [-15.125, "cab"], [0, "amp"], [-0.001, "amp"], [-1e9, "cab"], [1e9, "amp"], ["-18", "amp"], [true, "amp"], ["", "amp"], [[], "amp"], [[-12], "amp"], ["abc", "amp"], [null, "amp"], ["Infinity", "amp"], [-27.4, "amp"], [-19.55, "cab"]].forEach(([l, g], i) => addNam("loud-" + i, "f.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "x", gear_type: g, loudness: l } }))));
addNam("loud-output_loudness", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { output_loudness: -22.2 } })));
addNam("loud-loudness_db", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { loudness_db: -9.9 } })));
addNam("loud-nonfinite-then-next", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { loudness: "abc", output_loudness: -14 } })));
addNam("loud-in-data", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "x" }, loudness: -8.5 })));
addNam("loud-in-data-metadata", "f.nam", JSON.stringify(container([lite(W1870)], { metadata: { loudness: -23 } })));
// input level / trim
[12.5, 4, 0, -20, 30, 4.0001, 11.11111111, "7.5", true, "", "abc", null, [3], 100, -100, "Infinity", "-Infinity", 0.00005, 8.8888, -3.3333333].forEach((v, i) => addNam("lvl-" + i, "f.nam", JSON.stringify(wavenet(W1870, { metadata: { name: "x", input_level_dbu: v } }))));
["input_level", "input_dBu", "calibration_dBu"].forEach((k) => addNam("lvl-key-" + k, "f.nam", JSON.stringify(wavenet(W1870, { metadata: { [k]: 9.5 } }))));
addNam("lvl-config", "f.nam", JSON.stringify(wavenet(W1870, { config: { head_scale: 0.9, input_level_dbu: 6.25 } })));
addNam("lvl-data-top", "f.nam", JSON.stringify(wavenet(W1870, { input_level: 2 })));
addNam("lvl-first-key-wins", "f.nam", JSON.stringify(wavenet(W1870, { metadata: { input_level: 1, input_level_dbu: 10 } })));
// stripNam: the non-JSON containers
const rb = (n) => Uint8Array.from({ length: n }, () => ri(256));
const withHead = (h, n) => { const b = rb(n); b.set(h.map((c) => c.charCodeAt(0)), 0); return b; };
addNam("wave-blob-7504", "a.nam", undefined, withHead(["W", "A", "V", "E"], 7504));
addNam("wave-blob-8192", "a.nam", undefined, withHead(["W", "A", "V", "E"], 8192));
addNam("wave-blob-8193", "a.nam", undefined, withHead(["W", "A", "V", "E"], 8193));
addNam("wave-blob-4", "a.nam", undefined, withHead(["W", "A", "V", "E"], 4));
addNam("struct-3852", "a.namb", undefined, rb(3852));
addNam("struct-4040", "a.namb", undefined, rb(4040));
addNam("struct-3852-starting-with-WAVE", "a.namb", undefined, withHead(["W", "A", "V", "E"], 3852));
addNam("struct-4040-starting-with-brace", "a.namb", undefined, Uint8Array.from([0x7B, ...rb(4039)]));
addNam("container-@M-long", "a.namb", undefined, withHead(["@", "M", "A", "B"], 6204 + 3852));
addNam("container-@M-longer", "a.namb", undefined, withHead(["@", "M", "\0", "\0"], 12000));
addNam("container-@M-short", "a.namb", undefined, withHead(["@", "M", "x", "y"], 5000));
addNam("container-@M-too-short", "a.namb", undefined, withHead(["@", "M", "x", "y"], 3851));
addNam("container-@M-2-bytes", "a.namb", undefined, Uint8Array.from([0x40, 0x4D]));
addNam("container-NAM0-long", "a.namb", undefined, withHead(["N", "A", "M", "\0"], 10056));
addNam("container-NAM0-short", "a.namb", undefined, withHead(["N", "A", "M", "\0"], 4000));
addNam("container-NAM-no-nul", "a.namb", undefined, withHead(["N", "A", "M", "x"], 10056));
addNam("unknown", "a.bin", undefined, rb(1000));
addNam("empty", "a.bin", undefined, new Uint8Array(0));
addNam("one-byte", "a.bin", undefined, Uint8Array.from([0x7B]));
addNam("whitespace-only", "a.bin", undefined, utf8("   \n\r\t"));
addNam("ws-then-brace-bad-json", "a.bin", undefined, utf8(" \n {"));

// number formatting / parsing helpers the Swift side re-implements
const numCases = [0, -0, 1, -1, 0.5, 0.1, 1.5, 100, 1e21, 1e-7, 1.5e-7, 123456789012345680000, 1e100, 2.5e-10, 0.000001, 0.0000001, 4.0001, 7.5, -12.25, 3.14159265358979, 1 / 3, 5e-324, 1.7976931348623157e308, 0.03125, 1e20, 123456.789, 0.1 + 0.2, 25, 0.0313, 1.0e-5, 99999999999999990000].map((n) => ({ n, s: String(n) }));
const strCases = ["", " ", "12", " 12 ", "1e3", "-1.5e-3", ".5", "5.", "+.5", "0x1F", "0b101", "0o17", "0X", "Infinity", "-Infinity", "+Infinity", "infinity", "1_000", "1e", "e5", "abc", "12abc", "--1", "1 2", "\n7\t", "NaN", ".", "-", "+1", "1e+3", "0x", "00012", "-0", "1.5.2", " 5"].map((s) => { const n = Number(s); return { s, n: Number.isNaN(n) ? "NaN" : String(n) }; });
const fixedCases = [0.03125, 0.09375, 0.15625, 1.00005, 0.00005, 0.00015, 2.5, 0.99995, 12.34565, 1e-9, 1234.56785, 0.3125, 5, 1e21, 0.0001, 0.00004999, 7.00003125, -0.03125, 31.62277660168379, 0.0316227766, 12.589254117941675].map((x) => ({ x, r: Number(x.toFixed(4)) }));
const roundCases = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 0.49999999999999994, 2.4, -2.6, 1e15 + 0.5, 4503599627370497.5].map((x) => ({ x, r: Math.round(x) }));

// ---------------------------------------------------------------- cabinet
function wavBuild(o) {
  const code = o.code ?? 1, bits = o.bits ?? 16, ch = o.ch ?? 1, rate = o.rate ?? 44100, s = o.samples, bps = bits >> 3;
  const body = Buffer.alloc(s.length * ch * bps);
  s.forEach((v, i) => {
    for (let c = 0; c < ch; c++) {
      const x = c === 0 ? v : v * 0.37 + 0.11, off = (i * ch + c) * bps;
      if (bits === 16 && (code === 3 || o.subcode === 3)) body.writeInt16LE(1234, off);
      else if (code === 3 || (o.extensible && o.subcode === 3)) { if (bits === 32) body.writeFloatLE(x, off); else body.writeDoubleLE(x, off); }
      else if (bits === 16) body.writeInt16LE(Math.round(Math.max(-1, Math.min(0.99997, x)) * 32768), off);
      else if (bits === 24) body.writeIntLE(Math.round(Math.max(-1, Math.min(0.9999998, x)) * 8388608), off, 3);
      else if (bits === 32) body.writeInt32LE(Math.round(Math.max(-1, Math.min(0.99999999, x)) * 2147483648), off);
      else if (bits === 8) body.writeUInt8(128 + Math.round(Math.max(-1, Math.min(1, x)) * 127), off);
    }
  });
  const fmt = Buffer.alloc(o.extensible ? 40 : 16);
  fmt.writeUInt16LE(o.extensible ? 0xFFFE : code, 0); fmt.writeUInt16LE(ch, 2); fmt.writeUInt32LE(rate, 4); fmt.writeUInt32LE(rate * ch * bps, 8); fmt.writeUInt16LE(ch * bps, 12); fmt.writeUInt16LE(bits, 14);
  if (o.extensible) { fmt.writeUInt16LE(22, 16); fmt.writeUInt16LE(bits, 18); fmt.writeUInt16LE(o.maskLow ?? 1, 20); fmt.writeUInt16LE(o.subcode ?? code, 24); }
  const chunk = (id, b, claim) => { const h = Buffer.alloc(8); h.write(id, 0, "latin1"); h.writeUInt32LE(claim ?? b.length, 4); return Buffer.concat([h, b, b.length & 1 && !o.noPad ? Buffer.alloc(1) : Buffer.alloc(0)]); };
  const parts = [];
  if (!o.fmtAfterData) parts.push(chunk("fmt ", fmt));
  (o.pre || []).forEach(([id, b]) => parts.push(chunk(id, b)));
  if (!o.noData) parts.push(chunk("data", body, o.dataClaim));
  if (o.fmtAfterData) parts.push(chunk("fmt ", fmt));
  let all = Buffer.concat(parts);
  if (o.cut) all = all.slice(0, all.length - o.cut);
  const h = Buffer.alloc(12); h.write("RIFF", 0, "latin1"); h.writeUInt32LE(all.length + 4, 4); h.write(o.wave ?? "WAVE", 8, "latin1");
  return new Uint8Array(Buffer.concat([h, all]));
}
// a measured-looking impulse response: a delay, a decaying noisy burst
function ir(n, delay, amp) {
  const x = new Array(n).fill(0);
  for (let i = delay; i < n; i++) { const t = i - delay; x[i] = (R() * 2 - 1) * Math.exp(-t / (n / 8)) * (t === 0 ? 3 : 1) * (amp ?? 0.5) + (t === 0 ? 0.3 : 0); }
  return x;
}
const cabCases = [];
function addCab(id, bytes) {
  const r = run(() => E.checkCab(bytes)), c = { id, input: hex(bytes) };
  c.out = r.threw ? { threw: r.threw } : { error: r.error, taps: r.taps, peak: r.peak, how: r.how, ...outBytes(r.bytes) };
  cabCases.push(c);
}
const taps = (n, f) => { const b = new Uint8Array(n); const dv = new DataView(b.buffer); for (let i = 0; i < n / 4; i++) dv.setInt32(i * 4, f(i), true); return b; };
addCab("raw-64", taps(64, (i) => ri(1 << 20) - (1 << 19)));
addCab("raw-4096", taps(4096, (i) => ri(1 << 24) - (1 << 23)));
addCab("raw-4100", new Uint8Array(4100).fill(1));
addCab("raw-60", new Uint8Array(60).fill(1));
addCab("raw-63", new Uint8Array(63).fill(1));
addCab("raw-zeros", new Uint8Array(256));
addCab("raw-min-int", taps(64, (i) => (i === 5 ? -2147483648 : 0)));
addCab("raw-neg-peak", taps(128, (i) => (i === 3 ? -262144 : i === 4 ? 1000 : 0)));
addCab("raw-big-peak", taps(128, (i) => (i === 3 ? 2147483647 : 5)));
addCab("raw-empty", new Uint8Array(0));
addCab("raw-short-riff-like", Uint8Array.from([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 5, 6, 7, 8]));
addCab("riff-not-wav-64", (() => { const b = rb(64); b.set([0x52, 0x49, 0x46, 0x46], 0); return b; })());
addCab("riff-13-bytes", (() => { const b = rb(13); b.set([0x52, 0x49, 0x46, 0x46], 0); return b; })());
const sr = [44100, 48000, 96000, 22050, 88200, 32000, 192000, 8000];
for (const [bits, code] of [[16, 1], [24, 1], [32, 1], [32, 3], [64, 3]]) {
  addCab(`wav-${bits}-${code === 3 ? "float" : "pcm"}-44100-1500`, wavBuild({ bits, code, samples: ir(1500, 12) }));
  addCab(`wav-${bits}-${code === 3 ? "float" : "pcm"}-48000-2000-stereo`, wavBuild({ bits, code, ch: 2, rate: 48000, samples: ir(2000, 40) }));
}
for (const rate of sr) addCab(`wav-16-rate-${rate}`, wavBuild({ rate, samples: ir(Math.min(3000, Math.round(rate * 0.04)), 25) }));
addCab("wav-24-96000-longer-than-1024", wavBuild({ bits: 24, rate: 96000, samples: ir(9000, 100) }));
addCab("wav-float32-44100-4000-cut", wavBuild({ bits: 32, code: 3, samples: ir(4000, 70) }));
addCab("wav-16-44100-1024-exact", wavBuild({ samples: ir(1024, 0) }));
addCab("wav-16-44100-1100-leadin-0", wavBuild({ samples: ir(1100, 0) }));
addCab("wav-16-44100-leadin-3", wavBuild({ samples: ir(900, 3) }));
addCab("wav-16-44100-leadin-5", wavBuild({ samples: ir(900, 5) }));
addCab("wav-16-44100-leadin-400", wavBuild({ samples: ir(1600, 400) }));
addCab("wav-24-44100-1300-leadin-200-cut", wavBuild({ bits: 24, samples: ir(1800, 200) }));
addCab("wav-float-silent", wavBuild({ bits: 32, code: 3, samples: new Array(500).fill(0) }));
addCab("wav-16-too-short", wavBuild({ samples: ir(10, 0) }));
addCab("wav-16-exactly-16", wavBuild({ samples: [0.5, 0.4, 0.3, 0.2, 0.1, -0.1, -0.2, -0.3, 0.1, 0.05, 0.01, -0.01, 0.02, -0.02, 0.01, 0.005] }));
addCab("wav-16-15-samples", wavBuild({ samples: [0.5, 0.4, 0.3, 0.2, 0.1, -0.1, -0.2, -0.3, 0.1, 0.05, 0.01, -0.01, 0.02, -0.02, 0.01] }));
addCab("wav-upsample-small", wavBuild({ rate: 22050, samples: ir(18, 0) }));
addCab("wav-downsample-to-tiny", wavBuild({ rate: 192000, samples: ir(60, 0) }));
addCab("wav-negative-peak", wavBuild({ samples: ir(600, 10).map((v, i) => (i === 10 ? -0.9 : v * 0.2)) }));
addCab("wav-8bit", wavBuild({ bits: 8, samples: ir(300, 3) }));
addCab("wav-pcm-64bit", wavBuild({ bits: 64, code: 1, samples: ir(300, 3) }));
addCab("wav-float-16bit", wavBuild({ bits: 16, code: 3, samples: ir(300, 3) }));
addCab("wav-format-2", wavBuild({ code: 2, samples: ir(300, 3) }));
addCab("wav-no-data", wavBuild({ noData: true, samples: ir(300, 3), pre: [["LIST", Buffer.alloc(30, 1)]] }));
addCab("wav-fmt-after-data", wavBuild({ fmtAfterData: true, samples: ir(300, 3) }));
addCab("wav-wrong-wave-tag", wavBuild({ wave: "WAVX", samples: ir(300, 3) }));
addCab("wav-odd-chunk-padded", wavBuild({ samples: ir(800, 8), pre: [["LIST", Buffer.alloc(31, 7)], ["junk", Buffer.alloc(5, 1)]] }));
addCab("wav-odd-chunk-not-padded", wavBuild({ noPad: true, samples: ir(800, 8), pre: [["LIST", Buffer.alloc(31, 7)]] }));
addCab("wav-data-claim-too-big", wavBuild({ samples: ir(800, 8), dataClaim: 1 << 30 }));
addCab("wav-data-claim-small", wavBuild({ samples: ir(800, 8), dataClaim: 400 }));
addCab("wav-data-cut-mid-frame", wavBuild({ samples: ir(800, 8), dataClaim: 1 << 30, cut: 1 }));
addCab("wav-data-cut-stereo-24", wavBuild({ bits: 24, ch: 2, samples: ir(800, 8), dataClaim: 1 << 30, cut: 5 }));
addCab("wav-extensible-mask1-pcm", wavBuild({ extensible: true, maskLow: 1, subcode: 1, samples: ir(700, 5) }));
addCab("wav-extensible-mask3-float", wavBuild({ extensible: true, maskLow: 3, subcode: 3, bits: 32, samples: ir(700, 5) }));
addCab("wav-extensible-mask4-real", wavBuild({ extensible: true, maskLow: 4, subcode: 1, bits: 24, samples: ir(700, 5) }));
addCab("wav-extensible-mask0", wavBuild({ extensible: true, maskLow: 0, subcode: 1, samples: ir(700, 5) }));
addCab("wav-extensible-mask3-float64", wavBuild({ extensible: true, maskLow: 3, subcode: 3, bits: 64, samples: ir(700, 5) }));
addCab("wav-clipped-loud", wavBuild({ bits: 32, code: 3, samples: ir(500, 4).map((v) => v * 40) }));
addCab("wav-float-nan", wavBuild({ bits: 32, code: 3, samples: ir(500, 4).map((v, i) => (i === 100 ? NaN : v)) }));
addCab("wav-float-inf", wavBuild({ bits: 32, code: 3, samples: ir(500, 4).map((v, i) => (i === 100 ? Infinity : v)) }));
addCab("wav-header-only", wavBuild({ samples: [] }));
addCab("wav-44-bytes-exact-data-empty-claim", wavBuild({ samples: [], dataClaim: 0 }));
addCab("wav-44100-dc-offset", wavBuild({ samples: ir(700, 5).map((v) => v * 0.1 + 0.3) }));
addCab("wav-large-resample-96k-24k", wavBuild({ bits: 24, rate: 96000, samples: ir(12000, 300, 0.7) }));

// ---------------------------------------------------------------- preset documents
function randRecordObj(i) {
  const empty = R() < 0.2, name = Array.from({ length: ri(24) }, () => String.fromCharCode(pick([1 + ri(31), 32 + ri(95), 128 + ri(128)])));
  const nm = name.join("").slice(0, 23);
  const params = Array.from({ length: 8 }, () => Array.from({ length: 6 }, () => (R() < 0.1 ? pick([0, 65535, 32767, 32768]) : ri(65536))));
  const o = { slot: i + 1, name: nm, empty, seq: ri(1e9), bpm: 40 + ri(220), genre: ri(8), custom_cab_idx: pick([255, ri(15)]), custom_cab_blend: ri(101), input_trim_db: ri(25) - 12, gate_threshold_pct: ri(101),
    slot_enable_mask: ri(256), slot_order: [0, 1, 2, 3, 4, 5, 6, 7].sort(() => R() - 0.5), amp_model: ri(40), cab_model: ri(35), preset_vol: ri(101), flags: (ri(256) & ~1) | (empty ? 1 : 0),
    slot_type: Array.from({ length: 8 }, () => ri(10)), stomp_map: [ri(8), ri(8), ri(8), ri(8)], params };
  return E.presetToRecord(o);
}
// the two editor-written documents: read from a unit (some slots unreadable) and converted from a bank
function unitDoc(recs) {
  return { format: "pocket-amp-presets", version: 1, record_size: 164, note: "Onyx preset backup read from the unit. Edit names and values freely; 'params' are Q16 (0..65535 = 0..100 %), 'params_pct' is for reading only. Slot order: DYN DRV AMP CAB EQ MOD DLY REV.",
    presets: recs.map((r, i) => (r ? E.recordToPreset(i, r) : { slot: i + 1, unreadable: true })) };
}
const text = (doc) => JSON.stringify(doc, null, 1) + "\n";
const recsOut = (recs) => recs.map((r) => (r ? hex(r) : null));
const recsDigest = (recs) => sha(Buffer.concat(recs.map((r) => (r ? Buffer.concat([Buffer.from([1]), Buffer.from(r)]) : Buffer.from([0])))));

const unitCases = [];
function addUnit(id, recs, full) {
  const doc = unitDoc(recs), t = text(doc);
  unitCases.push({ id, records: recsOut(recs), docSha: sha(utf8(t)), docLen: t.length, ...(full ? { docText: t } : {}) });
}
const baseRecs = Array.from({ length: 80 }, (_, i) => randRecordObj(i));
addUnit("all-valid", baseRecs, true);
addUnit("some-unreadable", baseRecs.map((r, i) => (i % 7 === 3 ? null : r)), false);
addUnit("all-unreadable", new Array(80).fill(null), false);
addUnit("random-2", Array.from({ length: 80 }, (_, i) => (R() < 0.1 ? null : randRecordObj(i))), false);
addUnit("all-empty-flag", Array.from({ length: 80 }, (_, i) => { const r = randRecordObj(i); r[51] |= 1; const dv = new DataView(r.buffer); dv.setUint32(160, E.crc32(r.subarray(0, 160)), true); return r; }), false);
addUnit("fewer-than-80", baseRecs.slice(0, 5), false);

// hand-made / foreign documents, read like the editor reads them
const docCases = [];
function addDoc(id, textOrObj, raw) {
  const t = typeof textOrObj === "string" ? textOrObj : JSON.stringify(textOrObj), c = { id, text: t };
  let doc = null;
  try { doc = JSON.parse(t.replace(/^\uFEFF/, "")); } catch (e) { c.out = { kind: "notjson" }; docCases.push(c); return; }
  try {
    const recs = E.presetsFromDoc(doc);
    c.out = { kind: "ok", records: recsOut(recs), count: doc.presets.filter((p) => !p.empty && !p.unreadable).length, empty: doc.presets.filter((p) => p.empty).length };
    if (t.length > 3000) { c.out.recordsSha = recsDigest(recs); delete c.out.records; }
  } catch (e) { c.out = { kind: e.message === "not a pocket-amp-presets file" ? "notdoc" : e.message.startsWith("slot_order/slot_type") ? "length" : "other" }; }
  docCases.push(c);
}
const entry = (i, over) => Object.assign(E.recordToPreset(i, baseRecs[i]), over || {});
addDoc("editor-written-full", text(unitDoc(baseRecs)));
addDoc("compact-json", JSON.stringify(unitDoc(baseRecs.slice(0, 10))));
addDoc("bom-prefixed", "﻿" + JSON.stringify(unitDoc(baseRecs.slice(0, 3))));
addDoc("not-json", "<html>");
addDoc("empty-text", "");
addDoc("json-null", "null");
addDoc("json-array", "[]");
addDoc("json-number", "5");
addDoc("wrong-format", { format: "pocket-amp-backup", presets: [] });
addDoc("presets-not-array", { format: "pocket-amp-presets", presets: {} });
addDoc("presets-missing", { format: "pocket-amp-presets" });
addDoc("empty-presets", { format: "pocket-amp-presets", presets: [] });
addDoc("version-2-extra-keys", { format: "pocket-amp-presets", version: 2, foo: 1, presets: [entry(0, { extra: "x" })] });
addDoc("slot-out-of-range", { format: "pocket-amp-presets", presets: [entry(0, { slot: 0 }), entry(1, { slot: 81 }), entry(2, { slot: -3 }), entry(3, { slot: 80 }), entry(4, { slot: 1 })] });
addDoc("slot-duplicates-last-wins", { format: "pocket-amp-presets", presets: [entry(0, { slot: 7, name: "first" }), entry(1, { slot: 7, name: "second" })] });
addDoc("slot-fraction-string", { format: "pocket-amp-presets", presets: [entry(0, { slot: 2.9 }), entry(1, { slot: "5" }), entry(2, { slot: "x" }), entry(3, { slot: null }), entry(4, { slot: 4294967297 }), entry(5, { slot: 6.5e9 })] });
addDoc("unreadable-flag", { format: "pocket-amp-presets", presets: [entry(0, { unreadable: true }), { slot: 2, unreadable: true }, entry(2, { unreadable: 0 }), entry(3, { unreadable: "yes" })] });
addDoc("string-numbers", { format: "pocket-amp-presets", presets: [entry(0, { seq: "12345", bpm: "133", genre: "3", input_trim_db: "-5", preset_vol: "88", flags: "0" })] });
addDoc("wrapping-numbers", { format: "pocket-amp-presets", presets: [entry(0, { seq: -1, bpm: 70000, genre: 300, custom_cab_idx: -1, custom_cab_blend: 256.9, input_trim_db: 200, gate_threshold_pct: -0.5, slot_enable_mask: 511, amp_model: 1e10, cab_model: NaN, preset_vol: 1.5e19, flags: 255 })] });
addDoc("float-params", { format: "pocket-amp-presets", presets: [entry(0, { params: baseRecs.length ? Array.from({ length: 8 }, (_, s) => Array.from({ length: 6 }, (_, k) => s * 1000 + k * 0.7 + 65536 * (k % 2))) : [] })] });
addDoc("params-flat-48", { format: "pocket-amp-presets", presets: [entry(0, { params: Array.from({ length: 48 }, (_, i) => i * 100) })] });
addDoc("params-ragged-48", { format: "pocket-amp-presets", presets: [entry(0, { params: [[1, 2, 3], [4, 5, 6, 7, 8, 9, 10, 11], [], [12], ...Array.from({ length: 4 }, (_, i) => Array.from({ length: 6 }, (_, k) => i * 6 + k + 100))].slice(0, 8) })] });
addDoc("params-short", { format: "pocket-amp-presets", presets: [entry(0, { params: [[1, 2, 3]] })] });
addDoc("params-missing", { format: "pocket-amp-presets", presets: [(() => { const e = entry(0); delete e.params; return e; })()] });
addDoc("slot-order-7", { format: "pocket-amp-presets", presets: [entry(0, { slot_order: [0, 1, 2, 3, 4, 5, 6] })] });
addDoc("slot-type-9", { format: "pocket-amp-presets", presets: [entry(0, { slot_type: [0, 1, 2, 3, 4, 5, 6, 7, 8] })] });
addDoc("stomp-3", { format: "pocket-amp-presets", presets: [entry(0, { stomp_map: [1, 2, 3] })] });
addDoc("slot-order-missing", { format: "pocket-amp-presets", presets: [(() => { const e = entry(0); delete e.slot_order; return e; })()] });
addDoc("name-missing", { format: "pocket-amp-presets", presets: [(() => { const e = entry(0); delete e.name; return e; })()] });
addDoc("name-number", { format: "pocket-amp-presets", presets: [entry(0, { name: 42 })] });
addDoc("name-long-unicode", { format: "pocket-amp-presets", presets: [entry(0, { name: "A very long preset name with üŁ€\u{1F3B8} chars" }), entry(1, { name: "ĀǿሴABC" })] });
addDoc("name-empty", { format: "pocket-amp-presets", presets: [entry(0, { name: "" })] });
addDoc("empty-true-flags-wrong", { format: "pocket-amp-presets", presets: [entry(0, { empty: true, flags: 0 }), entry(1, { empty: false, flags: 1 }), entry(2, { empty: 1, flags: 255 }), entry(3, { empty: "no", flags: 254 })] });
addDoc("empty-missing", { format: "pocket-amp-presets", presets: [(() => { const e = entry(0, { flags: 1 }); delete e.empty; return e; })()] });
addDoc("numbers-missing", { format: "pocket-amp-presets", presets: [{ slot: 3, name: "bare", slot_order: [0, 1, 2, 3, 4, 5, 6, 7], slot_type: [0, 0, 0, 0, 0, 0, 0, 0], stomp_map: [0, 0, 0, 0], params: Array.from({ length: 8 }, () => [0, 0, 0, 0, 0, 0]) }] });
addDoc("abkx-style-empty-slot", { format: "pocket-amp-presets", presets: [E.abkxConvert(abkxBank({}), {}).presets[0]] });
addDoc("null-element-throws", { format: "pocket-amp-presets", presets: [null] });
addDoc("string-element", { format: "pocket-amp-presets", presets: ["x"] });
addDoc("array-element", { format: "pocket-amp-presets", presets: [[1, 2]] });

// ---------------------------------------------------------------- .abkx
function abkxBank(o) {
  const b = new Uint8Array(7370), kinds = o.kind || "mixed";
  for (let i = 0; i < 80; i++) {
    const r = b.subarray(i * 92, i * 92 + 92);
    for (let k = 0; k < 92; k++) r[k] = R() < 0.5 ? ri(101) : R() < 0.15 ? ri(256) : 0;
    r[0] = ri(kinds === "wild" ? 256 : 101);
    const order = [0, 1, 2, 3, 4, 5].sort(() => R() - 0.5); order.forEach((c, j) => { r[2 + j] = c; });
    for (let c = 0; c < 6; c++) r[8 + c] = R() < 0.6 ? 1 : (kinds === "wild" ? ri(3) : 0);
    r[0x0E] = pick([0, 1, 2, 3, 4, 0, 1, 2, ri(256)]); r[0x0F] = pick([ri(20), ri(20), ri(40), ri(256)]);
    r[0x10] = pick([0, 1, 2, 3, 4, 5, 6, 0, 1, 2, ri(256)]); r[0x11] = ri(10); r[0x12] = pick([0, 1, 2, 3, 4, 5, 6, 7, ri(256)]); r[0x13] = pick([ri(20), ri(20), 255]);
    for (const base of [0x14, 0x20, 0x2C, 0x38, 0x44, 0x50]) for (let k = 0; k < 6; k++) {
      const v = pick([ri(101), ri(101), ri(101), ri(256), ri(65536), 0, 100, 101]);
      r[base + 2 * k] = v & 255; r[base + 2 * k + 1] = v >> 8;
    }
    if (kinds !== "stock" && R() < (kinds === "ext" ? 0.9 : 0.4)) {
      const dly = ri(5), rev = ri(3), dyn = pick([0, 1, 1, 2]);
      r[1] = 0x80 | (1 << 5) | ((dly + 5 * rev + 15 * dyn) & 0x1F);
      r[0x2A] = ri(101); r[0x2B] = pick([38 + ri(25), ri(256)]); r[0x36] = 50 * pick([0, 1, 1, 2]) + pick([ri(6), ri(50)]); r[0x4E] = 50 * pick([0, 1, 1, 2]) + pick([ri(3), ri(50)]);
      for (const a of [0x37, 0x4F, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B]) r[a] = pick([ri(101), ri(256)]);
    } else r[1] = pick([0, ri(0x80), 0x80 | (ri(4) << 5) & 0x60, 0x80 | (2 << 5), 0x80 | (3 << 5)]) & (R() < 0.5 ? 0x7F : 0xFF);
    if (kinds === "stock") r[1] &= 0x7F;
    if (R() < 0.08) for (let c = 0; c < 6; c++) r[8 + c] = 0, r[1] &= 0x7F;     // an empty slot
  }
  b.set(utf8("PATCHEND"), 7360); b[7368] = ri(256); b[7369] = o.last ?? pick([0, 0x45]);
  return b;
}
const abkxCases = [];
const abkxBanks = {};
function addAbkx(id, bank, opt, full) {
  const c = { id, opt: opt || {} };
  const shared = Object.keys(abkxBanks).find((k) => abkxBanks[k] === bank);
  if (shared) c.bank = shared; else c.input = hex(bank);
  try {
    const doc = E.abkxConvert(bank, opt), t = text(doc), recs = E.presetsFromDoc(doc);
    c.out = { docSha: sha(utf8(t)), docLen: t.length, recordsSha: recsDigest(recs), presets: doc.presets.filter((p) => !p.empty).length, empty: doc.presets.filter((p) => p.empty).length };
    if (full) { c.out.docText = t; c.out.records = recsOut(recs); }
  } catch (e) { c.out = { error: e.message }; }
  abkxCases.push(c);
}
const bankA = abkxBank({ kind: "mixed" }), bankB = abkxBank({ kind: "ext" }), bankC = abkxBank({ kind: "stock" }), bankD = abkxBank({ kind: "wild" });
Object.assign(abkxBanks, { A: bankA, B: bankB, C: bankC, D: bankD });
addAbkx("mixed-default", bankA, {}, true);
addAbkx("mixed-all-options", bankA, { preserveChain: true, copyAmpLevel: true, namePrefix: "Fx", genre: 3 });
for (const [nm, bk] of [["mixed", bankA], ["ext", bankB], ["stock", bankC], ["wild", bankD]]) {
  for (const preserveChain of [false, true]) for (const copyAmpLevel of [false, true]) {
    if (nm === "mixed" && !preserveChain && !copyAmpLevel) continue;
    addAbkx(`${nm}-chain${+preserveChain}-level${+copyAmpLevel}`, bk, { preserveChain, copyAmpLevel });
  }
}
addAbkx("long-prefix", bankB, { namePrefix: "A very long prefix of a name" });
addAbkx("latin-prefix", bankB, { namePrefix: "Préé" });
addAbkx("empty-prefix", bankB, { namePrefix: "" });
addAbkx("genre-clamped-high", bankC, { genre: 99 });
addAbkx("genre-clamped-low", bankC, { genre: -4 });
addAbkx("genre-0", bankC, { genre: 0 });
addAbkx("genre-fraction", bankC, { genre: 2.7 });
addAbkx("random-5", abkxBank({ kind: "mixed" }), { preserveChain: true });
addAbkx("random-6", abkxBank({ kind: "ext" }), { copyAmpLevel: true });
addAbkx("random-7", abkxBank({ kind: "wild" }), { preserveChain: true, copyAmpLevel: true });
addAbkx("trailer-0x45", abkxBank({ last: 0x45 }), {});
addAbkx("trailer-0", abkxBank({ last: 0 }), {});
addAbkx("trailer-bad-byte", abkxBank({ last: 7 }), {});
addAbkx("too-short", bankA.slice(0, 7369), {});
addAbkx("too-long", Uint8Array.from([...bankA, 0]), {});
addAbkx("empty", new Uint8Array(0), {});
addAbkx("no-patchend", (() => { const b = bankA.slice(); b[7360] = 0x58; return b; })(), {});
addAbkx("bad-permutation", (() => { const b = bankA.slice(); b[5 * 92 + 2] = b[5 * 92 + 3]; return b; })(), {});
addAbkx("bad-permutation-slot-80", (() => { const b = bankA.slice(); b[79 * 92 + 7] = 6; return b; })(), {});
addAbkx("all-zero-records", (() => { const b = new Uint8Array(7370); for (let i = 0; i < 80; i++) [0, 1, 2, 3, 4, 5].forEach((c, j) => { b[i * 92 + 2 + j] = c; }); b.set(utf8("PATCHEND"), 7360); return b; })(), {}, true);
addAbkx("all-enabled-drive-eq-ext", (() => { const b = new Uint8Array(7370); for (let i = 0; i < 80; i++) { const r = b.subarray(i * 92, i * 92 + 92); [5, 4, 3, 2, 1, 0].forEach((c, j) => { r[2 + j] = c; }); for (let c = 0; c < 6; c++) r[8 + c] = 1; r[1] = 0x80 | 0x20 | (i % 30); r[0x36] = 50 + (i % 6); r[0x4E] = 50 + (i % 3); r[0x2A] = 77; r[0x2B] = 20 + i; r[0x0E] = i % 5; r[0x0F] = i % 25; r[0x10] = i % 8; r[0x12] = i % 10; r[0x13] = i % 8; r[0x37] = 10; r[0x4F] = 20; r[0x57] = 30; r[0x59] = 40; r[0x5B] = 50; r[0x56] = 60; r[0x58] = 70; r[0x5A] = 80; } b.set(utf8("PATCHEND"), 7360); return b; })(), { preserveChain: true }, false);

writeFixture("files", {
  nam: namCases, cab: cabCases, abkxBanks: Object.fromEntries(Object.entries(abkxBanks).map(([k, v]) => [k, hex(v)])), abkx: abkxCases, docs: docCases, unit: unitCases,
  numbers: { toString: numCases, toNumber: strCases, fixed4: fixedCases, round: roundCases },
});
