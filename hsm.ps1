$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Usage {
  @"
Hytale Server Manager (wrapper)

Usage: .\\hsm.ps1 <command> [args...]

Commands:
  manager <args>    Run scripts/manager.sh (default)
  gui              Launch instance GUI (PyQt6)
  mod-gui          Launch mod tools GUI (PyQt6)
  install-deps     Install local dependencies (Debian/Ubuntu via WSL)
  setup            Run scripts/setup.sh
  build            Run scripts/build.sh
  download <inst>  Run scripts/download.sh <instance>
  auth <inst>      Run scripts/auth.sh <instance>
  help             Show this help
"@ | Write-Host
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { "manager" }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }

switch ($cmd) {
  "manager" { & wsl bash "$RootDir/scripts/manager.sh" @rest; break }
  "gui" { & python "$RootDir/gui/app.py"; break }
  "mod-gui" { & python "$RootDir/mod_tools/app.py"; break }
  "install-deps" { & wsl bash "$RootDir/scripts/install-deps.sh"; break }
  "setup" { & wsl bash "$RootDir/scripts/setup.sh"; break }
  "build" { & wsl bash "$RootDir/scripts/build.sh"; break }
  "download" { & wsl bash "$RootDir/scripts/download.sh" @rest; break }
  "auth" { & wsl bash "$RootDir/scripts/auth.sh" @rest; break }
  "help" { Show-Usage; break }
  default { Write-Error "Unknown command: $cmd"; Show-Usage; exit 1 }
}
