const getStdin = require('get-stdin');
const {
  importCost, cleanup, JAVASCRIPT, TYPESCRIPT,
} = require('import-cost');

const printPackages = packages =>
  packages.forEach(({
    name,
    line,
    size,
    gzip,
  }) => process.stdout.write(`${name},${line},${size},${gzip}\n`));

async function start() {
  // Arguments
  const fileType = process.argv[2].includes('typescript') ? TYPESCRIPT : JAVASCRIPT;
  const filePath = process.argv[3];

  // File contents through stdin
  const fileContents = await getStdin();

  const emitter = importCost(filePath, fileContents, fileType);

  emitter.on('error', (err) => {
    process.stderr.write(`[error] ${err.toString()}`);
  });

  emitter.on('done', (packages) => {
    printPackages(packages);
    cleanup();
  });
}

start();
