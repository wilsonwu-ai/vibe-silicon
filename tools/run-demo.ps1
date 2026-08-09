<#
.SYNOPSIS
  Run the whole demo from a second Windows machine. Insurance for 8pm.

.DESCRIPTION
  Programs the bitstream, downloads the ELF over JTAG, and streams the model's
  output -- optionally forwarding it to the public page.

  This exists so that a dead laptop at 19:00 is an inconvenience rather than the
  end of the demo. Run it once before you need it.

.EXAMPLE
  .\run-demo.ps1 -Check
  .\run-demo.ps1
  .\run-demo.ps1 -Token vs_xxxxx      # also push to the public page

.NOTES
  The prebuilt DE10-Lite Computer is DUAL-CORE and ships without a .jdi, so the
  tools cannot tell which CPU you mean and refuse to connect at all:
     "There are two or more Nios II CPUs with debug modules available"
  Every command therefore carries --device 1 --instance 0. Instance 0 is the
  core the BSP targets. This cost real time to discover; do not remove it.
#>

param(
    [string]$Sof   = "Computer_System.sof",
    [string]$Elf   = "llama.elf",
    [string]$Token = "",
    [string]$Url   = "https://vibe-silicon.wilson-af8.workers.dev",
    [switch]$Check
)

$ErrorActionPreference = "Stop"

# The dual-core selector. Not optional -- see NOTES.
$DEV = @("--device", "1", "--instance", "0")
$CABLE = "USB-Blaster [USB-0]"

function Say($m, $c = "White") { Write-Host $m -ForegroundColor $c }
function Ok($m)   { Say "  [ok]   $m" Green }
function Warn($m) { Say "  [warn] $m" Yellow }
function Bad($m)  { Say "  [FAIL] $m" Red }

function Have($exe) { $null -ne (Get-Command $exe -ErrorAction SilentlyContinue) }

Say ""
Say "=== vibe-silicon :: second-machine demo runner ===" Cyan
Say ""

# ---------------------------------------------------------------- preflight
Say "Preflight" Cyan
$fail = $false

foreach ($t in @("quartus_pgm", "nios2-download", "nios2-terminal")) {
    if (Have $t) { Ok "$t found" }
    else { Bad "$t NOT found -- open a 'Nios II Command Shell', not a plain PowerShell"; $fail = $true }
}

# jtagconfig is the real test: is the board actually there?
if (Have "jtagconfig") {
    $jt = & jtagconfig 2>&1 | Out-String
    if ($jt -match "10M50") { Ok "board visible: $($jt.Trim() -split "`n" | Select-Object -First 1)" }
    else {
        Bad "jtagconfig does not see a 10M50."
        Say "         Driver lives under <quartus>\drivers -- point Device Manager at it." Yellow
        Say "         Raw output: $($jt.Trim())" DarkGray
        $fail = $true
    }
} else { Bad "jtagconfig not found"; $fail = $true }

foreach ($f in @(@($Sof, "bitstream"), @($Elf, "compiled model"))) {
    if (Test-Path $f[0]) {
        $kb = [math]::Round((Get-Item $f[0]).Length / 1KB)
        Ok "$($f[1]): $($f[0])  ($kb KB)"
    } else {
        Bad "$($f[1]) missing: $($f[0])  -- copy it from Justin"
        $fail = $true
    }
}

if (Have "python") { Ok "python found" } else { Warn "python not found -- bridge unavailable, demo still works" }

Say ""
if ($fail) { Bad "preflight failed. Fix the above before you need this."; exit 1 }
Ok "preflight passed"
Say ""

if ($Check) { Say "-Check only; stopping here." Cyan; exit 0 }

# ---------------------------------------------------------------- program
Say "1/3  Programming the FPGA" Cyan
& quartus_pgm -c $CABLE -m JTAG -o "p;$Sof"
if ($LASTEXITCODE -ne 0) { Bad "programming failed"; exit 1 }
Ok "bitstream loaded -- there is now a CPU on this chip"
Say ""

# ---------------------------------------------------------------- download
Say "2/3  Downloading the model over JTAG" Cyan
Say "     ~1.1 MB at roughly 58 KB/s, so expect 20-70 seconds. This is not a hang." DarkGray
& nios2-download -c $CABLE @DEV -g $Elf
if ($LASTEXITCODE -ne 0) {
    Bad "download failed"
    Say "     If it says two or more CPUs match: the --device/--instance flags were dropped." Yellow
    exit 1
}
Ok "loaded"
Say ""

# ---------------------------------------------------------------- run
Say "3/3  Running" Cyan
Say "     Expect: 'Once upon a time, there was a little girl named Lily...'" DarkGray
Say "     ~1.02 s/token, 256 tokens, so about four and a half minutes." DarkGray
Say ""

if ($Token) {
    if (-not (Test-Path "bridge.py")) { Bad "bridge.py not in this folder"; exit 1 }
    Say "     Forwarding to $Url  (page will read 'live from the board')" Green
    Say ""
    & python bridge.py --token $Token --url $Url --reset --cmd "nios2-terminal $($DEV -join ' ')"
} else {
    Say "     Local only. Pass -Token to also push to the public page." DarkGray
    Say ""
    & nios2-terminal @DEV
}

Say ""
Ok "done"
