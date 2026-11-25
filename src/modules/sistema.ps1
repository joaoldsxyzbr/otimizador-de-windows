# sistema.ps1 - preenche a pagina inicial com informacoes do pc

# detecta se o pc e gerenciado por empresa (dominio, azure ad, av corporativo)
# Common antivirus brands alone do not establish organizational management.
function Testar-AgenteGerenciamento {
    param($Servico)
    $texto=([string]$Servico.Name+' '+[string]$Servico.DisplayName)
    return ($texto -match '(?i)crowdstrike|falcon sensor|sentinelone|sentinel agent|carbon black|intunemanagementextension|ccmexec|tanium|(?:^|\s)sense(?:\s|$)|defender for endpoint|configuration manager client|trellix agent|sophos management')
}

function Testar-IngressoDispositivo {
    param([string]$Saida)
    if ($Saida -notmatch '(?m)^\s*AzureAdJoined\s*:\s*(YES|NO)\s*$' -or $Saida -notmatch '(?m)^\s*DomainJoined\s*:\s*(YES|NO)\s*$') {throw 'Estado de ingresso do dispositivo indisponivel.'}
    return ($Saida -match '(?m)^\s*(AzureAdJoined|DomainJoined|EnterpriseJoined)\s*:\s*YES\s*$')
}

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
        if ($LASTEXITCODE -ne 0) {throw 'Estado de registro indisponivel.'}
        if (Testar-IngressoDispositivo $saida) { $achados+='Ingresso organizacional do dispositivo detectado.' }
    } catch { $achados+='Inconclusivo: registro Entra/organizacional nao confirmado.' }
    try {
        $raiz='HKLM:\SOFTWARE\Microsoft\Enrollments'
        if (Test-Path -LiteralPath $raiz -ErrorAction Stop) {
            foreach ($ch in @(Get-ChildItem -LiteralPath $raiz -ErrorAction Stop | Where-Object {$_.PSChildName -match '^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$'})) {
                $v=Get-ItemProperty -LiteralPath $ch.PSPath -ErrorAction Stop
                if ($v.EnrollmentState -eq 1 -and ($v.ProviderID -or $v.EnrollmentType)) { $achados+='Sinal de inscricao de gerenciamento de dispositivo (MDM).'; break }
            }
        }
    } catch { $achados+='Inconclusivo: consulta de inscricao MDM indisponivel.' }
    try {
        $wu='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        if (Test-Path -LiteralPath $wu -ErrorAction Stop) {
            $v=Get-ItemProperty -LiteralPath $wu -ErrorAction Stop
            if ($v.WUServer -or $v.WUStatusServer -or $v.SetPolicyDrivenUpdateSourceForQualityUpdates -eq 1) { $achados+='Sinal de politica de atualizacao organizacional.' }
        }
    } catch { $achados+='Inconclusivo: consulta de politica de atualizacao indisponivel.' }
    try {
        $agentes=@(Get-Service -ErrorAction Stop | Where-Object {Testar-AgenteGerenciamento $_})
        if ($agentes.Count -gt 0) { $achados+='Sinal de agente de gerenciamento ou seguranca de endpoint organizacional.' }
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
    } catch { $sinais+='Inconclusivo: consulta de politica de proxy indisponivel.' }
    try {
        $p='HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment'
        if (Test-Path -LiteralPath $p -ErrorAction Stop) {
            $v=Get-ItemProperty -LiteralPath $p -ErrorAction Stop
            if ($v.AEPolicy -gt 0) { $sinais+='Sinal de politica de inscricao automatica de certificados.' }
        }
    } catch { $sinais+='Inconclusivo: consulta de politica de certificados indisponivel.' }
    # VPN pode ser pessoal; sua mera presenca nao classifica a maquina.
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
    if ($Diagnostico -or -not $Admin) { return 'Diagnostico' }
    if (-not $Pessoal) { return 'Diagnostico' }
    return 'Autorizacao por operacao'
}

function Inicializar-ModoOtimizador {
    param([switch]$Diagnostico,[switch]$Pessoal)
    $global:ModoProtegido=$true
    $global:ContextoAutorizacaoInicial=$null
    $sinais=@();$confirmados=$false
    try {$sinais=@(Detectar-AmbienteTrabalho);$confirmados=$true}
    catch {$sinais=@('Inconclusivo: consulta de gerenciamento indisponivel.')}
    $global:AmbienteTrabalho=$sinais
    $ctx=Obter-ContextoAjustes
    $id=Obter-IdentidadeAutorizacao
    $usuario=if ($id.admin -and $Pessoal -and -not $Diagnostico) {Testar-UsuarioInterativo $id.sid} else {$false}
    $global:ContextoAutorizacaoInicial=@{identidade=$id;windows=$ctx;diagnostico=[bool]$Diagnostico;consentiu=[bool]$Pessoal;usuarioCorreto=$usuario;sinais=$sinais;sinaisConfirmados=$confirmados}
    $global:ModoOtimizador=Resolver-ModoOtimizador -Admin $id.admin -Diagnostico ([bool]$Diagnostico) -Sinais $sinais -Pessoal ([bool]$Pessoal)
    # This flag denotes an explicit read-only session or missing base privilege, NOT PC classification.
    $global:ModoProtegido=($global:ModoOtimizador -eq 'Diagnostico' -or -not $id.visaoCorreta -or -not $ctx -or -not $ctx.cliente -or $ctx.build -lt 10240)
    if ($global:ModoProtegido) {$global:ModoOtimizador='Diagnostico'}
}

# Recomendacoes conservadoras, sem modificar configuracoes.
# Interpretacao pura: dados ausentes nunca equivalem a zero ou estado saudavel.
# Limites indicativos de triagem, nao diagnostico de causa.
function Avaliar-SaudeLocal {
    param($OS,$Disco,$Inicializacao,$Reinicio,$Bateria)
    if ($OS -and $OS.TotalVisibleMemorySize -gt 0 -and $null -ne $OS.FreePhysicalMemory -and $OS.FreePhysicalMemory -ge 0 -and $OS.FreePhysicalMemory -le $OS.TotalVisibleMemorySize) {
        $pct=100.0 * $OS.FreePhysicalMemory / $OS.TotalVisibleMemorySize
        $ram=[math]::Round($OS.TotalVisibleMemorySize / 1MB,1)
        if ($pct -lt 10) {
            [pscustomobject]@{id='ram';estado='atencao';evidencia=('{0:N1}% de RAM disponivel nesta amostra ({1:N1} GB totais).' -f $pct,$ram);orientacao='Abra Amostras de CPU, memoria e disco para investigar pressao persistente; uma amostra nao identifica gargalo.'}
        } elseif ($ram -lt 8) {
            [pscustomobject]@{id='ram';estado='informacao';evidencia=('{0:N1} GB de RAM visivel; {1:N1}% disponivel.' -f $ram,$pct);orientacao='Capacidade limitada pode afetar cargas pesadas; confirme com amostras antes de ajustar.'}
        } else {
            [pscustomobject]@{id='ram';estado='informacao';evidencia=('{0:N1}% de RAM disponivel nesta amostra.' -f $pct);orientacao='Amostra instantanea; nao certifica ausencia de pressao de memoria.'}
        }
    } else {
        [pscustomobject]@{id='ram';estado='indisponivel';evidencia='Dados de memoria ausentes ou inconsistentes.';orientacao='Tente atualizar a consulta; nao inferir falta de RAM.'}
    }
    if ($Disco -and $Disco.Size -gt 0 -and $null -ne $Disco.FreeSpace -and $Disco.FreeSpace -ge 0 -and $Disco.FreeSpace -le $Disco.Size) {
        $pct=100.0 * $Disco.FreeSpace / $Disco.Size
        $gb=$Disco.FreeSpace / 1GB
        $estado=if ($pct -lt 15 -or $gb -lt 5) {'atencao'} else {'informacao'}
        $orientacao=if ($estado -eq 'atencao') {'Use Revisar armazenamento; examine a previa antes de limpar.'} else {'Espaco livre nao mede latencia nem integridade do disco.'}
        [pscustomobject]@{id='disco';estado=$estado;evidencia=('{0:N1} GB livres ({1:N1}%) no disco do sistema.' -f $gb,$pct);orientacao=$orientacao}
    } else {
        [pscustomobject]@{id='disco';estado='indisponivel';evidencia='Espaco do disco do sistema nao confirmado.';orientacao='Tente novamente; nenhuma limpeza recomendada automaticamente.'}
    }
    if ($null -ne $Inicializacao -and $Inicializacao -ge 0) {
        [pscustomobject]@{id='inicio';estado='informacao';evidencia=('{0} entradas de inicializacao detectadas nesta consulta.' -f $Inicializacao);orientacao='A quantidade nao mede impacto. Use Revisar inicializacao e confira impacto no Gerenciador de Tarefas.'}
    } else {
        [pscustomobject]@{id='inicio';estado='indisponivel';evidencia='Entradas de inicializacao nao consultadas.';orientacao='Consulte o Gerenciador de Tarefas.'}
    }
    if ($Reinicio -eq $true) {
        [pscustomobject]@{id='reinicio';estado='atencao';evidencia='Indicador de reinicio pendente encontrado no Windows.';orientacao='Salve o trabalho e reinicie quando autorizado, antes de novos ajustes.'}
    } elseif ($null -eq $Reinicio) {
        [pscustomobject]@{id='reinicio';estado='indisponivel';evidencia='Indicadores de reinicio nao confirmados.';orientacao='Verifique o Windows Update.'}
    } else {
        [pscustomobject]@{id='reinicio';estado='informacao';evidencia='Nenhum indicador de reinicio encontrado nas duas chaves consultadas.';orientacao='Isso nao exclui outras solicitacoes de reinicio.'}
    }
    if ($Bateria -eq $true) {
        [pscustomobject]@{id='bateria';estado='informacao';evidencia='Bateria detectada.';orientacao='Consulte Bateria: capacidade e carga. Preserve autonomia; nao force alto desempenho.'}
    } elseif ($null -eq $Bateria) {
        [pscustomobject]@{id='bateria';estado='indisponivel';evidencia='Tipo de alimentacao nao confirmado.';orientacao='Consulte as configuracoes de energia do Windows.'}
    } else {
        [pscustomobject]@{id='bateria';estado='informacao';evidencia='Nenhuma bateria retornada pela consulta.';orientacao='Escolha o plano de energia conforme a carga; nao ha ganho de FPS garantido.'}
    }
}

# Snapshot collection is self-contained for a separate PS 5.1 runspace.
function Obter-SnapshotInicio {
    $os=$null; $cpu=$null; $gpu=@(); $disco=$null
    $inicio=$null; $reinicio=$null; $bateria=$null; $pontos=$null
    try {$os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop} catch {}
    try {$cpu=Get-CimInstance Win32_Processor -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1} catch {}
    try {$gpu=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec 8 -ErrorAction Stop | Where-Object {$_.Name})} catch {}
    try {$disco=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -OperationTimeoutSec 8 -ErrorAction Stop} catch {}
    try {$inicio=@(Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 8 -ErrorAction Stop).Count} catch {}
    try {
        $cbs=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Stop
        $wu=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction Stop
        $reinicio=($cbs -or $wu)
    } catch {}
    try {$bateria=(@(Get-CimInstance Win32_Battery -OperationTimeoutSec 8 -ErrorAction Stop).Count -gt 0)} catch {}
    try {$pontos=@(Get-ComputerRestorePoint -ErrorAction Stop).Count} catch {}
    [pscustomobject]@{os=$os;cpu=$cpu;gpu=$gpu;disco=$disco;inicio=$inicio;reinicio=$reinicio;bateria=$bateria;pontos=$pontos;data=(Get-Date)}
}

function Obter-DiagnosticoLocal {
    param($OS,$Disco,$Inicializacao,$Reinicio,$Bateria,[datetime]$Data=(Get-Date))
    $linhas=@(('Ultima analise local: '+$Data.ToString('dd/MM/yyyy HH:mm:ss')+' | Somente leitura, sem nota de saude.'))
    $itens=@(Avaliar-SaudeLocal $OS $Disco $Inicializacao $Reinicio $Bateria)
    $atencao=@($itens | Where-Object {$_.estado -eq 'atencao'}).Count
    $ausentes=@($itens | Where-Object {$_.estado -eq 'indisponivel'}).Count
    $linhas+=('Prioridades nesta amostra: '+$atencao+' indicador(es) de atencao; '+$ausentes+' indisponivel(is). Nao e uma nota de saude.')
    foreach ($item in @($itens | Sort-Object @{Expression={switch ($_.estado) {'atencao' {0} 'indisponivel' {1} default {2}}}})) {
        $linhas+=('[{0}] {1} {2}' -f $item.estado.ToUpperInvariant(),$item.evidencia,$item.orientacao)
    }
    if ($global:ModoProtegido) {$linhas+='Alteracoes indisponiveis no modo atual; consulte as permissoes e o administrador.'}
    return ($linhas -join [Environment]::NewLine)
}

# Render only on the WPF Dispatcher; no system inventory calls here.
function Mostrar-SnapshotInicio {
    param($Dados,$UI)
    $os=$Dados.os; $cpu=$Dados.cpu; $gpu=@($Dados.gpu | Where-Object {$_}); $disco=$Dados.disco
    $UI.InfoHost.Text=$env:COMPUTERNAME
    $UI.InfoSo.Text=Nome-Windows
    $UI.InfoCpu.Text=if ($cpu -and $cpu.Name) {('{0} ({1} nucleos / {2} threads)' -f $cpu.Name.Trim(),$cpu.NumberOfCores,$cpu.NumberOfLogicalProcessors)} else {'Indisponivel'}
    $UI.InfoGpu.Text=if ($gpu.Count) {($gpu | ForEach-Object {$_.Name}) -join ', '} else {'Indisponivel'}
    $UI.InfoRam.Text=if ($os -and $os.TotalVisibleMemorySize -gt 0 -and $null -ne $os.FreePhysicalMemory -and $os.FreePhysicalMemory -ge 0 -and $os.FreePhysicalMemory -le $os.TotalVisibleMemorySize) {('{0:N1} GB (livre: {1:N1} GB)' -f ($os.TotalVisibleMemorySize/1MB),($os.FreePhysicalMemory/1MB))} else {'Indisponivel'}
    $UI.InfoDisco.Text=if ($disco -and $disco.Size -gt 0 -and $null -ne $disco.FreeSpace -and $disco.FreeSpace -ge 0 -and $disco.FreeSpace -le $disco.Size) {('{0}: {1:N1} GB livres de {2:N1} GB' -f $env:SystemDrive,($disco.FreeSpace/1GB),($disco.Size/1GB))} else {'Indisponivel'}
    $UI.InfoUptime.Text=if ($os -and $os.LastBootUpTime) {$up=$Dados.data-$os.LastBootUpTime; ('{0}d {1}h {2}min' -f $up.Days,$up.Hours,$up.Minutes)} else {'Indisponivel'}
    $UI.InfoRestore.Text=if ($null -eq $Dados.pontos) {'estado da restauracao indisponivel'} elseif ($Dados.pontos -gt 0) {('{0} ponto(s) listado(s); protecao atual nao confirmada' -f $Dados.pontos)} else {'sem pontos de restauracao ainda'}
    $UI.InfoAmbiente.Text=if (@($global:AmbienteTrabalho | Where-Object {$_}).Count) {$global:ModoOtimizador+' - indicadores por operacao: '+($global:AmbienteTrabalho -join ' | ')} else {$global:ModoOtimizador+' - nenhum sinal consultado; nao comprova ausencia de gerenciamento.'}
    $UI.InfoDiagnostico.Text=Obter-DiagnosticoLocal $os $disco $Dados.inicio $Dados.reinicio $Dados.bateria $Dados.data
}

function Preencher-PaginaInicio {
    param([switch]$Forcar)
    Solicitar-SnapshotInicio -Forcar:$Forcar
}

# Inventario local, sem comandos de inicializacao, usuarios ou credenciais.
function Obter-InventarioLocal {
    param([bool]$Protegido=$true)
    $relatorio = [ordered]@{
        criado = (Get-Date -Format 'o')
        windows = ('{0} (build {1})' -f $(if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }),[Environment]::OSVersion.Version.Build)
        aplicativosWin32 = @()
        appxUsuario = @()
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
    # No Win32_Product (which can trigger MSI consistency checks). These are registration records.
    foreach ($origem in @(
        @{nome='Computador - visao nativa';chave='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'},
        @{nome='Computador - WOW6432Node';chave='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'},
        @{nome='Usuario atual';chave='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'}
    )) {
        try {
            if (-not (Test-Path -LiteralPath $origem.chave -ErrorAction Stop)) {continue}
            foreach ($k in @(Get-ChildItem -LiteralPath $origem.chave -ErrorAction Stop)) {
                $p=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace([string]$p.DisplayName)) {continue}
                $relatorio.aplicativosWin32+=[pscustomobject]@{
                    nome=[string]$p.DisplayName;versao=[string]$p.DisplayVersion;fabricanteDeclarado=[string]$p.Publisher
                    origem=$origem.nome;tecnologia=$(if ([string]$p.WindowsInstaller -eq '1') {'MSI'} else {'Win32 / nao identificada'})
                    indicadorProtecao=([string]$p.SystemComponent -eq '1' -or [string]$p.NoRemove -eq '1' -or -not [string]::IsNullOrWhiteSpace([string]$p.ParentKeyName))
                }
            }
        } catch {$relatorio.avisos+=('Inventario Win32 incompleto: '+$origem.nome+'. Ausencia nao confirmada.')}
    }
    $relatorio.aplicativosWin32=@($relatorio.aplicativosWin32 | Sort-Object nome,origem,versao)
    try {
        $relatorio.appxUsuario=@(Get-AppxPackage -ErrorAction Stop | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{nome=[string]$_.Name;versao=[string]$_.Version;fabricanteDeclarado=[string]$_.Publisher
                escopo='Usuario atual';framework=[bool]$_.IsFramework;recurso=[bool]$_.IsResourcePackage;naoRemovivel=[bool]$_.NonRemovable}
        })
    } catch {$relatorio.avisos+='Inventario AppX indisponivel; ausencia nao confirmada.'}
    $relatorio.avisos+='Registros Win32/MSI e pacotes AppX podem representar o mesmo produto. Indicadores de protecao nao certificam que um aplicativo possa ser removido.'
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
