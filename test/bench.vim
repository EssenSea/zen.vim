vim9script
# ============================================================================
# goyo.vim micro-benchmarks
#
# Run with:  sh test/bench.sh
#
# Prints median/min/max wall time per operation.  Not part of the test suite.
# The result is written to $GOYO_BENCH_OUT when set.
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
  goyo#Execute(false, '80x20')
  goyo#Execute(true, '')
enddef

try
Stat('GoyoOn + GoyoOff', 20, 11, OnOff)

goyo#Execute(false, '80x20')
Stat('Resize (active session)', 100, 11, () => goyo#Resize())
goyo#Execute(true, '')

# Open a full-width window while Goyo is active; ConfineWindows() has to
# pull it back into the content column.  A one-line scratch buffer is used so
# the benchmark does not depend on the size of the help files.
def WithStray()
  goyo#Execute(false, '80x20')
  topleft new
  goyo#Execute(true, '')
  silent! only!
  silent! enew!
  setlocal nomodified
enddef
Stat('On + stray split + Off', 10, 9, WithStray)
catch
  Report('benchmark aborted: ' .. v:exception)
endtry

var out = getenv('GOYO_BENCH_OUT')
if empty(out)
  out = '/tmp/goyo-bench.txt'
endif
writefile(lines, out)
qall!
