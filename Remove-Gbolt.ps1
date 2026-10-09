# Desinstala o Gbolt e fica vigiando: se ele for reinstalado, desinstala de novo.
#
# Uso (como administrador, ou deixe o script pedir elevacao sozinho):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Remove-Gbolt.ps1
#
# Na primeira execucao ele:
#   1. copia a si mesmo para C:\ProgramData\RemoveGbolt
#   2. desinstala o Gbolt, se estiver instalado
#   3. registra a tarefa "Remove-Gbolt" (SYSTEM) que roda no boot, no logon
#      e a cada hora com -Monitor, repetindo a desinstalacao se necessario.
# Log: C:\ProgramData\RemoveGbolt\log.txt
# Nao depende do Painel de Controle.

param([switch]$Monitor)

# Ajuste aqui se o nome no "Programas e Recursos" for diferente.
$PadraoNome  = '(?i)g[\s_-]?bolt'
$IntervaloH  = 1
$Pasta       = Join-Path $env:ProgramData 'RemoveGbolt'
$Log         = Join-Path $Pasta 'log.txt'
$TaskName    = 'Remove-Gbolt'

function Write-Log([string]$msg) {
    $linha = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $msg
    if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
    Add-Content -Path $Log -Value $linha
    if (-not $Monitor) { Write-Host $linha }
}

# 0. Auto-elevacao
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
        )
    } catch {
        Write-Warning 'Elevacao cancelada ou negada. Execute com uma conta de administrador.'
    }
    exit
}

function Get-GboltInstalado {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $chaves -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $PadraoNome }
}

function Uninstall-Gbolt {
    $apps = @(Get-GboltInstalado)
    if (-not $apps) { Write-Log 'Gbolt nao encontrado.'; return $false }

    # Encerra servicos e processos do Gbolt antes de desinstalar
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $PadraoNome -or $_.DisplayName -match $PadraoNome } |
        ForEach-Object { Write-Log "Parando servico $($_.Name)"; Stop-Service $_ -Force -ErrorAction SilentlyContinue }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $PadraoNome } |
        ForEach-Object { Write-Log "Encerrando processo $($_.ProcessName)"; Stop-Process $_ -Force -ErrorAction SilentlyContinue }

    foreach ($app in $apps) {
        Write-Log "Desinstalando: $($app.DisplayName) $($app.DisplayVersion)"
        $guid = $app.PSChildName
        if ($guid -match '^\{[0-9A-Fa-f-]{36}\}$') {
            $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        } elseif ($app.QuietUninstallString) {
            $p = Start-Process cmd.exe -ArgumentList "/c $($app.QuietUninstallString)" -Wait -PassThru
        } elseif ($app.UninstallString) {
            # Instalador nao-MSI sem modo silencioso declarado: tenta /S
            $p = Start-Process cmd.exe -ArgumentList "/c $($app.UninstallString) /S" -Wait -PassThru
        } else {
            Write-Log 'Sem UninstallString no registro; nada a executar.'
            continue
        }
        Write-Log "Codigo de saida: $($p.ExitCode) (3010 = reinicio pendente)"
    }

    if (Get-GboltInstalado) { Write-Log 'ATENCAO: Gbolt ainda consta como instalado.' }
    else { Write-Log 'Gbolt removido.' }
    return $true
}

# --- Modo vigia (tarefa agendada) ---
if ($Monitor) {
    Uninstall-Gbolt | Out-Null
    exit
}

# --- Modo instalacao ---
if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
$destino = Join-Path $Pasta 'Remove-Gbolt.ps1'
if ($PSCommandPath -ne $destino) { Copy-Item $PSCommandPath $destino -Force }

Uninstall-Gbolt | Out-Null

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destino`" -Monitor"
$triggers = @(
    New-ScheduledTaskTrigger -AtStartup
    New-ScheduledTaskTrigger -AtLogOn
    New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours $IntervaloH) -RepetitionDuration (New-TimeSpan -Days 3650)
)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
    -Description "Desinstala o Gbolt se for (re)instalado. Verifica a cada $IntervaloH h, no boot e no logon." -Force | Out-Null
Write-Log "Tarefa $TaskName registrada (boot, logon e a cada $IntervaloH h)."

Write-Host "`nConcluido. Log em $Log"
Read-Host 'Pressione Enter para fechar'
