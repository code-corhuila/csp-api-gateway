// Reads one JSON document from stdin. `keys` prints its sorted top-level keys comma-separated,
// `get <field>` prints one top-level string field; anything that is not a JSON object prints INVALID.
let input = '';
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const document = JSON.parse(input);
    if (document === null || typeof document !== 'object' || Array.isArray(document)) throw new Error('not an object');
    console.log(process.argv[2] === 'get' ? document[process.argv[3]] : Object.keys(document).sort().join(','));
  } catch (error) {
    console.log('INVALID');
  }
});
