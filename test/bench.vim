vim9script
# ============================================================================
# LLM POWERED
#
# Developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
# ============================================================================
# zen.vim micro-benchmarks
#
# Run with:  sh test/bench.sh
#
# Prints median/min/max wall time per operation.  Not part of the test suite.
# The result is written to $ZEN_BENCH_OUT when set.
# ============================================================================

set nocompatible
set nomore noswapfile
set columns=200 lines=60

var lines: list<string> = []

def Report(s: string)
  lines->add(s)
enddef

# Time reps calls of Fn() per round, rounds times; report median/min/max per
# call in milliseconds.
def Stat(name: string, reps: number, rounds: number, Fn: func)
  var samples: list<float> = []
  for _r in range(rounds)
    var t = reltime()
    for _i in range(reps)
      Fn()
    endfor
    samples->add(reltimefloat(reltime(t)) * 1000.0 / reps)
  endfor
  samples->sort()
  Report(printf('%-26s median=%7.3fms  min=%7.3fms  max=%7.3fms',
    name, samples[len(samples) / 2], samples[0], samples[len(samples) - 1]))
enddef

def OnOff()
  zen#Open('80x20')
  zen#Close()
enddef

try
Stat('ZenOn + ZenOff', 20, 11, OnOff)

zen#Open('80x20')
Stat('Re-layout (active session)', 100, 11, () => zen#Open('80x20'))
zen#Close()

# Open a full-width window while Zen is active; ConfineWindows() has to
# pull it back into the content column.  A one-line scratch buffer is used so
# the benchmark does not depend on the size of the help files.
def WithStray()
  zen#Open('80x20')
  topleft new
  zen#Close()
  silent! only!
  silent! enew!
  setlocal nomodified
enddef
Stat('On + stray split + Off', 10, 9, WithStray)
catch
  Report('benchmark aborted: ' .. v:exception)
endtry

var out = getenv('ZEN_BENCH_OUT')
if empty(out)
  out = '/tmp/zen-bench.txt'
endif
writefile(lines, out)
qall!
