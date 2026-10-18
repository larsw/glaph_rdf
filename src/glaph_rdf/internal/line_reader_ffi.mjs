// Returns the byte index of the first LF (0x0A) in the BitArray, or -1.
export function find_newline(bits) {
  if (bits.bitOffset === 0) {
    const index = bits.rawBuffer.indexOf(10);
    return index < bits.byteSize ? index : -1;
  }
  for (let i = 0; i < bits.byteSize; i++) {
    if (bits.byteAt(i) === 10) return i;
  }
  return -1;
}

// Strings decoded on JavaScript never alias the chunk buffer, so nothing to do.
export function detach(bits) {
  return bits;
}
