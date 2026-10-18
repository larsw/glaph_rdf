import { Ok, Error as GleamError } from "../../gleam.mjs";

// Unlike the stdlib's bit_array.to_string, keeps a leading U+FEFF
// (ignoreBOM: true) so decoding matches the Erlang target.
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

export function decode(bits) {
  if (bits.bitSize % 8 !== 0) return new GleamError(undefined);
  let bytes = bits.rawBuffer;
  if (bits.bitOffset !== 0) {
    bytes = new Uint8Array(bits.byteSize);
    for (let i = 0; i < bytes.length; i++) bytes[i] = bits.byteAt(i);
  }
  try {
    return new Ok(decoder.decode(bytes));
  } catch {
    return new GleamError(undefined);
  }
}
