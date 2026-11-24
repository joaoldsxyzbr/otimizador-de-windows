# gui.ps1 - monta as paginas a partir dos catalogos e liga todos os botoes

# ---- criacao de controles ----

function Nova-Checkbox {
    param([string]$Texto, $Tag, [string]$Dica, [bool]$Marcado = $false)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $Texto
    $cb.Tag = $Tag
    $cb.Margin = '2,3,0,3'
    $cb.Foreground = (Cor-Tema '#e5e7eb')
    $cb.FontSize = 13
    $cb.IsChecked = $Marcado
    if (-not [string]::IsNullOrWhiteSpace($Dica)) {
        $cb.ToolTip = $Dica
        [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($cb,$true)
    }
    return $cb
}

function Nova-Categoria {
    param([string]$Titulo)
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = $Titulo
    $gb.Foreground = (Cor-Tema '#93c5fd')
    $gb.BorderBrush = (Cor-Tema '#374151')
    $gb.Margin = '0,10,0,4'
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '6,4,0,0'
    $gb.Content = $sp
    return $gb
}

# percorre a arvore visual e devolve todos os checkboxes
function Get-Checkboxes {
    param($Elemento)
    $lista = @()
    if ($Elemento -is [System.Windows.Controls.Panel]) {
        foreach ($filho in $Elemento.Children) { $lista += (Get-Checkboxes $filho) }
    } elseif ($Elemento -is [System.Windows.Controls.ContentControl]) {
        if ($Elemento -is [System.Windows.Controls.CheckBox]) { $lista += $Elemento }
        elseif ($null -ne $Elemento.Content -and $Elemento.Content -isnot [string]) {
            $lista += (Get-Checkboxes $Elemento.Content)
        }
    }
    return $lista
}

# ---- montagem das paginas ----

# Cautela e finalidade sao distintas de ganho de desempenho.
function Classificar-RiscoAjuste {
    param($Tweak)
    if ($Tweak.apenasManual -or @($Tweak.acoes | Where-Object { $_.tipo -in @('servico','appx','recurso','energia') }).Count -gt 0) { return 'cautela alta' }
    if ($Tweak.categoria -in @('Preferencias','Barra de tarefas e menu Iniciar','Explorador de arquivos')) { return 'preferencia visual' }
    return 'revise impacto'
}

function Obter-GuiaAjuste {
    param($Tweak)
    $risco=Classificar-RiscoAjuste $Tweak
    $escopo=@($Tweak.acoes | ForEach-Object {
        if ($_.tipo -eq 'registro') { if ($_.caminho -like 'HKCU:*') {'usuario atual'} else {'computador'} }
        elseif ($_.tipo -eq 'servico') {'servicos do computador'}
        elseif ($_.tipo -eq 'energia') {'plano de energia'}
        else {$_.tipo}
    } | Sort-Object -Unique) -join ', '
    $recuperacao='Journal registra valores anteriores; conflitos ou falhas podem exigir revisao manual.'
    if (@($Tweak.acoes | Where-Object { $_.tipo -eq 'appx' }).Count -gt 0) { $recuperacao='Reinstalacao e dados do aplicativo nao garantidos.' }
    $compat=switch ($Tweak.so) {'win11' {'Windows 11'} 'win10' {'Windows 10'} default {'Windows 10/11'}}
    $impacto=if ($Tweak.impacto) {$Tweak.impacto} else {'Revise o efeito dos valores; impacto nao medido.'}
    $notaCompat=if ($Tweak.compatibilidade) {$Tweak.compatibilidade} else {'Compatibilidade especifica nao confirmada.'}
    if ($Tweak.buildMinima) {$notaCompat+=' Build minima conservadora: '+$Tweak.buildMinima+'.'}
    $reinicio=if ($Tweak.reinicio) {$Tweak.reinicio} else {'Pode exigir relogon ou reinicio.'}
    return [pscustomobject]@{ risco=$risco; texto=(@($Tweak.desc,"Impacto: $impacto","Compatibilidade: $compat. $notaCompat","Escopo: $escopo","Recuperacao: $recuperacao",$reinicio) -join "`n") }
}

function Atualizar-RotuloAjuste {
    param($Cb,[string]$Estado)
    $t=$Cb.Tag
    $rotulo=switch ($Estado) {'aplicado' {'ja aplicado'} 'parcial' {'parcial'} 'nao' {'nao aplicado'} default {'estado nao confirmado'}}
    $Cb.Content=$t.nome + ' [' + (Classificar-RiscoAjuste $t) + '] (' + $rotulo + ')'
    if ($t.apenasManual) { $Cb.Content += ' [manual]' }
    $Cb.ToolTip=(Obter-GuiaAjuste $t).texto
    if ($global:ModoProtegido) { $Cb.Content+=' [somente consulta]'; $Cb.IsChecked=$false; $Cb.IsEnabled=$false }
    elseif (-not $Cb.IsEnabled) { $Cb.Content+=' [indisponivel nesta instalacao]'; $Cb.IsChecked=$false }
    $Cb.Foreground=switch ($Estado) {'aplicado' {Cor-Tema '#86efac'} 'parcial' {Cor-Tema '#fde047'} default {Cor-Tema '#e5e7eb'}}
    if ($Estado -eq 'aplicado') { $Cb.IsChecked=$false }
}

function Montar-PaginaAjustes {
    $win11 = Eh-Win11
    $ctx=Obter-ContextoAjustes
    $painel = $global:UI.ListaAjustes
    $painel.Children.Clear()
    $grupos = @{}
    foreach ($t in $global:CatalogoTweaks.tweaks) {
        if ($t.so -eq 'win11' -and -not $win11) { continue }
        if ($t.so -eq 'win10' -and $win11) { continue }
        if (-not $grupos.ContainsKey($t.categoria)) {
            $grupos[$t.categoria] = Nova-Categoria $t.categoria
            [void]$painel.Children.Add($grupos[$t.categoria])
        }
        $cb=Nova-Checkbox -Texto $t.nome -Tag $t -Dica (Obter-GuiaAjuste $t).texto
        $cb.IsEnabled=(Testar-CompatibilidadeAjuste $t $ctx)
        Atualizar-RotuloAjuste $cb 'desconhecido'
        [void]$grupos[$t.categoria].Content.Children.Add($cb)
    }
}

function Obter-GuiaUwp {
    param($Entrada,$Pacotes)
    $achados=@($Pacotes | Where-Object { $_.Name -eq $Entrada.pacote })
    $dependentes=@($achados | ForEach-Object { Obter-DependentesAppx $_ $Pacotes } | Sort-Object -Unique)
    $bloqueado=(@($achados | Where-Object { Testar-AppxProtegido $_ }).Count -gt 0 -or $dependentes.Count -gt 0)
    $categoria=if ($bloqueado -or $Entrada.protegido) {'Sistema/dependencia - bloqueado'} elseif ($Entrada.desconhecido) {'Nao catalogado - bloqueado'} elseif ($Entrada.remover) {'Opcional - se nao usa'} else {'Aplicativo util - cautela'}
    $motivo=if ($bloqueado -or $Entrada.protegido) {'Metadados ou nome indicam componente protegido. Remocao indisponivel.'} elseif ($Entrada.desconhecido) {'Sem classificacao no catalogo local; remocao indisponivel.'} else {'Remover somente se nao usa. Outros recursos podem depender do aplicativo. Dados locais e reinstalacao nao garantidos.'}
    if ($dependentes.Count) { $motivo+=' Dependentes declarados: '+($dependentes -join ', ') }
    return [pscustomobject]@{ categoria=$categoria; permitido=(-not ($bloqueado -or $Entrada.protegido -or $Entrada.desconhecido) -and $achados.Count -gt 0); instalado=($achados.Count -gt 0); texto=($Entrada.desc + "`n" + $motivo + "`nEscopo: usuario atual. Nenhum desprovisionamento.") }
}

function Montar-PaginaDebloat {
    param([object[]]$Pacotes)
    $win11=Eh-Win11
    $painel=$global:UI.ListaUwp
    $painel.Children.Clear()
    $grupos=@{}
    $entradas=@($global:CatalogoUwp.pacotes | Where-Object { ($_.so -ne 'win11' -or $win11) -and ($_.so -ne 'win10' -or -not $win11) })
    foreach ($p in @($pacotes | Sort-Object Name -Unique)) {
        if ($p.Name -notin @($entradas | ForEach-Object {$_.pacote})) {
            $entradas += [pscustomobject]@{nome=$p.Name; pacote=$p.Name; desc='Pacote instalado nao catalogado.'; desconhecido=$true; protegido=(Testar-AppxProtegido $p)}
        }
    }
    foreach ($p in $entradas) {
        $info=Obter-GuiaUwp $p $pacotes
        $titulo=$info.categoria
        if (-not $grupos.ContainsKey($titulo)) {
            $grupos[$titulo]=Nova-Categoria $titulo
            [void]$painel.Children.Add($grupos[$titulo])
        }
        $estado=if ($info.instalado) {'instalado'} else {'nao instalado'}
        $cb=Nova-Checkbox -Texto ($p.nome + ' [' + $estado + ']') -Tag $p -Dica $info.texto
        $cb.IsEnabled=(-not $global:ModoProtegido -and $info.permitido)
        if (-not $cb.IsEnabled) {$cb.Foreground=Cor-Tema '#6b7280'}
        [void]$grupos[$titulo].Content.Children.Add($cb)
    }
    Aplicar-Filtro -Texto ([string]$global:UI.FiltroUwp.Text) -Painel $painel
}

function Montar-PaginaInstalar {
    $painel = $global:UI.ListaApps
    $painel.Children.Clear()
    $grupos = @{}
    foreach ($a in $global:CatalogoApps.aplicativos) {
        if (-not $grupos.ContainsKey($a.categoria)) {
            $grupos[$a.categoria] = Nova-Categoria $a.categoria
            [void]$painel.Children.Add($grupos[$a.categoria])
        }
        $fonte=if ($a.fonte -eq 'msstore') {'msstore'} else {'winget'}
        $dica=$a.desc+"`nID: "+$a.id+"`nFonte: "+$fonte+"`nInstalar nao solicita upgrade automatico. Use a consulta WinGet para identificar versoes instaladas/disponiveis."
        $cb=Nova-Checkbox -Texto ($a.nome+' ['+$fonte+']') -Tag $a -Dica $dica
        if ($global:ModoProtegido) { $cb.IsEnabled=$false }
        [void]$grupos[$a.categoria].Content.Children.Add($cb)
    }
}

function Montar-PaginaRecursos {
    $painel = $global:UI.ListaRecursos
    $painel.Children.Clear()
    $recursos = @(
        [pscustomobject]@{ nome = 'Hyper-V (virtualizacao)'; feat = 'Microsoft-Hyper-V-All'; desc = 'Plataforma de virtualizacao da Microsoft. Exige Windows Pro/Enterprise; no Home nao funciona.' }
        [pscustomobject]@{ nome = 'WSL 2 (plataforma de maquina virtual)'; feat = 'VirtualMachinePlatform'; desc = 'Base do WSL 2 para rodar Linux dentro do Windows. Depois de reiniciar rode: wsl --install -d Ubuntu' }
        [pscustomobject]@{ nome = 'WSL (componente)'; feat = 'Microsoft-Windows-Subsystem-Linux'; desc = 'Componente do Subsystem for Linux. Instale junto com o WSL 2.' }
        [pscustomobject]@{ nome = 'Windows Sandbox'; feat = 'Containers-DisposableClientVM'; desc = 'Windows descartavel e isolado para testar arquivos suspeitos. Exige Pro/Enterprise.' }
        [pscustomobject]@{ nome = '.NET Framework 3.5'; feat = 'NetFx3'; desc = 'Runtime antigo exigido por programas classicos. Baixa componentes da Microsoft, precisa de internet.' }
        [pscustomobject]@{ nome = 'DirectPlay (jogos antigos)'; feat = 'DirectPlay'; desc = 'Componente de rede para jogos classicos.' }
        [pscustomobject]@{ nome = 'Windows Media Player (legado)'; feat = 'WindowsMediaPlayer'; desc = 'WMP classico para midias antigas.' }
        [pscustomobject]@{ nome = 'Cliente Telnet'; feat = 'TelnetClient'; desc = 'Cliente telnet para testes de rede e equipamentos antigos.' }
    )
    $estados=@(); $consultou=$false
    if (-not $global:ModoProtegido) {
        try { $estados=@(Get-WindowsOptionalFeature -Online -ErrorAction Stop); $consultou=$true } catch { }
    }
    foreach ($r in $recursos) {
        $f=@($estados | Where-Object {$_.FeatureName -eq $r.feat})
        $estado=if (-not $consultou) {'consulta indisponivel'} elseif ($f.Count -ne 1) {'indisponivel nesta instalacao'} else {$f[0].State.ToString()}
        $cb=Nova-Checkbox -Texto ($r.nome+' ['+$estado+']') -Tag $r -Dica ($r.desc+"`nEstado: "+$estado+". Dependencias e reinicio podem exigir recuperacao manual.")
        $cb.IsEnabled=(-not $global:ModoProtegido -and $consultou -and $f.Count -eq 1 -and $estado -eq 'Disabled')
        [void]$painel.Children.Add($cb)
    }
}

function Montar-PaineisLegados {
    $painel = $global:UI.PainelLegado
    $painel.Children.Clear()
    $paineis = @(
        , @('Painel de Controle', 'control.exe')
        , @('Conexoes de Rede', 'ncpa.cpl')
        , @('Opcoes de Energia', 'powercfg.cpl')
        , @('Propriedades do Sistema', 'sysdm.cpl')
        , @('Data e Hora', 'timedate.cpl')
        , @('Som', 'mmsys.cpl')
        , @('Regiao', 'intl.cpl')
        , @('Contas de Usuario', 'netplwiz')
        , @('Gerenciador de Dispositivos', 'devmgmt.msc')
        , @('Gerenciamento de Disco', 'diskmgmt.msc')
    )
    foreach ($p in $paineis) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $p[0]
        $b.Tag = $p[1]
        $b.Margin = '3'
        $b.Padding = '10,6'
        $b.FontSize = 12
        $b.Add_Click({ Start-Process -FilePath $this.Tag | Out-Null })
        [void]$painel.Children.Add($b)
    }
}

function Atualizar-ListaDesfazer {
    $lb = $global:UI.ListaDesfazer
    $lb.Items.Clear()
    $lb.Tag = @{}
    foreach ($s in (Listar-Sessoes)) {
        $rotulo = $s.BaseName -replace '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_', ''
        $datahora = ($s.BaseName -split '_')[0]
        $extra = ''
        try {
            $json = Ler-JSON $s.FullName
            $concluidos = @($json.itens | Where-Object { $_.estadoReversao -eq 'concluido' }).Count
            $incertos = @($json.itens | Where-Object { $_.estadoReversao -eq 'em_andamento' }).Count
            $extra = (' - {0}/{1} revertidas: {2}' -f $concluidos, @($json.itens).Count, $json.rotulo)
            if ($incertos -gt 0) { $extra += ' [revisao manual necessaria]' }
        } catch { $extra = ' [journal invalido]' }
        [void]$lb.Items.Add(('{0} ({1}){2}' -f $datahora, $rotulo, $extra))
        $lb.Tag[$lb.Items.Count - 1] = $s.FullName
    }
    if ($lb.Items.Count -eq 0) { [void]$lb.Items.Add('(nenhuma sessao para desfazer ainda - vazio)') }
}

# ---- filtro das listas ----

# esconde checkbox cujo nome/descricao nao bate com o texto; colapsa grupos vazios
function Aplicar-Filtro {
    param([string]$Texto, $Painel)
    $f = $Texto.Trim().ToLower()
    foreach ($grupo in $Painel.Children) {
        if ($grupo -isnot [System.Windows.Controls.GroupBox]) { continue }
        $algumVisivel = $false
        foreach ($cb in $grupo.Content.Children) {
            $nome = ''
            $desc = ''
            if ($null -ne $cb.Tag) {
                if ($null -ne $cb.Tag.PSObject.Properties['nome']) { $nome = [string]$cb.Tag.nome }
                if ($null -ne $cb.Tag.PSObject.Properties['desc']) { $desc = [string]$cb.Tag.desc }
            }
            $ok = ($f -eq '') -or ($nome.ToLower().Contains($f)) -or ($desc.ToLower().Contains($f)) -or ([string]$cb.Content).ToLower().Contains($f) -or ([string]$cb.ToolTip).ToLower().Contains($f)
            if ($ok) {
                $cb.Visibility = 'Visible'
                $algumVisivel = $true
            } else {
                $cb.Visibility = 'Collapsed'
            }
        }
        if ($algumVisivel) { $grupo.Visibility = 'Visible' } else { $grupo.Visibility = 'Collapsed' }
    }
}

# ---- estado atual (o que ja esta aplicado) ----

function Verificar-EstadoAjustes {
    Status 'verificando estado dos ajustes...'
    Ocupado $true
    $contagens = @{ aplicado = 0; parcial = 0; nao = 0; desconhecido = 0 }
    foreach ($cb in (Get-Checkboxes $global:UI.ListaAjustes)) {
        $t = $cb.Tag
        $estado = Verificar-Tweak $t
        $contagens[$estado]++
        Atualizar-RotuloAjuste $cb $estado
        Atualizar-UI
    }
    Ocupado $false
    Log ('estado verificado: {0} ajuste(s) ja aplicado(s), {1} parcial(is), {2} nao aplicado(s), {3} sem verificacao automatica.' -f $contagens['aplicado'], $contagens['parcial'], $contagens['nao'], $contagens['desconhecido'])
    Status 'estado verificado.'
}

# Each window owns its snapshot. Only the Dispatcher touches WPF controls.
function Inicializar-ConsultaUwp {
    if ($null -eq $global:ConsultasUwpAtivas) { $global:ConsultasUwpAtivas=@{} }
    $global:ConsultaUwp=@{ ui=$global:UI; janela=$global:Janela; fase='inicial'; pacotes=@(); data=$null; trabalho=$null; fechada=$false; motivo='' }
    $global:UI.BotaoRemoverUwp.IsEnabled=$false
    $global:UI.BotaoCancelarUwp.IsEnabled=$false
}

function Mostrar-ConsultaUwp {
    param($Estado,[string]$Fase,[string]$Mensagem)
    $Estado.fase=$Fase
    if ($Estado.fechada) { return }
    $ui=$Estado.ui
    $ui.InfoConsultaUwp.Text=$Mensagem
    $ui.BotaoAtualizarUwp.IsEnabled=($null -eq $Estado.trabalho)
    $ui.BotaoCancelarUwp.IsEnabled=($Fase -eq 'carregando')
    $ui.BotaoRemoverUwp.IsEnabled=(-not $global:ModoProtegido -and $Fase -eq 'atualizado' -and -not $global:OperacaoUIAtiva)
    if ($Fase -ne 'atualizado') { $ui.ListaUwp.Children.Clear() }
}

function Cancelar-ConsultaUwp {
    param([string]$Motivo='Consulta cancelada.',[switch]$Fechar)
    $s=$global:ConsultaUwp
    if (-not $s) { return }
    if ($Fechar) { $s.fechada=$true }
    $s.data=$null; $s.pacotes=@()
    $j=$s.trabalho
    if ($j) {
        $s.motivo=$Motivo
        Mostrar-ConsultaUwp $s 'cancelando' ($Motivo+' Aguardando encerramento da consulta.')
        if (-not $j.cancelado) {
            $j.cancelado=$true
            if (-not $j.async.IsCompleted) {
                try { $j.parada=$j.ps.BeginStop($null,$null) } catch { }
            }
        }
    } else { Mostrar-ConsultaUwp $s 'indisponivel' $Motivo }
}

function Concluir-ConsultaUwp {
    param($Timer)
    $s=$global:ConsultasUwpAtivas[$Timer]
    if (-not $s) { $Timer.Stop(); return }
    $j=$s.trabalho
    if (-not $j.async.IsCompleted) {
        if (-not $j.cancelado -and $j.relogio.Elapsed.TotalSeconds -ge $j.limite) {
            if ([object]::ReferenceEquals($s,$global:ConsultaUwp)) { Cancelar-ConsultaUwp 'Tempo limite da consulta atingido.' }
        }
        return
    }
    if ($j.parada -and -not $j.parada.IsCompleted) { return }
    $Timer.Stop()
    $global:ConsultasUwpAtivas.Remove($Timer)
    $dados=@(); $falha=$false
    try {
        if ($j.parada) { try { $j.ps.EndStop($j.parada) } catch { } }
        $dados=@($j.ps.EndInvoke($j.async))
        if ($j.ps.Streams.Error.Count -gt 0) { $falha=$true }
    } catch { $falha=$true }
    finally { $j.ps.Dispose(); $s.trabalho=$null }
    if ($s.fechada -or -not [object]::ReferenceEquals($s,$global:ConsultaUwp)) { return }
    if ($j.cancelado) { Mostrar-ConsultaUwp $s 'indisponivel' ($s.motivo+' Use Atualizar para tentar novamente.'); return }
    if ($falha) { Mostrar-ConsultaUwp $s 'indisponivel' 'Consulta AppX falhou. Nenhuma ausencia confirmada. Tente novamente.'; return }
    if ($global:OperacaoUIAtiva) { Mostrar-ConsultaUwp $s 'indisponivel' 'Inventario invalidado durante uma operacao. Atualize a lista.'; return }
    try {
        Montar-PaginaDebloat -Pacotes $dados
        $s.pacotes=$dados; $s.data=Get-Date
        Mostrar-ConsultaUwp $s 'atualizado' ('Apps verificados as '+$s.data.ToString('HH:mm:ss')+'. Nenhuma remocao preselecionada.')
    } catch {
        $s.data=$null; $s.pacotes=@()
        Mostrar-ConsultaUwp $s 'indisponivel' 'Nao foi possivel exibir o inventario. Tente novamente.'
    }
}

function Verificar-EstadoUwp {
    param([switch]$Forcar,[scriptblock]$Codigo={ $ErrorActionPreference='Stop'; Get-AppxPackage -ErrorAction Stop },[int]$LimiteSegundos=30)
    $s=$global:ConsultaUwp
    if (-not $s -or $s.fechada -or $global:OperacaoUIAtiva -or $s.trabalho) { return }
    if (-not $Forcar -and $s.fase -eq 'atualizado' -and $s.data -and ((Get-Date)-$s.data).TotalSeconds -lt 120) { return }
    $s.data=$null; $s.pacotes=@()
    $ps=$null; $timer=$null
    try {
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript($Codigo.ToString())
        $timer=New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval=[TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({ param($sender,$eventArgs) Concluir-ConsultaUwp $sender })
        $j=@{ ps=$ps; async=$ps.BeginInvoke(); parada=$null; cancelado=$false; relogio=[Diagnostics.Stopwatch]::StartNew(); limite=$LimiteSegundos }
        $s.trabalho=$j
        $global:ConsultasUwpAtivas[$timer]=$s
        Mostrar-ConsultaUwp $s 'carregando' 'Verificando apps pre-instalados... Voce pode navegar para outras abas.'
        $timer.Start()
    } catch {
        if ($s.trabalho) {
            Cancelar-ConsultaUwp 'Falha ao iniciar consulta.'
            # Keep the completion poll alive until the worker stops.
            $timer.Start()
        } else {
            if ($timer) { $timer.Stop() }
            if ($ps) { $ps.Dispose() }
            Mostrar-ConsultaUwp $s 'indisponivel' 'Nao foi possivel iniciar a consulta. Tente novamente.'
        }
    }
}

# ---- navegacao ----

$global:PaginaAtual = 'PaginaInicio'

function Trocar-Pagina {
    param([string]$Nome)
    if ($global:OperacaoUIAtiva -or $global:NavegacaoAtiva) { return }
    $global:NavegacaoAtiva = $true
    try {
    foreach ($p in @('PaginaInicio', 'PaginaAjustes', 'PaginaDebloat', 'PaginaDesinstalar', 'PaginaInstalar', 'PaginaConfig', 'PaginaAtualizacoes', 'PaginaManutencao', 'PaginaDesfazer')) {
        $pg = $global:Janela.FindName($p)
        if ($p -eq $Nome) { $pg.Visibility = 'Visible' } else { $pg.Visibility = 'Collapsed' }
    }
    $global:PaginaAtual = $Nome
    # marca a aba ativa na barra lateral (o xaml tem trigger Tag='ativo')
    $navs = @{
        'PaginaInicio'       = 'BotaoNavInicio'
        'PaginaAjustes'      = 'BotaoNavAjustes'
        'PaginaDebloat'      = 'BotaoNavDebloat'
        'PaginaDesinstalar'  = 'BotaoNavDesinstalar'
        'PaginaInstalar'     = 'BotaoNavInstalar'
        'PaginaConfig'       = 'BotaoNavConfig'
        'PaginaAtualizacoes' = 'BotaoNavAtualizacoes'
        'PaginaManutencao'   = 'BotaoNavManutencao'
        'PaginaDesfazer'     = 'BotaoNavDesfazer'
    }
    foreach ($p in $navs.Keys) {
        $b = $global:UI.($navs[$p])
        if ($p -eq $Nome) { $b.Tag = 'ativo' } else { $b.Tag = '' }
    }
    if ($Nome -eq 'PaginaInicio') { Preencher-PaginaInicio }
    if ($Nome -eq 'PaginaAjustes') { Verificar-EstadoAjustes }
    if ($Nome -eq 'PaginaDebloat') { Verificar-EstadoUwp }
    if ($Nome -eq 'PaginaConfig') { Montar-PaginaRecursos }
    if ($Nome -eq 'PaginaDesfazer') {
        if ($global:ModoProtegido) {
            $global:UI.ListaDesfazer.Items.Clear()
            [void]$global:UI.ListaDesfazer.Items.Add('Historico indisponivel no modo protegido; nenhuma sessao sera alterada.')
        } else { Atualizar-ListaDesfazer }
    }
    if ($Nome -eq 'PaginaDesinstalar') {
        if ($null -eq $global:ProgramasInstalados) { Carregar-Programas }
        Atualizar-ListaProgramas
    }
    if ($Nome -eq 'PaginaAtualizacoes') {
        try {
            $atual=Tem-Atualizacoes
            $global:UI.ChkBloquearDrivers.IsChecked=($null -ne $atual -and $atual.ExcludeWUDriverInQualityUpdate -eq 1)
            $global:UI.ChkAdiarRecursos.IsChecked=($null -ne $atual -and $atual.DeferFeatureUpdates -eq 1)
            $global:UI.InfoPoliticasUpdate.Text=('Drivers: '+(Formatar-PoliticaAtualizacao $atual.ExcludeWUDriverInQualityUpdate)+"`nVersoes: "+(Formatar-PoliticaAtualizacao $atual.DeferFeatureUpdates)+"`nPeriodo registrado: "+$atual.DeferFeatureUpdatesPeriodInDays+"`nValores do registro nao comprovam politica efetiva.")
        } catch { $global:UI.InfoPoliticasUpdate.Text='Consulta de politicas indisponivel.' }
    }
    } catch {
        Log ('falha ao carregar ' + $Nome + ': ' + $_.Exception.Message) -Erro
        Status 'Falha na consulta; tente outra aba ou reabra esta aba.'
    } finally {
        if ($global:UI.ContainsKey('BarraProgresso')) { $global:UI.BarraProgresso.IsIndeterminate = $false }
        if ($global:ModoProtegido) { Status 'Modo protegido: somente consulta; alteracoes e exportacoes bloqueadas.' }
        $global:NavegacaoAtiva = $false
    }
}

# ---- cliques ----

function Clique-AplicarAjustes {
    $selecionados = @(Get-Checkboxes $global:UI.ListaAjustes | Where-Object { $_.IsChecked })
    $ctx=Obter-ContextoAjustes
    foreach ($cb in $selecionados) {if (-not (Testar-CompatibilidadeAjuste $cb.Tag $ctx)) {Avisar 'Ajuste indisponivel' ('Compatibilidade minima nao atendida: '+$cb.Tag.nome); return}}
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os ajustes desejados ou use um dos presets.'
        return
    }
    # modo simulacao: so descreve no log, nao toca em nada
    if ($global:UI.ChkSimularAjustes.IsChecked) {
        Ocupado $true
        Log ('==== SIMULACAO de {0} ajuste(s): nada sera alterado ====' -f $selecionados.Count)
        foreach ($cb in $selecionados) {
            $t = $cb.Tag
            Log ('== ajuste: ' + $t.nome + ' (simulado)')
            foreach ($acao in $t.acoes) {
                Executar-Acao $acao $t.nome -Simular
                Atualizar-UI
            }
        }
        Ocupado $false
        Log 'SIMULACAO concluida: o pc NAO foi alterado. pra aplicar de vez, desmarque "simular" e clique em aplicar.'
        Status 'simulacao concluida (nada foi alterado).'
        return
    }
    $manuais = @($selecionados | Where-Object { $_.Tag.apenasManual -or (Classificar-RiscoAjuste $_.Tag) -eq 'cautela alta' })
    if ($manuais.Count -gt 0 -and -not (Perguntar 'Ajustes de cautela' ('Ajustes manuais podem reduzir funcionalidades ou ter reversao aproximada: ' + (($manuais | ForEach-Object { $_.Tag.nome }) -join ', ') + '. Continuar?'))) { return }
    $nomes = ($selecionados | ForEach-Object { $_.Tag.nome }) -join ', '
    $conf = Perguntar 'Aplicar ajustes' ("Aplicar {0} ajuste(s):`n`n{1}`n`nContinuar?" -f $selecionados.Count, $nomes)
    if (-not $conf) { return }
    Status 'preparando ajustes...'
    Ocupado $true
    if ($global:UI.ChkPontoRestore.IsChecked -and -not (Criar-PontoRestauracao)) { Ocupado $false; Avisar 'Ponto nao confirmado' 'Operacao cancelada. Revise a protecao do sistema.'; return }
    Iniciar-Sessao 'ajustes'
    $total = 0
    foreach ($cb in $selecionados) { $total += @($cb.Tag.acoes).Count }
    $progresso = Iniciar-ProgressoLote 'Aplicando ajustes' $total
    try {
        :ajustes foreach ($cb in $selecionados) {
            $t = $cb.Tag
            Log ('== ajuste: ' + $t.nome)
            foreach ($acao in $t.acoes) {
                if (-not (Continuar-ProgressoLote $progresso $t.nome)) { break ajustes }
                Executar-Acao $acao $t.nome
                Atualizar-UI
            }
        }
    } finally { Fechar-ProgressoLote $progresso }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($progresso.cancelado) { Log 'lote interrompido a pedido; journal preservado.'; Status 'lote interrompido.'; return }
    if ($global:ErrosSessao -gt 0) {
        Log ('ajustes concluidos com ' + $global:ErrosSessao + ' erro(s); veja as linhas [ERRO] acima.') -Erro
    } else {
        Log ('todos os ' + $selecionados.Count + ' ajustes foram aplicados sem erros.')
    }
    if ($arq) { Log ('salvei o journal desta sessao para desfazer depois: ' + (Split-Path -Leaf $arq)) }
    if ($global:ErrosSessao -gt 0) { Status 'ajustes com falhas; consulte o log.' }
    else { Status 'ajustes aplicados. alguns exigem relogar no windows.' }
    if (Perguntar 'Explorador de Arquivos' 'Reiniciar o Explorador agora para aplicar as mudancas visuais? (aquivos abertos em janelas do explorer fecham)') {
        Reiniciar-Explorer
    }
}

function Clique-RemoverUwp {
    if (-not $global:ConsultaUwp -or $global:ConsultaUwp.fase -ne 'atualizado') { Avisar 'Inventario indisponivel' 'Atualize a lista antes de remover aplicativos.'; return }
    $selecionados = @(Get-Checkboxes $global:UI.ListaUwp | Where-Object { $_.IsChecked -and $_.IsEnabled })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os aplicativos que quer remover.'
        return
    }
    try {
        $pacotes=@(Get-AppxPackage -ErrorAction Stop)
        foreach ($cb in $selecionados) {
            if (-not (Obter-GuiaUwp $cb.Tag $pacotes).permitido) { throw ('Pacote indisponivel ou protegido: ' + $cb.Tag.nome) }
        }
    } catch { Avisar 'Remocao bloqueada' $_.Exception.Message; return }
    $nomes = ($selecionados | ForEach-Object { $_.Tag.nome }) -join ', '
    $conf = Perguntar 'Remover aplicativos' ("Remover {0} aplicativo(s) pre-instalado(s):`n`n{1}`n`nRemocao apenas do usuario atual. Dados locais e reinstalacao nao sao garantidos. Outros usuarios nao serao alterados. Continuar?" -f $selecionados.Count, $nomes)
    if (-not $conf) { return }
    Status 'removendo aplicativos...'
    Ocupado $true
    if ($global:UI.ChkPontoRestoreUwp.IsChecked -and -not (Criar-PontoRestauracao)) { Ocupado $false; Avisar 'Ponto nao confirmado' 'Operacao cancelada.'; return }
    Iniciar-Sessao 'debloat'
    $progresso = Iniciar-ProgressoLote 'Removendo aplicativos' $selecionados.Count
    try {
        foreach ($cb in $selecionados) {
            $p = $cb.Tag
            if (-not (Continuar-ProgressoLote $progresso $p.nome)) { break }
            Executar-Acao ([pscustomobject]@{ tipo='appx'; pacote=$p.pacote }) $p.nome
            Atualizar-UI
        }
    } finally { Fechar-ProgressoLote $progresso }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($progresso.cancelado) { Log 'debloat interrompido; journal preservado.'; Status 'debloat interrompido.'; return }
    Log ('debloat concluido' + $(if ($arq) { ' - journal: ' + (Split-Path -Leaf $arq) } else { ' (nada foi removido)' }))
    if ($global:ErrosSessao -gt 0) { Status 'debloat com falhas; consulte o log.' }
    else { Status 'debloat concluido; relogar pode ser necessario.' }
}

function Clique-InstalarApps {
    param([ValidateSet('install','upgrade')][string]$Operacao='install')
    $selecionados = @(Get-Checkboxes $global:UI.ListaApps | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    Instalar-Aplicativos -Selecionados $selecionados -Operacao $Operacao
}

function Clique-InstalarRecursos {
    $selecionados = @(Get-Checkboxes $global:UI.ListaRecursos | Where-Object { $_.IsChecked -and $_.IsEnabled })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os recursos do Windows que quer habilitar.'
        return
    }
    $conf = Perguntar 'Habilitar recursos' ('Habilitar {0} recurso(s) do Windows? Alguns pedem reinicializacao e internet. Se dependencias forem alteradas, a reversao exigira revisao manual.' -f $selecionados.Count)
    if (-not $conf) { return }
    Status 'habilitando recursos...'
    Ocupado $true
    Iniciar-Sessao 'recursos'
    $progresso = Iniciar-ProgressoLote 'Habilitando recursos' $selecionados.Count
    try {
        foreach ($cb in $selecionados) {
            $r = $cb.Tag
            if (-not (Continuar-ProgressoLote $progresso $r.nome)) { break }
            Executar-Acao ([pscustomobject]@{ tipo='recurso'; nome=$r.feat; ativar=$true }) $r.nome
            Atualizar-UI
        }
    } finally { Fechar-ProgressoLote $progresso }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($progresso.cancelado) { Log 'recursos interrompidos; journal preservado.'; Status 'lote interrompido.'; return }
    Log ('recursos processados; confira erros e reinicio pendente.' + $(if ($arq) { ' - journal: ' + (Split-Path -Leaf $arq) } else { '' }))
    if ($global:ErrosSessao -gt 0) { Status 'recursos com falhas; consulte o log.' } else { Status 'recursos processados; confira reinicio pendente.' }
}

function Clique-Preset {
    param([string]$Nivel)
    $cbs = Get-Checkboxes $global:UI.ListaAjustes
    try {
        $perfil=$Nivel
        if ($Nivel -eq 'recomendado') { $perfil=Obter-PerfilRecomendado }
        $ids = @(Selecionar-TweaksPreset -Nivel $perfil -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11) | ForEach-Object { $_.id })
    } catch {
        Avisar 'Preset invalido' $_.Exception.Message
        return
    }
    foreach ($cb in $cbs) {
        $cb.IsChecked = ($cb.IsEnabled -and $ids -contains $cb.Tag.id -and (Verificar-Tweak $cb.Tag) -ne 'aplicado')
    }
    if ($Nivel -eq 'recomendado') {
        $motivo=switch ($perfil) {'corporativo' {'Possivel ambiente gerenciado; apenas extensoes de arquivos.'} 'notebook' {'Bateria detectada; ajustes leves sem forcar energia.'} default {'Sem evidencia para ajustes agressivos; selecao essencial.'}}
        Avisar 'Recomendacao explicada' ($motivo + ' A selecao nao aplica nada e ignora ajustes ja aplicados.')
    }
    Log ('preset marcado: ' + $Nivel + ' (' + @(($cbs | Where-Object { $_.IsChecked })).Count + ' ajustes). confira a lista e clique em aplicar.')
}

# exporta os ajustes marcados num .json (pra repetir depois ou levar pra outro pc)
function Clique-ExportarPlano {
    Confirmar-PermissaoAlteracao
    $selecionados = @(Get-Checkboxes $global:UI.ListaAjustes | Where-Object { $_.IsChecked })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os ajustes que quer salvar no plano.'
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Plano OtimizadorPC (*.json)|*.json'
    $dlg.FileName = ('plano-ajustes-{0}.json' -f (Get-Date -Format 'yyyy-MM-dd'))
    if (-not $dlg.ShowDialog()) { return }
    $plano = [pscustomobject]@{
        app     = 'otimizadorpc'
        versao  = 1
        criado  = (Get-Date -Format 'o')
        ajustes = @($selecionados | ForEach-Object { [string]$_.Tag.id })
    }
    ConvertTo-Json -InputObject $plano -Depth 4 | Set-Content -Path $dlg.FileName -Encoding UTF8
    Log ('plano exportado com ' + $selecionados.Count + ' ajuste(s): ' + $dlg.FileName)
    Status ('plano exportado (' + $selecionados.Count + ' ajustes).')
}

# importa um plano exportado: so marca as checkboxes na lista, nao aplica nada
function Clique-ImportarPlano {
    Confirmar-PermissaoAlteracao
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Plano OtimizadorPC (*.json)|*.json|Todos os arquivos (*.*)|*.*'
    if (-not $dlg.ShowDialog()) { return }
    try {
        $plano = Ler-JSON $dlg.FileName
    } catch {
        Avisar 'Arquivo invalido' 'Nao consegui ler esse arquivo como plano do OtimizadorPC.'
        return
    }
    if ($null -eq $plano.ajustes) {
        Avisar 'Arquivo invalido' 'Esse .json nao parece um plano do OtimizadorPC (nao encontrei a lista de ajustes).'
        return
    }
    $ids = @($plano.ajustes)
    $conhecidos = @($global:CatalogoTweaks.tweaks | ForEach-Object { [string]$_.id })
    $desconhecidos = @($ids | Where-Object { $conhecidos -notcontains [string]$_ })
    if ($desconhecidos.Count -gt 0) {
        Log ('aviso: ' + $desconhecidos.Count + ' ajuste(s) do plano nao existem neste catalogo: ' + ($desconhecidos -join ', '))
    }
    $marcados = 0
    foreach ($cb in (Get-Checkboxes $global:UI.ListaAjustes)) {
        $cb.IsChecked = ($cb.IsEnabled -and $ids -contains [string]$cb.Tag.id)
        if ($cb.IsChecked) { $marcados++ }
    }
    Log ('plano importado: marquei ' + $marcados + ' ajuste(s) na lista. confira e clique em aplicar (ou em simular primeiro).')
    Status ('plano importado: ' + $marcados + ' ajuste(s) marcados.')
}

function Clique-Desfazer {
    param([switch]$UmaAcao)
    $lb = $global:UI.ListaDesfazer
    if ($lb.SelectedIndex -lt 0) {
        Avisar 'Selecione' 'Escolha na lista a sessao que quer desfazer.'
        return
    }
    $caminho = $lb.Tag[$lb.SelectedIndex]
    if (-not $caminho -or -not (Test-Path $caminho)) {
        Avisar 'Arquivo nao encontrado' 'A sessao escolhida nao esta disponivel.'
        Atualizar-ListaDesfazer
        return
    }
    if ($UmaAcao) {
        $conf = Perguntar 'Desfazer ultima acao' 'Reverter somente a ultima acao pendente, respeitando a ordem inversa?'
    } else {
        $conf = Perguntar 'Desfazer sessao' ('Desfazer todas as acoes da sessao selecionada?' + "`n" + $lb.SelectedItem)
    }
    if (-not $conf) { return }
    Status 'revertendo sessao...'
    Ocupado $true
    $global:Janela.IsEnabled = $false
    try {
        $resultado = Reverter-Sessao -Arquivo $caminho -UmaAcao:$UmaAcao
    } finally {
        $global:Janela.IsEnabled = (-not $global:OperacaoUIAtiva)
        Ocupado $false
    }
    Atualizar-ListaDesfazer
    if ($resultado -eq $true) {
        if (Test-Path -LiteralPath $caminho) { Status 'uma acao revertida; restam itens.' }
        else { Status 'sessao revertida.' }
    } else {
        Status 'reversao incompleta - consulte o log.'
        Cor-Status 'vermelho'
        Avisar 'Reversao incompleta' 'O journal foi preservado. Consulte o log e revise a acao incerta antes de continuar.'
    }
}

# ---- ligacao geral (chamada pelo script principal) ----

# Consulta sob demanda; nenhuma alteracao automatica em servicos ou tarefas.
function Clique-ConfirmarManual {
    try {
        $lb = $global:UI.ListaDesfazer
        if ($lb.SelectedIndex -lt 0) { Avisar 'Selecione' 'Escolha uma sessao na lista.'; return }
        $arquivo = $lb.Tag[$lb.SelectedIndex]
        if (-not $arquivo -or -not (Test-Path -LiteralPath $arquivo)) { throw 'Sessao indisponivel.' }
        $json = Ler-JSON $arquivo
        $itens = @($json.itens)
        for ($i = $itens.Count - 1; $i -ge 0; $i--) {
            $item = $itens[$i]
            if ($item.estadoReversao -eq 'concluido') { continue }
            if ($item.estadoReversao -ne 'em_andamento') { throw 'A ultima acao pendente nao esta incerta.' }
            $alvo = @($item.caminho,$item.origem,$item.chave,$item.nome,$item.pacote,$item.contexto) -join ' '
            $msg = ('Acao {0}: {1} - {2}. Confirme SOMENTE se voce verificou e restaurou manualmente o estado anterior. O programa nao testa nem repete essa operacao. Confirmar?' -f $i,$item.tipo,$alvo)
            if (Perguntar 'Atestado de recuperacao manual' $msg) {
                Confirmar-ReversaoManual -Arquivo $arquivo -Indice $i
                Atualizar-ListaDesfazer
                Status 'confirmacao manual registrada.'
            }
            return
        }
        throw 'Nenhuma acao incerta encontrada.'
    } catch { Avisar 'Confirmacao indisponivel' $_.Exception.Message }
}

function Filtrar-Inventario {
    param($Dados,[string]$Texto)
    foreach ($item in @($Dados)) {
        if ($null -eq $item) { continue }
        $textoItem = ($item.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Texto) -or $textoItem.IndexOf($Texto.Trim(),[StringComparison]::OrdinalIgnoreCase) -ge 0) { $item }
    }
}

# Mudancas pequenas e explicitas no gerenciador; outras ficam nas ferramentas nativas.
function Alterar-ItemInventario {
    param([string]$Grupo,$Item)
    Confirmar-PermissaoAlteracao
    if ($null -eq $Item) { throw 'Selecione uma linha.' }
    if ($Grupo -eq 'servicos') {
        $permitidos = @($global:CatalogoTweaks.tweaks | ForEach-Object { $_.acoes } | Where-Object { $_.tipo -eq 'servico' } | ForEach-Object { $_.nome })
        if ($Item.nome -notin $permitidos) { throw 'Servico fora do catalogo; use o gerenciador nativo.' }
        $atual = Obter-EstadoServico $Item.nome
        if ($atual.tipo -ne $Item.inicio -or $atual.estado -ne $Item.estado) { throw 'Inventario desatualizado; reabra antes de alterar.' }
        if ($atual.tipo -eq 'Manual') { throw 'Servico ja esta em inicio manual.' }
        if (-not (Perguntar 'Servico - inicio manual' ('Alterar ' + $Item.nome + ' para inicio manual? Pode afetar funcionalidades. O estado atual sera preservado.'))) { return $false }
        Iniciar-Sessao 'gerenciador-servicos'
        Alterar-ServicoComJournal $Item.nome 'Manual'
    } elseif ($Grupo -eq 'tarefas') {
        if ($Item.nome -match '[*?\[\]]' -or $Item.caminho -match '[*?\[\]]') { throw 'Identificador ambiguo.' }
        $atual = Get-ScheduledTask -TaskPath $Item.caminho -TaskName $Item.nome -ErrorAction Stop
        if ($atual.State -ne $Item.estado -or $atual.State -ne 'Ready') { throw 'Tarefa indisponivel ou inventario desatualizado.' }
        if (-not (Perguntar 'Desativar tarefa' ('Desativar ' + $Item.caminho + $Item.nome + '? Tarefas de sistema nao sao aceitas.'))) { return $false }
        Iniciar-Sessao 'gerenciador-tarefas'
        Desativar-TarefaComJournal $Item.caminho $Item.nome
    } elseif ($Grupo -eq 'runUsuario') {
        $ck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $atual = Ler-ValorRegistro $ck $Item.nome
        if (-not (Registro-Corresponde $atual $true $Item.tipo $Item.valor)) { throw 'Entrada mudou; reabra o inventario.' }
        if (-not (Perguntar 'Inicializacao do usuario' ('Remover somente a entrada Run de ' + $Item.nome + '? O programa nao sera desinstalado; o valor original sera salvo.'))) { return $false }
        Iniciar-Sessao 'gerenciador-inicializacao'
        Executar-Acao ([pscustomobject]@{ tipo='registro'; caminho=$ck; nome=$Item.nome; remover=$true }) 'entrada Run'
    } else { throw 'Grupo nao editavel.' }
    [void](Salvar-Sessao)
    if ($global:ErrosSessao -gt 0) { throw 'Operacao com falha; consulte o journal.' }
    return $true
}

function Clique-InventarioLocal {
    try {
        Status 'coletando inventario local...'
        $resultado = @(Executar-ConsultaLocal -Titulo 'Inventario local' -Codigo ${function:Obter-InventarioLocal} -Parametros @{Protegido=[bool]$global:ModoProtegido})
        if ($resultado.Count -ne 1 -or $null -eq $resultado[0]) { Status 'inventario cancelado.'; return }
        $dados = $resultado[0]
        $dlg = New-Object System.Windows.Window
        $dlg.Title = 'Gerenciador local - OtimizadorPC'
        $dlg.Owner = $global:Janela
        $dlg.WindowStartupLocation = 'CenterOwner'
        $dlg.Width = 760
        $dlg.Height = 560
        $dlg.MaxWidth = [System.Windows.SystemParameters]::WorkArea.Width
        $dlg.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
        $painel = New-Object System.Windows.Controls.DockPanel
        $painel.Margin = '12'
        $barra = New-Object System.Windows.Controls.WrapPanel
        [System.Windows.Controls.DockPanel]::SetDock($barra, 'Top')
        [void]$painel.Children.Add($barra)
        $salvar = New-Object System.Windows.Controls.Button
        $salvar.Content = 'Exportar JSON'
        $salvar.Padding = '10,6'
        $salvar.Margin = '0,0,8,8'
        $salvar.Tag = $dados
        $salvar.Add_Click({
            $arq = New-Object Microsoft.Win32.SaveFileDialog
            $arq.Filter = 'Inventario JSON (*.json)|*.json'
            $arq.FileName = 'inventario-otimizadorpc.json'
            if ($arq.ShowDialog()) {
                try { Gravar-JSONAtomico -Arquivo $arq.FileName -Objeto $this.Tag; Log 'inventario exportado.' }
                catch { Avisar 'Falha na exportacao' $_.Exception.Message }
            }
        })
        if (-not $global:ModoProtegido) { [void]$barra.Children.Add($salvar) }
        foreach ($atalho in @(
            @{ nome='Inicializacao'; comando='taskmgr.exe' },
            @{ nome='Servicos'; comando='services.msc' },
            @{ nome='Tarefas'; comando='taskschd.msc' },
            @{ nome='Drivers'; comando='devmgmt.msc' }
        )) {
            $botao = New-Object System.Windows.Controls.Button
            $botao.Content = $atalho.nome
            $botao.Tag = $atalho.comando
            $botao.Padding = '10,6'
            $botao.Margin = '0,0,8,8'
            $botao.Add_Click({
                try { Start-Process -FilePath (Join-Path $env:SystemRoot ('System32\' + [string]$this.Tag)) -ErrorAction Stop | Out-Null }
                catch { Avisar 'Falha ao abrir ferramenta' $_.Exception.Message }
            })
            if (-not $global:ModoProtegido) { [void]$barra.Children.Add($botao) }
        }
        $nota = New-Object System.Windows.Controls.TextBlock
        $nota.TextWrapping = 'Wrap'
        $nota.Text = 'Inventario com acoes limitadas e journal. Alteracoes nas ferramentas nativas nao entram no journal. Ordene pelos cabecalhos e filtre por texto. Revise antes de compartilhar. ' + ($dados.avisos -join ' | ')
        if ($global:ModoProtegido) { $nota.Text='Diagnostico local somente leitura. Exportacao e alteracoes indisponiveis. '+($dados.avisos -join ' | ') }
        $nota.Margin = '0,0,0,8'
        [System.Windows.Controls.DockPanel]::SetDock($nota,'Top')
        [void]$painel.Children.Add($nota)
        $abas = New-Object System.Windows.Controls.TabControl
        foreach ($grupo in @('inicializacao','runUsuario','servicos','tarefas','discos','rede','drivers','processos')) {
            $tab = New-Object System.Windows.Controls.TabItem
            $tab.Header = $grupo
            $corpo = New-Object System.Windows.Controls.DockPanel
            $filtro = New-Object System.Windows.Controls.TextBox
            $filtro.Margin = '6'; $filtro.ToolTip='Digite nome, estado ou outro campo para filtrar'
            [System.Windows.Controls.DockPanel]::SetDock($filtro,'Top')
            [void]$corpo.Children.Add($filtro)
            $grade = New-Object System.Windows.Controls.DataGrid
            $grade.IsReadOnly=$true; $grade.AutoGenerateColumns=$true
            $grade.CanUserAddRows=$false; $grade.CanUserDeleteRows=$false
            $grade.SelectionMode='Single'; $grade.EnableRowVirtualization=$true
            $grade.ItemsSource = @($dados.$grupo)
            $filtro.Tag = @{ dados=@($dados.$grupo); grade=$grade }
            $filtro.Add_TextChanged({ $this.Tag.grade.ItemsSource = @(Filtrar-Inventario $this.Tag.dados $this.Text) })
            if (-not $global:ModoProtegido -and $grupo -in @('runUsuario','servicos','tarefas')) {
                $acao = New-Object System.Windows.Controls.Button
                $acao.Content = switch ($grupo) { 'runUsuario' {'Remover entrada Run selecionada'} 'servicos' {'Inicio manual (servicos do catalogo)'} 'tarefas' {'Desativar tarefa selecionada'} }
                $acao.Margin='6'; $acao.Padding='8,4'
                $acao.Tag=@{ grupo=$grupo; grade=$grade; janela=$dlg }
                $acao.Add_Click({
                    $ctx=$this.Tag
                    if ($global:OperacaoUIAtiva) { return }
                    $global:OperacaoUIAtiva=$true
                    $ctx.janela.IsEnabled=$false
                    try {
                        if (Alterar-ItemInventario $ctx.grupo $ctx.grade.SelectedItem) {
                            Avisar 'Operacao concluida' 'Reabra o inventario para atualizar. Veja a sessao na aba Desfazer.'
                            $ctx.janela.IsEnabled=$true
                            $ctx.janela.Close()
                        }
                    } catch { Avisar 'Operacao interrompida' $_.Exception.Message }
                    finally { if ($ctx.janela.IsLoaded) { $ctx.janela.IsEnabled=$true }; $global:OperacaoUIAtiva=$false }
                })
                [System.Windows.Controls.DockPanel]::SetDock($acao,'Top')
                [void]$corpo.Children.Add($acao)
            }
            [void]$corpo.Children.Add($grade)
            $tab.Content=$corpo
            [void]$abas.Items.Add($tab)
        }
        [void]$painel.Children.Add($abas)
        $dlg.Content = $painel
        Status 'inventario coletado.'
        [void]$dlg.ShowDialog()
    } catch {
        Log ('falha ao exibir inventario: ' + $_.Exception.Message) -Erro
        Status 'falha no inventario.'
    }
}

# Exporta drivers de terceiros do Driver Store. Nunca instala ou remove drivers.
function Clique-BackupDrivers {
    Confirmar-PermissaoAlteracao
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $escolher = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $escolher.Description = 'Escolha uma pasta para o backup dos drivers de terceiros'
            if ($escolher.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $pasta = Join-Path $escolher.SelectedPath ('drivers-otimizadorpc-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        } finally { $escolher.Dispose() }
        if (-not (Perguntar 'Backup de drivers' ('Exportar drivers de terceiros? Pode ocupar varios GB. A pasta sera criada em: ' + $pasta))) { return }
        $global:Janela.IsEnabled = $false
        try {
            Ocupado $true
            Status 'exportando drivers...'
            New-Item -ItemType Directory -Path $pasta -ErrorAction Stop | Out-Null
            $drivers = @(Executar-ConsultaLocal -Titulo 'Exportando drivers' -Codigo { param([string]$Destino) Export-WindowsDriver -Online -Destination $Destino -ErrorAction Stop } -Parametros @{Destino=$pasta} -Mensagem 'Copiando drivers para a pasta escolhida. Nao interrompa a exportacao.' -SemCancelar)
            Log ('exportacao de drivers: ' + $pasta + ' (' + $drivers.Count + ' pacote(s) informado(s)).')
            Status 'exportacao de drivers concluida.'
        } finally {
            $global:Janela.IsEnabled = (-not $global:OperacaoUIAtiva)
            Ocupado $false
        }
        Avisar 'Backup concluido' ('Confira os arquivos em: ' + $pasta + '. O backup nao inclui todos os drivers nativos do Windows.')
    } catch {
        Log ('falha no backup de drivers: ' + $_.Exception.Message) -Erro
        Status 'backup de drivers incompleto.'
        Avisar 'Falha no backup' 'Confira o log. Arquivos parcialmente exportados foram preservados.'
    }
}

function Clique-AnalisarArmazenamento {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $escolher = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $escolher.Description = 'Escolha uma pasta para localizar arquivos grandes'
            if ($escolher.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $pasta = $escolher.SelectedPath
        } finally { $escolher.Dispose() }
        $resultado = @(Executar-ConsultaLocal -Titulo 'Analisando armazenamento' -Codigo ${function:Analisar-Armazenamento} -Parametros @{ Pasta = $pasta })
        if ($resultado.Count -ne 1 -or $null -eq $resultado[0]) { Status 'analise cancelada.'; return }
        $dados = $resultado[0]
        $dlg = New-Object System.Windows.Window
        $dlg.Title = 'Analise de armazenamento - somente leitura'
        $dlg.Owner = $global:Janela
        $dlg.WindowStartupLocation = 'CenterOwner'
        $dlg.Width = 800
        $dlg.Height = 550
        $dlg.MaxWidth = [System.Windows.SystemParameters]::WorkArea.Width
        $dlg.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
        $caixa = New-Object System.Windows.Controls.TextBox
        $caixa.IsReadOnly = $true
        $caixa.AcceptsReturn = $true
        $caixa.VerticalScrollBarVisibility = 'Auto'
        $caixa.HorizontalScrollBarVisibility = 'Auto'
        $caixa.FontFamily = 'Consolas'
        $linhas = @($dados.pasta, ('Arquivos examinados: {0}; tamanho logico: {1:N2} GB; itens ignorados: {2}' -f $dados.arquivos, ($dados.bytes / 1GB), $dados.ignorados))
        if ($dados.parcial) { $linhas += 'Resultado parcial: limite de tempo/itens ou acesso restrito.' }
        $linhas += @('', 'Maiores arquivos encontrados (ate 30):', '')
        foreach ($arq in $dados.maiores) { $linhas += ('{0,12:N2} MB  {1}' -f ($arq.bytes / 1MB), $arq.caminho) }
        $linhas += @('', 'Nenhum arquivo foi apagado. Nao exclua arquivos de sistema com base apenas no tamanho.')
        $caixa.Text = ($linhas -join [Environment]::NewLine)
        $dlg.Content = $caixa
        Status 'analise de armazenamento concluida.'
        [void]$dlg.ShowDialog()
    } catch {
        Log ('falha na analise de armazenamento: ' + $_.Exception.Message) -Erro
        Status 'falha na analise de armazenamento.'
    }
}

# Inspecao do journal selecionado; nao executa comandos nem apaga backups.
function Formatar-ValorRecuperacao {
    param([bool]$Existe,[string]$Tipo,$Valor)
    if (-not $Existe) { return '(ausente)' }
    $texto=ConvertTo-Json -InputObject $Valor -Depth 4 -Compress
    if ($texto.Length -gt 350) { $texto=$texto.Substring(0,350)+' ...' }
    return ($Tipo+': '+$texto)
}

function Obter-DetalheRecuperacao {
    param($Item)
    $linhas=@()
    switch ($Item.tipo) {
        'registro' {
            if ($Item.valorAnteriorEstruturado) { $linhas+=('Anterior: '+(Formatar-ValorRecuperacao ([bool]$Item.existia) $Item.tipoAnterior $Item.valorAnteriorEstruturado.valor)) }
            else { $linhas+='Anterior: formato legado; revise journal.' }
            if ($Item.PSObject.Properties['existiaDepois']) {
                $linhas+=('Alvo registrado: '+(Formatar-ValorRecuperacao ([bool]$Item.existiaDepois) $Item.tipoDepois $Item.valorDepoisEstruturado.valor))
            }
            try {
                $atual=Ler-ValorRegistro $Item.caminho $Item.nome
                $linhas+=('Atual: '+(Formatar-ValorRecuperacao ([bool]$atual.existia) $atual.tipo $atual.valor))
                if ($Item.PSObject.Properties['existiaDepois'] -and $Item.valorAnteriorEstruturado) {
                    if (Registro-Corresponde $atual ([bool]$Item.existia) $Item.tipoAnterior $Item.valorAnteriorEstruturado.valor) { $linhas+='Estado anterior ja presente.' }
                    elseif (Registro-Corresponde $atual ([bool]$Item.existiaDepois) $Item.tipoDepois $Item.valorDepoisEstruturado.valor) { $linhas+='Candidato a reversao automatica.' }
                    else { $linhas+='Possivel conflito; nao sobrescrever.' }
                }
            } catch { $linhas+='Estado atual indisponivel.' }
        }
        'servico' {
            $linhas+=('Anterior: '+$Item.tipoAnterior+' / '+$Item.estadoAnterior+' / atraso='+$Item.atrasoAnterior)
            $linhas+=('Alvo registrado: '+$Item.tipoDepois+' / '+$Item.estadoDepois)
            try { $s=Obter-EstadoServico $Item.nome; $linhas+=('Atual: '+$s.tipo+' / '+$s.estado+' / atraso='+$s.atraso) } catch { $linhas+='Estado atual indisponivel.' }
        }
        'quarantena-arquivo' { $linhas+=('Origem existe: '+(Test-Path -LiteralPath $Item.origem)); $linhas+=('Backup existe: '+(Test-Path -LiteralPath $Item.destino)); $linhas+='Reversao condicionada a origem livre e backup disponivel.' }
        'quarantena-registro' { $linhas+=('Chave existe: '+(Test-Path -LiteralPath ('Registry::'+$Item.chave))); $linhas+='Importacao condicionada a chave nao recriada.' }
        'recurso' { $linhas+=('Anterior: '+$Item.estadoAnterior+'; alvo: '+$Item.estadoDepois); $linhas+=('Dependencias alteradas: '+@($Item.alteracoes).Count); $linhas+='Pode exigir reinicio ou revisao manual.' }
        'appx' { $linhas+='Reinstalacao condicionada a disponibilidade do pacote; dados nao garantidos.' }
        'desinstalado-app' { $linhas+='Reinstalacao manual; o journal nao e backup do aplicativo.' }
        'comando' { $linhas+='Recuperacao manual de comando legado.' }
        'reg-import' { $linhas+='Recuperacao manual de importacao integral legada.' }
        default { $linhas+='Consulte o snapshot e os backups; recuperacao depende do estado atual.' }
    }
    return $linhas
}

function Clique-DetalhesSessao {
    try {
        $lb = $global:UI.ListaDesfazer
        if ($lb.SelectedIndex -lt 0) { Avisar 'Selecione' 'Escolha uma sessao na lista.'; return }
        $arquivo = $lb.Tag[$lb.SelectedIndex]
        if (-not $arquivo -or -not (Test-Path -LiteralPath $arquivo -PathType Leaf)) { Avisar 'Sessao ausente' 'Atualize a lista de sessoes.'; return }
        $json = Ler-JSON $arquivo
        $linhas = @('Journal: ' + $arquivo, ('Sessao: ' + $json.rotulo), ('Criada: ' + $json.criado), '', 'Inspecao somente leitura; nao apague backups manualmente.', '')
        foreach ($item in @($json.itens)) {
            $estado = 'pendente'
            if ($item.estadoReversao -eq 'concluido') { $estado = 'revertido' }
            elseif ($item.estadoReversao -eq 'em_andamento') { $estado = 'incerto - revisao manual' }
            $alvo = @($item.caminho, $item.origem, $item.chave, $item.nome, $item.tarefaNome, $item.pacote, $item.displayName, $item.contexto | Where-Object { $_ }) -join ' '
            if ($item.confirmadoManualEm) { $estado = 'confirmado manualmente' }
            $linhas += ('[{0}] {1}: {2}' -f $estado, $item.tipo, $alvo)
            foreach ($detalhe in @(Obter-DetalheRecuperacao $item)) { $linhas += ('    '+$detalhe) }
            foreach ($backup in @($item.destino, $item.arquivoReg, $item.backupReg) + @($item.backups)) {
                if (-not $backup) { continue }
                $disp = 'ausente'
                if (Test-Path -LiteralPath $backup) { $disp = 'presente' }
                $linhas += ('    backup ({0}): {1}' -f $disp, $backup)
            }
        }
        $dlg = New-Object System.Windows.Window
        $dlg.Title = 'Detalhes da sessao e quarentena'
        $dlg.Owner = $global:Janela
        $dlg.WindowStartupLocation = 'CenterOwner'
        $dlg.Width = 800
        $dlg.Height = 550
        $dlg.MaxWidth = [System.Windows.SystemParameters]::WorkArea.Width
        $dlg.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
        $caixa = New-Object System.Windows.Controls.TextBox
        $caixa.IsReadOnly = $true
        $caixa.AcceptsReturn = $true
        $caixa.TextWrapping = 'Wrap'
        $caixa.VerticalScrollBarVisibility = 'Auto'
        $caixa.Text = ($linhas -join [Environment]::NewLine)
        $dlg.Content = $caixa
        [void]$dlg.ShowDialog()
    } catch {
        Log ('falha ao consultar sessao: ' + $_.Exception.Message) -Erro
        Avisar 'Sessao invalida' 'Nao foi possivel ler os detalhes. Preserve os arquivos e consulte o log.'
    }
}

# Executa consultas somente leitura em um runspace separado, com janela modal.
function Executar-ConsultaLocal {
    param([string]$Titulo, [scriptblock]$Codigo, [hashtable]$Parametros = @{}, [string]$Mensagem='Consultando o sistema. Nenhuma alteracao sera aplicada.', [switch]$SemCancelar)
    $ps = [PowerShell]::Create()
    $estado = @{ cancelado=$false; resultado=$null; erro=$null; terminou=$false; parada=$null }
    $dlg = New-Object System.Windows.Window
    $dlg.Title = $Titulo
    $dlg.Owner = $global:Janela
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Width = 400
    $dlg.Height = 160
    $dlg.ResizeMode = 'NoResize'
    $painel = New-Object System.Windows.Controls.StackPanel
    $painel.Margin = '16'
    $mensagem = New-Object System.Windows.Controls.TextBlock
    $mensagem.Text = $Mensagem
    $mensagem.TextWrapping = 'Wrap'
    [void]$painel.Children.Add($mensagem)
    $barra = New-Object System.Windows.Controls.ProgressBar
    $barra.IsIndeterminate = $true
    $barra.Height = 12
    $barra.Margin = '0,10,0,10'
    [void]$painel.Children.Add($barra)
    $cancelar = New-Object System.Windows.Controls.Button
    $cancelar.Content = 'Cancelar'
    if ($SemCancelar) { $cancelar.IsEnabled=$false; $cancelar.Content='Aguarde a conclusao' }
    [void]$painel.Children.Add($cancelar)
    $dlg.Content = $painel
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    try {
        [void]$ps.AddScript($Codigo.ToString())
        foreach ($chave in $Parametros.Keys) { [void]$ps.AddParameter($chave,$Parametros[$chave]) }
        $async = $ps.BeginInvoke()
        $pedirCancelamento = {
            if (-not $SemCancelar -and -not $estado.cancelado -and -not $async.IsCompleted) {
                $estado.cancelado = $true
                $cancelar.IsEnabled = $false
                $mensagem.Text = 'Cancelando consulta...'
                try { $estado.parada = $ps.BeginStop($null,$null) }
                catch { $estado.erro = $_.Exception }
            }
        }.GetNewClosure()
        $cancelar.Add_Click($pedirCancelamento)
        $dlg.Add_Closing({
            param($sender,$eventArgs)
            if (-not $estado.terminou) { $eventArgs.Cancel = $true; & $pedirCancelamento }
        }.GetNewClosure())
        $timer.Add_Tick({
            if (-not $async.IsCompleted) { return }
            $timer.Stop()
            try {
                $estado.resultado = @($ps.EndInvoke($async))
                if ($ps.Streams.Error.Count -gt 0 -and -not $estado.cancelado) { throw $ps.Streams.Error[0].Exception }
            } catch { if (-not $estado.cancelado) { $estado.erro = $_.Exception } }
            $estado.terminou = $true
            $dlg.Close()
        }.GetNewClosure())
        $timer.Start()
        [void]$dlg.ShowDialog()
        if ($estado.cancelado) { return $null }
        if ($estado.erro) { throw $estado.erro }
        return $estado.resultado
    } finally {
        $timer.Stop()
        if ($estado.parada -and $estado.parada.IsCompleted) {
            try { $ps.EndStop($estado.parada) } catch { }
        }
        $ps.Dispose()
    }
}

function Clique-Medicoes {
    Confirmar-PermissaoAlteracao
    try {
        $escolha = Perguntar 'Comparativo do sistema' 'Sim: capturar a referencia antes dos ajustes. Nao: abrir uma referencia salva e comparar com a medicao atual.'
        $antes = $null
        if (-not $escolha) {
            $abrir = New-Object Microsoft.Win32.OpenFileDialog
            $abrir.Filter = 'Medicao JSON (*.json)|*.json'
            if (-not $abrir.ShowDialog()) { return }
            $antes = Ler-JSON $abrir.FileName
        }
        $n=3
        if ($antes -and $antes.amostras) { $n=[int]$antes.amostras }
        $medicoes = @(Executar-ConsultaLocal -Titulo 'Medindo o sistema' -Codigo ${function:Medir-EstadoSistema} -Parametros @{Amostras=$n; Cenario=[string]$antes.cenario})
        if ($medicoes.Count -ne 1 -or $null -eq $medicoes[0]) { Status 'medicao cancelada.'; return }
        $atual = $medicoes[0]
        if ($escolha) {
            $salvar = New-Object Microsoft.Win32.SaveFileDialog
            $salvar.Filter = 'Medicao JSON (*.json)|*.json'
            $salvar.FileName = 'otimizadorpc-antes.json'
            if ($salvar.ShowDialog()) {
                Gravar-JSONAtomico -Arquivo $salvar.FileName -Objeto $atual
                Avisar 'Referencia salva' 'Repita a medicao em condicoes semelhantes, com os mesmos programas abertos. O JSON inclui o nome do computador; nao compartilhe sem revisar.'
            }
        } else {
            $linhas = @(Comparar-Medicoes -Antes $antes -Depois $atual | Format-Table -AutoSize | Out-String -Width 120)
            Avisar 'Comparativo observacional' (($linhas -join '') + [Environment]::NewLine + 'Amostras de CPU, RAM e processos. A carga de trabalho pode variar; diferencas nao provam ganho de desempenho ou FPS.')
        }
    } catch {
        Log ('falha na medicao: ' + $_.Exception.Message) -Erro
        Avisar 'Medicao indisponivel' $_.Exception.Message
    }
}

function Clique-VerificarRelease {
    Confirmar-PermissaoAlteracao
    try {
        $dados = @(Executar-ConsultaLocal -Titulo 'Consultando versao oficial' -Codigo ${function:Consultar-ReleaseOficial})
        if ($dados.Count -ne 1 -or $null -eq $dados[0]) { return }
        $info=$dados[0]
        $tag = if ($info.estavel) { $info.estavel } else { $info.previa }
        $msg = "Versao atual: $global:VersaoOtimizador`nEstavel: $($info.estavel)`nPrevia: $($info.previa)"
        if (-not $tag) { Avisar 'Versao oficial' ($msg + "`nNenhuma release compativel."); return }
        if (-not (Perguntar 'Versao oficial' ($msg + "`n`nBaixar $tag com verificacao SHA256? Nada sera executado."))) { return }
        $res = @(Executar-ConsultaLocal -Titulo 'Baixando e conferindo SHA256' -Codigo ${function:Baixar-ReleaseVerificada} -Parametros @{Tag=$tag})
        if ($res.Count -ne 1) { return }
        $salvar = New-Object Microsoft.Win32.SaveFileDialog
        $salvar.Filter='Script PowerShell (*.ps1)|*.ps1'
        $salvar.FileName=('otimizadorpc-' + $tag + '.ps1')
        if ($salvar.ShowDialog()) {
            [IO.File]::WriteAllBytes($salvar.FileName,[byte[]]$res[0].bytes)
            if ((Get-FileHash -LiteralPath $salvar.FileName -Algorithm SHA256).Hash -ne $res[0].hash) { throw 'Arquivo salvo com hash divergente.' }
            Avisar 'Download verificado' 'Script salvo; nenhuma atualizacao foi executada. SHA256 verifica integridade, nao substitui assinatura digital. Revise o codigo antes de executar.'
        }
    } catch { Avisar 'Falha na consulta/download' $_.Exception.Message }
}

function Clique-CargaPadronizada {
    Confirmar-PermissaoAlteracao
    try {
        if (-not (Perguntar 'Teste de carga' 'Executar tres rodadas de SHA256 e copia de memoria? Feche outras tarefas para comparacao. Este teste sintetico nao representa FPS ou desempenho geral.')) { return }
        $res=@(Executar-ConsultaLocal -Titulo 'Teste de carga padronizada' -Codigo ${function:Medir-CargaPadronizada})
        if ($res.Count -ne 1) { return }
        $dados=$res[0]
        $linhas=$dados.rodadas | Format-Table -AutoSize | Out-String -Width 100
        if (Perguntar 'Resultados (ms) - salvar?' ($linhas + "`nMenor tempo e melhor neste teste especifico. Repita com mesma energia, temperatura e programas abertos. Exportar JSON?")) {
            $salvar=New-Object Microsoft.Win32.SaveFileDialog
            $salvar.Filter='Teste JSON (*.json)|*.json'; $salvar.FileName='otimizadorpc-carga.json'
            if ($salvar.ShowDialog()) { Gravar-JSONAtomico -Arquivo $salvar.FileName -Objeto $dados }
        }
    } catch { Avisar 'Teste indisponivel' $_.Exception.Message }
}

function Clique-ResumoDriversPnP {
    try {
        $res=@(Executar-ConsultaLocal -Titulo 'Consultando dispositivos presentes e drivers' -Codigo ${function:Obter-ResumoDriversPnP})
        if ($res.Count -eq 1 -and $res[0]) {Avisar 'Dispositivos e drivers - somente leitura' ([string]$res[0])}
    } catch {Avisar 'Consulta indisponivel' $_.Exception.Message}
}

function Clique-ResumoBateria {
    try {
        $res=@(Executar-ConsultaLocal -Titulo 'Consultando bateria' -Codigo ${function:Obter-ResumoBateria})
        if ($res.Count -eq 1 -and $res[0]) {Avisar 'Bateria - estimativas locais' ([string]$res[0])}
    } catch {Avisar 'Consulta indisponivel' $_.Exception.Message}
}

function Clique-GargalosLocais {
    try {
        $res=@(Executar-ConsultaLocal -Titulo 'Amostrando CPU, memoria e disco' -Codigo ${function:Medir-GargalosLocais})
        if ($res.Count -ne 1 -or -not $res[0]) {return}
        $msg=($res[0].serie | Format-Table -AutoSize | Out-String -Width 100)+"`n"+($res[0].avisos -join "`n")
        Avisar 'Amostras de desempenho - diagnostico local' $msg
    } catch {Avisar 'Consulta indisponivel' $_.Exception.Message}
}

function Clique-DiagnosticoAvancado {
    try {
        $res=@(Executar-ConsultaLocal -Titulo 'Diagnostico de dispositivos e eventos' -Codigo ${function:Obter-DiagnosticoAvancado})
        if ($res.Count -eq 1 -and $res[0]) { Avisar 'Diagnostico avancado - somente leitura' ([string]$res[0]) }
    } catch { Avisar 'Consulta indisponivel' $_.Exception.Message }
}

function Clique-HistoricoAtualizacoes {
    try {
        $res=@(Executar-ConsultaLocal -Titulo 'Historico local de atualizacoes' -Codigo ${function:Obter-HistoricoAtualizacoes})
        if ($res.Count -eq 1 -and $res[0]) { Avisar 'Historico local do Windows Update' ([string]$res[0]) }
    } catch { Avisar 'Consulta indisponivel' $_.Exception.Message }
}

function Clique-MonitorSistema {
    try {
        $med = @(Executar-ConsultaLocal -Titulo 'Monitor de recursos - 10 amostras' -Codigo ${function:Medir-EstadoSistema} -Parametros @{Amostras=10; Cenario='monitor'})
        if ($med.Count -ne 1) { return }
        $dados=$med[0]
        $linhas = ($dados.serie | Format-Table -AutoSize | Out-String -Width 100)
        $msg = $linhas + "`nCPU media: $($dados.cpuMedia)% | RAM usada: $($dados.ramUsadaGB) GB | Disco livre: $($dados.discoLivreGB) GB"
        if ($global:ModoProtegido) { Avisar 'Monitor - diagnostico local' $msg; return }
        if (Perguntar 'Monitor - salvar relatorio?' ($msg + "`nExportar amostras em JSON?")) {
            $salvar=New-Object Microsoft.Win32.SaveFileDialog
            $salvar.Filter='Relatorio JSON (*.json)|*.json'; $salvar.FileName='otimizadorpc-monitor.json'
            if ($salvar.ShowDialog()) { Gravar-JSONAtomico -Arquivo $salvar.FileName -Objeto $dados }
        }
    } catch { Avisar 'Monitor indisponivel' $_.Exception.Message }
}

# Um unico controlador de cliques mutaveis evita reentrada pelo Dispatcher.
function Executar-OperacaoUI {
    param([scriptblock]$Acao)
    if ($global:OperacaoUIAtiva) { return }
    if ($global:ModoProtegido) { Avisar 'Modo protegido' 'Alteracoes indisponiveis. Consulte o TI.'; return }
    $global:OperacaoUIAtiva = $true
    $janela = $global:Janela
    $antes = $janela.IsEnabled
    $janela.IsEnabled = $false
    try { & $Acao }
    catch {
        Log ('operacao interrompida: ' + $_.Exception.Message) -Erro
        Status 'operacao interrompida; consulte o log.'
        Avisar 'Operacao interrompida' $_.Exception.Message
    } finally {
        $janela.IsEnabled = $antes
        $global:OperacaoUIAtiva = $false
        if ($global:ConsultaUwp) {
            Cancelar-ConsultaUwp 'Inventario desatualizado apos operacao.'
            if ($global:PaginaAtual -eq 'PaginaDebloat') { Verificar-EstadoUwp }
        }
        if ($global:UI.ContainsKey('BarraProgresso')) { $global:UI.BarraProgresso.IsIndeterminate = $false }
    }
}

# WPF usa unidades independentes de DPI; respeita a area util da tela.
function Ajustar-TamanhoJanela {
    $area = [System.Windows.SystemParameters]::WorkArea
    $j = $global:Janela
    $j.MaxWidth = $area.Width
    $j.MaxHeight = $area.Height
    $j.MinWidth = [math]::Min(900,[math]::Max(0,$area.Width))
    $j.MinHeight = [math]::Min(580,[math]::Max(0,$area.Height))
    $j.Width = [math]::Min(1200,$area.Width)
    $j.Height = [math]::Min(780,$area.Height)
}

function Ligar-Tudo {
    Ajustar-TamanhoJanela
    Inicializar-ConsultaUwp
    $global:Janela.Add_Closed({ Cancelar-ConsultaUwp -Fechar })
    $global:UI.BotaoAtualizarUwp.Add_Click({ Verificar-EstadoUwp -Forcar })
    $global:UI.BotaoCancelarUwp.Add_Click({ Cancelar-ConsultaUwp })
    $global:Janela.Add_Closing({ param($sender,$eventArgs) if ($global:OperacaoUIAtiva) { $eventArgs.Cancel = $true } })
    # navegacao da barra lateral
    $global:UI.BotaoNavInicio.Add_Click({ Trocar-Pagina 'PaginaInicio' })
    $global:UI.BotaoNavAjustes.Add_Click({ Trocar-Pagina 'PaginaAjustes' })
    $global:UI.BotaoNavDebloat.Add_Click({ Trocar-Pagina 'PaginaDebloat' })
    $global:UI.BotaoNavDesinstalar.Add_Click({ Trocar-Pagina 'PaginaDesinstalar' })
    $global:UI.BotaoNavInstalar.Add_Click({ Trocar-Pagina 'PaginaInstalar' })
    $global:UI.BotaoNavConfig.Add_Click({ Trocar-Pagina 'PaginaConfig' })
    $global:UI.BotaoNavAtualizacoes.Add_Click({ Trocar-Pagina 'PaginaAtualizacoes' })
    $global:UI.BotaoNavManutencao.Add_Click({ Trocar-Pagina 'PaginaManutencao' })
    $global:UI.BotaoNavDesfazer.Add_Click({ Trocar-Pagina 'PaginaDesfazer' })

    if ($global:ModoProtegido) {
        # Registra somente eventos de consulta. A lista de permissoes falha fechada
        # para novos botoes; nenhuma acao administrativa e ligada neste modo.
        $permitidos=@('BotaoNavInicio','BotaoNavAjustes','BotaoNavDebloat','BotaoNavDesinstalar','BotaoNavInstalar','BotaoNavConfig','BotaoNavAtualizacoes','BotaoNavManutencao','BotaoNavDesfazer','BotaoInventario','BotaoMonitor','BotaoDiagnosticoAvancado','BotaoResumoBateria','BotaoGargalosLocais','BotaoResumoDriversPnP','BotaoAtualizarProgramas','BotaoDetalhesPrograma','BotaoAtualizarUwp','BotaoCancelarUwp')
        foreach ($nome in $global:UI.Keys) {
            $controle=$global:UI[$nome]
            if (($controle -is [System.Windows.Controls.Button] -and $nome -notin $permitidos) -or $controle -is [System.Windows.Controls.CheckBox]) {
                $controle.IsEnabled=$false
                $controle.ToolTip='Indisponivel no modo protegido.'
                [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($controle,$true)
            }
        }
        $global:UI.BotaoInventario.Add_Click({ Clique-InventarioLocal })
        $global:UI.BotaoMonitor.Add_Click({ Clique-MonitorSistema })
        $global:UI.BotaoDiagnosticoAvancado.Add_Click({ Clique-DiagnosticoAvancado })
        $global:UI.BotaoResumoBateria.Add_Click({ Clique-ResumoBateria })
        $global:UI.BotaoGargalosLocais.Add_Click({ Clique-GargalosLocais })
        $global:UI.BotaoResumoDriversPnP.Add_Click({ Clique-ResumoDriversPnP })
        $global:UI.FiltroAjustes.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaAjustes })
        $global:UI.FiltroUwp.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaUwp })
        $global:UI.FiltroApps.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaApps })
        $global:UI.FiltroDesinstalar.Add_TextChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
        $global:UI.CategoriaDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
        $global:UI.OrdemDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
        $global:UI.ListaProgramas.Add_SelectionChanged({ Atualizar-DetalhePrograma })
        $global:UI.BotaoDetalhesPrograma.Add_Click({ Clique-DetalhesPrograma })
        $global:UI.BotaoAtualizarProgramas.Add_Click({ Carregar-Programas; Atualizar-ListaProgramas })
        Atualizar-DetalhePrograma
        Montar-PaginaAjustes
        Montar-PaginaInstalar
        Trocar-Pagina 'PaginaInicio'
        Status 'Modo protegido: somente consulta; alteracoes e exportacoes bloqueadas.'
        return
    }

    # filtros de busca das listas
    $global:UI.FiltroAjustes.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaAjustes })
    $global:UI.FiltroUwp.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaUwp })
    $global:UI.FiltroApps.Add_TextChanged({ Aplicar-Filtro -Texto $this.Text -Painel $global:UI.ListaApps })

    # pagina ajustes
    $global:UI.BotaoPresetSeguro.Add_Click({ Clique-Preset 'seguro' })
    $global:UI.BotaoPresetBalanceado.Add_Click({ Clique-Preset 'balanceado' })
    $global:UI.BotaoPresetAgressivo.Add_Click({ Clique-Preset 'agressivo' })
    $global:UI.BotaoPerfilEssencial.Add_Click({ Clique-Preset 'essencial' })
    $global:UI.BotaoPerfilGamer.Add_Click({ Clique-Preset 'gamer' })
    $global:UI.BotaoPerfilNotebook.Add_Click({ Clique-Preset 'notebook' })
    $global:UI.BotaoPerfilPrivacidade.Add_Click({ Clique-Preset 'privacidade' })
    $global:UI.BotaoPerfilCorporativo.Add_Click({ Clique-Preset 'corporativo' })
    $global:UI.BotaoPerfilRecomendado.Add_Click({ Clique-Preset 'recomendado' })
    $global:UI.BotaoAplicarAjustes.Add_Click({ Executar-OperacaoUI { Clique-AplicarAjustes } })
    $global:UI.BotaoExportarPlano.Add_Click({ Clique-ExportarPlano })
    $global:UI.BotaoImportarPlano.Add_Click({ Clique-ImportarPlano })

    # pagina debloat
    $global:UI.BotaoRemoverUwp.Add_Click({ Executar-OperacaoUI { Clique-RemoverUwp } })

    # pagina desinstalar
    $global:UI.FiltroDesinstalar.Add_TextChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.CategoriaDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.OrdemDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.ListaProgramas.Add_SelectionChanged({ Atualizar-DetalhePrograma })
    $global:UI.BotaoDetalhesPrograma.Add_Click({ Clique-DetalhesPrograma })
    Atualizar-DetalhePrograma
    $global:UI.BotaoAtualizarProgramas.Add_Click({ Carregar-Programas; Atualizar-ListaProgramas })
    $global:UI.BotaoDesinstalarProg.Add_Click({ Executar-OperacaoUI { Clique-DesinstalarProg } })
    $global:UI.BotaoVarrerRastros.Add_Click({ Executar-OperacaoUI { Clique-VarrerRastros } })
    $global:UI.BotaoMarcarRastros.Add_Click({ Marcar-Rastros $true })
    $global:UI.BotaoDesmarcarRastros.Add_Click({ Marcar-Rastros $false })
    $global:UI.BotaoApagarRastros.Add_Click({ Executar-OperacaoUI { Clique-ApagarRastros } })

    # pagina instalar
    $global:UI.BotaoInstalarApps.Add_Click({ Executar-OperacaoUI { Clique-InstalarApps } })
    $global:UI.BotaoAtualizarTudo.Add_Click({ Executar-OperacaoUI { Atualizar-Tudo } })
    $global:UI.BotaoAtualizarSelecionados.Add_Click({ Executar-OperacaoUI { Clique-InstalarApps -Operacao upgrade } })
    $global:UI.BotaoMarcarPadroes.Add_Click({
        foreach ($cb in (Get-Checkboxes $global:UI.ListaApps)) { $cb.IsChecked = [bool]$cb.Tag.padrao }
        Log 'apps padroes marcados.'
    })

    # pagina config
    $global:UI.BotaoInstalarRecursos.Add_Click({ Executar-OperacaoUI { Clique-InstalarRecursos } })
    $global:UI.BotaoFixUpdate.Add_Click({ Executar-OperacaoUI { Resetar-WindowsUpdate } })
    $global:UI.BotaoFixRede.Add_Click({ Executar-OperacaoUI { Resetar-Rede } })
    $global:UI.BotaoFixWinget.Add_Click({ Executar-OperacaoUI { Instalar-Winget } })
    $global:UI.BotaoTema.Add_Click({
        try {
            $novo=if ($global:TemaOtimizador -eq 'claro') { 'escuro' } else { 'claro' }
            Gravar-JSONAtomico -Arquivo (Join-Path $global:RaizEstado 'preferencias.json') -Objeto ([pscustomobject]@{tema=$novo})
            Avisar 'Tema salvo' ('Tema ' + $novo + ' sera usado quando reabrir o app.')
        } catch { Avisar 'Falha ao salvar tema' $_.Exception.Message }
    })

    # pagina atualizacoes
    $global:UI.BotaoAplicarAtualizacoes.Add_Click({ Clique-HistoricoAtualizacoes })
    $global:UI.BotaoFixIntegridade.Add_Click({ Executar-OperacaoUI { Verificar-Integridade } })
    $global:UI.BotaoBuscarAtualizacoes.Add_Click({ Start-Process 'ms-settings:windowsupdate' | Out-Null })
    $global:UI.BotaoResetUpdate2.Add_Click({ Executar-OperacaoUI { Resetar-WindowsUpdate } })

    # pagina manutencao
    $global:UI.BotaoLimparTemp.Add_Click({ Executar-OperacaoUI { Limpar-Temporarios } })
    $global:UI.BotaoLimparDns.Add_Click({ Executar-OperacaoUI { Limpar-DNS; Status 'dns limpo.' } })
    $global:UI.BotaoSincronizarHora.Add_Click({ Executar-OperacaoUI { Sincronizar-Hora } })
    $global:UI.BotaoBackupDrivers.Add_Click({ Executar-OperacaoUI { Clique-BackupDrivers } })
    $global:UI.BotaoAnalisarArmazenamento.Add_Click({ Clique-AnalisarArmazenamento })
    $global:UI.BotaoRecuperarIcones.Add_Click({ Executar-OperacaoUI { Recuperar-CacheIcones } })
    $global:UI.BotaoLimpezaDisco.Add_Click({ Executar-OperacaoUI { Limpeza-Disco } })
    $global:UI.BotaoVerificarDisco.Add_Click({ Executar-OperacaoUI { Verificar-Disco } })
    $global:UI.BotaoLimpezaDism.Add_Click({ Executar-OperacaoUI { Manutencao-DISM } })
    $global:UI.BotaoAnalisarComponentes.Add_Click({ Executar-OperacaoUI { Analisar-ComponentesWindows } })
    $global:UI.BotaoDiagnosticarIntegridade.Add_Click({ Executar-OperacaoUI { Diagnosticar-Integridade } })
    $global:UI.BotaoConsultarEnergia.Add_Click({ Executar-OperacaoUI { Consultar-Energia } })
    $global:UI.BotaoOtimizarVolume.Add_Click({ Executar-OperacaoUI { Abrir-OtimizacaoVolume } })
    $global:UI.BotaoVerificarIntegridade.Add_Click({ Executar-OperacaoUI { Verificar-Integridade } })

    # pagina desfazer
    $global:UI.BotaoDesfazer.Add_Click({ Executar-OperacaoUI { Clique-Desfazer } })
    $global:UI.BotaoDesfazerUma.Add_Click({ Executar-OperacaoUI { Clique-Desfazer -UmaAcao } })
    $global:UI.BotaoConfirmarManual.Add_Click({ Executar-OperacaoUI { Clique-ConfirmarManual } })
    $global:UI.BotaoDetalhesSessao.Add_Click({ Clique-DetalhesSessao })
    $global:UI.BotaoAtualizarListaSessoes.Add_Click({ Atualizar-ListaDesfazer; Log 'lista de sessoes atualizada.' })

    # pagina inicio
    $global:UI.BotaoInventario.Add_Click({ Clique-InventarioLocal })
    $global:UI.BotaoMedicoes.Add_Click({ Clique-Medicoes })
    $global:UI.BotaoMonitor.Add_Click({ Clique-MonitorSistema })
    $global:UI.BotaoDiagnosticoAvancado.Add_Click({ Clique-DiagnosticoAvancado })
    $global:UI.BotaoResumoBateria.Add_Click({ Clique-ResumoBateria })
    $global:UI.BotaoGargalosLocais.Add_Click({ Clique-GargalosLocais })
    $global:UI.BotaoResumoDriversPnP.Add_Click({ Clique-ResumoDriversPnP })
    $global:UI.BotaoCarga.Add_Click({ Clique-CargaPadronizada })
    $global:UI.BotaoVerificarRelease.Add_Click({ Clique-VerificarRelease })
    $global:UI.BotaoCriarRestore.Add_Click({
        Executar-OperacaoUI { Ocupado $true; try { [void](Criar-PontoRestauracao) } finally { Ocupado $false }; Preencher-PaginaInicio }
    })

    # monta conteudo dinamico
    Montar-PaginaAjustes
    # Debloat consulta pacotes somente ao abrir a aba.
    Montar-PaginaInstalar
    Montar-PaineisLegados
    Trocar-Pagina 'PaginaInicio'
}
