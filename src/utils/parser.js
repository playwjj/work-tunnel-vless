// src/utils/parser.js

const { TextDecoder } = require('util');
const textDecoder = new TextDecoder();

function createUUIDValidator(uuid) {
  const uuidBytes = Buffer.from(uuid.replace(/-/g, ''), 'hex');
  return (id) => id.equals(uuidBytes);
}

function parseHost(msg, startIndex) {
  const ATYP = msg[startIndex];
  let host, endIndex;

  switch (ATYP) {
    case 1: // IPv4
      host = msg.slice(startIndex + 1, startIndex + 5).join('.');
      endIndex = startIndex + 5;
      break;
    case 2: { // Domain
      const domainLength = msg[startIndex + 1];
      host = textDecoder.decode(msg.slice(startIndex + 2, startIndex + 2 + domainLength));
      endIndex = startIndex + 2 + domainLength;
      break;
    }
    case 3: { // IPv6
      const ipv6Bytes = msg.slice(startIndex + 1, startIndex + 17);
      host = ipv6Bytes.reduce((acc, byte, i) => {
        if (i % 2 === 0) {
          acc.push(byte.toString(16).padStart(2, '0') +
                   ipv6Bytes[i + 1].toString(16).padStart(2, '0'));
        }
        return acc;
      }, []).join(':');
      endIndex = startIndex + 17;
      break;
    }
    default:
      throw new Error('Invalid address type');
  }

  return { host, endIndex };
}

module.exports = {
  createUUIDValidator,
  parseHost
};
