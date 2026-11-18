`golden-pmp2.bin` is an independently constructed 164-byte firmware record, using
the PMP2 layout in the pinned Pocket-Onyx editor. It includes a signed input
trim, reordered effects, model indices above the factory range, and Q16 values
0, 1, 65535, 32768, 65534 and 12345. Its CRC is generated with Python's standard
`zlib.crc32`, not the Dart implementation being tested.

The MIDI wire constants are independent 7-bit packing vectors. ABKX and WAV
inputs are constructed directly in their binary layouts by the tests. Demo
transport tests exercise the controller, request queue and preset verification
together; they do not validate a physical amplifier's Bluetooth implementation.
