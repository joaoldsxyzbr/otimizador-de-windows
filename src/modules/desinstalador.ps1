# desinstalador.ps1 - aba Desinstalar: lista programas instalados, desinstala e varre os rastros que sobram
# rastros apagados vao para uma pasta de quarantena (arquivos movidos, registro exportado em .reg);
# a aba Desfazer tudo restaura a partir do journal da sessao

if (-not $global:RaizEstado) { $global:RaizEstado = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'otimizadorpc-v2' }
$global:PastaQuarantena = Join-Path $global:RaizEstado 'quarentena'

# ---- listagem dos programas instalados ----

# Classificacao local, conservadora. Metadados do registro nao sao prova de origem.
function Classificar-Programa {
    param($Prog)
    $n = ([string]$Prog.nome).Trim()
    $editor = ([string]$Prog.editor).Trim()
    $ms = $editor -match '^Microsoft(?: Corporation| Corp\.?| Inc\.?)?$'
    $grupo='Desconhecido'; $risco='Revisar'; $finalidade='Finalidade nao identificada'; $motivo='Nao ha regra local suficiente para identificar este programa.'
    if ($Prog.componenteSistema -or $Prog.naoRemover -or $Prog.pai -or $Prog.tipoRelease -match '^(Security Update|Critical Update|Update|Hotfix|Service Pack)$' -or
        $n -match '^(KB[0-9]+\b|(?:Security |Critical )?Update for |Hotfix\b|Language (Pack|Interface)\b|Windows (Security|Defender|Update Health Tools|Setup|Servicing Stack)\b|Microsoft (Windows Defender|Defender Antivirus|Edge(?: WebView2 Runtime| Update)?(?:\s*\(.*\))?)$)' -or
        ($ms -and $n -match '^(Microsoft (Windows (?:10|11|Operating System|Update)|Edge|OneDrive|Update Health Tools)\b|Windows (?:Security|Defender|Update Health Tools|Setup|Servicing Stack)\b)')) {
        $grupo='Sistema'; $risco='Bloqueado'; $finalidade='Componente, atualizacao ou entrada protegida'; $motivo='Indicador de sistema/nao remocao no registro ou nome de componente protegido conhecido.'
    } elseif ($n -match '(?i)\b(CrowdStrike|Falcon Sensor|SentinelOne|Microsoft Intune|Intune Management Extension|Configuration Manager Client|Microsoft Defender for Endpoint|Tanium|Carbon Black|Endpoint Detection|Endpoint Agent|EDR Agent)\b') {
        $grupo='Sistema'; $risco='Bloqueado'; $finalidade='Possivel agente de seguranca ou gerenciamento'; $motivo='Agente corporativo conhecido ou suspeito; remover pelo OtimizadorPC nao e permitido.'
    } elseif ($n -match '(?i)\b(VPN|GlobalProtect|AnyConnect|Cisco Secure Client|FortiClient|Zscaler|WireGuard|OpenVPN|Tailscale|ZeroTier)\b') {
        $grupo='Seguranca'; $risco='Bloqueado'; $finalidade='Conectividade ou acesso remoto'; $motivo='Cliente de rede/VPN reconhecido; preserve o acesso e use o fluxo autorizado do Windows ou fabricante.'
    } elseif ($n -match '\b(driver|drivers|driver package|chipset|graphics driver|audio driver|display driver|wireless driver)\b' -or $n -match '^(Realtek (?:High Definition Audio|Audio|Ethernet|PCIe)|NVIDIA Graphics Driver|AMD (?:Chipset|Software: Adrenalin Edition))\b') {
        $grupo='Driver'; $risco='Cautela'; $finalidade='Hardware, video, audio ou rede'; $motivo='Nome sugere driver ou pacote de hardware; remover pode prejudicar dispositivos.'
    } elseif ($n -match '\b(visual c\+\+|redistributable|runtime|directx|xna|physx|openal)\b' -or $n -match '^(Microsoft )?\.NET\b|^Microsoft ASP\.NET\b|^Java \d|^Microsoft Windows Desktop Runtime\b') {
        $grupo='Dependencia'; $risco='Cautela'; $finalidade='Biblioteca, runtime ou plataforma compartilhada'; $motivo='Outros programas ou jogos podem depender deste componente; dependentes reais nao foram verificados.'
    } elseif ($n -match '\b(antivirus|endpoint protection|internet security|firewall|security agent|antimalware)\b' -or $n -match '^(McAfee|Norton|Kaspersky|Avast|Bitdefender|ESET|Malwarebytes)\b') {
        $grupo='Seguranca'; $risco='Bloqueado'; $finalidade='Protecao ou seguranca'; $motivo='Software de protecao: remocao e limpeza indisponiveis no OtimizadorPC. Use o fluxo autorizado do fabricante.'
    } elseif ($ms -and $n -match '^(Microsoft )?(Clipchamp|OneDrive|PowerToys|Teams|Office|Microsoft 365)(?:\b|$)') {
        $grupo='Opcional'; $risco='Normal'; $finalidade='Aplicativo de uso pessoal ou produtividade'; $motivo='Nome e fabricante declarados correspondem a aplicativo opcional conhecido; dados e integracoes podem ser afetados.'
    } else {
        $conhecido=@($global:CatalogoApps.aplicativos | Where-Object { $_.nome -eq $n })
        if ($conhecido.Count -eq 1 -and $editor) {
            $grupo='Aplicativo'; $risco='Normal'; $finalidade=[string]$conhecido[0].desc; $motivo='Nome exato no catalogo local de aplicativos; fabricante declarado, nao autenticado.'
        }
    }
    $temComando = -not ([string]::IsNullOrWhiteSpace([string]$Prog.comando) -and [string]::IsNullOrWhiteSpace([string]$Prog.quiet))
    if (-not $temComando -and $risco -ne 'Bloqueado') { $motivo += ' Nenhum desinstalador registrado.' }
    return [pscustomobject]@{ categoria=$grupo; risco=$risco; finalidade=$finalidade; motivo=$motivo; podeDesinstalar=($risco -ne 'Bloqueado' -and $temComando) }
}

function Converter-EntradaPrograma {
    param($Entrada)
    $kb=$null; $data=$null
    $num=0L
    if ([long]::TryParse([string]$Entrada.EstimatedSize,[ref]$num) -and $num -gt 0) { $kb=$num }
    $dt=[datetime]::MinValue
    if ([datetime]::TryParseExact([string]$Entrada.InstallDate,'yyyyMMdd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$dt)) { $data=$dt }
    return [pscustomobject]@{
        nome=[string]$Entrada.DisplayName; versao=[string]$Entrada.DisplayVersion; editor=[string]$Entrada.Publisher
        comando=[string]$Entrada.UninstallString; quiet=[string]$Entrada.QuietUninstallString; chavePs=[string]$Entrada.PSPath
        instaladoEm=[string]$Entrada.InstallLocation; tamanhoKB=$kb; dataInstalacao=$data
        componenteSistema=([string]$Entrada.SystemComponent -eq '1'); naoRemover=([string]$Entrada.NoRemove -eq '1')
        pai=[string]$Entrada.ParentKeyName; tipoRelease=[string]$Entrada.ReleaseType
        msi=([string]$Entrada.WindowsInstaller -eq '1'); codigoMsi=$(if ([string]$Entrada.WindowsInstaller -eq '1' -and [string]$Entrada.PSChildName -match '^\{[A-Fa-f0-9-]{36}\}$') {[string]$Entrada.PSChildName} else {''})
    }
}

# Bloqueio no ponto de execucao, inclusive quando chamado sem a interface.
# Releia metadados existentes; nao execute um comando que mudou apos a listagem.
function Validar-ProtecaoPrograma {
    param($Prog,[switch]$Desinstalar)
    if ($null -eq $Prog -or [string]::IsNullOrWhiteSpace([string]$Prog.nome)) { throw 'Programa nao identificado.' }
    $info=Classificar-Programa $Prog
    if ($info.risco -eq 'Bloqueado') { throw ('Componente protegido: ' + $Prog.nome + '. ' + $info.motivo) }
    if ($Prog.chavePs) {
        if (Test-Path -LiteralPath $Prog.chavePs -ErrorAction Stop) {
            $atual=Converter-EntradaPrograma (Get-ItemProperty -LiteralPath $Prog.chavePs -ErrorAction Stop)
            $novo=Classificar-Programa $atual
            if ($novo.risco -eq 'Bloqueado') { throw ('Entrada agora protegida: ' + $atual.nome) }
            if ($atual.nome -cne $Prog.nome -or $atual.editor -cne $Prog.editor -or $atual.versao -cne $Prog.versao -or $atual.msi -ne $Prog.msi -or $atual.codigoMsi -ne $Prog.codigoMsi -or $atual.comando -cne $Prog.comando -or $atual.quiet -cne $Prog.quiet -or $novo.risco -ne $info.risco -or $novo.categoria -ne $info.categoria) { throw 'Entrada mudou desde a listagem; atualize a lista e refaca a selecao.' }
        } elseif ($Desinstalar) { throw 'Entrada nao existe mais; atualize a lista.' }
    } elseif ($Desinstalar) { throw 'Entrada de registro nao identificada.' }
    if ($Desinstalar -and -not $info.podeDesinstalar) { throw 'Nenhum desinstalador registrado.' }
    return $info
}

# Worker inventory. Missing optional roots are normal; a failed read is not.
function Obter-SnapshotProgramas {
    $chaves=@(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $vistos=@{}; $lista=New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in $chaves) {
        if (-not (Test-Path -LiteralPath $c -ErrorAction Stop)) {continue}
        foreach ($chave in @(Get-ChildItem -LiteralPath $c -ErrorAction Stop)) {
            $p=Get-ItemProperty -LiteralPath $chave.PSPath -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$p.DisplayName) -or -not $p.PSPath -or $vistos.ContainsKey([string]$p.PSPath)) {continue}
            $vistos[[string]$p.PSPath]=$true
            $pr=Converter-EntradaPrograma $p
            $pr | Add-Member -NotePropertyName classificacao -NotePropertyValue (Classificar-Programa $pr)
            $lista.Add($pr)
        }
    }
    [pscustomobject]@{itens=@($lista.ToArray() | Sort-Object nome,versao);data=(Get-Date)}
}

function Carregar-Programas {
    param([switch]$Forcar)
    Solicitar-SnapshotProgramas -Forcar:$Forcar
}

function Filtrar-Programas {
    param($Programas,[string]$Texto,[string]$Categoria='Todos',[string]$Ordem='Nome')
    $filtrados=@($Programas | Where-Object {
        $info=$_.classificacao
        if (-not $info) { $info=Classificar-Programa $_ }
        ($Categoria -eq 'Todos' -or $info.categoria -eq $Categoria) -and
        (($_.nome + ' ' + $_.editor + ' ' + $_.versao + ' ' + $info.categoria + ' ' + $info.finalidade).IndexOf($Texto.Trim(),[StringComparison]::OrdinalIgnoreCase) -ge 0)
    })
    switch ($Ordem) {
        'Tamanho' { $filtrados | Sort-Object @{Expression={if ($null -eq $_.tamanhoKB) {-1} else {$_.tamanhoKB}};Descending=$true},nome }
        'Data' { $filtrados | Sort-Object @{Expression={if ($null -eq $_.dataInstalacao) {[datetime]::MinValue} else {$_.dataInstalacao}};Descending=$true},nome }
        default { $filtrados | Sort-Object nome,versao }
    }
}

function Formatar-TamanhoPrograma {
    param($KB)
    if ($null -eq $KB) { return 'Nao informado' }
    if ($KB -ge 1048576) { return ('{0:N2} GB (estimado)' -f ($KB/1048576)) }
    return ('{0:N1} MB (estimado)' -f ($KB/1024))
}

function Atualizar-ListaProgramas {
    $lb=$global:UI.ListaProgramas
    $filtro=[string]$global:UI.FiltroDesinstalar.Text
    $cat='Todos'; $ordem='Nome'
    if ($global:UI.CategoriaDesinstalar.SelectedItem) { $cat=[string]$global:UI.CategoriaDesinstalar.SelectedItem.Tag }
    if ($global:UI.OrdemDesinstalar.SelectedItem) { $ordem=[string]$global:UI.OrdemDesinstalar.SelectedItem.Tag }
    $lb.Items.Clear()
    $global:ProgramasExibidos=@()
    if ($null -eq $global:ProgramasInstalados) { return }
    foreach ($pr in @(Filtrar-Programas $global:ProgramasInstalados $filtro $cat $ordem)) {
        $info=$pr.classificacao
        $linha=('[{0} | {1}] {2}  |  {3} {4}  |  {5}' -f $info.categoria,$info.risco,$pr.nome,$pr.editor,$pr.versao,(Formatar-TamanhoPrograma $pr.tamanhoKB))
        $item=New-Object System.Windows.Controls.ListBoxItem
        $item.Content=$linha; $item.Tag=$pr
        $item.ToolTip=$info.finalidade + ' - ' + $info.motivo
        [void]$lb.Items.Add($item)
        $global:ProgramasExibidos += $pr
    }
    if ($lb.Items.Count -eq 0) {
        $vazio=New-Object System.Windows.Controls.ListBoxItem
        $vazio.Content='(nenhuma entrada neste filtro)'; $vazio.IsEnabled=$false
        [void]$lb.Items.Add($vazio)
    }
    $global:UI.InfoProgramas.Text=('{0} de {1} entradas | classificacao indicativa, nao certificada' -f $global:ProgramasExibidos.Count,$global:ProgramasInstalados.Count)
    Atualizar-DetalhePrograma
}

function Atualizar-DetalhePrograma {
    $selecionados=@(Obter-Selecionados $global:UI.ListaProgramas $global:ProgramasExibidos)
    $global:UI.BotaoDetalhesPrograma.IsEnabled=($selecionados.Count -eq 1)
    $bloqueados=@($selecionados | Where-Object { -not $_.classificacao.podeDesinstalar })
    $global:UI.BotaoDesinstalarProg.IsEnabled=(-not $global:ModoProtegido -and $selecionados.Count -gt 0 -and $bloqueados.Count -eq 0)
    $global:UI.BotaoVarrerRastros.IsEnabled=(-not $global:ModoProtegido -and $selecionados.Count -eq 1 -and $selecionados[0].classificacao.risco -ne 'Bloqueado')
    if ($selecionados.Count -eq 1) {
        $pr=$selecionados[0]; $info=$pr.classificacao
        $global:UI.DetalhePrograma.Text=('{0}: {1}. {2}' -f $info.categoria,$info.finalidade,$info.motivo)
    } elseif ($selecionados.Count -gt 1) { $global:UI.DetalhePrograma.Text=('{0} selecionados; {1} com remocao indisponivel.' -f $selecionados.Count,$bloqueados.Count) }
    else { $global:UI.DetalhePrograma.Text='Selecione uma entrada para ver a finalidade e o risco.' }
}

# Consulta MSI via automacao oficial; abre o MSI em cache somente leitura.
# ComponentClients indica compartilhamento registrado, nao dependencias reais.
function Obter-ResumoMsi {
    param([string]$Codigo)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($Codigo,[ref]$id)) {return 'Identificador MSI indisponivel.'}
    $codigo=$id.ToString('B')
    $installer=$null; $db=$null; $view=$null; $rec=$null; $clients=$null
    $linhas=@()
    try {
        $installer=New-Object -ComObject WindowsInstaller.Installer -ErrorAction Stop
        $nome=$installer.GetType().InvokeMember('ProductInfo','GetProperty',$null,$installer,@($codigo,'ProductName'))
        $local=[string]$installer.GetType().InvokeMember('ProductInfo','GetProperty',$null,$installer,@($codigo,'LocalPackage'))
        $linhas+=('Produto MSI consultado no contexto atual: '+$nome)
        $root=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'Installer')).TrimEnd('\')+'\'
        if (-not $local -or -not [IO.Path]::GetFullPath($local).StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($local) -ine '.msi') {throw 'Cache local nao confirmado.'}
        $file=Get-Item -LiteralPath $local -Force -ErrorAction Stop
        $dir=Get-Item -LiteralPath $root.TrimEnd('\') -Force -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Cache redirecionado.'}
        $db=$installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($local,0))
        $view=$db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@('SELECT `ComponentId` FROM `Component`'))
        [void]$view.GetType().InvokeMember('Execute','InvokeMethod',$null,$view,$null)
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $n=0;$compartilhados=0;$falhas=0;$limite=$false
        while ($true) {
            if ($n -ge 100 -or $sw.Elapsed.TotalSeconds -ge 8) {$limite=$true;break}
            $rec=$view.GetType().InvokeMember('Fetch','InvokeMethod',$null,$view,$null)
            if ($null -eq $rec) {break}
            try {
                $comp=[string]$rec.GetType().InvokeMember('StringData','GetProperty',$null,$rec,@(1))
                $n++
                if (-not $comp) {continue}
                try {
                    $clients=$installer.GetType().InvokeMember('ComponentClients','GetProperty',$null,$installer,@($comp))
                    $count=$clients.GetType().InvokeMember('Count','GetProperty',$null,$clients,$null)
                    if ([int]$count -gt 1) {$compartilhados++}
                } catch {$falhas++}
                finally {if ($null -ne $clients -and [Runtime.InteropServices.Marshal]::IsComObject($clients)) {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($clients)};$clients=$null}
            } finally {if ([Runtime.InteropServices.Marshal]::IsComObject($rec)) {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($rec)};$rec=$null}
        }
        $linhas+=('Componentes examinados: '+$n+' | com mais de um cliente registrado: '+$compartilhados+' | consultas falhas: '+$falhas)
        if ($limite) {$linhas+='Consulta parcial (limite de 100 componentes ou 8 segundos).'}
        $linhas+='Compartilhamento registrado nao comprova dependencia real, nem ausencia significa seguro remover. Nao usa Win32_Product.'
    } catch {$linhas+='Metadados MSI ou clientes compartilhados indisponiveis; nao conclua que nao ha dependencias.'}
    finally {
        foreach ($obj in @($rec,$clients,$view,$db,$installer)) {if ($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)) {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)}}
    }
    return ($linhas -join [Environment]::NewLine)
}

function Clique-DetalhesPrograma {
    $sel=@(Obter-Selecionados $global:UI.ListaProgramas $global:ProgramasExibidos)
    if ($sel.Count -ne 1) { return }
    $pr=$sel[0]; $info=$pr.classificacao
    $data=if ($pr.dataInstalacao) { $pr.dataInstalacao.ToString('dd/MM/yyyy') } else {'Nao informada'}
    $local=if ($pr.instaladoEm) {$pr.instaladoEm} else {'Nao informado'}
    $nl=[Environment]::NewLine
    $msg=@("Nome: $($pr.nome)","Fabricante declarado: $($pr.editor)","Versao: $($pr.versao)","Categoria: $($info.categoria)","Risco: $($info.risco)","Finalidade: $($info.finalidade)","Motivo: $($info.motivo)","Tamanho: $(Formatar-TamanhoPrograma $pr.tamanhoKB)","Data: $data","Local: $local","Desinstalacao disponivel: $($info.podeDesinstalar)","","Dependencias reais nao foram inventariadas. Metadados podem estar incompletos ou incorretos.") -join $nl
    if ($pr.msi -and $pr.codigoMsi) {
        try {
            $msi=@(Executar-ConsultaLocal -Titulo 'Consultando componentes MSI' -Codigo ${function:Obter-ResumoMsi} -Parametros @{Codigo=$pr.codigoMsi})
            if ($msi.Count -eq 1 -and $msi[0]) {$msg+=$nl+$nl+[string]$msi[0]}
        } catch {$msg+=$nl+'Consulta MSI indisponivel.'}
    }
    Avisar 'Detalhes do programa' $msg
}

# devolve os objetos por tras das linhas selecionadas de uma listbox
function Obter-Selecionados {
    param($ListBox, [object[]]$Exibidos)
    foreach ($linha in $ListBox.SelectedItems) {
        if ($linha -is [System.Windows.Controls.ListBoxItem] -and $null -ne $linha.Tag) { $linha.Tag }
    }
}

# ---- desinstalacao ----

# separa uma linha de comando em executavel + argumentos
function Analisar-LinhaComando {
    param([string]$Linha)
    $t = $Linha.Trim()
    if ($t -match '^"([^"]+)"\s*(.*)$') {
        return @{ exe = $Matches[1]; args = $Matches[2].Trim() }
    }
    $m = [regex]::Match($t, '^(.*?\.exe)\s+(.*)$', 'IgnoreCase')
    if ($m.Success) { return @{ exe = $m.Groups[1].Value; args = $m.Groups[2].Value.Trim() } }
    if ($t -match '\.exe$') { return @{ exe = $t; args = '' } }
    return $null
}

# Accept only an MSI product code linked to the exact selected registry entry.
function Obter-CodigoMsiDesinstalacao {
    param($Prog,[string]$Argumentos)
    $id=[guid]::Empty
    if (-not $Prog.msi -or -not [guid]::TryParse([string]$Prog.codigoMsi,[ref]$id) -or $id -eq [guid]::Empty) {throw 'Entrada MSI sem codigo de produto confirmado.'}
    $folha=([string]$Prog.chavePs -split '\\')[-1]
    $chave=[guid]::Empty
    if (-not [guid]::TryParse($folha,[ref]$chave) -or $chave -ne $id) {throw 'Codigo MSI nao corresponde a chave selecionada.'}
    $m=[regex]::Match($Argumentos,'(?i)^\s*/[ix]\s*(\{[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\})(?:\s+(?:/quiet|/passive|/qn|/norestart))*\s*$')
    $comando=[guid]::Empty
    if (-not $m.Success -or -not [guid]::TryParse($m.Groups[1].Value,[ref]$comando) -or $comando -ne $id) {throw 'Comando MSI ambiguo ou produto divergente. Use Aplicativos instalados do Windows.'}
    return $id.ToString('B')
}

function Confirmar-ExecutavelDesinstalacao {
    param([string]$Exe)
    $full=[IO.Path]::GetFullPath($Exe)
    $roots=@($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) | Where-Object {$_}
    if (-not @($roots | Where-Object {$full.StartsWith(([IO.Path]::GetFullPath($_).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)}).Count) {throw 'Desinstalador fora de Program Files; use Aplicativos instalados do Windows.'}
    $atual=$full
    while ($atual) {
        $item=Get-Item -LiteralPath $atual -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Caminho do desinstalador redirecionado.'}
        $pai=Split-Path -Parent $atual
        if (-not $pai -or $pai -eq $atual) {break}
        $atual=$pai
    }
    $sig=Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
    if ($sig.Status -ne 'Valid') {throw 'Assinatura do desinstalador nao validada; use Aplicativos instalados do Windows.'}
    return (Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Desinstalar-Programa {
    param($Prog)
    Confirmar-PermissaoAlteracao
    $info = Validar-ProtecaoPrograma $Prog -Desinstalar
    if ([string]$Prog.chavePs -notmatch '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\SOFTWARE\\(?:WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$') {
        throw 'Entrada por usuario ou fora da raiz de desinstalacao confiavel. Use Aplicativos instalados do Windows.'
    }
    $nome = [string]$Prog.nome
    if ($info.risco -ne 'Normal' -and -not (Perguntar 'Cautela na desinstalacao' ($info.motivo + ' Continuar com ' + $nome + '?'))) { throw 'Desinstalacao cancelada pelo usuario.' }
    # Preferir o desinstalador normal; nao inventar flags silenciosas pelo nome.
    $linha = [string]$Prog.comando
    if ([string]::IsNullOrWhiteSpace($linha)) { $linha = [string]$Prog.quiet }
    if ([string]::IsNullOrWhiteSpace($linha)) { throw 'Desinstalador ausente. Use Aplicativos instalados do Windows.' }
    $an = Analisar-LinhaComando ([Environment]::ExpandEnvironmentVariables($linha))
    if (-not $an) { throw 'Comando nao reconhecido. Use Aplicativos instalados do Windows.' }
    $folha = [IO.Path]::GetFileName($an.exe)
    $hashExe=$null
    if ($folha -ieq 'msiexec.exe') {
        $codigo=Obter-CodigoMsiDesinstalacao $Prog $an.args
        $exe=Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $argumentos='/x '+$codigo+' /norestart'
    } else {
        if ($folha -in @('cmd.exe','powershell.exe','pwsh.exe','wscript.exe','cscript.exe','mshta.exe','rundll32.exe','regsvr32.exe')) {
            throw 'Desinstalador usa interpretador generico. Use o desinstalador oficial pelo Windows.'
        }
        if ($an.exe -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($an.exe) -ine '.exe' -or -not (Test-Path -LiteralPath $an.exe -PathType Leaf)) {
            throw 'Executavel local do desinstalador nao encontrado. Use Aplicativos instalados do Windows.'
        }
        $exe=[IO.Path]::GetFullPath($an.exe)
        $hashExe=Confirmar-ExecutavelDesinstalacao $exe
        $argumentos = $an.args
    }
    $msg = ('Executar o desinstalador de {0}?{1}{1}{2}{1}{3}{1}{1}Confirme que reconhece este arquivo.' -f $nome,[Environment]::NewLine,$exe,$argumentos)
    if (-not (Perguntar 'Confirmar desinstalador' $msg)) { throw 'Desinstalacao cancelada pelo usuario.' }
    # Revalidate after the confirmation dialog; no stale identity or changed binary.
    Confirmar-PermissaoAlteracao
    [void](Validar-ProtecaoPrograma $Prog -Desinstalar)
    if ($hashExe -and (Confirmar-ExecutavelDesinstalacao $exe) -cne $hashExe) {throw 'Executavel alterado desde a confirmacao; operacao cancelada.'}
    $params = @{ FilePath=$exe; Wait=$true; PassThru=$true; ErrorAction='Stop' }
    if ($argumentos) { $params.ArgumentList = $argumentos }
    $proc = Start-Process @params
    try {
        if ($proc.ExitCode -notin @(0,3010,1641)) { throw ('Desinstalador falhou ou foi cancelado: ' + $proc.ExitCode) }
        Log ('desinstalador finalizado, codigo de saida: ' + $proc.ExitCode)
    } finally { $proc.Dispose() }
}

function Clique-DesinstalarProg {
    Confirmar-PermissaoAlteracao
    $selecionados = @(Obter-Selecionados $global:UI.ListaProgramas $global:ProgramasExibidos)
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Escolha na lista o(s) programa(s) que quer desinstalar.'
        return
    }
    try { foreach ($pr in $selecionados) { [void](Validar-ProtecaoPrograma $pr -Desinstalar) } }
    catch { Avisar 'Remocao bloqueada' $_.Exception.Message; return }
    $nomes = ($selecionados | ForEach-Object { $_.nome }) -join "`n"
    $msg = ("Desinstalar {0} programa(s):`n`n{1}`n`nAlguns desinstaladores abrem janelas proprias; siga as telas se aparecerem. Continuar?" -f $selecionados.Count, $nomes)
    if (-not (Perguntar 'Desinstalar programas' $msg)) { return }

    Status 'desinstalando...'
    Ocupado $true
    if ($global:UI.ChkPontoRestoreDesinstalar.IsChecked -and -not (Criar-PontoRestauracao)) { Ocupado $false; Avisar 'Ponto nao confirmado' 'Operacao cancelada.'; return }
    Iniciar-Sessao 'desinstalar'
    $concluidos = @()
    $i = 0
    foreach ($pr in $selecionados) {
        $i++
        Status ('desinstalando {0}/{1}: {2}' -f $i, $selecionados.Count, $pr.nome)
        Registrar-Jornal ([pscustomobject]@{ tipo = 'desinstalado-app'; nome = $pr.nome })
        try {
            Desinstalar-Programa $pr
            try { [void](Confirmar-ProgramaAusenteParaLimpeza $pr); $concluidos += $pr }
            catch { Log ('Remocao ainda nao confirmada; rastros preservados: '+$pr.nome) }
        } catch {
            Log ('falha ao desinstalar {0}: {1}' -f $pr.nome, $_.Exception.Message) -Erro
        }
        Atualizar-UI
    }
    $arq = Salvar-Sessao
    Ocupado $false
    $resumo = if ($global:ErrosSessao -gt 0) { 'desinstalacao com falhas; confira o log.' } else { 'desinstaladores encerrados; confira se os programas foram removidos.' }
    if ($arq) { $resumo = $resumo + ' journal: ' + (Split-Path -Leaf $arq) }
    Log $resumo
    Status $resumo
    # The UI wrapper invalidates and refreshes the inventory after the operation.
    foreach ($pr in $concluidos) {
        if (Perguntar 'Varrer rastros' ('Procurar agora os rastros que sobraram de "{0}" (pastas, registro, atalhos)?' -f $pr.nome)) {
            Executar-Varredura $pr
        }
    }
}

# ---- varredura de rastros ----

function Bater-Nome {
    param([string]$Candidato, [string]$AlvoBase, [string]$Compacto)
    if ([string]::IsNullOrWhiteSpace($Candidato)) { return $false }
    $c = $Candidato.ToLower()
    if ($AlvoBase.Length -ge 4 -and $c.Contains($AlvoBase)) { return $true }
    if ($Compacto.Length -ge 4) {
        $cc = ($c -replace '[^a-z0-9]', '')
        if ($cc.Contains($Compacto)) { return $true }
    }
    return $false
}

# Correspondencia conservadora para pastas e chaves. Versoes/sufixos ambiguos
# deixam de ser candidatos automaticos; uma correspondencia nao prova propriedade.
function Nome-RastroExato {
    param([string]$Candidato,[string]$Compacto)
    if ($Compacto.Length -lt 4) { return $false }
    $normal = ($Candidato.ToLower() -replace '[^a-z0-9]','')
    return ($normal -eq $Compacto)
}

function Caminho-LocalAusente {
    param([string]$Caminho)
    try {
        $p = [Environment]::ExpandEnvironmentVariables($Caminho.Trim().Trim('"'))
        if ($p -notmatch '^[A-Za-z]:\\' -or $p.Contains('%')) { return $false }
        $raiz = [IO.Path]::GetPathRoot($p)
        if (([IO.DriveInfo]::new($raiz)).DriveType -ne [IO.DriveType]::Fixed) { return $false }
        return (-not (Test-Path -LiteralPath $p -ErrorAction Stop))
    } catch { return $false }
}

function Executavel-RastroAusente {
    param([string]$Comando)
    if ([string]::IsNullOrWhiteSpace($Comando)) { return $false }
    $an = Analisar-LinhaComando ([Environment]::ExpandEnvironmentVariables($Comando))
    if (-not $an -or [IO.Path]::GetExtension($an.exe) -ine '.exe') { return $false }
    return (Caminho-LocalAusente $an.exe)
}

function Caminho-RastroSeguro {
    param([string]$Caminho)
    try {
        if ($Caminho -notmatch '^[A-Za-z]:\\') { return $false }
        $full = [IO.Path]::GetFullPath($Caminho).TrimEnd('\')
        foreach ($bloqueado in @($env:SystemRoot,(Join-Path $env:ProgramData 'otimizadorpc'),$global:RaizEstado,$global:PastaApp)) {
            if (-not $bloqueado) { continue }
            $p = [IO.Path]::GetFullPath($bloqueado).TrimEnd('\')
            if ($full -ieq $p -or $full.StartsWith($p + '\',[StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        if ($full -match '\\(WindowsApps|Common Files|Microsoft\\Windows Defender)(\\|$)') { return $false }
        if ($full -match '\\Microsoft\\Windows(\\|$)') {
            $menuOk = $false
            foreach ($menu in @((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),(Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'))) {
                if ($full.StartsWith($menu + '\',[StringComparison]::OrdinalIgnoreCase)) { $menuOk = $true }
            }
            if (-not $menuOk) { return $false }
        }
        $permitido = $false
        foreach ($base in @($env:APPDATA,$env:LOCALAPPDATA,$env:ProgramData,$env:ProgramFiles,${env:ProgramFiles(x86)},(Join-Path $env:USERPROFILE 'Desktop'),(Join-Path $env:PUBLIC 'Desktop'))) {
            if ($base -and $full.StartsWith(([IO.Path]::GetFullPath($base).TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) { $permitido = $true; break }
        }
        if (-not $permitido) { return $false }
        $atual = $full
        while ($atual) {
            $item = Get-Item -LiteralPath $atual -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
            $pai = Split-Path -Parent $atual
            if (-not $pai -or $pai -eq $atual) { break }
            $atual = $pai
        }
        return $true
    } catch { return $false }
}

function Chave-RastroSegura {
    param([string]$Nativa)
    if ($Nativa -match '^HKEY_(LOCAL_MACHINE|CURRENT_USER)\\SOFTWARE\\(?:WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$') { return $true }
    if ($Nativa -notmatch '^HKEY_(LOCAL_MACHINE|CURRENT_USER)\\SOFTWARE\\(?:WOW6432Node\\)?[^\\]+(?:\\[^\\]+)?$') { return $false }
    return ($Nativa -notmatch '^HKEY_(LOCAL_MACHINE|CURRENT_USER)\\SOFTWARE\\(?:WOW6432Node\\)?(Microsoft|Classes|Policies|Clients|RegisteredApplications|WOW6432Node)(\\|$)')
}

# le o PATH bruto do registro (variaveis nao expandidas), junto com o tipo do valor
function Obter-PathBruto {
    param([string]$Escopo)
    try {
        $ck = $null
        if ($Escopo -eq 'Machine') {
            $ck = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
        } else {
            $ck = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
        }
        if ($null -eq $ck) { return $null }
        $valor = $ck.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $tipo = $null
        try { $tipo = $ck.GetValueKind('Path') } catch { }
        $ck.Close()
        return @{ valor = $valor; tipo = $tipo }
    } catch { return $null }
}

function Varrer-Rastros {
    param($Prog)
    $achados = New-Object System.Collections.ArrayList
    $alvoBase = ([string]$Prog.nome).ToLower()
    $alvoBase = $alvoBase -replace '\([^)]*\)', ''
    $alvoBase = $alvoBase -replace '\b(x64|x86|64-bit|32-bit)\b', ''
    $alvoBase = $alvoBase.Trim()
    if ([string]::IsNullOrWhiteSpace($alvoBase)) { $alvoBase = ([string]$Prog.nome).ToLower() }
    $compacto = ($alvoBase -replace '[^a-z0-9]', '')

    $genericos = @('microsoft', 'windows', 'programs', 'program', 'common files', 'security', 'update', 'runtime', 'intel', 'nvidia', 'amd', 'realtek')
    if ($genericos -contains $alvoBase) {
        Avisar 'Nome generico' ('"{0}" e generico demais pra uma varredura segura (casaria com muitas coisas inocentes). desinstale primeiro e use programas de nome especifico.' -f $Prog.nome)
        return @()
    }

    # 1. entrada de desinstalacao que sobrou no registro
    try {
        if (-not [string]::IsNullOrWhiteSpace($Prog.chavePs) -and (Test-Path -LiteralPath $Prog.chavePs)) {
            [void]$achados.Add([pscustomobject]@{ tipo = 'chave'; caminho = $Prog.chavePs; extra = 'entrada de desinstalacao - confirme que o app foi desinstalado' })
        }
    } catch { }

    # 2. pastas em appdata, programdata e program files
    $raizesPastas = @(
        , @($env:APPDATA, 1)
        , @($env:LOCALAPPDATA, 1)
        , @($env:PROGRAMDATA, 1)
        , @($env:ProgramFiles, 0)
        , @(${env:ProgramFiles(x86)}, 0)
    )
    foreach ($par in $raizesPastas) {
        $raiz = $par[0]
        $prof = [int]$par[1]
        if ([string]::IsNullOrWhiteSpace($raiz) -or -not (Test-Path $raiz)) { continue }
        try {
            $pastas = @(Get-ChildItem -Path $raiz -Directory -Depth $prof -ErrorAction SilentlyContinue)
        } catch { $pastas = @() }
        foreach ($d in $pastas) {
            if ((Nome-RastroExato $d.Name $compacto) -and (Caminho-RastroSeguro $d.FullName)) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'pasta'; caminho = $d.FullName; extra = 'pasta com nome correspondente; confira o conteudo' })
            }
        }
        Atualizar-UI
    }

    # 3. atalhos do menu iniciar e da area de trabalho
    $menus = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop')
    )
    foreach ($menu in $menus) {
        if ([string]::IsNullOrWhiteSpace($menu) -or -not (Test-Path $menu)) { continue }
        try {
            $itens = @(Get-ChildItem -Path $menu -Recurse -Depth 1 -ErrorAction SilentlyContinue)
        } catch { $itens = @() }
        foreach ($f in $itens) {
            if (-not (Nome-RastroExato $f.BaseName $compacto) -or -not (Caminho-RastroSeguro $f.FullName)) { continue }
            if ($f.PSIsContainer) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'pasta'; caminho = $f.FullName; extra = 'pasta do menu iniciar' })
            } elseif ($f.Extension -eq '.lnk') {
                [void]$achados.Add([pscustomobject]@{ tipo = 'arquivo'; caminho = $f.FullName; extra = 'atalho' })
            }
        }
        Atualizar-UI
    }

    # 4. chaves de registro com o nome do programa
    $raizesReg = @(
        , @('HKCU:\Software', 1)
        , @('HKLM:\Software', 0)
        , @('HKLM:\SOFTWARE\WOW6432Node', 0)
    )
    foreach ($par in $raizesReg) {
        $raiz = $par[0]
        $prof = [int]$par[1]
        if (-not (Test-Path $raiz)) { continue }
        try {
            $chs = @(Get-ChildItem -Path $raiz -Depth $prof -ErrorAction SilentlyContinue)
        } catch { $chs = @() }
        foreach ($k in $chs) {
            if ((Nome-RastroExato $k.PSChildName $compacto) -and (Chave-RastroSegura $k.Name)) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'chave'; caminho = $k.PSPath; extra = 'chave de registro' })
            }
        }
        Atualizar-UI
    }

    # 5. servicos que apontam pro programa (vao ficar orfaos)
    try {
        $servicos = @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | Where-Object { (Bater-Nome ([string]$_.PathName) $alvoBase $compacto) -and (Executavel-RastroAusente $_.PathName) })
        foreach ($s in $servicos) {
            if ([string]::IsNullOrWhiteSpace([string]$s.Name)) { continue }
            [void]$achados.Add([pscustomobject]@{ tipo = 'servico'; caminho = [string]$s.Name; extra = ('servico orfao: ' + [string]$s.State + ' - ' + [string]$s.PathName) })
        }
    } catch { }
    Atualizar-UI

    # 6. tarefas agendadas que executam o programa
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            if (@($t.Actions).Count -ne 1 -or $t.TaskPath -like '\\Microsoft\\*') { continue }
            $exe = ''
            $casou = $false
            foreach ($a in @($t.Actions)) {
                if ($null -eq $a) { continue }
                if (Bater-Nome ([string]$a.Execute) $alvoBase $compacto) { $casou = $true }
                if (Bater-Nome ([string]$a.Arguments) $alvoBase $compacto) { $casou = $true }
                if ($exe -eq '' -and -not [string]::IsNullOrWhiteSpace([string]$a.Execute)) { $exe = [string]$a.Execute }
            }
            if (-not $casou -or -not (Caminho-LocalAusente $exe)) { continue }
            [void]$achados.Add([pscustomobject]@{ tipo = 'tarefa'; caminho = ([string]$t.TaskPath + [string]$t.TaskName); tarefaPath = [string]$t.TaskPath; tarefaNome = [string]$t.TaskName; extra = ('tarefa agendada: ' + $exe) })
        }
    } catch { }
    Atualizar-UI

    # 7. regras de firewall cujo programa e o do alvo
    try {
        $fw = netsh advfirewall firewall show rule name=all verbose 2>$null
        $nomeRegra = ''
        foreach ($ln in @($fw)) {
            $l = ([string]$ln).Trim()
            if ($l -match '^(Rule Name|Nome da Regra)\s*:\s*(.+)$') { $nomeRegra = $Matches[2].Trim(); continue }
            if ($nomeRegra -ne '' -and $l -match '^(Program|Programa)\s*:\s*(.*)$') {
                $prog = $Matches[2].Trim()
                if ((Bater-Nome $prog $alvoBase $compacto) -and (Caminho-LocalAusente $prog)) {
                    [void]$achados.Add([pscustomobject]@{ tipo = 'firewall'; caminho = $nomeRegra; programa = $prog; extra = ('regra de firewall: ' + $prog) })
                }
            }
        }
    } catch { }
    Atualizar-UI

    # 8. inicializacao (entradas Run) que apontam pro programa
    $chavesRun = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($ck2 in $chavesRun) {
        if (-not (Test-Path $ck2)) { continue }
        $item = Get-Item -Path $ck2 -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        foreach ($vn in @($item.GetValueNames())) {
            $dado = [string]$item.GetValue($vn)
            if (((Bater-Nome $vn $alvoBase $compacto) -or (Bater-Nome $dado $alvoBase $compacto)) -and (Executavel-RastroAusente $dado)) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'run'; caminho = ($ck2 + ' :: ' + $vn); chave = $ck2; valor = [string]$vn; extra = ('inicializacao: ' + $dado) })
            }
        }
    }

    # 9. PATH: entradas com o nome do programa
    foreach ($escopo in @('Machine', 'User')) {
        $bruto = Obter-PathBruto $escopo
        if ($null -eq $bruto -or $null -eq $bruto.valor) { continue }
        foreach ($ent in @($bruto.valor -split ';')) {
            if ([string]::IsNullOrWhiteSpace($ent)) { continue }
            if ((Bater-Nome $ent $alvoBase $compacto) -and (Caminho-LocalAusente $ent)) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'path'; caminho = ('PATH ' + $escopo + ' :: ' + $ent.Trim()); escopo = $escopo; entrada = $ent; extra = 'entrada do PATH' })
            }
        }
    }

    # tira duplicados (mesmo caminho achado em mais de uma raiz)
    $vistos = @{}
    $finais = New-Object System.Collections.ArrayList
    foreach ($a in $achados) {
        $id = $a.tipo + '|' + $a.caminho
        if ($vistos.ContainsKey($id)) { continue }
        $vistos[$id] = $true
        [void]$finais.Add($a)
    }
    return @($finais | Where-Object {$_.tipo -ne 'firewall'})
}

function Executar-Varredura {
    param($Prog)
    $global:ProgVarredura=$null
    $global:RastrosExibidos=@()
    $global:UI.ListaRastros.Items.Clear()
    Atualizar-ContagemRastros
    try { $info=Validar-ProtecaoPrograma $Prog }
    catch { Avisar 'Varredura bloqueada' $_.Exception.Message; return }
    Status ('varrendo rastros de ' + $Prog.nome + '...')
    Ocupado $true
    # PowerShell 5.1 desembrulha a saida de um unico item; preserve o array.
    $rastros = @(Varrer-Rastros $Prog)
    Ocupado $false
    $global:ProgVarredura = $Prog
    $global:RastrosExibidos = $rastros
    $lb = $global:UI.ListaRastros
    $lb.Items.Clear()
    foreach ($r in $rastros) {
        $mostro = $r.caminho -replace '^.*::', ''
        $extra = ''
        if (-not [string]::IsNullOrWhiteSpace($r.extra)) { $extra = '  (' + $r.extra + ')' }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $marca = New-Object System.Windows.Controls.CheckBox
        $marca.Content = ('[{0}]  {1}{2}' -f $r.tipo, $mostro, $extra)
        $marca.IsChecked = $false
        $marca.Add_Checked({ Atualizar-ContagemRastros })
        $marca.Add_Unchecked({ Atualizar-ContagemRastros })
        $item.Content = $marca
        $item.Tag = $r
        [void]$lb.Items.Add($item)
    }
    Atualizar-ContagemRastros
    if ($rastros.Count -eq 0) {
        $global:UI.RotuloRastros.Text = ('varredura de "{0}": nenhum rastro encontrado (limpo!).' -f $Prog.nome)
        Log ('varredura de "' + $Prog.nome + '": nenhum rastro encontrado.')
        Status 'nenhum rastro encontrado.'
    } else {
        $global:UI.RotuloRastros.Text = ('rastros de "{0}": {1} candidato(s). marque as caixas do que deseja remover.' -f $Prog.nome, $rastros.Count)
        Log ('varredura de "' + $Prog.nome + '": ' + $rastros.Count + ' rastro(s) encontrado(s).')
        Status ('{0} rastro(s) encontrado(s).' -f $rastros.Count)
    }
}

function Clique-VarrerRastros {
    $selecionados = @(Obter-Selecionados $global:UI.ListaProgramas $global:ProgramasExibidos)
    if ($selecionados.Count -eq 0) {
        Avisar 'Selecione um programa' 'Clique numa linha da lista de programas acima (so um por vez).'
        return
    }
    if ($selecionados.Count -gt 1) {
        Avisar 'Um por vez' 'A varredura e feita em um programa por vez; deixe so uma linha selecionada.'
        return
    }
    Executar-Varredura $selecionados[0]
}

# ---- limpeza dos rastros (tudo pra quarantena, nada apagado de vez) ----

function Apagar-Rastro {
    param($Rastro, [string]$PastaSessao, [int]$Num)
    Confirmar-PermissaoAlteracao

    # servico orfao: para e desativa (nunca apaga; desfazer restaura tipo e estado)
    if ($Rastro.tipo -eq 'servico') {
        $detalhes = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -eq $Rastro.caminho })
        if ($detalhes.Count -ne 1 -or -not (Executavel-RastroAusente $detalhes[0].PathName)) { throw 'Servico nao confirmado como candidato orfao.' }
        Alterar-ServicoComJournal $Rastro.caminho 'Disabled'
        Log ('servico candidato desativado com snapshot: ' + $Rastro.caminho)
        return
    }

    # tarefa agendada: so desativa (nunca apaga; desfazer reativa)
    if ($Rastro.tipo -eq 'tarefa') {
        $t = Get-ScheduledTask -TaskPath $Rastro.tarefaPath -TaskName $Rastro.tarefaNome -ErrorAction Stop
        if ($t.TaskPath -like '\\Microsoft\\*' -or @($t.Actions).Count -ne 1 -or -not (Caminho-LocalAusente ([string]$t.Actions[0].Execute))) { throw 'Tarefa nao confirmada como candidata orfa.' }
        Desativar-TarefaComJournal $Rastro.tarefaPath $Rastro.tarefaNome
        Log ('tarefa candidata processada com journal: ' + $Rastro.caminho)
        return
    }

    # Desativa a regra local pelo ID; preserva todos os filtros e propriedades.
    if ($Rastro.tipo -eq 'firewall') {throw 'Firewall somente consulta; revise regras pela ferramenta autorizada.'}

    # Run: preserva somente o valor removido, nao sobrescreve os outros.
    if ($Rastro.tipo -eq 'run') {
        $leitura = Ler-ValorRegistro -CaminhoPS $Rastro.chave -Nome $Rastro.valor
        if (-not $leitura.existia) { Log ('ja sumiu: ' + $Rastro.caminho); return }
        if (-not (Executavel-RastroAusente ([string]$leitura.valor))) { throw 'Entrada de inicializacao ainda aponta para executavel existente ou incerto.' }
        Registrar-Jornal ([pscustomobject]@{
            tipo = 'registro'; caminho = $Rastro.chave; nome = $Rastro.valor
            existia = $true; tipoAnterior = $leitura.tipo
            valorAnterior = (ConvertTo-Json -InputObject $leitura.valor -Compress)
            valorAnteriorEstruturado = [pscustomobject]@{ valor = $leitura.valor }
            existiaDepois = $false; tipoDepois = $leitura.tipo
            valorDepoisEstruturado = [pscustomobject]@{ valor = $null }
        })
        Remove-ItemProperty -LiteralPath $Rastro.chave -Name $Rastro.valor -ErrorAction Stop
        Log ('entrada de inicializacao removida com journal: ' + $Rastro.caminho)
        return
    }

    # entrada do PATH: tira so a entrada morta, mantendo o resto e o tipo do valor
    if ($Rastro.tipo -eq 'path') {
        if (-not (Caminho-LocalAusente $Rastro.entrada)) { throw 'Entrada PATH existente ou incerta; preservada.' }
        $bruto = Obter-PathBruto $Rastro.escopo
        if ($null -eq $bruto -or $null -eq $bruto.valor) { Log ('nao consegui ler o PATH ' + $Rastro.escopo); return }
        $lista = @($bruto.valor -split ';')
        if ($lista -notcontains $Rastro.entrada) { Log ('ja saiu do PATH: ' + $Rastro.entrada); return }
        $nova = @(($bruto.valor -split ';') | Where-Object { $_ -ne $Rastro.entrada }) -join ';'
        Registrar-Jornal ([pscustomobject]@{ tipo = 'path-entrada'; escopo = $Rastro.escopo; entrada = $Rastro.entrada; valorAnterior = $bruto.valor; valorDepois = $nova; tipoAnterior = [string]$bruto.tipo })
        $ck = $null
        if ($Rastro.escopo -eq 'Machine') {
            $ck = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
        } else {
            $ck = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        }
        if ($null -eq $ck) { Log ('nao consegui abrir a chave do PATH ' + $Rastro.escopo); return }
        if ($null -ne $bruto.tipo) { $ck.SetValue('Path', $nova, $bruto.tipo) } else { $ck.SetValue('Path', $nova) }
        $ck.Close()
        Log ('entrada morta removida do PATH ' + $Rastro.escopo + ' (vale apos relogon; desfazer restaura): ' + $Rastro.entrada)
        return
    }

    if ($Rastro.tipo -eq 'chave') {
        if (-not (Test-Path -LiteralPath $Rastro.caminho)) { Log ('ja sumiu: ' + $Rastro.caminho); return }
        $chaveReg = Get-Item -LiteralPath $Rastro.caminho -ErrorAction Stop
        try { $nativa = [string]$chaveReg.Name } finally { $chaveReg.Close() }
        if (-not (Chave-RastroSegura $nativa)) { throw 'Chave protegida ou fora dos escopos suportados.' }
        $folha = ($nativa -replace '\\', '_')
        $folha = ($folha -replace '[^a-zA-Z0-9_.{}-]', '')
        if ($folha.Length -gt 70) { $folha = $folha.Substring($folha.Length - 70) }
        $arqReg = Join-Path $PastaSessao ('{0:00}_registro_{1}.reg' -f $Num, $folha)
        Executar-RegNativo -Operacao export -Alvo $nativa -Arquivo $arqReg
        if (-not (Test-Path -LiteralPath $arqReg -PathType Leaf)) { throw 'Backup do registro falhou; chave preservada.' }
        $hash=(Get-FileHash -LiteralPath $arqReg -Algorithm SHA256 -ErrorAction Stop).Hash
        [void](Confirmar-BackupQuarentena $arqReg $hash)
        $entrada=[pscustomobject]@{ tipo = 'quarantena-registro'; chave = $nativa; arquivoReg = $arqReg;hashBackup=$hash }
        Registrar-Jornal $entrada
        Remove-Item -LiteralPath $Rastro.caminho -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Rastro.caminho) {throw 'Remocao de chave nao confirmada.'}
        Confirmar-EfeitoJournal $entrada
        Log ('chave apagada (backup .reg na quarantena): ' + $nativa)
    } elseif ($Rastro.tipo -in @('arquivo','pasta')) {
        if (-not (Test-Path -LiteralPath $Rastro.caminho)) { Log ('ja sumiu: ' + $Rastro.caminho); return }
        if (-not (Caminho-RastroSeguro $Rastro.caminho)) { throw 'Caminho protegido, redirecionado ou fora dos locais permitidos.' }
        $folha = Split-Path -Leaf $Rastro.caminho
        $destino = Join-Path $PastaSessao ('{0:00}_{1}' -f $Num, $folha)
        if (Test-Path -LiteralPath $destino) { throw 'Destino da quarentena ja existe.' }
        $origem=Get-Item -LiteralPath $Rastro.caminho -Force -ErrorAction Stop
        $hash=if (-not $origem.PSIsContainer) {(Get-FileHash -LiteralPath $Rastro.caminho -Algorithm SHA256 -ErrorAction Stop).Hash} else {$null}
        $entrada=[pscustomobject]@{ tipo = 'quarantena-arquivo'; origem = $Rastro.caminho; destino = $destino;hashBackup=$hash;pasta=[bool]$origem.PSIsContainer }
        Registrar-Jornal $entrada
        Move-Item -LiteralPath $Rastro.caminho -Destination $destino -ErrorAction Stop
        [void](Confirmar-BackupQuarentena $destino $hash -PastaPermitida:([bool]$origem.PSIsContainer))
        if (Test-Path -LiteralPath $Rastro.caminho) {throw 'Movimentacao nao confirmada.'}
        Confirmar-EfeitoJournal $entrada
        Log ('rastro movido pra quarantena: ' + $Rastro.caminho)
    } else { throw ('Tipo de rastro desconhecido: ' + $Rastro.tipo) }
}

# A caixa marcada e a unica fonte de verdade; o realce azul nao seleciona rastros.
function Obter-RastrosMarcados {
    param($ListBox)
    foreach ($linha in $ListBox.Items) {
        if ($linha -is [System.Windows.Controls.ListBoxItem] -and $null -ne $linha.Tag -and
            $linha.Content -is [System.Windows.Controls.CheckBox] -and $linha.Content.IsChecked -eq $true) {
            $linha.Tag
        }
    }
}

function Atualizar-ContagemRastros {
    if ($global:UI.ContainsKey('InfoMarcadosRastros') -and $global:UI.InfoMarcadosRastros) {
        $global:UI.InfoMarcadosRastros.Text = ('{0} marcado(s)' -f @(Obter-RastrosMarcados $global:UI.ListaRastros).Count)
    }
}

function Marcar-Rastros {
    param([bool]$Marcar)
    foreach ($linha in $global:UI.ListaRastros.Items) {
        if ($linha.Content -is [System.Windows.Controls.CheckBox]) { $linha.Content.IsChecked = $Marcar }
    }
    Atualizar-ContagemRastros
}

function Confirmar-ProgramaAusenteParaLimpeza {
    param($Prog)
    $info=Validar-ProtecaoPrograma $Prog
    if (-not $Prog.chavePs) { throw 'Registro original nao identificado. Limpeza indisponivel.' }
    if (Test-Path -LiteralPath $Prog.chavePs -ErrorAction Stop) { throw 'Entrada de desinstalacao ainda existe. Desinstale pelo Windows antes de remover rastros.' }
    return $info
}

function Clique-ApagarRastros {
    Confirmar-PermissaoAlteracao
    $lb = $global:UI.ListaRastros
    $selecionados = @(Obter-RastrosMarcados $lb)
    Log ('limpeza de rastros: {0} marcado(s) de {1} exibido(s).' -f $selecionados.Count, $lb.Items.Count)
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque a caixa ao lado de cada rastro ou use "Marcar todos". Apenas o realce azul nao marca a caixa.'
        return
    }
    try { $info=Confirmar-ProgramaAusenteParaLimpeza $global:ProgVarredura }
    catch { Avisar 'Limpeza bloqueada' $_.Exception.Message; return }
    $resumo = ''
    if ($selecionados.Count -le 12) {
        $resumo = ($selecionados | ForEach-Object { ($_.tipo + ': ' + ($_.caminho -replace '^.*::', '')) }) -join "`n"
    } else {
        $resumo = (($selecionados | Select-Object -First 10 | ForEach-Object { ($_.tipo + ': ' + ($_.caminho -replace '^.*::', '')) }) -join "`n")
        $resumo = $resumo + "`n...e mais " + ($selecionados.Count - 10) + ' item(ns).'
    }
    $nomeProg = ''
    if ($null -ne $global:ProgVarredura) { $nomeProg = [string]$global:ProgVarredura.nome }
    $msg = ('Apagar {0} rastro(s)' -f $selecionados.Count)
    if ($nomeProg -ne '') { $msg = $msg + (' de "{0}"' -f $nomeProg) }
    if ($info.risco -ne 'Normal') { $msg += (' - CAUTELA: ' + $info.motivo) }
    $msg = $msg + ("`n`n" + $resumo + "`n`nConfirme que o aplicativo ja foi desinstalado. A varredura por nome pode encontrar dados de aplicativos ainda instalados; apagar a entrada de desinstalacao nao desinstala o programa. Arquivos e chaves selecionados recebem journal antes da alteracao. A recuperacao pode exigir revisao manual. Continuar?")
    if (-not (Perguntar 'Apagar rastros' $msg)) { return }
    try { [void](Confirmar-ProgramaAusenteParaLimpeza $global:ProgVarredura) }
    catch { Avisar 'Limpeza bloqueada' $_.Exception.Message; return }

    Garantir-PastaPrivada $global:PastaQuarantena
    $pastaSessao = Join-Path $global:PastaQuarantena ((Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,12))
    Garantir-PastaPrivada $pastaSessao

    Status 'limpando rastros...'
    Ocupado $true
    Iniciar-Sessao 'limpar-rastros'
    $apagados = 0
    $i = 0
    $progresso = Iniciar-ProgressoLote 'Quarentena de rastros' $selecionados.Count
    try { foreach ($r in $selecionados) {
        if (-not (Continuar-ProgressoLote $progresso $r.caminho)) { break }
        $i++
        Status ('limpando {0}/{1}...' -f $i, $selecionados.Count)
        try {
            [void](Confirmar-ProgramaAusenteParaLimpeza $global:ProgVarredura)
            Apagar-Rastro $r $pastaSessao $i
            $apagados++
        } catch {
            Log ('falha ao apagar {0}: {1}' -f $r.caminho, $_.Exception.Message) -Erro
        }
        Atualizar-UI
    } } finally { Fechar-ProgressoLote $progresso }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($progresso.cancelado) { Log 'limpeza interrompida; journal preservado.'; Status 'limpeza interrompida.'; return }
    $res = ('limpeza: {0} rastro(s) processado(s) sem excecao; consulte o log para confirmar as alteracoes.' -f $apagados)
    if ($arq) { $res = $res + ' journal: ' + (Split-Path -Leaf $arq) }
    Log $res
    if ($global:ErrosSessao -gt 0) { Status 'limpeza com falhas; consulte o log.' } else { Status 'limpeza processada; confira o log.' }
    if (Perguntar 'Conferir' 'Varrer de novo para conferir se sobrou algo?') {
        if ($null -ne $global:ProgVarredura) { Executar-Varredura $global:ProgVarredura }
    } else {
        $lb.Items.Clear()
        $global:RastrosExibidos = @()
        Atualizar-ContagemRastros
        $global:UI.RotuloRastros.Text = 'rastros: selecione um programa e clique em varrer.'
    }
}
