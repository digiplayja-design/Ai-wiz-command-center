// Validate one ordinary ZIP directory before a second library consumes it.
// Readers disagree about whether to trust the entry count or scan all records;
// a forged count must not hide unchecked compressed entries from the preflight.
export function zipDirectory(buffer) {
  let end = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65557); i--) {
    if (buffer.readUInt32LE(i) === 0x06054b50 && i + 22 + buffer.readUInt16LE(i + 20) === buffer.length) {
      end = i;
      break;
    }
  }
  if (end < 0) throw Error('Invalid archive directory.');
  const count = buffer.readUInt16LE(end + 10), start = buffer.readUInt32LE(end + 16);
  const size = buffer.readUInt32LE(end + 12);
  if (!count || count === 0xffff || buffer.readUInt16LE(end + 4) || buffer.readUInt16LE(end + 6) ||
      buffer.readUInt16LE(end + 8) !== count || start + size !== end) throw Error('Unsupported archive directory.');
  let position = start;
  for (let i = 0; i < count; i++) {
    if (position + 46 > end || buffer.readUInt32LE(position) !== 0x02014b50) throw Error('Invalid archive entry.');
    position += 46 + buffer.readUInt16LE(position + 28) + buffer.readUInt16LE(position + 30) + buffer.readUInt16LE(position + 32);
  }
  if (position !== end) throw Error('Archive entry count does not match its directory.');
  return { count, start };
}
