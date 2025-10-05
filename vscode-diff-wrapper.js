#!/usr/bin/env node

const { AdvancedLinesDiffComputer } = require('vscode-diff');

async function readInput() {
  let input = '';
  process.stdin.setEncoding('utf8');
  
  return new Promise((resolve) => {
    process.stdin.on('data', (chunk) => {
      input += chunk;
    });
    
    process.stdin.on('end', () => {
      try {
        resolve(JSON.parse(input));
      } catch (e) {
        console.log(JSON.stringify({
          success: false,
          error: "Failed to parse input: " + e.message
        }));
        process.exit(1);
      }
    });
  });
}

async function main() {
  try {
    const { original, modified, options = {} } = await readInput();
    
    // VSCode partial-diff default settings
    const diffOptions = {
      ignoreTrimWhitespace: options.ignoreTrimWhitespace || false,
      computeMoves: false,  // Better for indentation changes
      maxComputationTimeMs: options.maxComputationTimeMs || 5000
    };
    
    const diffComputer = new AdvancedLinesDiffComputer();
    const result = diffComputer.computeDiff(original, modified, diffOptions);
    
    // Output result with innerChanges
    console.log(JSON.stringify({
      success: true,
      changes: result.changes.map(change => ({
        originalRange: change.originalRange,
        modifiedRange: change.modifiedRange,
        innerChanges: change.innerChanges || []
      })),
      moves: result.moves || []
    }));
    
  } catch (error) {
    console.log(JSON.stringify({
      success: false,
      error: error.message
    }));
    process.exit(1);
  }
}

main();
