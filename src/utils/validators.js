function isValidUUID(uuid) {
  const uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  return uuidRegex.test(uuid);
}

function isValidPort(port, min = 1, max = 65535) {
  if (typeof port === 'string') {
    port = port.trim();
  }
  const portNum = parseInt(port, 10);
  return !isNaN(portNum) && 
         Number.isInteger(portNum) && 
         portNum >= min && 
         portNum <= max;
}

function isValidDomain(domain) {
  const domainRegex = /^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$/;
  return domainRegex.test(domain) && domain.length <= 255;
}

module.exports = {
  isValidUUID,
  isValidPort,
  isValidDomain,
};


