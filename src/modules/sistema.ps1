# sistema.ps1 - preenche a pagina inicial com informacoes do pc

# detecta se o pc e gerenciado por empresa (dominio, azure ad, av corporativo)
function Detectar-AmbienteTrabalho {
    $achados = @()
    $dominio = ''
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PartOfDomain) { $dominio = [string]$cs.Domain }
    } catch { }
    if ($dominio -ne '') {
        $achados += ('ingressado no dominio: ' + $dominio)
    } elseif ($env:USERDNSDOMAIN) {
        $achados += ('variavel de dominio presente: ' + $env:USERDNSDOMAIN)
    }
    try {
        $saidaDs = (dsregcmd /status) 2>&1 | Out-String
        if ($saidaDs -match 'AzureAdJoined\s*:\s*YES') { $achados += 'ingressado no azure ad (entra da empresa)' }
    } catch { }
    try {
        $avs = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)mcafee|symantec|norton|crowdstrike|sentinel|sophos|trend micro|trendmicro|kaspersky|bitdefender|eset|malwarebytes|trellix|carbon black|cylance|f-secure|webroot|palo alto' })
        if ($avs.Count -gt 0) {
            $nomesAv = ($avs | Select-Object -First 3 | ForEach-Object { $_.DisplayName }) -join ', '
            $achados += ('antivirus de terceiros ativo: ' + $nomesAv)
        }
    } catch { }
    return @($achados)
}

# Recomendacoes conservadoras, sem modificar configuracoes.
function Obter-DiagnosticoLocal {
    param($OS, $Disco)
    $avisos = @()
    if ($OS.TotalVisibleMemorySize -gt 0) {
        $livre = 100.0 * $OS.FreePhysicalMemory / $OS.TotalVisibleMemorySize
        if ($livre -lt 10) { $avisos += 'Pouca RAM disponivel nesta amostra. Revise processos antes de aplicar ajustes.' }
    }
    if ($Disco.Size -gt 0) {
        $livre = 100.0 * $Disco.FreeSpace / $Disco.Size
        if ($livre -lt 15) { $avisos += 'Pouco espaco livre no disco do sistema. Revise arquivos e use a manutencao.' }
    }
    try {
        $inicio = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
        $avisos += ('Entradas de inicializacao detectadas: {0}. Revise no Gerenciador de Tarefas.' -f $inicio.Count)
    } catch { $avisos += 'Nao foi possivel consultar a inicializacao.' }
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        $avisos += 'Reinicio pendente detectado. Reinicie antes de aplicar ajustes.'
    }
    if (@($global:AmbienteTrabalho | Where-Object { $_ }).Count -gt 0) {
        $avisos += 'Possivel ambiente gerenciado. Consulte o administrador antes de alterar politicas.'
    }
    if ($avisos.Count -eq 0) { $avisos += 'Nenhum alerta nas verificacoes disponiveis.' }
    return ($avisos -join [Environment]::NewLine)
}

function Preencher-PaginaInicio {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpu = @(Get-CimInstance Win32_VideoController | Where-Object { $null -ne $_.Name })
        $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"

        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramLivre = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $discoTotal = [math]::Round($disco.Size / 1GB, 0)
        $discoLivre = [math]::Round($disco.FreeSpace / 1GB, 1)

        $uptime = (Get-Date) - $os.LastBootUpTime
        $upTexto = ('{0}d {1}h {2}min' -f $uptime.Days, $uptime.Hours, $uptime.Minutes)

        if ($global:UI.ContainsKey('InfoDiagnostico')) {
            $global:UI.InfoDiagnostico.Text = Obter-DiagnosticoLocal -OS $os -Disco $disco
        }

        $gpuTexto = ($gpu | ForEach-Object { $_.Name }) -join ', '

        if ($global:UI.ContainsKey('InfoHost')) { $global:UI.InfoHost.Text = $env:COMPUTERNAME }
        if ($global:UI.ContainsKey('InfoSo')) { $global:UI.InfoSo.Text = (Nome-Windows) }
        if ($global:UI.ContainsKey('InfoCpu')) { $global:UI.InfoCpu.Text = ('{0} ({1} nucleos / {2} threads)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors) }
        if ($global:UI.ContainsKey('InfoGpu')) { $global:UI.InfoGpu.Text = $gpuTexto }
        if ($global:UI.ContainsKey('InfoRam')) { $global:UI.InfoRam.Text = ('{0} GB (livre: {1} GB)' -f $ramTotal, $ramLivre) }
        if ($global:UI.ContainsKey('InfoDisco')) { $global:UI.InfoDisco.Text = ('{0}: {1} GB livres de {2} GB' -f $env:SystemDrive, $discoLivre, $discoTotal) }
        if ($global:UI.ContainsKey('InfoUptime')) { $global:UI.InfoUptime.Text = $upTexto }
        if ($global:UI.ContainsKey('InfoRestore')) {
            try {
                $pontos = @(Get-ComputerRestorePoint -ErrorAction Stop)
                if ($pontos.Count -gt 0) {
                    $global:UI.InfoRestore.Text = ('protecao ativa, {0} ponto(s) criado(s)' -f $pontos.Count)
                } else {
                    $global:UI.InfoRestore.Text = 'sem pontos de restauracao ainda'
                }
            } catch {
                $global:UI.InfoRestore.Text = 'protecao do sistema desativada'
            }
        }
        if ($global:UI.ContainsKey('InfoAmbiente')) {
            if ($null -ne $global:AmbienteTrabalho -and $global:AmbienteTrabalho.Count -gt 0) {
                $global:UI.InfoAmbiente.Text = ('gerenciado: ' + ($global:AmbienteTrabalho -join ' | '))
            } else {
                $global:UI.InfoAmbiente.Text = 'pc pessoal (sem dominio, sem av corporativo)'
            }
        }
    } catch {
        Log ('falha ao coletar informacoes do sistema: ' + $_.Exception.Message) -Erro
    }
}
