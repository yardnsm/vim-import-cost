const getStdin = require('get-stdin');
const {
  importCost, cleanup, JAVASCRIPT, TYPESCRIPT,
} = require('import-cost');

const write = payload => process.nextTick(() => {
  process.stdout.write(JSON.stringify(payload) + '\n');
});

const extractPackage = package => ({
  name: package.name,
  line: package.line,
  size: typeof package.size === 'undefined' ? -1 : package.size,
  gzip: typeof package.gzip === 'undefined' ? -1 : package.gzip,
});

async function start() {

  // Arguments
  const fileType = process.argv[2].includes('typescript') ? TYPESCRIPT : JAVASCRIPT;
  const filePath = process.argv[3];

  /*
   * This script can be executed in 2 modes:
   *
   *  - In async mode, when this script will write the events as JSON to stdout as they'll arrive.
   *    This mode can be used to update the editor on the fly, rather than waiting for the entire
   *    process to complete. This is the default mode.
   *
   *  - In sync mode, when this script only write the final result as JSON when this script
   *    finishes.
   */
  const isSync = process.argv[4] === 'sync';

  // File contents through stdin
  const fileContents = await getStdin();

  const emitter = importCost(filePath, fileContents, fileType);

  emitter.on('start', (packages) => {
    if (isSync) {
      return;
    }

    write({
      type: 'start',
      payload: packages.map(extractPackage),
    });
  });

  emitter.on('calculated', (package) => {
    if (isSync) {
      return;
    }

    write({
      type: 'calculated',
      payload: [extractPackage(package)],
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

try {
  start();
} catch (e) {
}
