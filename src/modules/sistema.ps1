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

# Inventario local, sem comandos de inicializacao, usuarios ou credenciais.
function Obter-InventarioLocal {
    $relatorio = [ordered]@{
        criado = (Get-Date -Format 'o')
        windows = (Nome-Windows)
        inicializacao = @()
        servicos = @()
        tarefas = @()
        discos = @()
        rede = @()
        avisos = @()
    }
    try {
        $relatorio.inicializacao = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Location | Sort-Object Name)
    } catch { $relatorio.avisos += 'Nao foi possivel consultar entradas de inicializacao.' }
    try {
        $relatorio.servicos = @(Get-Service -ErrorAction Stop | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ nome = $_.Name; descricao = $_.DisplayName; estado = $_.Status.ToString(); inicio = $_.StartType.ToString() }
        })
    } catch { $relatorio.avisos += 'Nao foi possivel consultar servicos.' }
    try {
        $relatorio.tarefas = @(Get-ScheduledTask -ErrorAction Stop | Sort-Object TaskPath, TaskName | ForEach-Object {
            [pscustomobject]@{ nome = $_.TaskName; caminho = $_.TaskPath; estado = $_.State.ToString() }
        })
    } catch { $relatorio.avisos += 'Nao foi possivel consultar tarefas agendadas.' }
    try {
        $relatorio.discos = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ unidade = $_.DeviceID; capacidadeGB = [math]::Round($_.Size / 1GB, 2); livreGB = [math]::Round($_.FreeSpace / 1GB, 2) }
        })
    } catch { $relatorio.avisos += 'Nao foi possivel consultar discos.' }
    try {
        $relatorio.rede = @(Get-NetAdapter -ErrorAction Stop | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ nome = $_.Name; estado = $_.Status.ToString(); velocidadeLink = [string]$_.LinkSpeed }
        })
    } catch { $relatorio.avisos += 'Nao foi possivel consultar adaptadores de rede.' }
    return [pscustomobject]$relatorio
}

# Analise limitada e somente leitura. Nao segue junctions nem links simbolicos.
function Analisar-Armazenamento {
    param([string]$Pasta, [ValidateRange(1,1000000)][int]$Limite = 100000, [ValidateRange(1,120)][int]$Segundos = 20)
    $raiz = Get-Item -LiteralPath $Pasta -ErrorAction Stop
    if (-not $raiz.PSIsContainer -or ($raiz.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Escolha uma pasta real, sem redirecionamento.' }
    $pilha = New-Object 'System.Collections.Generic.Stack[string]'
    $pilha.Push($raiz.FullName)
    $maiores = New-Object 'System.Collections.Generic.List[object]'
    $cron = [Diagnostics.Stopwatch]::StartNew()
    $contagem = 0
    $visitados = 0
    $bytes = [long]0
    $ignorados = 0
    $incompleto = $false
    while ($pilha.Count -gt 0 -and -not $incompleto) {
        $dir = $pilha.Pop()
        try {
            foreach ($caminho in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
                if ($cron.Elapsed.TotalSeconds -ge $Segundos -or $visitados -ge $Limite) { $incompleto = $true; break }
                $visitados++
                try {
                    $item = Get-Item -LiteralPath $caminho -Force -ErrorAction Stop
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $ignorados++; continue }
                    if ($item.PSIsContainer) { $pilha.Push($item.FullName); continue }
                    $contagem++
                    $bytes += [long]$item.Length
                    if ($maiores.Count -lt 30) {
                        $maiores.Add([pscustomobject]@{ caminho = $item.FullName; bytes = [long]$item.Length })
                    } else {
                        $menor = 0
                        for ($j = 1; $j -lt $maiores.Count; $j++) {
                            if ($maiores[$j].bytes -lt $maiores[$menor].bytes) { $menor = $j }
                        }
                        if ($item.Length -gt $maiores[$menor].bytes) {
                            $maiores[$menor] = [pscustomobject]@{ caminho = $item.FullName; bytes = [long]$item.Length }
                        }
                    }
                } catch { $ignorados++ }
            }
        } catch { $ignorados++ }
    }
    return [pscustomobject]@{ pasta = $raiz.FullName; arquivos = $contagem; bytes = $bytes; ignorados = $ignorados; parcial = ($incompleto -or $ignorados -gt 0); maiores = @($maiores | Sort-Object bytes -Descending) }
}

# Amostra observacional. Nao executa benchmark nem promete ganhos de desempenho.
function Medir-EstadoSistema {
    $cpu = @()
    $ram = @()
    $processos = @()
    for ($i = 0; $i -lt 3; $i++) {
        $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($null -eq $p -or $os.TotalVisibleMemorySize -le 0) { throw 'Contadores do sistema indisponiveis.' }
        $cpu += [double]$p.PercentProcessorTime
        $ram += [double]($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        $processos += @(Get-Process -ErrorAction Stop).Count
        if ($i -lt 2) { Start-Sleep -Seconds 1 }
    }
    $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
    if ($null -eq $disco) { throw 'Disco do sistema indisponivel.' }
    return [pscustomobject]@{
        formato = 'otimizadorpc-medicao-v1'
        criado = (Get-Date -Format 'o')
        maquina = $env:COMPUTERNAME
        build = [Environment]::OSVersion.Version.Build
        unidade = $env:SystemDrive
        ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        discoTotalGB = [math]::Round($disco.Size / 1GB, 2)
        cpuMedia = [math]::Round(($cpu | Measure-Object -Average).Average, 2)
        ramUsadaGB = [math]::Round(($ram | Measure-Object -Average).Average, 2)
        processosMedia = [math]::Round(($processos | Measure-Object -Average).Average, 2)
        discoLivreGB = [math]::Round($disco.FreeSpace / 1GB, 2)
        amostras = 3
    }
}

function Comparar-Medicoes {
    param($Antes, $Depois)
    foreach ($item in @($Antes,$Depois)) {
        if ($item.formato -ne 'otimizadorpc-medicao-v1' -or $item.amostras -ne 3) { throw 'Formato de medicao invalido.' }
        foreach ($campo in @('cpuMedia','ramUsadaGB','processosMedia','discoLivreGB','ramTotalGB','discoTotalGB')) {
            $v = $item.$campo
            if ($null -eq $v -or ($v -isnot [ValueType]) -or $v -is [bool]) { throw ('Campo numerico invalido: ' + $campo) }
            $n = [double]$v
            if ([double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt 0) { throw ('Valor invalido: ' + $campo) }
        }
        if ($item.cpuMedia -gt 100 -or $item.ramUsadaGB -gt $item.ramTotalGB -or $item.discoLivreGB -gt $item.discoTotalGB) { throw 'Medicao fora dos limites.' }
    }
    foreach ($campo in @('maquina','build','unidade','ramTotalGB','discoTotalGB')) {
        if ($null -eq $Antes.$campo -or $Antes.$campo -ne $Depois.$campo) { throw 'Medicoes de computadores ou configuracoes diferentes.' }
    }
    $linhas = @()
    foreach ($metrica in @(
        @{ campo='cpuMedia'; nome='CPU media (%)' },
        @{ campo='ramUsadaGB'; nome='RAM usada (GB)' },
        @{ campo='processosMedia'; nome='Processos (media)' },
        @{ campo='discoLivreGB'; nome='Disco livre (GB)' }
    )) {
        $v1 = [double]$Antes.($metrica.campo)
        $v2 = [double]$Depois.($metrica.campo)
        $linhas += [pscustomobject]@{ metrica=$metrica.nome; antes=$v1; depois=$v2; diferenca=[math]::Round($v2-$v1,2) }
    }
    return $linhas
}
