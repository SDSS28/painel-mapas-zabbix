# Remove o Diebold Network Monitor (wsddntf) e cria tarefa de contingencia.
# Nao mexe no wsddin64.sys (driver principal do Warsaw).
# Nao depende do Painel de Controle: usa apenas cmdlets, sc.exe e pnputil.
# Se nao estiver elevado, pede elevacao (UAC) sozinho.

# 0. Auto-elevacao
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
        )
    } catch {
        Write-Warning "Elevacao cancelada ou negada. Execute com uma conta de administrador."
    }
    exit
}

$svc = "wsddntf"
$sys = "$env:SystemRoot\System32\drivers\wsddntf.sys"

# 1. Parar, desabilitar e deletar o servico
if (Get-CimInstance Win32_SystemDriver -Filter "Name='$svc'" -ErrorAction SilentlyContinue) {
    sc.exe stop $svc | Out-Null
    sc.exe config $svc start= disabled | Out-Null
    sc.exe delete $svc | Out-Null
    Write-Host "[OK] Servico $svc removido"
} else {
    Write-Host "[--] Servico $svc nao encontrado"
}

# 2. Remover o pacote do Driver Store (oemXX.inf detectado dinamicamente)
$pacotes = Get-WindowsDriver -Online -All | Where-Object { $_.OriginalFileName -match 'wsddntf\.inf$' }
if ($pacotes) {
    foreach ($p in $pacotes) {
        pnputil.exe /delete-driver $p.Driver /uninstall | Out-Null
        Write-Host "[OK] Pacote $($p.Driver) removido"
    }
} else {
    Write-Host "[--] Nenhum pacote wsddntf.inf no Driver Store"
}

# 3. Apagar o .sys (falha se o driver ainda estiver carregado: precisa reiniciar)
if (Test-Path $sys) {
    try {
        Remove-Item $sys -Force -ErrorAction Stop
        Write-Host "[OK] $sys removido"
    } catch {
        Write-Warning "$sys em uso. Reinicie e apague manualmente (ou rode o script de novo)."
    }
}

# 4. Tarefa de contingencia (SYSTEM): desabilita o binding no boot e diariamente.
#    Casa por *Diebold* em qualquer adaptador, sem depender de nome de adaptador.
$cmd = 'Get-NetAdapterBinding -AllBindings -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ''*Diebold*'' -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID $_.ComponentID -ErrorAction SilentlyContinue }'
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "{0}"' -f $cmd)
$triggers = @(
    New-ScheduledTaskTrigger -AtStartup
    New-ScheduledTaskTrigger -Daily -At 8:00AM
)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName "Disable-DieboldNetworkMonitor" -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "Desabilita binding do Diebold Network Monitor" -Force | Out-Null
Write-Host "[OK] Tarefa Disable-DieboldNetworkMonitor registrada"

Write-Host "`nConcluido. Reinicie o computador."
Read-Host "Pressione Enter para fechar"
