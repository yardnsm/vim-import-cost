const getStdin = require('get-stdin');
const {
  importCost, cleanup, JAVASCRIPT, TYPESCRIPT,
} = require('import-cost');

const write = payload => process.nextTick(() => {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
});

const extractPackage = pkg => ({
  name: pkg.name,
  line: pkg.line,
  size: typeof pkg.size === 'undefined' ? -1 : pkg.size,
  gzip: typeof pkg.gzip === 'undefined' ? -1 : pkg.gzip,
});

async function start() {
  // Arguments
  const fileType = process.argv[2].includes('typescript') ? TYPESCRIPT : JAVASCRIPT;
  const filePath = process.argv[3];

  // File contents through stdin
  const fileContents = await getStdin();

  const emitter = importCost(filePath, fileContents, fileType);

  emitter.on('start', (packages) => {
    write({
      type: 'start',
      payload: packages.map(extractPackage),
    });
  });

  emitter.on('calculated', (pkg) => {
    write({
      type: 'calculated',
      payload: [extractPackage(pkg)],
    });
  });

  emitter.on('error', (err) => {
    write({
      type: 'error',
      payload: `[error] ${err.toString()}`,
    });
  });

  emitter.on('done', (packages) => {
    write({
      type: 'done',
      payload: packages.map(extractPackage),
    });

    cleanup();
  });
}

// Wrapping it in try/catch to prevent errors to go to stderr
try {
  start();
} catch (e) {
  // empty
}
