// Runs the ORIGINAL editor JavaScript on fixed + seeded-random inputs and writes the golden vectors for the protocol,
// state-record and preset-record tests: protocol.json, state.json, presetrecord.json.   node Tools/golden/gen_protocol.cjs
const { loadEditor, rng, hex, writeFixture } = require("./editor.cjs");
const E = loadEditor();

const arr = (a) => Array.from(a);
const rint = (r, n) => Math.floor(r() * n);
const bytes = (r, n, max = 256) => Array.from({ length: n }, () => rint(r, max));
const pick = (r, a) => a[rint(r, a.length)];
const mkFrame = (inner) => [0xF0, ...E.pack8to7(inner), 0xF7];      // a frame around hand-made inner bytes
const chk = (cmd, l0, l1, l2, data) => { let s = cmd + l0 + l1 + l2; for (const b of data) s += b; return (~s) & 0xFF; };
const mkReply = (type, data, o = {}) => {                              // a well formed device reply (data may exceed 256: parseReply does not care)
  const l = o.len === undefined ? data.length : o.len;
  const inner = [0x00, 0x59, type, l & 0xFF, (l >> 8) & 0xFF, (l >> 16) & 0xFF, ...data];
  inner.push(o.chk === undefined ? chk(type, l & 0xFF, (l >> 8) & 0xFF, (l >> 16) & 0xFF, data) : o.chk);
  return mkFrame(inner);
};

// ================================================================ protocol.json
function protocol() {
  const out = {};
  let r = rng(0xB17E);

  // ---- pack8to7 / unpack7to8
  out.pack = [];
  out.unpack = [];
  const lens = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 16, 28, 29, 30, 31, 64, 127, 128, 129, 255, 256, 257, 300];
  for (const n of lens) {
    const a = bytes(r, n);
    out.pack.push({ in: hex(a), out: hex(E.pack8to7(a)) });
    const b = bytes(r, n);                                           // 7-bit input is NOT guaranteed: the high bit must be ignored
    out.unpack.push({ in: hex(b), out: hex(E.unpack7to8(b)) });
  }
  for (const a of [[0xFF], [0x00], [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], [0x80, 0x7F, 0x01, 0xFE]]) {
    out.pack.push({ in: hex(a), out: hex(E.pack8to7(a)) });
    out.unpack.push({ in: hex(a), out: hex(E.unpack7to8(a)) });
  }
  for (let i = 0; i < 40; i++) {                                    // pack -> unpack round trip is checked in Swift too
    const a = bytes(r, rint(r, 70));
    out.pack.push({ in: hex(a), out: hex(E.pack8to7(a)) });
  }

  // ---- buildFrame
  out.build = [];
  const cmds = [0, 1, 25, 80, 83, 0x63, 127, 128, 200, 255];
  for (const cmd of cmds) for (const n of [0, 1, 2, 5, 17, 164, 255, 256]) {
    const p = bytes(r, n);
    out.build.push({ cmd, payload: hex(p), frame: hex(E.buildFrame(cmd, p)) });
  }
  for (const n of [257, 300, 1000]) {
    let threw = false; try { E.buildFrame(1, bytes(r, n)); } catch (e) { threw = true; }
    if (!threw) throw new Error("buildFrame did not throw for " + n);
    out.build.push({ cmd: 1, payload: hex(bytes(r, n)), frame: null });
  }
  for (const p of [[0xFF, 0xFF, 0xFF], new Array(256).fill(0xFF), new Array(256).fill(0)])
    out.build.push({ cmd: 0xFF, payload: hex(p), frame: hex(E.buildFrame(0xFF, p)) });
  out.build.push({ cmd: 5, payload: "", frame: hex(E.buildFrame(5)) });                 // payload omitted

  // ---- parseReply (valid, built through buildFrame / mkReply, then corrupted)
  out.parse = [];
  const add = (frame, note) => {
    const p = E.parseReply(frame);
    out.parse.push({ note, frame: hex(frame || []), isNull: frame === null, reply: p ? { type: p.type, data: hex(p.data) } : null });
  };
  add(null, "null"); add([], "empty"); add([0xF0], "lone F0"); add([0xF7], "lone F7"); add([0xF0, 0xF7], "F0 F7");
  add([0xF7, 0xF0], "reversed"); add([0x00, 0x59, 0xF7], "no F0"); add([0xF0, 0x00, 0x59], "no F7");
  const valid = [];
  for (let i = 0; i < 40; i++) {
    const type = rint(r, 256), data = bytes(r, pick(r, [0, 1, 2, 7, 8, 9, 31, 128, 164, 200, 256]));
    valid.push(mkReply(type, data));
  }
  valid.push(mkReply(0x63, bytes(r, 300)), mkReply(0x50, bytes(r, 1000)));                  // longer than a request may be
  for (let i = 0; i < 15; i++) valid.push(E.buildFrame(rint(r, 256), bytes(r, rint(r, 257))));
  valid.forEach((f) => add(f, "valid"));
  for (const f of valid) {
    const k = rint(r, 8), g = f.slice();
    if (k === 0) { g[g.length - 2] ^= 0x01; add(g, "checksum flip (last 7-bit byte)"); }
    else if (k === 1) { const i = 1 + rint(r, g.length - 2); g[i] = (g[i] ^ (1 << rint(r, 7))) & 0x7F; add(g, "bit flip somewhere"); }
    else if (k === 2) { add(g.slice(0, -1), "no F7"); }
    else if (k === 3) { add(g.slice(1), "no F0"); }
    else if (k === 4) { add([...g.slice(0, -2), 0xF7], "last 7-bit byte dropped"); }
    else if (k === 5) { const i = 1 + rint(r, g.length - 2); g[i] |= 0x80; add(g, "high bit set inside (ignored by the unpacker)"); }
    else if (k === 6) { add([...g.slice(0, -1), 0x00, 0x00, 0xF7], "two stray 7-bit bytes before F7"); }
    else { add([...g.slice(0, 1), ...g.slice(2)], "first 7-bit byte dropped"); }
  }
  const inner = (cmd, data) => [0x00, 0x59, cmd, data.length, 0, 0, ...data, chk(cmd, data.length, 0, 0, data)];
  add(mkFrame([0x01, 0x59, 2, 0, 0, 0, chk(2, 0, 0, 0, [])]), "wrong first magic byte");
  add(mkFrame([0x00, 0x58, 2, 0, 0, 0, chk(2, 0, 0, 0, [])]), "wrong second magic byte");
  add(mkFrame([0x00, 0x59, 2, 0, 0]), "inner too short (5)");
  add(mkFrame([0x00, 0x59, 2, 0, 0, 0]), "inner too short (6)");
  add(mkFrame([0x00, 0x59, 2, 0, 0, 0, chk(2, 0, 0, 0, [])]), "empty reply");
  add(mkFrame([0x00, 0x59, 2, 0, 0, 0, 0x00]), "empty reply, wrong checksum");
  add(mkReply(2, [1, 2, 3], { len: 4 }), "length longer than the data");
  add(mkReply(2, [1, 2, 3], { len: 0x010000 }), "length 65536");
  add(mkReply(2, [1, 2, 3], { len: 2, chk: chk(2, 2, 0, 0, [1, 2]) }), "length shorter, checksum fits the shorter data");
  add(mkReply(2, [1, 2, 3], { len: 2 }), "length shorter, checksum of the longer");
  add(mkFrame([...inner(9, [5, 6, 7]), 0x42, 0x43, 0x44]), "trailing bytes after the checksum");
  add(mkFrame(inner(9, [0xFF, 0x80, 0x00, 0x7F])), "high data bytes");
  add(mkReply(0x63, bytes(r, 5), { chk: 0x100 & 0xFF }), "checksum 0");
  for (let i = 0; i < 40; i++) add([0xF0, ...bytes(r, rint(r, 40), 128), 0xF7], "random 7-bit garbage");
  for (let i = 0; i < 20; i++) add([0xF0, ...bytes(r, rint(r, 40), 256), 0xF7], "random garbage with high bits");

  // ---- bleFrames
  out.ble = [];
  const msgs = [];
  msgs.push([0xF0, 0xF7], [0xF0, 0x00, 0xF7], []);
  for (const n of [0, 1, 2, 5, 9, 10, 11, 12, 13, 17, 18, 19, 20, 33, 100, 164, 256]) msgs.push(E.buildFrame(rint(r, 256), bytes(r, n)));
  msgs.push(E.pc(5), E.cc(7, 100), E.nrpn(3, 2, 77), E.nrpn(10, 7, 1234, true), E.chainMoveMsg(5, 2), [0xC0, 0x00]);
  const tss = [0, 1, 127, 128, 0x1FFF, 0x2000, 0x2001, 12345, 0xFFFF, 1700000000000, -1, 0x7FFFFFFF, 0xFFFFFFFF];
  for (const m of msgs) for (const chunk of [20, 100]) {
    const ts = pick(r, tss);
    out.ble.push({ msg: hex(m), chunk, ts, packets: E.bleFrames(m, chunk, ts).map(hex) });
  }
  for (const m of [msgs[3], msgs[10], msgs[14], msgs[16]]) for (const ts of tss) for (const chunk of [20, 100, 7, 8, 23, 185]) {
    if (m.length < 3 && chunk < 5) continue;
    out.ble.push({ msg: hex(m), chunk, ts, packets: E.bleFrames(m, chunk, ts).map(hex) });
  }

  // ---- BleUnframer
  out.unframe = [];
  const scenario = (pushes, note) => {
    const u = new E.BleUnframer();
    out.unframe.push({ note, pushes: pushes.map(hex), frames: pushes.map((p) => u.push(p).map(hex)) });
  };
  const ts = 0x1234;
  for (let i = 0; i < 25; i++) {                                    // frames cut into notification packets of random size
    const frames = Array.from({ length: 1 + rint(r, 3) }, () => E.buildFrame(rint(r, 256), bytes(r, rint(r, 120))));
    const pkts = [];
    for (const f of frames) pkts.push(...E.bleFrames(f, pick(r, [20, 23, 100, 185]), ts + rint(r, 500)));
    scenario(pkts, "real BLE-MIDI packets");
    // the same bytes re-cut at arbitrary places, each piece with a dummy header byte
    const flat = pkts.map((p) => p.slice(1)).flat(), cut = [];
    for (let i = 0; i < flat.length;) { const n = 1 + rint(r, 12); cut.push([0x80 | rint(r, 64), ...flat.slice(i, i + n)]); i += n; }
    scenario(cut, "re-cut at arbitrary places");
    scenario([[0x80, 0x90, ...frames.flat().slice(0, 40)], ...pkts], "frames in one packet, then more");
  }
  for (let i = 0; i < 40; i++) {                                    // garbage
    const pk = [];
    for (let k = 0; k < 1 + rint(r, 8); k++) pk.push(bytes(r, rint(r, 30), pick(r, [256, 128, 3])).map((b) => pick(r, [b, b, b, 0xF0, 0xF7, 0x80, 0x9F, 0xB0])));
    scenario(pk, "garbage");
  }
  scenario([], "no packets");
  scenario([[], [0x80], [0x80, 0xF7], [0x80, 0xF0], [0x80, 0x01, 0xF7]], "empty and one byte packets");
  scenario([[0x80, 0x81, 0xF0, 0x01, 0x02], [0x80, 0x03, 0xF7], [0x80, 0x04, 0xF7]], "F7 outside sysex after a frame");
  scenario([[0x80, 0x81, 0xF0, 0x01, 0xF0, 0x02, 0xF7]], "F0 restarts a frame");
  scenario([[0x80, 0x81, 0xF0, 0x01, 0x90, 0x02, 0xF7]], "status byte inside a frame is skipped");
  scenario([[0xF0, 0xF0, 0x05, 0xF7]], "first byte (header) is never data");
  scenario([[0x80, 0x01, 0x02, 0xF7, 0xF0, 0x03, 0xF7]], "data before F0 is dropped");
  scenario([[0x80, 0xF0, 0xF7, 0xF0, 0xF7]], "empty frames");
  scenario([[0x80, 0xF0, 0x01], [0x80, 0xF0, 0x02, 0xF7]], "unterminated frame is replaced");

  // ---- cc / pc / nrpn
  out.cc = []; out.pc = [];
  for (const [c, v] of [[0, 0], [7, 127], [127, 128], [128, 255], [-1, -1], [300, 300], [99, 64], [38, 1000], [255, 255], [64, 63]]) out.cc.push({ c, v, out: E.cc(c, v) });
  for (const n of [0, 1, 79, 80, 127, 128, 255, -1, 300]) out.pc.push({ n, out: E.pc(n) });
  out.nrpn = [];
  const pctVals = [-100, -1, 0, 1, 2, 3, 49, 50, 51, 99, 100, 101, 1000];
  for (let m = 0; m < 8; m++) for (let p = 0; p < 7; p++) for (const d of pctVals) out.nrpn.push({ module: m, param: p, d, raw: false, out: E.nrpn(m, p, d, false) });
  for (let d = 0; d <= 100; d++) out.nrpn.push({ module: 3, param: 1, d, raw: false, out: E.nrpn(3, 1, d) });     // raw omitted
  const rawVals = [-5, -1, 0, 1, 63, 64, 126, 127, 128, 129, 255, 256, 1000, 8191, 16383, 16384, 20000, 100000];
  for (let m = 8; m <= 10; m++) for (let p = 0; p < 9; p++) for (const d of rawVals) out.nrpn.push({ module: m, param: p, d, raw: true, out: E.nrpn(m, p, d, true) });
  for (const [m, p] of [[200, 130], [-1, -1], [128, 128]]) for (const raw of [false, true]) out.nrpn.push({ module: m, param: p, d: 77, raw, out: E.nrpn(m, p, 77, raw) });
  out.nrpn.forEach((x) => { x.out = hex(x.out); });
  out.cc.forEach((x) => { x.out = hex(x.out); }); out.pc.forEach((x) => { x.out = hex(x.out); });

  // ---- chainMove / chainMoveMsg
  out.chain = [];
  const orders = [[0, 1, 2, 3, 4, 5, 6, 7], [7, 6, 5, 4, 3, 2, 1, 0], [0, 1, 2], [], [0, 0, 1, 1, 2, 2, 3, 3], [3, 3, 3, 3, 3, 3, 3, 3], [9, 8, 7, 6, 5, 4, 3, 2]];
  for (let i = 0; i < 12; i++) { const o = [0, 1, 2, 3, 4, 5, 6, 7]; for (let k = 7; k > 0; k--) { const j = rint(r, k + 1); [o[k], o[j]] = [o[j], o[k]]; } orders.push(o); }
  for (const o of orders) for (let slot = -1; slot <= 8; slot++) for (const to of [-2, -1, 0, 1, 3, 6, 7, 8, 9]) out.chain.push({ order: o, slot, to, out: E.chainMove(o, slot, to) });
  out.chainMsg = [];
  for (let slot = 0; slot < 8; slot++) for (let to = 0; to < 8; to++) out.chainMsg.push({ slot, to, out: hex(E.chainMoveMsg(slot, to)) });
  return out;
}

// ================================================================ state.json
function state() {
  const r = rng(0x57A7E), list = [];
  const nameBytes = [0x41, 0x42, 0x63, 0x7A, 0x30, 0x39, 0x20, 0x20, 0x00, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1F, 0x7F, 0x80, 0x85, 0xA0, 0xA1, 0xE9, 0xFF];
  const perm = () => { const o = [0, 1, 2, 3, 4, 5, 6, 7]; for (let k = 7; k > 0; k--) { const j = rint(r, k + 1); [o[k], o[j]] = [o[j], o[k]]; } return o; };
  const norm = (s) => s && {
    view: s.view, preset: s.preset, flags: s.flags, presetVol: s.presetVol, outLevel: s.outLevel, name: s.name,
    slots: s.slots.map((x) => ({ on: !!x.on, rawOn: x.on, type: x.type, knobs: arr(x.knobs) })), g: s.g, stomp: s.stomp,
    namCount: s.namCount, userCab: !!s.userCab, cabCount: s.cabCount === undefined ? 0 : s.cabCount,    // absent -> 0 (Swift has no undefined)
    namFree: s.namFree === undefined ? 0 : s.namFree, cabFree: s.cabFree === undefined ? 0 : s.cabFree, order: arr(s.order),
  };
  const push = (rec, note) => {
    const a = rec instanceof Uint8Array ? rec : Uint8Array.from(rec);
    list.push({ note, record: hex(a), state: norm(E.decodeState(Array.from(a))) });
  };
  const mk = (o = {}) => {
    const a = new Uint8Array(o.len || 128);
    for (let i = 0; i < a.length; i++) a[i] = rint(r, o.wild ? 256 : 128);
    a[0] = 1;
    for (let s = 0; s < 8; s++) { a[22 + s * 8] = rint(r, 2); a[23 + s * 8] = rint(r, 50); for (let k = 0; k < 6; k++) a[24 + s * 8 + k] = rint(r, 101); }
    for (let i = 6; i < 22; i++) a[i] = 0;
    const n = o.nameLen === undefined ? rint(r, 17) : o.nameLen, start = rint(r, 17 - n + 1);
    for (let i = 0; i < n; i++) a[6 + start + i] = pick(r, nameBytes);
    if (a.length >= 125) { const p = o.badOrder ? bytes(r, 8, 10) : perm(); for (let i = 0; i < 8; i++) a[117 + i] = p[i]; }
    return a;
  };
  for (let i = 0; i < 60; i++) push(mk(), "random 128 byte record");
  for (let i = 0; i < 25; i++) push(mk({ wild: true }), "wild bytes");
  for (let i = 0; i < 12; i++) push(mk({ badOrder: true }), "order bytes random (usually invalid)");
  for (const len of [127, 126, 125, 124, 120, 118, 117]) for (let i = 0; i < 3; i++) push(mk({ len }), "short record " + len);
  for (const len of [116, 100, 1, 0]) push(mk({ len }).subarray(0, len), "too short " + len);
  for (const v of [0, 2, 3, 255]) { const a = mk(); a[0] = v; push(a, "version " + v); }
  { const a = mk(); a[6] = a[7] = 0x20; for (let i = 8; i < 22; i++) a[i] = 0x20; push(a, "name only blanks"); }
  { const a = mk(); a.fill(0, 6, 22); push(a, "no name"); }
  for (const b of [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x85, 0xA0, 0x7F, 0x80, 0xAD]) {
    const a = mk(); a.fill(0, 6, 22); a[6] = b; a[7] = 0x58; a[8] = b; a[9] = 0; a[10] = b; push(a, "name edge char 0x" + b.toString(16));
    const c = mk(); c.fill(0, 6, 22); c[6] = b; c[7] = b; push(c, "name only 0x" + b.toString(16));
  }
  { const a = mk(); a.fill(0x41, 6, 22); push(a, "name fills all 16 bytes"); }
  { const a = mk(); a[3] = 0xFF; a[116] = 0xFF; push(a, "all flag bits"); }
  { const a = mk(); a[3] = 0x00; a[116] = 0; push(a, "no flag bits"); }
  for (let f = 0; f < 256; f += 7) { const a = mk(); a[3] = f; a[116] = f & 1; push(a, "flags " + f); }
  { const a = mk(); a[106] = 0xFF; a[107] = 0xFF; a[86] = 0; a[87] = 0; a[94] = 0; a[101] = 255; for (let i = 96; i < 101; i++) a[i] = 0; push(a, "extreme globals"); }
  { const a = mk(); a[106] = 0x34; a[107] = 0x12; push(a, "bpm 0x1234"); }
  { const a = mk(); for (let i = 117; i < 125; i++) a[i] = 7 - (i - 117); push(a, "reversed order"); }
  { const a = mk(); for (let i = 117; i < 125; i++) a[i] = i - 117; push(a, "identity order"); }
  { const a = mk(); for (let i = 117; i < 125; i++) a[i] = 0; push(a, "all-zero order"); }
  { const a = mk(); const p = perm(); p[3] = 8; for (let i = 0; i < 8; i++) a[117 + i] = p[i]; push(a, "order with 8"); }
  return list;
}

// ================================================================ presetrecord.json
function presetrecord() {
  const r = rng(0xFEED5), out = {};
  const perm = () => { const o = [0, 1, 2, 3, 4, 5, 6, 7]; for (let k = 7; k > 0; k--) { const j = rint(r, k + 1); [o[k], o[j]] = [o[j], o[k]]; } return o; };
  const names = ["", "Clean", "CLEAN 2", "A".repeat(22), "B".repeat(23), "C".repeat(24), "D".repeat(30), "Café ÿü", "ÀÉÎÕÜ",
    "Ā tail", "ŁŁx", "€ uro", "emoji 😀 name", "😀".repeat(14), "with\u0000nul", "\u0000", "  padded  ", "x".repeat(40), "tab\there",
    "0123456789012345678901Ā", "01234567890123456789012Āx"];
  const randName = () => { const a = Array.from({ length: rint(r, 30) }, () => String.fromCharCode(pick(r, [rint(r, 128), 32 + rint(r, 95), 32 + rint(r, 95), 128 + rint(r, 128), 256 + rint(r, 500)]))); return a.join(""); };
  const u32s = [0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x32504D50];
  const mk = (i) => ({
    seq: i % 3 === 0 ? pick(r, u32s) : rint(r, 4294967296) >>> 0, name: i < names.length ? names[i] : (i % 4 === 0 ? pick(r, names) : randName()),
    bpm: pick(r, [0, 60, 120, 255, 256, 300, 65535, rint(r, 65536)]), genre: rint(r, 9), custom_cab_idx: pick(r, [0, 1, 19, 20, 255, rint(r, 256)]),
    custom_cab_blend: rint(r, 101), input_trim_db: pick(r, [0, 0, -1, -12, 12, -128, 127, rint(r, 25) - 12, rint(r, 256) - 128]), gate_threshold_pct: rint(r, 101),
    slot_enable_mask: rint(r, 256), slot_order: i % 5 === 0 ? bytes(r, 8) : perm(), amp_model: rint(r, 40), cab_model: rint(r, 20), preset_vol: rint(r, 101),
    flags: i % 3 === 0 ? undefined : pick(r, [0, 1, 2, 4, 0xFE, 0xFF, rint(r, 256)]), empty: r() < 0.3,
    slot_type: bytes(r, 8, 50), stomp_map: bytes(r, 4, 8),
    params: Array.from({ length: 8 }, () => Array.from({ length: 6 }, () => pick(r, [0, 65535, 32768, 32767, rint(r, 65536), rint(r, 65536), Math.round(rint(r, 101) * 65535 / 100)]))),
  });
  const chk = (rec) => JSON.stringify({ hex: hex(rec), ok: E.recordOk(rec) });
  out.presets = [];
  const total = names.length + 60;
  for (let i = 0; i < total; i++) {
    const o = mk(i), rec = E.presetToRecord(o), slot = rint(r, 80), p = E.recordToPreset(slot, rec);
    out.presets.push({ in: o, record: hex(rec), ok: E.recordOk(rec), slot, preset: { ...p, slot_order: arr(p.slot_order) } });
  }
  // records handmade (not through presetToRecord), with a valid CRC unless said otherwise
  const sign = (a, fixCrc = true) => { const v = new DataView(a.buffer); if (fixCrc) v.setUint32(160, E.crc32(a.subarray(0, 160)), true); return a; };
  const base = () => { const a = Uint8Array.from(E.presetToRecord(mk(1))); return a; };
  out.raw = [];
  const addRaw = (a, note) => {
    const ok = E.recordOk(a);
    out.raw.push({ note, record: hex(a), ok, preset: ok ? (() => { const p = E.recordToPreset(5, a); return { ...p, slot_order: arr(p.slot_order) }; })() : null });
  };
  { const a = base(); a.fill(0x41, 8, 32); sign(a); addRaw(a, "24 character name, no NUL"); }
  { const a = base(); a.fill(0, 8, 32); a.set([0x61, 0x62, 0, 0x63, 0x64], 8); sign(a); addRaw(a, "garbage after the NUL"); }
  { const a = base(); a.fill(0, 8, 32); a.set([0xFF, 0xE9, 0x80, 0x85, 0xA0], 8); sign(a); addRaw(a, "high bytes in the name"); }
  { const a = base(); a.fill(0, 8, 32); sign(a); addRaw(a, "empty name"); }
  { const a = base(); a[51] = 0xFF; sign(a); addRaw(a, "all flags"); }
  { const a = base(); a[51] = 0xFE; sign(a); addRaw(a, "no EMPTY flag"); }
  { const a = base(); a[37] = 0x80; sign(a); addRaw(a, "trim -128"); }
  { const a = base(); a[37] = 0xF4; sign(a); addRaw(a, "trim -12"); }
  { const a = base(); a[37] = 0x0C; sign(a); addRaw(a, "trim +12"); }
  { const a = base(); a.fill(0xFF, 64, 160); sign(a); addRaw(a, "all params 65535"); }
  { const a = base(); a.fill(0, 64, 160); sign(a); addRaw(a, "all params 0"); }
  { const a = base(); a[32] = 0xFF; a[33] = 0xFF; sign(a); addRaw(a, "bpm 65535"); }
  { const a = base(); a.fill(0xFF, 4, 8); sign(a); addRaw(a, "seq 0xFFFFFFFF"); }
  { const a = base(); a[0] ^= 1; sign(a); addRaw(a, "wrong magic, valid CRC"); }
  { const a = base(); a[0] ^= 1; addRaw(a, "wrong magic, stale CRC"); }
  { const a = base(); a[163] ^= 0x80; addRaw(a, "CRC bit flipped"); }
  { const a = base(); a[100] ^= 0x01; addRaw(a, "payload bit flipped"); }
  { const a = base(); a[4] ^= 0x01; addRaw(a, "seq bit flipped"); }
  { const a = new Uint8Array(164); addRaw(a, "all zero"); }
  { const a = new Uint8Array(164).fill(0xFF); addRaw(a, "all FF"); }
  for (const n of [0, 1, 160, 163, 165, 200]) { const a = new Uint8Array(n); const b = base(); a.set(b.subarray(0, Math.min(n, 164))); addRaw(a, "length " + n); }
  for (let i = 0; i < 40; i++) { const a = base(); a[rint(r, 164)] ^= 1 << rint(r, 8); addRaw(a, "single bit flip"); }
  for (let i = 0; i < 20; i++) { const a = Uint8Array.from(bytes(r, 164)); addRaw(a, "random bytes"); }
  for (let i = 0; i < 20; i++) { const a = Uint8Array.from(bytes(r, 164)); new DataView(a.buffer).setUint32(0, 0x32504D50, true); sign(a); addRaw(a, "random bytes with magic and CRC"); }

  // crc32
  out.crc = [{ in: hex(Array.from("123456789", (c) => c.charCodeAt(0))), crc: E.crc32(Array.from("123456789", (c) => c.charCodeAt(0))) }];
  for (const n of [0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 31, 64, 100, 160, 164, 255, 256, 1000]) { const a = bytes(r, n); out.crc.push({ in: hex(a), crc: E.crc32(Uint8Array.from(a)) }); }
  out.crc.push({ in: hex(new Array(64).fill(0)), crc: E.crc32(new Array(64).fill(0)) }, { in: hex(new Array(64).fill(255)), crc: E.crc32(new Array(64).fill(255)) });

  // Q16 <-> percent. percent(q16): the editor's `Math.round(x * 100 / 65535)` as in recordToPreset's params_pct; dense around every rounding boundary.
  const xs = new Set();
  for (let x = 0; x < 65536; x += 97) xs.add(x);
  for (let p = 0; p <= 100; p++) { const b = Math.round((p - 0.5) * 65535 / 100); for (let d = -3; d <= 3; d++) { const x = b + d; if (x >= 0 && x <= 65535) xs.add(x); } }
  xs.add(0); xs.add(65535);
  out.pct = [...xs].sort((a, b) => a - b).map((x) => [x, Math.round(x * 100 / 65535)]);
  // q16(percent:): the formula of the editor's abQ16 (a local, not exported, helper) and of the firmware's pct16, with the clamp
  out.q16 = [];
  for (let p = -20; p <= 130; p++) { const c = Math.max(0, Math.min(100, p)); out.q16.push([p, Math.floor((c * 65535 + 50) / 100)]); }
  return out;
}

writeFixture("protocol", protocol());
writeFixture("state", state());
writeFixture("presetrecord", presetrecord());
