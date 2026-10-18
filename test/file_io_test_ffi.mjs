// Returns an integer that is unique within this process and, thanks to the
// wall-clock component, practically unique across test runs too.
// Kept below Number.MAX_SAFE_INTEGER (~9.0e15): Date.now() is ~1.8e12 in
// 2026, so the 1000x scale leaves room for a 0-999 counter for centuries.
let counter = 0;

export function unique_id() {
  counter = (counter + 1) % 1000;
  return Date.now() * 1000 + counter;
}
