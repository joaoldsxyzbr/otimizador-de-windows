# sistema.ps1 - preenche a pagina inicial com informacoes do pc

# detecta se o pc e gerenciado por empresa (dominio, azure ad, av corporativo)
function Detectar-AmbienteTrabalho {
    $achados=@()
    try {
        $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($null -eq $cs.PartOfDomain) { throw 'Estado de dominio ausente.' }
        if ($cs.PartOfDomain -or $env:USERDNSDOMAIN) { $achados+='Dominio ou conta de dominio detectado.' }
    } catch { $achados+='Inconclusivo: consulta de dominio indisponivel.' }
    try {
        $exe=Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
        $saida=(& $exe /status 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $saida -notmatch 'AzureAdJoined\s*:\s*(YES|NO)' -or $saida -notmatch 'DomainJoined\s*:\s*(YES|NO)') { throw 'Estado de registro indisponivel.' }
        if ($saida -match '(AzureAdJoined|DomainJoined|EnterpriseJoined|WorkplaceJoined)\s*:\s*YES') { $achados+='Registro ou ingresso organizacional detectado.' }
    } catch { $achados+='Inconclusivo: registro Entra/organizacional nao confirmado.' }
    try {
        $raiz='HKLM:\SOFTWARE\Microsoft\Enrollments'
        if (Test-Path -LiteralPath $raiz -ErrorAction Stop) {
            foreach ($ch in @(Get-ChildItem -LiteralPath $raiz -ErrorAction Stop | Where-Object {$_.PSChildName -match '^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$'})) {
                $v=Get-ItemProperty -LiteralPath $ch.PSPath -ErrorAction Stop
                if ($v.EnrollmentState -eq 1 -and ($v.ProviderID -or $v.EnrollmentType)) { $achados+='Sinal de inscricao de gerenciamento de dispositivo (MDM).'; break }
            }
        }
        $wu='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        if (Test-Path -LiteralPath $wu -ErrorAction Stop) {
            $v=Get-ItemProperty -LiteralPath $wu -ErrorAction Stop
            if ($v.WUServer -or $v.WUStatusServer -or $v.SetPolicyDrivenUpdateSourceForQualityUpdates -eq 1) { $achados+='Sinal de politica de atualizacao organizacional.' }
        }
    } catch { $achados+='Inconclusivo: consulta de gerenciamento/politicas indisponivel.' }
    try {
        $avs=@(Get-Service -ErrorAction Stop | Where-Object {
            ($_.Name+' '+$_.DisplayName) -match '(?i)mcafee|symantec|norton|crowdstrike|sentinel|sophos|trend micro|trendmicro|kaspersky|bitdefender|eset|malwarebytes|trellix|carbon black|cylance|f-secure|webroot|palo alto|intunemanagementextension|ccmexec|tanium|sense\b'
        })
        if ($avs.Count -gt 0) { $achados+='Sinal de seguranca de terceiros ou gerenciamento; pode ser PC pessoal.' }
    } catch { $achados+='Inconclusivo: consulta de agentes/servicos indisponivel.' }
    $achados+=@(Obter-SinaisRedeGerenciada)
    return @($achados | Sort-Object -Unique)
}

# Consulta local de sinais, sem leitura de certificados, URLs ou credenciais.
function Obter-SinaisRedeGerenciada {
    $sinais=@()
    try {
        foreach ($hive in @('HKLM','HKCU')) {
            $p=$hive+':\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings'
            if (Test-Path -LiteralPath $p -ErrorAction Stop) {
                $v=Get-ItemProperty -LiteralPath $p -ErrorAction Stop
                if ($null -ne $v.ProxySettingsPerUser -or $null -ne $v.ProxyEnable -or $v.ProxyServer -or $v.AutoConfigURL) { $sinais+='Sinal de politica de proxy.'; break }
            }
        }
        $p='HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment'
        if (Test-Path -LiteralPath $p -ErrorAction Stop) {
            $v=Get-ItemProperty -LiteralPath $p -ErrorAction Stop
            if ($v.AEPolicy -gt 0) { $sinais+='Sinal de politica de inscricao automatica de certificados.' }
        }
    } catch { $sinais+='Inconclusivo: politicas de rede/certificados.' }
    try {
        if (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue) {
            $perfis=@(Get-VpnConnection -ErrorAction Stop)+@(Get-VpnConnection -AllUserConnection -ErrorAction Stop)
            if ($perfis.Count -gt 0) { $sinais+='Perfil VPN nativo detectado; pode ser pessoal.' }
        } else { $sinais+='Inconclusivo: consulta VPN nativa indisponivel.' }
    } catch { $sinais+='Inconclusivo: consulta VPN nativa falhou.' }
    return @($sinais | Sort-Object -Unique)
}

# Consultas independentes: falhas nao viram zero ou estado saudavel.
function Obter-DiagnosticoAvancado {
    $linhas=@()
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $linhas+=('Windows: {0} | edicao {1} | versao {2} | build {3}.{4}' -f $os.Caption,$cv.EditionID,$cv.DisplayVersion,$os.BuildNumber,$cv.UBR)
        if ([int]$os.BuildNumber -eq 19045) { $linhas+='Windows 10 22H2: suporte regular encerrado; verificar ESU ou ciclo de vida aplicavel com TI.' }
    } catch { $linhas+='Edicao/build indisponivel.' }
    try {
        $discos=@(Get-PhysicalDisk -ErrorAction Stop)
        if (-not $discos.Count) { $linhas+='Nenhum disco fisico informado pelo provedor.' }
        foreach ($d in $discos) {
            $linhas+=('Disco: {0} | midia {1} | saude reportada {2}' -f $d.FriendlyName,$d.MediaType,$d.HealthStatus)
            try {
                $rel=$d | Get-StorageReliabilityCounter -ErrorAction Stop
                $temperatura=if ($null -ne $rel.Temperature -and $rel.Temperature -gt 0) { "$($rel.Temperature) C" } else {'indisponivel'}
                $desgaste=if ($null -ne $rel.Wear) {"$($rel.Wear)% reportado"} else {'indisponivel'}
                $linhas+=('  Temperatura: '+$temperatura+'; desgaste: '+$desgaste+' (quando reportados; nao e previsao de falha).')
            } catch { $linhas+='  Contadores de confiabilidade indisponiveis.' }
        }
    } catch { $linhas+='Consulta de discos fisicos indisponivel.' }
    try {
        $dev=@(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop)
        $linhas+=('Dispositivos com codigo PnP diferente de zero: '+$dev.Count+' (inclui dispositivos desabilitados; nao implica falha).')
        foreach ($d in @($dev | Select-Object -First 10)) { $linhas+=('  '+$d.Name+' | codigo '+$d.ConfigManagerErrorCode) }
    } catch { $linhas+='Consulta PnP indisponivel.' }
    try {
        $f=@{LogName='System';Level=@(1,2);StartTime=(Get-Date).AddDays(-7)}
        $ev=@(Get-WinEvent -FilterHashtable $f -MaxEvents 200 -ErrorAction Stop)
        $linhas+=('Eventos criticos/erro do sistema nos ultimos 7 dias: '+$ev.Count+' na amostra (limite 200).')
        foreach ($grupo in @($ev | Group-Object ProviderName,Id | Sort-Object Count -Descending | Select-Object -First 8)) { $linhas+=('  '+$grupo.Name+' | '+$grupo.Count+' ocorrencias') }
        $linhas+='Eventos sao evidencias para investigar, nao diagnostico de causa. Mensagens e identificadores pessoais nao sao coletados.'
    } catch {
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { $linhas+='Nenhum evento critico/erro encontrado no periodo consultado.' }
        else { $linhas+='Consulta de eventos indisponivel.' }
    }
    try {
        $bat=@(Get-CimInstance Win32_Battery -ErrorAction Stop)
        if ($bat.Count) { $linhas+='Bateria detectada. Avalie autonomia e temperatura antes de ajustes de energia.' }
        else { $linhas+='Nenhuma bateria informada por CIM.' }
    } catch { $linhas+='Estado de bateria indisponivel.' }
    return ($linhas -join [Environment]::NewLine)
}

# Somente leitura, sem gravar relatorios nem expor identificadores de bateria.
function Obter-ResumoBateria {
    try {
        $bat=@(Get-CimInstance Win32_Battery -ErrorAction Stop)
        if (-not $bat.Count) { return 'Nenhuma bateria informada pelo Windows; pode ser desktop ou provedor indisponivel.' }
        $linhas=@()
        foreach ($b in $bat) {
            $carga=if ($null -ne $b.EstimatedChargeRemaining -and $b.EstimatedChargeRemaining -ge 0 -and $b.EstimatedChargeRemaining -le 100) { "$($b.EstimatedChargeRemaining)%" } else {'indisponivel'}
            $linhas+=('Carga atual: '+$carga+' | codigo de estado: '+$b.BatteryStatus)
        }
        try {
            $projeto=@(Get-CimInstance -Namespace root/WMI -ClassName BatteryStaticData -ErrorAction Stop)
            $cheia=@(Get-CimInstance -Namespace root/WMI -ClassName BatteryFullChargedCapacity -ErrorAction Stop)
            $n=0
            foreach ($p in $projeto) {
                $f=@($cheia | Where-Object {$_.InstanceName -eq $p.InstanceName})
                if ($f.Count -ne 1 -or $p.DesignedCapacity -le 0 -or $p.DesignedCapacity -ge 4294967295 -or $f[0].FullChargedCapacity -le 0 -or $f[0].FullChargedCapacity -ge 4294967295) {continue}
                $n++
                $pct=[math]::Round(100.0*$f[0].FullChargedCapacity/$p.DesignedCapacity,1)
                $linhas+=('Bateria {0}: projeto {1} mWh, carga cheia estimada {2} mWh, proporcao {3}%' -f $n,$p.DesignedCapacity,$f[0].FullChargedCapacity,$pct)
                if ($pct -lt 70) {$linhas+='Capacidade estimada reduzida; investigue autonomia com o fabricante/TI.'}
            }
            if (-not $n) {$linhas+='Capacidade de projeto/carga cheia indisponivel ou nao correlacionada.'}
        } catch {$linhas+='Contadores de capacidade indisponiveis.'}
        $linhas+='Valores do firmware sao estimativas; nao indicam risco fisico nem garantem autonomia.'
        return ($linhas -join [Environment]::NewLine)
    } catch {return 'Consulta de bateria indisponivel.'}
}

# Amostra observacional, sem ETW, sem exportar nomes ou comand lines.
function Medir-GargalosLocais {
    param([ValidateRange(3,20)][int]$Amostras=10)
    $serie=@()
    for ($i=0;$i -lt $Amostras;$i++) {
        $cpu=$null; $ram=$null; $leituras=$null; $fila=$null; $transferencias=$null
        try {
            $p=Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
            if ($null -ne $p.PercentProcessorTime) {$cpu=[double]$p.PercentProcessorTime}
        } catch {}
        try {
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os.TotalVisibleMemorySize -gt 0 -and $null -ne $os.FreePhysicalMemory) {$ram=[math]::Round(100.0*$os.FreePhysicalMemory/$os.TotalVisibleMemorySize,1)}
        } catch {}
        try {
            $mem=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
            if ($null -ne $mem.PageReadsPersec) {$leituras=[double]$mem.PageReadsPersec}
        } catch {}
        try {
            $disk=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop
            if ($null -ne $disk.AvgDiskQueueLength) {$fila=[double]$disk.AvgDiskQueueLength}
            if ($null -ne $disk.DiskTransfersPersec) {$transferencias=[double]$disk.DiskTransfersPersec}
        } catch {}
        $serie+=[pscustomobject]@{amostra=$i+1;CPU_pct=$cpu;RAM_livre_pct=$ram;PageReads_s=$leituras;Fila_disco=$fila;IO_s=$transferencias}
        if ($i -lt ($Amostras-1)) {Start-Sleep -Seconds 1}
    }
    $avisos=@()
    $cpuValidos=@($serie | Where-Object {$null -ne $_.CPU_pct})
    $ramValidos=@($serie | Where-Object {$null -ne $_.RAM_livre_pct})
    if ($cpuValidos.Count -lt $Amostras) {$avisos+='CPU: amostras incompletas.'}
    if ($ramValidos.Count -lt $Amostras) {$avisos+='RAM: amostras incompletas.'}
    if ($cpuValidos.Count -eq $Amostras -and @($cpuValidos | Where-Object {$_.CPU_pct -ge 90}).Count -ge [math]::Ceiling($Amostras*0.8)) {$avisos+='CPU elevada na maior parte desta janela. Investigue processos; nao desative servicos automaticamente.'}
    if ($ramValidos.Count -eq $Amostras -and @($ramValidos | Where-Object {$_.RAM_livre_pct -lt 10}).Count -ge [math]::Ceiling($Amostras*0.8)) {$avisos+='Pouca RAM livre na maior parte desta janela. Correlacione com atividade de paginacao e aplicativos.'}
    $avisos+='Fila e I/O de disco dependem da midia/carga; sem limiar universal. Celulas vazias significam indisponivel. Amostras nao demonstram causa nem ganho de desempenho.'
    return [pscustomobject]@{serie=$serie;avisos=$avisos}
}

# Inventario de dispositivos presentes; nao remove, atualiza ou reinstala drivers.
function Obter-ResumoDriversPnP {
    try {
        $devs=@(Get-PnpDevice -PresentOnly -ErrorAction Stop)
        $drivers=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)
        $mapa=@{}
        foreach ($d in $drivers) {
            if (-not $d.DeviceID) {continue}
            if (-not $mapa.ContainsKey([string]$d.DeviceID)) {$mapa[[string]$d.DeviceID]=@()}
            $mapa[[string]$d.DeviceID]+=$d
        }
        $linhas=@('Dispositivos presentes: '+$devs.Count)
        $problemas=@($devs | Where-Object {$_.Status -ne 'OK'})
        $linhas+=('Estado diferente de OK: '+$problemas.Count+' (inclui desabilitados e desconhecidos).')
        $semAssoc=0;$assinaturaNaoConfirmada=0
        foreach ($dev in $devs) {
            $ds=@()
            if ($dev.InstanceId -and $mapa.ContainsKey([string]$dev.InstanceId)) {$ds=@($mapa[[string]$dev.InstanceId])}
            if ($ds.Count -ne 1) {$semAssoc++;continue}
            if ($ds[0].IsSigned -ne $true) {$assinaturaNaoConfirmada++}
        }
        $linhas+=('Sem associacao unica a driver: '+$semAssoc+' | driver associado sem indicador de assinatura positiva: '+$assinaturaNaoConfirmada)
        foreach ($dev in @($problemas | Select-Object -First 15)) {
            $nome=if ($dev.FriendlyName) {$dev.FriendlyName} else {'Dispositivo sem nome'}
            $linhas+=($nome+' | estado '+$dev.Status+' | codigo '+$dev.ConfigManagerErrorCode)
            if ($dev.InstanceId -and $mapa.ContainsKey([string]$dev.InstanceId) -and $mapa[[string]$dev.InstanceId].Count -eq 1) {
                $d=$mapa[[string]$dev.InstanceId][0]
                $linhas+=('  Driver: '+$d.DriverProviderName+' | versao '+$d.DriverVersion+' | assinatura reportada '+$d.IsSigned)
            } else {$linhas+='  Associacao de driver indisponivel ou ambigua.'}
        }
        if ($problemas.Count -gt 15) {$linhas+='Lista de detalhes limitada a 15 dispositivos.'}
        $linhas+='Metadados do Windows, nao verificacao criptografica de cada arquivo. Nao identifica pacotes dispensaveis. Use o Gerenciador de Dispositivos ou consulte TI.'
        return ($linhas -join [Environment]::NewLine)
    } catch {return 'Inventario PnP ou drivers indisponivel. Nenhuma conclusao de saude.'}
}

function Resolver-ModoOtimizador {
    param([bool]$Admin,[bool]$Diagnostico,$Sinais,[bool]$Pessoal=$false)
    # decisao do joao (v2): administrador explicito libera o uso completo.
    # sinais de gerenciamento continuam detectados e informados no inicio/log,
    # mas nao bloqueiam quem abriu como admin; -Diagnostico continua forcando consulta.
    if ($Diagnostico -or -not $Admin) { return 'Diagnostico' }
    if (@($Sinais | Where-Object {$_}).Count -gt 0) { return 'Administrador (sinais de gerenciamento detectados; revise-os abaixo)' }
    return 'Administrador'
}

function Inicializar-ModoOtimizador {
    param([switch]$Diagnostico,[switch]$Pessoal)
    $global:ModoProtegido=$true
    $global:AmbienteTrabalho=@(Detectar-AmbienteTrabalho)
    $ctx=Obter-ContextoAjustes
    if (-not $ctx -or -not $ctx.cliente -or $ctx.build -lt 10240) { $global:AmbienteTrabalho+= 'Windows cliente compativel nao confirmado; modo protegido.' }
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($id)
        $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } finally { $id.Dispose() }
    $global:ModoOtimizador=Resolver-ModoOtimizador -Admin $admin -Diagnostico ([bool]$Diagnostico) -Sinais $global:AmbienteTrabalho -Pessoal ([bool]$Pessoal)
    $global:ModoProtegido=($global:ModoOtimizador -eq 'Diagnostico')
}

# Recomendacoes conservadoras, sem modificar configuracoes.
function Obter-DiagnosticoLocal {
    param($OS, $Disco)
    $avisos = @()
    if ($OS.TotalVisibleMemorySize -gt 0) {
        if ($OS.TotalVisibleMemorySize -lt 8MB) { $avisos += 'Menos de 8 GB de RAM visivel: priorize revisar inicializacao e processos; evite ajustes agressivos.' }
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
    if ($global:ModoProtegido) { $avisos += 'Modo protegido: somente diagnostico. Consulte o TI antes de qualquer alteracao.' }
    elseif (@($global:AmbienteTrabalho | Where-Object { $_ }).Count -gt 0) { $avisos += 'Possivel ambiente gerenciado. Consulte o administrador.' }
    try {
        if (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0) { $avisos += 'Bateria detectada: prefira o perfil Notebook e preserve economia de energia.' }
        else { $avisos += 'Use o perfil Essencial como ponto de partida; nao ha ganho de FPS garantido.' }
    } catch { $avisos += 'Tipo de alimentacao nao confirmado.' }
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
                    $global:UI.InfoRestore.Text = ('{0} ponto(s) listado(s); protecao atual nao confirmada' -f $pontos.Count)
                } else {
                    $global:UI.InfoRestore.Text = 'sem pontos de restauracao ainda'
                }
            } catch {
                $global:UI.InfoRestore.Text = 'estado da restauracao indisponivel'
            }
        }
        if ($global:UI.ContainsKey('InfoAmbiente')) {
            if ($null -ne $global:AmbienteTrabalho -and $global:AmbienteTrabalho.Count -gt 0) {
                $global:UI.InfoAmbiente.Text = ($global:ModoOtimizador + ': ' + ($global:AmbienteTrabalho -join ' | '))
            } else {
                $global:UI.InfoAmbiente.Text = ($global:ModoOtimizador + ' - nenhum sinal consultado; nao comprova ausencia de gerenciamento.')
            }
        }
    } catch {
        Log ('falha ao coletar informacoes do sistema: ' + $_.Exception.Message) -Erro
    }
}

# Inventario local, sem comandos de inicializacao, usuarios ou credenciais.
function Obter-InventarioLocal {
    param([bool]$Protegido=$true)
    $relatorio = [ordered]@{
        criado = (Get-Date -Format 'o')
        windows = ('{0} (build {1})' -f $(if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }),[Environment]::OSVersion.Version.Build)
        inicializacao = @()
        runUsuario = @()
        servicos = @()
        tarefas = @()
        discos = @()
        rede = @()
        drivers = @()
        processos = @()
        avisos = @()
    }
    try {
        $relatorio.inicializacao = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Location | Sort-Object Name)
    } catch { $relatorio.avisos += 'Nao foi possivel consultar entradas de inicializacao.' }
    try {
        $chave = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
        if ($chave) {
            try { $relatorio.runUsuario = @($chave.GetValueNames() | ForEach-Object { [pscustomobject]@{ nome=$_; tipo=$chave.GetValueKind($_).ToString(); valor=$(if ($Protegido) {'(oculto no modo protegido)'} else {$chave.GetValue($_,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}) } }) }
            finally { $chave.Dispose() }
        }
    } catch { $relatorio.avisos += 'Nao foi possivel consultar Run do usuario.' }
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
    try {
        $relatorio.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceName } | Select-Object DeviceName,DriverVersion,DriverProviderName,IsSigned | Sort-Object DeviceName)
    } catch { $relatorio.avisos += 'Nao foi possivel consultar drivers.' }
    try {
        $relatorio.processos = @(Get-Process -ErrorAction Stop | Sort-Object WorkingSet64 -Descending | Select-Object -First 100 | ForEach-Object {
            [pscustomobject]@{ nome=$_.ProcessName; pid=$_.Id; memoriaMB=[math]::Round($_.WorkingSet64 / 1MB,1) }
        })
    } catch { $relatorio.avisos += 'Nao foi possivel consultar processos.' }
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
    param([ValidateRange(3,30)][int]$Amostras=3,[string]$Cenario='')
    $cpu = @()
    $ram = @()
    $processos = @()
    $serie = @()
    for ($i = 0; $i -lt $Amostras; $i++) {
        $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($null -eq $p -or $os.TotalVisibleMemorySize -le 0) { throw 'Contadores do sistema indisponiveis.' }
        $cpu += [double]$p.PercentProcessorTime
        $ram += [double]($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        $processos += @(Get-Process -ErrorAction Stop).Count
        $serie += [pscustomobject]@{ segundo=$i; cpuPct=$cpu[-1]; ramGB=[math]::Round($ram[-1],2); processos=$processos[-1] }
        if ($i -lt ($Amostras-1)) { Start-Sleep -Seconds 1 }
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
        amostras = $Amostras
        cenario = $Cenario
        serie = $serie
    }
}

# Carga fixa em memoria; nao mede FPS nem desempenho geral.
function Medir-CargaPadronizada {
    param([ValidateRange(1,16)][int]$MiB=8,[ValidateRange(1,32)][int]$Repeticoes=16)
    $dados=New-Object byte[] ($MiB*1MB)
    $destino=New-Object byte[] ($dados.Length)
    for ($i=0; $i -lt $dados.Length; $i+=4096) { $dados[$i]=[byte](($i/4096)%251) }
    $sha=[Security.Cryptography.SHA256]::Create()
    $rodadas=@()
    try {
        [void]$sha.ComputeHash($dados)
        [Buffer]::BlockCopy($dados,0,$destino,0,$dados.Length)
        for ($r=1; $r -le 3; $r++) {
            $sw=[Diagnostics.Stopwatch]::StartNew()
            for ($j=0; $j -lt $Repeticoes; $j++) { [void]$sha.ComputeHash($dados) }
            $sw.Stop()
            $hashMs=[math]::Round($sw.Elapsed.TotalMilliseconds,3)
            $sw.Restart()
            for ($j=0; $j -lt ($Repeticoes*4); $j++) { [Buffer]::BlockCopy($dados,0,$destino,0,$dados.Length) }
            $sw.Stop()
            $rodadas += [pscustomobject]@{ rodada=$r; hashMs=$hashMs; copiaMemoriaMs=[math]::Round($sw.Elapsed.TotalMilliseconds,3) }
        }
    } finally { $sha.Dispose() }
    return [pscustomobject]@{ formato='otimizadorpc-carga-v1'; criado=(Get-Date -Format 'o'); maquina=$env:COMPUTERNAME; build=[Environment]::OSVersion.Version.Build; MiB=$MiB; repeticoes=$Repeticoes; rodadas=$rodadas }
}

function Comparar-Medicoes {
    param($Antes, $Depois)
    foreach ($item in @($Antes,$Depois)) {
        if ($item.formato -ne 'otimizadorpc-medicao-v1' -or $item.amostras -lt 3 -or $item.amostras -gt 30) { throw 'Formato de medicao invalido.' }
        foreach ($campo in @('cpuMedia','ramUsadaGB','processosMedia','discoLivreGB','ramTotalGB','discoTotalGB')) {
            $v = $item.$campo
            if ($null -eq $v -or ($v -isnot [ValueType]) -or $v -is [bool]) { throw ('Campo numerico invalido: ' + $campo) }
            $n = [double]$v
            if ([double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt 0) { throw ('Valor invalido: ' + $campo) }
        }
        if ($item.cpuMedia -gt 100 -or $item.ramUsadaGB -gt $item.ramTotalGB -or $item.discoLivreGB -gt $item.discoTotalGB) { throw 'Medicao fora dos limites.' }
    }
    foreach ($campo in @('maquina','build','unidade','ramTotalGB','discoTotalGB','amostras')) {
        if ($null -eq $Antes.$campo -or $Antes.$campo -ne $Depois.$campo) { throw 'Medicoes de computadores ou configuracoes diferentes.' }
    }
    if ([string]$Antes.cenario -cne [string]$Depois.cenario) { throw 'Cenarios de medicao diferentes.' }
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

# Consulta apenas metadados publicos do proprio repositorio.
# Nunca baixa, instala ou executa uma atualizacao automaticamente.
function Consultar-ReleaseOficial {
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        $headers = @{ 'User-Agent' = 'OtimizadorPC'; Accept = 'application/vnd.github+json' }
        $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/joaoldsxyzbr/otimizador-de-windows/releases?per_page=20' -Headers $headers -TimeoutSec 20 -ErrorAction Stop
        $validas = @($releases | Where-Object {
            -not $_.draft -and $_.tag_name -match '^v[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[0-9]+)?$' -and
            @($_.assets | Where-Object { $_.name -eq 'otimizadorpc.ps1' }).Count -eq 1 -and
            @($_.assets | Where-Object { $_.name -eq 'otimizadorpc.ps1.sha256' }).Count -eq 1
        })
        $estavel = @($validas | Where-Object { -not $_.prerelease } | Select-Object -First 1)
        $previa = @($validas | Where-Object { $_.prerelease } | Select-Object -First 1)
        return [pscustomobject]@{ estavel=$(if ($estavel.Count) { [string]$estavel[0].tag_name } else { '' }); previa=$(if ($previa.Count) { [string]$previa[0].tag_name } else { '' }) }
    } finally { [Net.ServicePointManager]::SecurityProtocol = $tls }
}

# Download explicito, somente do repositorio oficial, sem executar o conteudo.
function Baixar-ReleaseVerificada {
    param([ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-rc\.[0-9]+)?$')][string]$Tag)
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        $base = 'https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/' + $Tag + '/otimizadorpc.ps1'
        $manifesto = Invoke-WebRequest -Uri ($base + '.sha256') -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        if (-not $manifesto.RawContentStream -or $manifesto.RawContentStream.Length -gt 1024) { throw 'Manifesto SHA256 com tamanho inesperado.' }
        $manifesto.RawContentStream.Position=0
        $leitor=[IO.StreamReader]::new($manifesto.RawContentStream,[Text.Encoding]::UTF8,$true,1024,$true)
        try { $textoHash=$leitor.ReadToEnd() } finally { $leitor.Dispose() }
        if ($textoHash -notmatch '^([a-fA-F0-9]{64})\s+otimizadorpc\.ps1\s*$') { throw 'Manifesto SHA256 invalido.' }
        $esperado = $Matches[1]
        $arquivo = Invoke-WebRequest -Uri $base -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $stream = $arquivo.RawContentStream
        if (-not $stream -or $stream.Length -lt 1 -or $stream.Length -gt 2MB) { throw 'Tamanho inesperado do script.' }
        $stream.Position=0
        $mem = New-Object IO.MemoryStream
        try { $stream.CopyTo($mem); $bytes=$mem.ToArray() } finally { $mem.Dispose(); $stream.Dispose() }
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
        if ($hash -ne $esperado) { throw 'SHA256 divergente; arquivo recusado.' }
        return [pscustomobject]@{ tag=$Tag; hash=$hash; bytes=$bytes }
    } finally { [Net.ServicePointManager]::SecurityProtocol = $tls }
}
