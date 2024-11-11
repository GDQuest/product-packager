# Script to test and monitor the performance of the MDX parser across updates
import times, stats, strutils
import parser_mdx_component

proc performanceTest(source: string, iterations: int = 1000, runs: int = 10) =
  var timings: RunningStat

  echo "Running performance test..."
  echo "Source length: ", source.len, " characters"
  echo "Iterations per run: ", iterations
  echo "Number of runs: ", runs

  for run in 1..runs:
    let startTime = cpuTime()

    for i in 1..iterations:
      let tokens = parser_mdx_component.tokenize(source)
      var scanner = parser_mdx_component.TokenScanner(
        tokens: tokens,
        current: 0,
        source: source
      )
      discard parser_mdx_component.parseMdxDocumentBlocks(scanner)

    let duration = cpuTime() - startTime
    timings.push(duration)

  echo "---"
  echo "Total characters parsed: ", source.len * iterations * runs
  echo "Average time: ", formatFloat(timings.mean * 1000, ffDecimal, 2), "ms"
  echo "Min time: ", formatFloat(timings.min * 1000, ffDecimal, 2), "ms"
  echo "Max time: ", formatFloat(timings.max * 1000, ffDecimal, 2), "ms"

when isMainModule:
  const source = """
# Document heading

```gdscript
extends Node

func _ready():
print("Hello, World!")
```

Some more text.
"""

  performanceTest(source)
