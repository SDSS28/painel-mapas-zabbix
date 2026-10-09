# Remove o Diebold Network Monitor (driver wsddntf) e fica vigiando:
# se ele for reinstalado, remove de novo.
# Nao mexe no wsddin64.sys (driver principal do Warsaw).
#
# Uso (pede elevacao sozinho se precisar):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Remove-DieboldNetworkMonitor.ps1
#
# Na primeira execucao ele:
#   1. copia a si mesmo para C:\ProgramData\RemoveDiebold
#   2. remove o Diebold Network Monitor
#   3. registra a tarefa "Remove-DieboldNetworkMonitor" (SYSTEM) que roda no boot,
#      no logon e a cada hora com -Monitor.
# Log: C:\ProgramData\RemoveDiebold\log.txt
# Nao depende do Painel de Controle.

param([switch]$Monitor)

$IntervaloH = 1
# Opcional: regex do nome de um PROGRAMA (Programas e Recursos) a desinstalar.
# Vazio = nao desinstala programa nenhum. Cuidado: 'Diebold' puro pode pegar o Warsaw.
$PadraoApp  = ''
$Pasta      = Join-Path $env:ProgramData 'RemoveDiebold'
$Log        = Join-Path $Pasta 'log.txt'
$TaskName   = 'Remove-DieboldNetworkMonitor'
$svc        = 'wsddntf'
$sys        = "$env:SystemRoot\System32\drivers\wsddntf.sys"

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

function Remove-DieboldNetworkMonitor {
    $achou = $false

    # 1. Servico/driver
    if (Get-CimInstance Win32_SystemDriver -Filter "Name='$svc'" -ErrorAction SilentlyContinue) {
        $achou = $true
        sc.exe stop $svc | Out-Null
        sc.exe config $svc start= disabled | Out-Null
        sc.exe delete $svc | Out-Null
        Write-Log "Servico $svc removido"
    }

    # 2. Pacote no Driver Store
    $pacotes = Get-WindowsDriver -Online -All -ErrorAction SilentlyContinue | Where-Object { $_.OriginalFileName -match 'wsddntf\.inf$' }
    foreach ($p in $pacotes) {
        $achou = $true
        pnputil.exe /delete-driver $p.Driver /uninstall | Out-Null
        Write-Log "Pacote $($p.Driver) removido do Driver Store"
    }

    # 3. Binding nos adaptadores (independe de idioma e de nome de adaptador)
    Get-NetAdapterBinding -AllBindings -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Diebold*' -and $_.Enabled } |
        ForEach-Object {
            $achou = $true
            Disable-NetAdapterBinding -Name $_.Name -ComponentID $_.ComponentID -ErrorAction SilentlyContinue
            Write-Log "Binding '$($_.DisplayName)' desabilitado em $($_.Name)"
        }

    # 4. Arquivo .sys (falha se o driver ainda estiver carregado: apaga apos reinicio)
    if (Test-Path $sys) {
        $achou = $true
        try { Remove-Item $sys -Force -ErrorAction Stop; Write-Log "$sys removido" }
        catch { Write-Log "$sys em uso; sera removido na proxima verificacao apos reinicio." }
    }

    # 5. Programa instalado (somente se $PadraoApp estiver preenchido)
    if ($PadraoApp) {
        $chaves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty -Path $chaves -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $PadraoApp } |
            ForEach-Object {
                $achou = $true
                Write-Log "Desinstalando programa: $($_.DisplayName)"
                if ($_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                    Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait
                } elseif ($_.QuietUninstallString) {
                    Start-Process cmd.exe -ArgumentList "/c $($_.QuietUninstallString)" -Wait
                } elseif ($_.UninstallString) {
                    Start-Process cmd.exe -ArgumentList "/c $($_.UninstallString) /S" -Wait
                }
            }
    }

    if (-not $achou) { Write-Log 'Nada do Diebold Network Monitor encontrado.' }
}

if ($Monitor) { Remove-DieboldNetworkMonitor; exit }

# --- Modo instalacao ---
if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
$destino = Join-Path $Pasta 'Remove-DieboldNetworkMonitor.ps1'
if ($PSCommandPath -ne $destino) { Copy-Item $PSCommandPath $destino -Force }

Remove-DieboldNetworkMonitor

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destino`" -Monitor"
$triggers = @(
    New-ScheduledTaskTrigger -AtStartup
    New-ScheduledTaskTrigger -AtLogOn
    New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours $IntervaloH) -RepetitionDuration (New-TimeSpan -Days 3650)
)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
    -Description "Remove o Diebold Network Monitor se reaparecer. Verifica a cada $IntervaloH h, no boot e no logon." -Force | Out-Null
Write-Log "Tarefa $TaskName registrada (boot, logon e a cada $IntervaloH h)."

# Remove a tarefa antiga, se existir
Unregister-ScheduledTask -TaskName 'Disable-DieboldNetworkMonitor' -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "`nConcluido. Reinicie o computador. Log em $Log"
Read-Host 'Pressione Enter para fechar'
