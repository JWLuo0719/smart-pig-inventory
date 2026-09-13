const mdns = require('multicast-dns');
const net = require('node:net');
const address = process.argv[2];
if (net.isIP(address) !== 4 || !/^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/.test(address)) {
  throw new Error('A private LAN IPv4 address is required');
}
const host = 'pig-inventory.local';
const socket = mdns({ interface: address });
const answer = {name:host,type:'A',ttl:30,flush:true,data:address};
socket.on('error', () => { console.error('mDNS socket failed'); process.exit(1); });
socket.on('warning', () => console.error('mDNS packet warning'));
socket.on('query', (packet, remote) => {
  if (!packet.questions.some(q => q.name.toLowerCase() === host && ['A','ANY','AAAA'].includes(q.type))) return;
  // Android's one-shot resolver may use a non-5353 source port.
  if (remote.port !== 5353) socket.respond({id:packet.id,questions:packet.questions,answers:[answer]}, remote);
  else socket.respond({answers:[answer]});
});
socket.on('response', packet => {
  if (packet.answers.some(a => a.name.toLowerCase() === host && a.type === 'A' && a.data !== address)) {
    console.error('Conflicting LAN hostname detected; stopping'); process.exit(2);
  }
});
socket.on('ready', () => {socket.respond({answers:[answer]}); console.log('mDNS LAN responder ready');});
setInterval(() => socket.respond({answers:[answer]}), 20000);
process.on('SIGTERM', () => socket.destroy(() => process.exit(0)));
