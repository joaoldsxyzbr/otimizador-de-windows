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
    $bloqueio=Obter-BloqueioAjuste $Tweak
    $protecao=if ($bloqueio) { 'Somente consulta: '+$bloqueio } else { 'Protecao por alvo: verificacoes adicionais no executor.' }
    $auditoria=if ($Tweak.auditoria) {
        @(('Objetivo: '+$Tweak.auditoria.objetivo),('Decisao: '+$Tweak.auditoria.decisao),('Evidencia: '+$Tweak.auditoria.evidencia),('Risco: '+$Tweak.auditoria.risco),('Orientacao: '+$Tweak.auditoria.orientacao),('Verificacao: '+$Tweak.auditoria.verificacao),('Fonte: '+$Tweak.auditoria.fonte))
    } else {@('Plano local sem auditoria de beneficio.')}
    $proposta=@('Valores propostos (nao comprova efeito):')
    foreach ($acao in @($Tweak.acoes)) {$proposta+=('  '+(Descrever-Acao $acao))}
    return [pscustomobject]@{ risco=$risco; texto=((@($Tweak.desc,"Impacto: $impacto","Compatibilidade: $compat. $notaCompat","Escopo: $escopo","Recuperacao: $recuperacao",$reinicio,$protecao)+$auditoria+$proposta) -join [Environment]::NewLine) }
}

function Atualizar-RotuloAjuste {
    param($Cb,[string]$Estado)
    $t=$Cb.Tag
    $rotulo=switch ($Estado) {'aplicado' {'ja aplicado'} 'parcial' {'parcial'} 'nao' {'nao aplicado'} default {'estado nao confirmado'}}
    $Cb.Content=$t.nome + ' [' + (Classificar-RiscoAjuste $t) + '] (' + $rotulo + ')'
    if ($t.apenasManual) { $Cb.Content += ' [manual]' }
    if (Obter-BloqueioAjuste $t) { $Cb.Content += ' [somente consulta/simulacao]' }
    $Cb.ToolTip=(Obter-GuiaAjuste $t).texto
    $decisao=@(@(foreach ($a in @($t.acoes)) {Avaliar-PermissaoOperacao (Obter-IdOperacaoAcao $a) -Previa}) | Where-Object {$_.estado -ne 'permitido'} | Select-Object -First 1)
    if ($global:ModoProtegido -or $decisao.Count) { $Cb.Content+=' [somente consulta]'; $Cb.IsChecked=$false; $Cb.IsEnabled=$false; if ($decisao.Count) {$Cb.ToolTip += [Environment]::NewLine+$decisao[0].motivo} }
    elseif (-not $Cb.IsEnabled) { $Cb.Content+=' [indisponivel nesta instalacao]'; $Cb.IsChecked=$false }
    $Cb.Foreground=switch ($Estado) {'aplicado' {Cor-Tema '#86efac'} 'parcial' {Cor-Tema '#fde047'} default {Cor-Tema '#e5e7eb'}}
    if ($Estado -eq 'aplicado') { $Cb.IsChecked=$false }
}

function Montar-PaginaAjustes {
    param($Contexto=$null)
    $win11 = Eh-Win11
    $ctx=$Contexto
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
    $identidade=if ($achados.Count) {(@($achados | ForEach-Object {('{0} | {1} | {2}' -f $_.Name,$_.Version,$_.Publisher)} | Sort-Object -Unique) -join '; ')} else {'sem pacote instalado confirmado'}
    $motivo+=' Identidade: '+$identidade+'.'
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
        $cb.IsEnabled=((Testar-PermissaoPrevia 'appx') -and $info.permitido)
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
        if (-not (Testar-PermissaoPrevia 'winget')) { $cb.IsEnabled=$false }
        [void]$grupos[$a.categoria].Content.Children.Add($cb)
    }
}

function Montar-PaginaRecursos {
    param([object[]]$Estados=@(),[bool]$Consultou=$false)
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
    foreach ($r in $recursos) {
        $f=@($estados | Where-Object {$_.FeatureName -eq $r.feat})
        $estado=if (-not $consultou) {'consulta indisponivel'} elseif ($f.Count -ne 1) {'indisponivel nesta instalacao'} else {$f[0].State.ToString()}
        $cb=Nova-Checkbox -Texto ($r.nome+' ['+$estado+']') -Tag $r -Dica ($r.desc+"`nEstado: "+$estado+". Dependencias e reinicio podem exigir recuperacao manual.")
        $cb.IsEnabled=((Testar-PermissaoPrevia 'recurso') -and $consultou -and $f.Count -eq 1 -and $estado -eq 'Disabled')
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
    param([switch]$Forcar)
    Solicitar-ConsultaPainel 'Historico' -Forcar:$Forcar
}

function Mostrar-SnapshotHistorico {
    param($Dados,$UI)
    $lb=$UI.ListaDesfazer
    $lb.Items.Clear()
    $lb.Tag=@{}
    foreach ($item in @($Dados.itens)) {
        [void]$lb.Items.Add([string]$item.rotulo)
        if ($item.valido) {$lb.Tag[$lb.Items.Count-1]=[string]$item.arquivo}
    }
    if ($lb.Items.Count -eq 0) {[void]$lb.Items.Add('(nenhuma sessao encontrada)')}
}

function Mostrar-SnapshotAtualizacoes {
    param($Dados,$UI)
    $atual=$Dados.politica
    $UI.ChkBloquearDrivers.IsChecked=($null -ne $atual -and $atual.ExcludeWUDriverInQualityUpdate -eq 1)
    $UI.ChkAdiarRecursos.IsChecked=($null -ne $atual -and $atual.DeferFeatureUpdates -eq 1)
    $UI.InfoPoliticasUpdate.Text=('Drivers: '+(Formatar-PoliticaAtualizacao $atual.ExcludeWUDriverInQualityUpdate)+[Environment]::NewLine+'Versoes: '+(Formatar-PoliticaAtualizacao $atual.DeferFeatureUpdates)+[Environment]::NewLine+'Periodo registrado: '+$atual.DeferFeatureUpdatesPeriodInDays+[Environment]::NewLine+'Valores do registro nao comprovam politica efetiva.')
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
    param([switch]$Forcar)
    Solicitar-ConsultaPainel 'Ajustes' -Forcar:$Forcar
}

# Each window owns its snapshot. Only the Dispatcher touches WPF controls.
# Shared admission and completion for all navigation inventory workers.
# Count even a cancelled provider that has not stopped; never allocate unlimited runspaces.
function Contar-ConsultasAtivas {
    $total=0
    foreach ($nome in @('ConsultasUwpAtivas','ConsultasInicioAtivas','ConsultasProgramasAtivas','TimersPaineis')) {
        $v=Get-Variable -Name $nome -Scope Global -ErrorAction SilentlyContinue
        if ($v -and $v.Value) {$total+=$v.Value.Count}
    }
    if ($global:ConsultasDialogoAtivas) {$total+=$global:ConsultasDialogoAtivas.Count}
    return $total
}

function Testar-VagaConsulta {
    param([int]$Limite=4)
    return ((Contar-ConsultasAtivas) -lt $Limite)
}

function Testar-PrazoConsulta {
    param($Trabalho)
    return ($Trabalho.relogio.Elapsed.TotalSeconds -lt $Trabalho.limite)
}

# Only called after the async and stop handles have completed.
function Receber-ResultadoConsulta {
    param($Trabalho)
    $dados=@();$falha=$false
    try {
        if ($Trabalho.parada) {try {$Trabalho.ps.EndStop($Trabalho.parada)} catch {}}
        $dados=@($Trabalho.ps.EndInvoke($Trabalho.async))
        if ($Trabalho.ps.Streams.Error.Count -gt 0) {$falha=$true}
    } catch {$falha=$true}
    finally {$Trabalho.ps.Dispose()}
    return [pscustomobject]@{dados=$dados;falha=$falha}
}

# One waiting request per panel, FIFO, no worker allocated while waiting.
function Inicializar-FilaConsultas {
    if ($global:TimerFilaConsultas) {$global:TimerFilaConsultas.Stop()}
    $global:FilaConsultas=[ordered]@{}
    $global:ConsultasDialogoAtivas=@{}
    $global:TimerFilaConsultas=New-Object System.Windows.Threading.DispatcherTimer
    $global:TimerFilaConsultas.Interval=[TimeSpan]::FromMilliseconds(100)
    $global:TimerFilaConsultas.Add_Tick({Processar-FilaConsultas})
}

function Remover-ConsultaFila {
    param([string]$Chave)
    if ($null -ne $global:FilaConsultas -and $global:FilaConsultas.Contains($Chave)) {$global:FilaConsultas.Remove($Chave)}
    if ($global:TimerFilaConsultas -and $global:FilaConsultas.Count -eq 0) {$global:TimerFilaConsultas.Stop()}
}

function Adicionar-ConsultaFila {
    param([string]$Chave,$Estado,[string]$Funcao,[hashtable]$Parametros,[string]$Mostrar)
    if ($Estado.fechada -or $global:FilaConsultas.Contains($Chave)) {return}
    $global:FilaConsultas[$Chave]=@{estado=$Estado;funcao=$Funcao;parametros=$Parametros;mostrar=$Mostrar;espera=[Diagnostics.Stopwatch]::StartNew()}
    & $Mostrar $Estado 'na_fila' 'Consulta na fila. Inicia automaticamente quando houver vaga; voce pode cancelar.'
    $global:TimerFilaConsultas.Start()
}

function Processar-FilaConsultas {
    if ($global:OperacaoUIAtiva -or $null -eq $global:FilaConsultas) {return}
    foreach ($chave in @($global:FilaConsultas.Keys)) {
        $pedido=$global:FilaConsultas[$chave]
        if (-not $pedido) {continue}
        $s=$pedido.estado
        if ($s.fechada) {Remover-ConsultaFila $chave;continue}
        if ($pedido.espera.Elapsed.TotalSeconds -ge 90) {
            Remover-ConsultaFila $chave
            & $pedido.mostrar $s 'indisponivel' 'Tempo de espera na fila atingido. Atualize para tentar novamente.'
            continue
        }
        if ($s.trabalho -or -not (Testar-VagaConsulta)) {continue}
        Remover-ConsultaFila $chave
        $params=$pedido.parametros
        & $pedido.funcao @params
    }
    if ($global:FilaConsultas.Count -eq 0) {$global:TimerFilaConsultas.Stop()}
}

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
    $ui.BotaoAtualizarUwp.IsEnabled=($null -eq $Estado.trabalho -and $Fase -ne 'na_fila')
    $ui.BotaoCancelarUwp.IsEnabled=($Fase -in @('carregando','na_fila'))
    $ui.BotaoRemoverUwp.IsEnabled=((Testar-PermissaoPrevia 'appx') -and $Fase -eq 'atualizado' -and -not $global:OperacaoUIAtiva)
    if ($Fase -ne 'atualizado') { $ui.ListaUwp.Children.Clear() }
}

function Cancelar-ConsultaUwp {
    param([string]$Motivo='Consulta cancelada.',[switch]$Fechar)
    $s=$global:ConsultaUwp
    if (-not $s) { return }
    Remover-ConsultaFila 'Uwp'
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
    # Completion observed after deadline is discarded, even if provider returned success.
    if (-not $j.cancelado -and -not (Testar-PrazoConsulta $j)) {$j.cancelado=$true;$s.motivo='Tempo limite atingido; resultado tardio descartado.'}
    try {$resultado=Receber-ResultadoConsulta $j} finally {$s.trabalho=$null}
    $dados=@($resultado.dados)
    $falha=($resultado.falha)
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
    if ($global:FilaConsultas.Contains('Uwp')) {return}
    if (-not (Testar-VagaConsulta)) {Adicionar-ConsultaFila 'Uwp' $s 'Verificar-EstadoUwp' @{Forcar=$true;Codigo=$Codigo;LimiteSegundos=$LimiteSegundos} 'Mostrar-ConsultaUwp';return}
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
    if ($Nome -eq 'PaginaConfig') { Solicitar-ConsultaPainel 'Recursos' }
    if ($Nome -eq 'PaginaDesfazer') { Atualizar-ListaDesfazer }
    if ($Nome -eq 'PaginaDesinstalar') { Carregar-Programas }
    if ($Nome -eq 'PaginaAtualizacoes') { Solicitar-ConsultaPainel 'Atualizacoes' }
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
    if ($global:ConsultasPaineis.Ajustes.fase -ne 'atualizado') { Avisar 'Consulta indisponivel' 'Atualize os ajustes antes de aplicar.'; return }
    $selecionados = @(Get-Checkboxes $global:UI.ListaAjustes | Where-Object { $_.IsChecked -and $_.IsEnabled })
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
    try {Confirmar-LoteAjustes @($selecionados | ForEach-Object {$_.Tag})} catch {Avisar 'Selecao conflitante' $_.Exception.Message;return}
    foreach ($cb in $selecionados) {
        try {Confirmar-AutorizacaoAjuste $cb.Tag $ctx} catch {Avisar 'Ajuste indisponivel' $_.Exception.Message;return}
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
            try {Confirmar-AutorizacaoAjuste $t (Obter-ContextoAjustes)} catch {Log ('Ajuste preservado: '+$_.Exception.Message) -Erro;continue}
            foreach ($acao in $t.acoes) {
                if (-not (Continuar-ProgressoLote $progresso $t.nome)) { break ajustes }
                Executar-Acao $acao $t.nome
                if (Testar-SessaoInterrompida) {break ajustes}
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
    Log 'Se necessario, salve o trabalho e encerre a sessao pelo Windows. O aplicativo nao encerra processos Explorer.'
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
            if (Testar-SessaoInterrompida) {break}
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
    if ($global:ConsultasPaineis.Recursos.fase -ne 'atualizado') { Avisar 'Consulta indisponivel' 'Atualize os recursos antes de habilitar.'; return }
    $selecionados = @(Get-Checkboxes $global:UI.ListaRecursos | Where-Object { $_.IsChecked -and $_.IsEnabled })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os recursos do Windows que quer habilitar.'
        return
    }
    $conf = Perguntar 'Habilitar recursos' ('Habilitar {0} recurso(s) do Windows? Alguns pedem reinicializacao e internet. Virtualizacao pode afetar hipervisores, jogos e outras cargas. Revise compatibilidade, dependencias e autorizacao. Se dependencias forem alteradas, a reversao exigira revisao manual.' -f $selecionados.Count)
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
            if (Testar-SessaoInterrompida) {break}
            Atualizar-UI
        }
    } finally { Fechar-ProgressoLote $progresso }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($progresso.cancelado) { Log 'recursos interrompidos; journal preservado.'; Status 'lote interrompido.'; return }
    Log ('recursos processados; confira erros e reinicio pendente.' + $(if ($arq) { ' - journal: ' + (Split-Path -Leaf $arq) } else { '' }))
    if ($global:ErrosSessao -gt 0) { Status 'recursos com falhas; consulte o log.' } else { Status 'recursos processados; confira reinicio pendente.' }
}

# Preview never creates a session or executes an action.
function Obter-PreviaEssencial {
    param($Catalogo,[bool]$Win11)
    $linhas=@('Previa hipotetica: nao confirma compatibilidade, politica ou autorizacao.')
    foreach ($ajuste in @(Selecionar-TweaksPreset -Nivel essencial -Catalogo $Catalogo -Win11 $Win11)) {
        $linhas+=('Ajuste: '+$ajuste.nome)
        foreach ($acao in $ajuste.acoes) {$linhas+=('  '+(Descrever-Acao $acao))}
    }
    $linhas+='Nenhuma configuracao foi modificada.'
    return ($linhas -join [Environment]::NewLine)
}

function Clique-Preset {
    param([string]$Nivel)
    if ($global:ConsultasPaineis.Ajustes.fase -ne 'atualizado') {return}
    $cbs = Get-Checkboxes $global:UI.ListaAjustes
    try {
        $perfil=$Nivel
        if ($Nivel -eq 'recomendado') { $perfil='essencial' }
        $ids = @(Selecionar-TweaksPreset -Nivel $perfil -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11) | ForEach-Object { $_.id })
    } catch {
        Avisar 'Preset invalido' $_.Exception.Message
        return
    }
    foreach ($cb in $cbs) {
        $cb.IsChecked = ($cb.IsEnabled -and $ids -contains $cb.Tag.id -and $global:ConsultasPaineis.Ajustes.resultados[[string]$cb.Tag.id] -in @('nao','parcial'))
    }
    $orientacao=switch ($Nivel) {
        'gamer' {'Meca o tempo de quadro no proprio jogo, CPU/GPU e temperatura sob a mesma carga; nao desative SysMain ou servicos sem diagnostico.'}
        'notebook' {'Revise consumo, bateria e plano de energia; compare autonomia na mesma carga, sem forcar alto desempenho.'}
        'privacidade' {'Revise permissoes por aplicativo e configuracoes de publicidade, localizacao e diagnostico; politicas administrativas ficam em consulta.'}
        'corporativo' {'Use somente operacoes autorizadas pelo TI; preserve VPN, atualizacoes e protecoes.'}
        'recomendado' {'Comece pelos indicadores da central de saude; escolha a manutencao correspondente apenas se houver evidencia.'}
        default {'Sem ganho medido para ajustes adicionais; a selecao essencial e uma preferencia de visualizacao.'}
    }
    Avisar 'Orientacao do perfil' ($orientacao + [Environment]::NewLine + 'Todos os perfis selecionam somente extensoes de arquivos. Nada foi aplicado; itens ja aplicados nao sao selecionados.')
    Log 'Todos os aliases de preset usam apenas a preferencia essencial; ajustes manuais nao sao preselecionados.'
    Log ('preset marcado: ' + $Nivel + ' (' + @(($cbs | Where-Object { $_.IsChecked })).Count + ' ajustes). confira a lista e clique em aplicar.')
}

# exporta os ajustes marcados num .json (pra repetir depois ou levar pra outro pc)
function Clique-ExportarPlano {
    Confirmar-PermissaoAlteracao 'exportar'
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
    Confirmar-PermissaoAlteracao 'exportar'
    Gravar-JSONAtomico -Arquivo $dlg.FileName -Objeto $plano
    Log ('plano exportado com ' + $selecionados.Count + ' ajuste(s): ' + $dlg.FileName)
    Status ('plano exportado (' + $selecionados.Count + ' ajustes).')
}

# importa um plano exportado: so marca as checkboxes na lista, nao aplica nada
function Clique-ImportarPlano {
    Confirmar-PermissaoAlteracao 'estado-local'
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
    if ($caminho -like '*.revertido') {Avisar 'Historico arquivado' 'Esta sessao nao permite nova reversao. Use Detalhes para consultar.';return}
    if (-not $caminho -or -not (Test-Path -LiteralPath $caminho)) {
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
        else { Status 'sessao arquivada; confira itens manuais.' }
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
        $arquivo=Confirmar-ArquivoJournal $arquivo
        $json = Ler-JSON $arquivo
        Confirmar-ContextoJournal $json
        Confirmar-FormatoJournal $json
        $itens = @($json.itens)
        for ($i = $itens.Count - 1; $i -ge 0; $i--) {
            $item = $itens[$i]
            if ($item.estadoReversao -in @('concluido','manual-sem-restauracao')) { continue }
            $manual=(Obter-TipoRecuperacao $item) -eq 'manual-sem-garantia'
            if ($manual) {
                if (Perguntar 'Encerrar sem restauracao' ('Acao '+$i+' ('+$item.tipo+') nao tem desfazer automatico. Encerrar a revisao SEM afirmar que o estado anterior foi recuperado?')) {
                    Confirmar-ReversaoManual -Arquivo $arquivo -Indice $i -SemRestauracao
                    Atualizar-ListaDesfazer
                    Status 'Encerramento manual registrado, sem garantia de restauracao.'
                }
                return
            }
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
    Confirmar-PermissaoAlteracao $(switch ($Grupo) {'servicos' {'servico'} 'tarefas' {'tarefa'} 'runUsuario' {'registro-local'} default {'nao-catalogado'}})
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
        $resultado = @(Executar-ConsultaLocal -Titulo 'Inventario local' -Codigo ${function:Obter-InventarioLocal} -Parametros @{Protegido=(-not (Testar-PermissaoPrevia 'exportar'))})
        if ($resultado.Count -ne 1 -or $null -eq $resultado[0]) { Status 'inventario cancelado.'; return }
        $dados = $resultado[0]
        $dlg = New-Object System.Windows.Window
        $dlg.Title = 'Gerenciador local - OtimizadorPC'
        try { if ($global:Janela -and $global:Janela.IsLoaded) { $dlg.Owner = $global:Janela } } catch { }
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
        if (Testar-PermissaoPrevia 'exportar') { [void]$barra.Children.Add($salvar) }
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
            [void]$barra.Children.Add($botao)
        }
        $nota = New-Object System.Windows.Controls.TextBlock
        $nota.TextWrapping = 'Wrap'
        $nota.Text = 'Inventario com acoes limitadas e journal. Alteracoes nas ferramentas nativas nao entram no journal. Win32/MSI e AppX sao inventarios distintos; use as abas Desinstalar e Debloat para avaliar remocao. Ordene pelos cabecalhos e filtre por texto. Revise antes de compartilhar. ' + ($dados.avisos -join ' | ')
        if (-not (Testar-PermissaoPrevia 'exportar')) { $nota.Text='Diagnostico local somente leitura. Exportacao e alteracoes indisponiveis. '+($dados.avisos -join ' | ') }
        $nota.Margin = '0,0,0,8'
        [System.Windows.Controls.DockPanel]::SetDock($nota,'Top')
        [void]$painel.Children.Add($nota)
        $abas = New-Object System.Windows.Controls.TabControl
        foreach ($grupo in @('aplicativosWin32','appxUsuario','inicializacao','runUsuario','servicos','tarefas','discos','rede','drivers','processos')) {
            $tab = New-Object System.Windows.Controls.TabItem
            $tab.Header = switch ($grupo) {'aplicativosWin32' {'Aplicativos Win32/MSI'} 'appxUsuario' {'AppX do usuario'} default {$grupo}}
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
            $idGrupo=switch ($grupo) {'runUsuario' {'registro-local'} 'servicos' {'servico'} 'tarefas' {'tarefa'} default {'nao-catalogado'}}
            if (Testar-PermissaoPrevia $idGrupo) {
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
    Confirmar-PermissaoAlteracao 'exportar'
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
            Confirmar-PermissaoAlteracao 'exportar'
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
        try { if ($global:Janela -and $global:Janela.IsLoaded) { $dlg.Owner = $global:Janela } } catch { }
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
        'instalacao-app' { $linhas+='Instalador delegado; codigo do processo nao prova todos os efeitos. Sem rollback automatico.' }
        'temp' {$linhas+='Exclusao definitiva; registro agregado, nao backup de arquivo.'}
        'manutencao' {$linhas+='Comando nativo; sem restauracao automatica e sem garantia de resultado funcional.'}
        'path-entrada' {$linhas+=('Escopo: '+$Item.escopo);$linhas+='Snapshot do PATH preservado no journal local. Nao compartilhe o valor bruto.'}
        'comando' { $linhas+='Recuperacao manual de comando legado.' }
        'reg-import' { $linhas+='Recuperacao manual de importacao integral legada.' }
        default { $linhas+='Consulte o snapshot e os backups; recuperacao depende do estado atual.' }
    }
    return $linhas
}

function Exportar-RelatorioRecuperacao {
    param([string]$Arquivo)
    Confirmar-PermissaoAlteracao 'exportar'
    $origem=Confirmar-ArquivoJournal $Arquivo -PermitirArquivado
    $relatorio=Obter-RelatorioRecuperacao (Ler-JSON $origem)
    if (-not (Perguntar 'Exportar resumo sanitizado' 'O resumo inclui somente tipos e estados, sem nomes, valores, caminhos, identidade da maquina, SID, datas ou mensagens de erro. Ainda revele apenas a destinatarios autorizados. Continuar?')) {return}
    $dlg=New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter='Relatorio JSON (*.json)|*.json';$dlg.FileName='recuperacao-resumo.json';$dlg.OverwritePrompt=$true
    if (-not $dlg.ShowDialog()) {return}
    Confirmar-PermissaoAlteracao 'exportar'
    $destino=[IO.Path]::GetFullPath($dlg.FileName)
    if ($destino -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($destino) -ine '.json' -or $destino.Substring(2).Contains(':')) {throw 'Destino local JSON exigido.'}
    if ([IO.File]::Exists($destino)) {throw 'Escolha um arquivo novo; nenhum arquivo existente sera sobrescrito.'}
    $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $relatorio -Depth 6))
    $stream=[IO.File]::Open($destino,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    Avisar 'Exportacao concluida' 'Resumo sanitizado salvo. Nao e um backup restauravel.'
}

function Clique-DetalhesSessao {
    try {
        $lb = $global:UI.ListaDesfazer
        if ($lb.SelectedIndex -lt 0) { Avisar 'Selecione' 'Escolha uma sessao na lista.'; return }
        $arquivo = $lb.Tag[$lb.SelectedIndex]
        if (-not $arquivo -or -not (Test-Path -LiteralPath $arquivo -PathType Leaf)) { Avisar 'Sessao ausente' 'Atualize a lista de sessoes.'; return }
        $arquivo=Confirmar-ArquivoJournal $arquivo -PermitirArquivado
        $json = Ler-JSON $arquivo
        Confirmar-ContextoJournal $json
        Confirmar-FormatoJournal $json
        $linhas = @('Sessao: ' + $json.rotulo, ('Criada: ' + $json.criado), '', 'Inspecao local somente leitura; pode conter dados privados. Compartilhe apenas o relatorio sanitizado.', 'Nao apague backups manualmente.', '')
        foreach ($item in @($json.itens)) {
            $estado = 'pendente'
            if ($item.estadoReversao -eq 'concluido') { $estado = 'revertido' }
            elseif ($item.estadoReversao -eq 'em_andamento') {
                $estado=if ($json.versaoEsquema -eq 2 -and (Testar-ItemJaRestaurado $item)) {'incerto - estado anterior confirmado; pode reconciliar'} else {'incerto - verificacao ao desfazer ou revisao manual'}
            }
            if ($item.reconciliadoEm) {$estado='reconciliado por leitura'}
            $alvo = @($item.caminho, $item.origem, $item.chave, $item.nome, $item.tarefaNome, $item.pacote, $item.displayName, $item.contexto | Where-Object { $_ }) -join ' '
            if ($item.confirmadoManualEm) { $estado = 'confirmado manualmente' }
            if ($item.estadoReversao -eq 'manual-sem-restauracao') {$estado='encerrado sem afirmar restauracao'}
            $aplicacao=if ($item.estadoAplicacao) {$item.estadoAplicacao} else {'legado / nao confirmado'}
            $linhas += ('[{0}] {1}: {2} | aplicacao: {3}' -f $estado, $item.tipo, $alvo,$aplicacao)
            $linhas+=('    Recuperacao: '+(Obter-TipoRecuperacao $item))
            if ($item.erroAplicacao) {$linhas+='    Aplicacao nao confirmada; consulte estado real e backups.'}
            if ($item.erroReversao) {$linhas+='    Reversao nao confirmada ou conflito; nao repetir sem verificar.'}
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
        try { if ($global:Janela -and $global:Janela.IsLoaded) { $dlg.Owner = $global:Janela } } catch { }
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
        $painel=New-Object System.Windows.Controls.DockPanel
        $exportar=New-Object System.Windows.Controls.Button
        $exportar.Content='Exportar resumo sanitizado (sem valores, nomes ou caminhos)'
        $exportar.Margin='8';$exportar.Padding='8,4'
        $exportar.IsEnabled=Testar-PermissaoPrevia 'exportar'
        $exportar.Tag=$arquivo
        $exportar.Add_Click({try {Exportar-RelatorioRecuperacao $this.Tag} catch {Avisar 'Exportacao indisponivel' $_.Exception.Message}})
        [System.Windows.Controls.DockPanel]::SetDock($exportar,'Bottom')
        [void]$painel.Children.Add($exportar);[void]$painel.Children.Add($caixa)
        $dlg.Content = $painel
        [void]$dlg.ShowDialog()
    } catch {
        Log ('falha ao consultar sessao: ' + $_.Exception.Message) -Erro
        Avisar 'Sessao invalida' 'Nao foi possivel ler os detalhes. Preserve os arquivos e consulte o log.'
    }
}

# Executa consultas somente leitura em um runspace separado, com janela modal.
# Usa a mesma admissao global das consultas de navegacao: espera vaga antes de
# comecar, ocupa um slot enquanto executa e nunca trava o encerramento do host.
function Executar-ConsultaLocal {
    param([string]$Titulo, [scriptblock]$Codigo, [hashtable]$Parametros = @{}, [string]$Mensagem='Consultando o sistema. Nenhuma alteracao sera aplicada.', [switch]$SemCancelar)
    if (-not $global:ConsultasDialogoAtivas) { $global:ConsultasDialogoAtivas=@{} }
    $ps = [PowerShell]::Create()
    $estado = @{ chave=[Guid]::NewGuid().ToString(); fase='aguardando'; cancelado=$false; resultado=$null; erro=$null; terminou=$false; abandonado=$false; pediuFechar=$null; esperando=[Diagnostics.Stopwatch]::StartNew(); parada=$null; async=$null; ps=$ps }
    $dlg = New-Object System.Windows.Window
    $dlg.Title = $Titulo
    try { if ($global:Janela -and $global:Janela.IsLoaded) { $dlg.Owner = $global:Janela } } catch { }
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
        $pedirCancelamento = {
            if ($estado.fase -eq 'aguardando' -and -not $estado.cancelado) { $estado.cancelado = $true; try { $dlg.Close() } catch { }; return }
            if ($estado.fase -eq 'executando' -and -not $estado.cancelado -and $estado.async -and -not $estado.async.IsCompleted) {
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
            if ($estado.terminou -or $estado.abandonado) { return }
            if ($estado.fase -eq 'aguardando') { $estado.cancelado = $true; return }
            if (-not $estado.pediuFechar) { $estado.pediuFechar = [Diagnostics.Stopwatch]::StartNew() }
            & $pedirCancelamento
            if ($estado.pediuFechar.Elapsed.TotalSeconds -ge 10) { $estado.abandonado = $true; return }
            $eventArgs.Cancel = $true
        }.GetNewClosure())
        $dlg.Add_Closed({
            if ($estado.terminou -or $estado.fase -eq 'aguardando') { return }
            if ($estado.abandonado) {
                $global:ConsultasDialogoAtivas[$estado.chave] = @{ estado = $estado }
                if (-not $estado.parada -and $estado.async -and -not $estado.async.IsCompleted) {
                    try { $estado.parada = $ps.BeginStop($null,$null) } catch { }
                }
            }
        }.GetNewClosure())
        $timer.Add_Tick({
            if ($estado.terminou) { $timer.Stop(); return }
            if ($estado.abandonado) {
                if (-not $estado.async) { $timer.Stop(); return }
                if (-not $estado.async.IsCompleted) { return }
                if ($estado.parada -and -not $estado.parada.IsCompleted) { return }
                $timer.Stop()
                Concluir-ConsultaDialogo $estado.chave
                return
            }
            if ($global:JanelaFechada) {
                $estado.cancelado = $true
                $estado.abandonado = $true
                if ($estado.fase -eq 'executando' -and -not $estado.parada -and $estado.async -and -not $estado.async.IsCompleted) {
                    try { $estado.parada = $ps.BeginStop($null,$null) } catch { }
                }
                $dlg.Close()
                return
            }
            if ($estado.fase -eq 'aguardando') {
                if ($estado.esperando.Elapsed.TotalSeconds -ge 90) { $estado.cancelado = $true; $estado.terminou = $true; $dlg.Close(); return }
                if (-not (Testar-VagaConsulta)) { return }
                try { $estado.async = $ps.BeginInvoke() }
                catch { $estado.erro = $_.Exception; $estado.terminou = $true; $dlg.Close(); return }
                $estado.fase = 'executando'
                $global:ConsultasDialogoAtivas[$estado.chave] = @{ estado = $estado }
                $mensagem.Text = 'Executando a consulta...'
                return
            }
            if (-not $estado.async.IsCompleted) { return }
            $timer.Stop()
            try { $global:ConsultasDialogoAtivas.Remove($estado.chave) } catch { }
            try {
                $estado.resultado = @($ps.EndInvoke($estado.async))
                if ($ps.Streams.Error.Count -gt 0 -and -not $estado.cancelado) { throw $ps.Streams.Error[0].Exception }
            } catch { if (-not $estado.cancelado) { $estado.erro = $_.Exception } }
            $estado.terminou = $true
            $dlg.Close()
        }.GetNewClosure())
        $timer.Start()
        if (-not (Testar-VagaConsulta)) { $mensagem.Text = 'Outras consultas em andamento. Aguardando vaga para comecar...' }
        [void]$dlg.ShowDialog()
        if ($estado.cancelado -or $estado.abandonado) { return $null }
        if ($estado.erro) { throw $estado.erro }
        return $estado.resultado
    } finally {
        if (-not $estado.abandonado) {
            $timer.Stop()
            try { $global:ConsultasDialogoAtivas.Remove($estado.chave) } catch { }
            if ($estado.parada -and $estado.parada.IsCompleted) {
                try { $ps.EndStop($estado.parada) } catch { }
            }
            $ps.Dispose()
        }
    }
}

function Clique-Medicoes {
    Confirmar-PermissaoAlteracao 'exportar'
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
    Confirmar-PermissaoAlteracao 'download'
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
            Confirmar-PermissaoAlteracao 'download'
            [IO.File]::WriteAllBytes($salvar.FileName,[byte[]]$res[0].bytes)
            if ((Get-FileHash -LiteralPath $salvar.FileName -Algorithm SHA256).Hash -ne $res[0].hash) { throw 'Arquivo salvo com hash divergente.' }
            Avisar 'Download verificado' 'Script salvo; nenhuma atualizacao foi executada. SHA256 verifica integridade, nao substitui assinatura digital. Revise o codigo antes de executar.'
        }
    } catch { Avisar 'Falha na consulta/download' $_.Exception.Message }
}

function Clique-CargaPadronizada {
    Confirmar-PermissaoAlteracao 'exportar'
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
        if (-not (Testar-PermissaoPrevia 'exportar')) { Avisar 'Monitor - diagnostico local' $msg; return }
        if (Perguntar 'Monitor - salvar relatorio?' ($msg + "`nExportar amostras em JSON?")) {
            $salvar=New-Object Microsoft.Win32.SaveFileDialog
            $salvar.Filter='Relatorio JSON (*.json)|*.json'; $salvar.FileName='otimizadorpc-monitor.json'
            if ($salvar.ShowDialog()) { Gravar-JSONAtomico -Arquivo $salvar.FileName -Objeto $dados }
        }
    } catch { Avisar 'Monitor indisponivel' $_.Exception.Message }
}

# Um unico controlador de cliques mutaveis evita reentrada pelo Dispatcher.
function Executar-OperacaoUI {
    param([scriptblock]$Acao,[string]$Id)
    if ($global:OperacaoUIAtiva) { return }
    try {Confirmar-PermissaoAlteracao $Id} catch {Avisar 'Operacao indisponivel' $_.Exception.Message;return}
    $global:OperacaoUIAtiva = $true
    $janela = $global:Janela
    $antes = $janela.IsEnabled
    $janela.IsEnabled = $false
    try { & $Acao }
    catch {
        try {Registrar-FalhaOperacao 'interrompido'} catch {Log 'Resultado nao persistido; preserve o journal.' -Erro}
        Log ('operacao interrompida: ' + $_.Exception.Message) -Erro
        Status 'operacao interrompida; consulte o log.'
        Avisar 'Operacao interrompida' $_.Exception.Message
    } finally {
        $janela.IsEnabled = $antes
        $global:OperacaoUIAtiva = $false
        if ($global:ConsultasPaineis) {
            Cancelar-ConsultaPainel 'Ajustes' 'Consulta desatualizada apos operacao.'
            Cancelar-ConsultaPainel 'Recursos' 'Consulta desatualizada apos operacao.'
            Cancelar-ConsultaPainel 'Atualizacoes' 'Consulta desatualizada apos operacao.'
            Cancelar-ConsultaPainel 'Historico' 'Consulta desatualizada apos operacao.'
            if ($global:PaginaAtual -eq 'PaginaDesfazer') { Atualizar-ListaDesfazer -Forcar }
            if ($global:PaginaAtual -eq 'PaginaAtualizacoes') { Solicitar-ConsultaPainel 'Atualizacoes' -Forcar }
            if ($global:PaginaAtual -eq 'PaginaAjustes') { Verificar-EstadoAjustes -Forcar }
            if ($global:PaginaAtual -eq 'PaginaConfig') { Solicitar-ConsultaPainel 'Recursos' -Forcar }
        }
        if ($global:ConsultaProgramas) {
            Cancelar-ConsultaProgramas 'Inventario desatualizado apos operacao.'
            if ($global:PaginaAtual -eq 'PaginaDesinstalar') { Carregar-Programas -Forcar }
        }
        if ($global:ConsultaInicio) {
            Cancelar-ConsultaInicio 'Analise desatualizada apos operacao.'
            if ($global:PaginaAtual -eq 'PaginaInicio') { Preencher-PaginaInicio -Forcar }
        }
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

# Read-only home inventory: one worker per window, independent of navigation.
function Inicializar-ConsultaInicio {
    if ($null -eq $global:ConsultasInicioAtivas) {$global:ConsultasInicioAtivas=@{}}
    $global:ConsultaInicio=@{ui=$global:UI;fase='inicial';data=$null;trabalho=$null;fechada=$false;motivo=''}
    $global:UI.BotaoCancelarInicio.IsEnabled=$false
}

function Mostrar-EstadoInicio {
    param($s,[string]$Fase,[string]$Mensagem)
    $s.fase=$Fase
    if ($s.fechada) {return}
    $s.ui.BotaoAtualizarInicio.IsEnabled=($null -eq $s.trabalho -and $Fase -ne 'na_fila')
    $s.ui.BotaoCancelarInicio.IsEnabled=($Fase -in @('carregando','na_fila'))
    if ($Fase -ne 'atualizado') {
        foreach ($campo in @('InfoCpu','InfoGpu','InfoRam','InfoDisco','InfoUptime','InfoRestore')) {
            $s.ui[$campo].Text=if ($Fase -eq 'carregando') {'Consultando...'} else {'Indisponivel'}
        }
        $s.ui.InfoDiagnostico.Text=$Mensagem
    }
}

function Cancelar-ConsultaInicio {
    param([string]$Motivo='Consulta cancelada.',[switch]$Fechar)
    $s=$global:ConsultaInicio
    if (-not $s) {return}
    Remover-ConsultaFila 'Inicio'
    if ($Fechar) {$s.fechada=$true}
    $s.data=$null; $s.motivo=$Motivo
    $j=$s.trabalho
    if ($j) {
        Mostrar-EstadoInicio $s 'cancelando' ($Motivo+' Aguardando encerramento.')
        if (-not $j.cancelado) {
            $j.cancelado=$true
            if (-not $j.async.IsCompleted) {try {$j.parada=$j.ps.BeginStop($null,$null)} catch {}}
        }
    } else {Mostrar-EstadoInicio $s 'indisponivel' $Motivo}
}

function Concluir-ConsultaInicio {
    param($Timer)
    $s=$global:ConsultasInicioAtivas[$Timer]
    if (-not $s) {$Timer.Stop();return}
    $j=$s.trabalho
    if (-not $j.async.IsCompleted) {
        if (-not $j.cancelado -and $j.relogio.Elapsed.TotalSeconds -ge $j.limite -and [object]::ReferenceEquals($s,$global:ConsultaInicio)) {Cancelar-ConsultaInicio 'Tempo limite da analise atingido.'}
        return
    }
    if ($j.parada -and -not $j.parada.IsCompleted) {return}
    $Timer.Stop()
    $global:ConsultasInicioAtivas.Remove($Timer)
    # Completion observed after deadline is discarded, even if provider returned success.
    if (-not $j.cancelado -and -not (Testar-PrazoConsulta $j)) {$j.cancelado=$true;$s.motivo='Tempo limite atingido; resultado tardio descartado.'}
    try {$resultado=Receber-ResultadoConsulta $j} finally {$s.trabalho=$null}
    $dados=@($resultado.dados)
    $falha=($resultado.falha -or $dados.Count -ne 1 -or -not $dados[0].data)
    if ($s.fechada -or -not [object]::ReferenceEquals($s,$global:ConsultaInicio)) {return}
    if ($j.cancelado) {Mostrar-EstadoInicio $s 'indisponivel' ($s.motivo+' Use Atualizar analise.');return}
    if ($falha -or $global:OperacaoUIAtiva) {Mostrar-EstadoInicio $s 'indisponivel' 'Analise indisponivel ou desatualizada. Use Atualizar analise.';return}
    try {
        Mostrar-SnapshotInicio $dados[0] $s.ui
        $s.data=Get-Date
        Mostrar-EstadoInicio $s 'atualizado' ''
    } catch {Mostrar-EstadoInicio $s 'indisponivel' 'Nao foi possivel apresentar a analise. Tente novamente.'}
}

function Solicitar-SnapshotInicio {
    param([switch]$Forcar,[scriptblock]$Codigo=$null,[int]$LimiteSegundos=60)
    $s=$global:ConsultaInicio
    if (-not $s -or $s.fechada -or $s.trabalho -or $global:OperacaoUIAtiva) {return}
    if (-not $Forcar -and $s.fase -eq 'atualizado' -and $s.data -and ((Get-Date)-$s.data).TotalSeconds -lt 60) {return}
    if ($global:FilaConsultas.Contains('Inicio')) {return}
    if (-not (Testar-VagaConsulta)) {Adicionar-ConsultaFila 'Inicio' $s 'Solicitar-SnapshotInicio' @{Forcar=$true;Codigo=$Codigo;LimiteSegundos=$LimiteSegundos} 'Mostrar-EstadoInicio';return}
    $s.data=$null
    $ps=$null;$timer=$null
    try {
        if (-not $Codigo) {$Codigo=(Get-Command Obter-SnapshotInicio -CommandType Function).ScriptBlock}
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript($Codigo.ToString())
        $timer=New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval=[TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({param($sender,$eventArgs) Concluir-ConsultaInicio $sender})
        $s.trabalho=@{ps=$ps;async=$ps.BeginInvoke();parada=$null;cancelado=$false;relogio=[Diagnostics.Stopwatch]::StartNew();limite=$LimiteSegundos}
        $global:ConsultasInicioAtivas[$timer]=$s
        Mostrar-EstadoInicio $s 'carregando' 'Analisando o PC em segundo plano. Voce pode trocar de aba.'
        $timer.Start()
    } catch {
        if ($s.trabalho) {Cancelar-ConsultaInicio 'Falha ao iniciar analise.';$timer.Start()}
        else {if ($timer) {$timer.Stop()};if ($ps) {$ps.Dispose()};Mostrar-EstadoInicio $s 'indisponivel' 'Nao foi possivel iniciar a analise.'}
    }
}

# Read-only installed-program inventory.
function Inicializar-ConsultaProgramas {
    if ($null -eq $global:ConsultasProgramasAtivas) {$global:ConsultasProgramasAtivas=@{}}
    $global:ConsultaProgramas=@{ui=$global:UI;fase='inicial';data=$null;trabalho=$null;fechada=$false;motivo=''}
    $global:ProgramasInstalados=$null
    $global:ProgramasExibidos=@()
    $global:UI.BotaoCancelarProgramas.IsEnabled=$false
}

function Mostrar-EstadoProgramas {
    param($s,[string]$Fase,[string]$Mensagem)
    $s.fase=$Fase
    if ($s.fechada) {return}
    $s.ui.BotaoAtualizarProgramas.IsEnabled=($null -eq $s.trabalho -and $Fase -ne 'na_fila')
    $s.ui.BotaoCancelarProgramas.IsEnabled=($Fase -in @('carregando','na_fila'))
    if ($Fase -ne 'atualizado') {
        $global:ProgramasInstalados=$null
        $global:ProgramasExibidos=@()
        $s.ui.ListaProgramas.Items.Clear()
        $s.ui.InfoProgramas.Text=$Mensagem
        foreach ($nome in @('BotaoDesinstalarProg','BotaoVarrerRastros','BotaoDetalhesPrograma')) {$s.ui[$nome].IsEnabled=$false}
    }
}

function Cancelar-ConsultaProgramas {
    param([string]$Motivo='Consulta cancelada.',[switch]$Fechar)
    $s=$global:ConsultaProgramas
    if (-not $s) {return}
    Remover-ConsultaFila 'Programas'
    if ($Fechar) {$s.fechada=$true}
    $s.data=$null; $s.motivo=$Motivo
    $j=$s.trabalho
    if ($j) {
        Mostrar-EstadoProgramas $s 'cancelando' ($Motivo+' Aguardando encerramento.')
        if (-not $j.cancelado) {
            $j.cancelado=$true
            if (-not $j.async.IsCompleted) {try {$j.parada=$j.ps.BeginStop($null,$null)} catch {}}
        }
    } else {Mostrar-EstadoProgramas $s 'indisponivel' $Motivo}
}

function Concluir-ConsultaProgramas {
    param($Timer)
    $s=$global:ConsultasProgramasAtivas[$Timer]
    if (-not $s) {$Timer.Stop();return}
    $j=$s.trabalho
    if (-not $j.async.IsCompleted) {
        if (-not $j.cancelado -and $j.relogio.Elapsed.TotalSeconds -ge $j.limite -and [object]::ReferenceEquals($s,$global:ConsultaProgramas)) {Cancelar-ConsultaProgramas 'Tempo limite do inventario atingido.'}
        return
    }
    if ($j.parada -and -not $j.parada.IsCompleted) {return}
    $Timer.Stop()
    $global:ConsultasProgramasAtivas.Remove($Timer)
    # Completion observed after deadline is discarded, even if provider returned success.
    if (-not $j.cancelado -and -not (Testar-PrazoConsulta $j)) {$j.cancelado=$true;$s.motivo='Tempo limite atingido; resultado tardio descartado.'}
    try {$resultado=Receber-ResultadoConsulta $j} finally {$s.trabalho=$null}
    $dados=@($resultado.dados)
    $falha=($resultado.falha -or $dados.Count -ne 1 -or -not $dados[0].data -or -not $dados[0].PSObject.Properties['itens'])
    if ($s.fechada -or -not [object]::ReferenceEquals($s,$global:ConsultaProgramas)) {return}
    if ($j.cancelado) {Mostrar-EstadoProgramas $s 'indisponivel' ($s.motivo+' Use Atualizar lista.');return}
    if ($falha -or $global:OperacaoUIAtiva) {Mostrar-EstadoProgramas $s 'indisponivel' 'Inventario indisponivel ou desatualizado. Use Atualizar lista.';return}
    try {
        $global:ProgramasInstalados=@($dados[0].itens | Where-Object {$_})
        Atualizar-ListaProgramas
        $s.data=Get-Date
        Mostrar-EstadoProgramas $s 'atualizado' ''
    } catch {Mostrar-EstadoProgramas $s 'indisponivel' 'Nao foi possivel apresentar a lista. Tente novamente.'}
}

function Solicitar-SnapshotProgramas {
    param([switch]$Forcar,[scriptblock]$Codigo=$null,[int]$LimiteSegundos=30)
    $s=$global:ConsultaProgramas
    if (-not $s -or $s.fechada -or $s.trabalho -or $global:OperacaoUIAtiva) {return}
    if (-not $Forcar -and $s.fase -eq 'atualizado' -and $s.data -and ((Get-Date)-$s.data).TotalSeconds -lt 60) {return}
    if ($global:FilaConsultas.Contains('Programas')) {return}
    if (-not (Testar-VagaConsulta)) {Adicionar-ConsultaFila 'Programas' $s 'Solicitar-SnapshotProgramas' @{Forcar=$true;Codigo=$Codigo;LimiteSegundos=$LimiteSegundos} 'Mostrar-EstadoProgramas';return}
    $s.data=$null
    $ps=$null;$timer=$null
    try {
        $ps=[PowerShell]::Create()
        if ($Codigo) {[void]$ps.AddScript($Codigo.ToString())}
        else {
            $fonte='param([string]$CatalogoJson)'+"`n"+'$ErrorActionPreference="Stop"; $global:CatalogoApps=ConvertFrom-Json $CatalogoJson'+"`n"
            foreach ($fn in @('Converter-EntradaPrograma','Classificar-Programa','Obter-SnapshotProgramas')) {
                $corpo=(Get-Command $fn -CommandType Function).ScriptBlock.ToString()
                $fonte+=("function "+$fn+" {"+$corpo+"}"+[Environment]::NewLine)
            }
            $fonte+='Obter-SnapshotProgramas'
            [void]$ps.AddScript($fonte).AddArgument((ConvertTo-Json -InputObject $global:CatalogoApps -Depth 12 -Compress))
        }
        $timer=New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval=[TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({param($sender,$eventArgs) Concluir-ConsultaProgramas $sender})
        $s.trabalho=@{ps=$ps;async=$ps.BeginInvoke();parada=$null;cancelado=$false;relogio=[Diagnostics.Stopwatch]::StartNew();limite=$LimiteSegundos}
        $global:ConsultasProgramasAtivas[$timer]=$s
        Mostrar-EstadoProgramas $s 'carregando' 'Consultando programas em segundo plano. Voce pode trocar de aba.'
        $timer.Start()
    } catch {
        if ($s.trabalho) {Cancelar-ConsultaProgramas 'Falha ao iniciar inventario.';$timer.Start()}
        else {if ($timer) {$timer.Stop()};if ($ps) {$ps.Dispose()};Mostrar-EstadoProgramas $s 'indisponivel' 'Nao foi possivel iniciar o inventario.'}
    }
}

# Shared read-only worker for adjustment state and optional feature inventories.
function Inicializar-ConsultasPaineis {
    if ($null -eq $global:TimersPaineis) {$global:TimersPaineis=@{}}
    $global:ConsultasPaineis=@{}
    foreach ($tipo in @('Ajustes','Recursos','Atualizacoes','Historico')) {
        $global:ConsultasPaineis[$tipo]=@{tipo=$tipo;ui=$global:UI;fase='inicial';data=$null;trabalho=$null;fechada=$false;motivo='';resultados=@{}}
        Mostrar-EstadoPainel $global:ConsultasPaineis[$tipo] 'inicial' 'Inventario ainda nao consultado.'
    }
}

function Mostrar-EstadoPainel {
    param($s,[string]$Fase,[string]$Mensagem)
    $s.fase=$Fase
    if ($s.fechada) {return}
    $ui=$s.ui
    $ui[('InfoConsulta'+$s.tipo)].Text=$Mensagem
    $ui[('BotaoAtualizar'+$s.tipo)].IsEnabled=($null -eq $s.trabalho -and $Fase -ne 'na_fila')
    $ui[('BotaoCancelar'+$s.tipo)].IsEnabled=($Fase -in @('carregando','na_fila'))
    $habilitar=($Fase -eq 'atualizado' -and -not $global:ModoProtegido -and -not $global:OperacaoUIAtiva)
    if ($s.tipo -eq 'Atualizacoes') {
        if ($Fase -ne 'atualizado') {
            $ui.ChkBloquearDrivers.IsChecked=$null
            $ui.ChkAdiarRecursos.IsChecked=$null
            $ui.InfoPoliticasUpdate.Text='Valores ainda nao confirmados.'
        }
        return
    }
    if ($s.tipo -eq 'Historico') {
        foreach ($nome in @('BotaoDesfazer','BotaoDesfazerUma','BotaoConfirmarManual','BotaoDetalhesSessao')) {$ui[$nome].IsEnabled=$habilitar}
        if ($Fase -ne 'atualizado') {$ui.ListaDesfazer.Items.Clear();$ui.ListaDesfazer.Tag=@{}}
        return
    }
    $botoes=if ($s.tipo -eq 'Ajustes') {@('BotaoAplicarAjustes','BotaoPresetSeguro','BotaoPresetBalanceado','BotaoPresetAgressivo','BotaoPerfilEssencial','BotaoPerfilGamer','BotaoPerfilNotebook','BotaoPerfilPrivacidade','BotaoPerfilCorporativo','BotaoPerfilRecomendado','BotaoImportarPlano','BotaoExportarPlano')} else {@('BotaoInstalarRecursos')}
    foreach ($nome in $botoes) {
        $id=if ($s.tipo -eq 'Recursos') {'recurso'} elseif ($nome -eq 'BotaoExportarPlano') {'exportar'} else {'estado-local'}
        $ui[$nome].IsEnabled=($habilitar -and (Testar-PermissaoPrevia $id))
    }
    if ($Fase -ne 'atualizado') {
        $s.resultados=@{}
        foreach ($cb in @(Get-Checkboxes $ui[('Lista'+$s.tipo)])) {
            $cb.IsChecked=$false;$cb.IsEnabled=$false
            if ($s.tipo -eq 'Ajustes') {Atualizar-RotuloAjuste $cb 'desconhecido'}
        }
        if ($s.tipo -eq 'Recursos') {Montar-PaginaRecursos}
    }
}

function Cancelar-ConsultaPainel {
    param([string]$Tipo,[string]$Motivo='Consulta cancelada.',[switch]$Fechar)
    $s=$global:ConsultasPaineis[$Tipo]
    if (-not $s) {return}
    Remover-ConsultaFila $Tipo
    if ($Fechar) {$s.fechada=$true}
    $s.data=$null;$s.motivo=$Motivo
    $j=$s.trabalho
    if ($j) {
        Mostrar-EstadoPainel $s 'cancelando' ($Motivo+' Aguardando encerramento.')
        if (-not $j.cancelado) {
            $j.cancelado=$true
            if (-not $j.async.IsCompleted) {try {$j.parada=$j.ps.BeginStop($null,$null)} catch {}}
        }
    } else {Mostrar-EstadoPainel $s 'indisponivel' $Motivo}
}

function Concluir-ConsultaPainel {
    param($Timer)
    $s=$global:TimersPaineis[$Timer]
    if (-not $s) {$Timer.Stop();return}
    $j=$s.trabalho
    if (-not $j.async.IsCompleted) {
        if (-not $j.cancelado -and $j.relogio.Elapsed.TotalSeconds -ge $j.limite -and [object]::ReferenceEquals($s,$global:ConsultasPaineis[$s.tipo])) {Cancelar-ConsultaPainel $s.tipo 'Tempo limite atingido.'}
        return
    }
    if ($j.parada -and -not $j.parada.IsCompleted) {return}
    $Timer.Stop();$global:TimersPaineis.Remove($Timer)
    # Completion observed after deadline is discarded, even if provider returned success.
    if (-not $j.cancelado -and -not (Testar-PrazoConsulta $j)) {$j.cancelado=$true;$s.motivo='Tempo limite atingido; resultado tardio descartado.'}
    try {$resultado=Receber-ResultadoConsulta $j} finally {$s.trabalho=$null}
    $dados=@($resultado.dados)
    $falha=($resultado.falha -or $dados.Count -ne 1 -or -not $dados[0].PSObject.Properties['itens'])
    if ($s.fechada -or -not [object]::ReferenceEquals($s,$global:ConsultasPaineis[$s.tipo])) {return}
    if ($j.cancelado) {Mostrar-EstadoPainel $s 'indisponivel' ($s.motivo+' Atualize para tentar novamente.');return}
    if ($falha -or $global:OperacaoUIAtiva) {Mostrar-EstadoPainel $s 'indisponivel' 'Consulta indisponivel ou desatualizada. Tente novamente.';return}
    try {
        if ($s.tipo -eq 'Ajustes') {
            if (-not $dados[0].contexto) {throw 'Compatibilidade nao confirmada.'}
            Montar-PaginaAjustes $dados[0].contexto
            foreach ($item in @($dados[0].itens)) {
                if ($item.estado -notin @('aplicado','parcial','nao','desconhecido')) {throw 'Estado invalido.'}
                $s.resultados[[string]$item.id]=[string]$item.estado
            }
            foreach ($cb in @(Get-Checkboxes $s.ui.ListaAjustes)) {
                $estado=$s.resultados[[string]$cb.Tag.id]
                if (-not $estado) {$estado='desconhecido'}
                Atualizar-RotuloAjuste $cb $estado
            }
            Aplicar-Filtro -Texto $s.ui.FiltroAjustes.Text -Painel $s.ui.ListaAjustes
        } elseif ($s.tipo -eq 'Recursos') {
            Montar-PaginaRecursos -Estados @($dados[0].itens) -Consultou $true
        } elseif ($s.tipo -eq 'Atualizacoes') {
            Mostrar-SnapshotAtualizacoes $dados[0] $s.ui
        } else {
            Mostrar-SnapshotHistorico $dados[0] $s.ui
        }
        $s.data=Get-Date
        Mostrar-EstadoPainel $s 'atualizado' ('Consulta concluida as '+$s.data.ToString('HH:mm:ss')+'. Revise antes de alterar.')
    } catch {Mostrar-EstadoPainel $s 'indisponivel' 'Nao foi possivel apresentar os dados. Tente novamente.'}
}

function Solicitar-ConsultaPainel {
    param([ValidateSet('Ajustes','Recursos','Atualizacoes','Historico')][string]$Tipo,[switch]$Forcar,[scriptblock]$Codigo=$null,[int]$LimiteSegundos=60)
    $s=$global:ConsultasPaineis[$Tipo]
    if (-not $s -or $s.fechada -or $s.trabalho -or $global:OperacaoUIAtiva) {return}
    if ($Tipo -eq 'Historico' -and $global:ModoProtegido) {Mostrar-EstadoPainel $s 'indisponivel' 'Consulta indisponivel no modo protegido.';return}
    if (-not $Forcar -and $s.fase -eq 'atualizado' -and $s.data -and ((Get-Date)-$s.data).TotalSeconds -lt 60) {return}
    if ($global:FilaConsultas.Contains($Tipo)) {return}
    if (-not (Testar-VagaConsulta)) {Adicionar-ConsultaFila $Tipo $s 'Solicitar-ConsultaPainel' @{Tipo=$Tipo;Forcar=$true;Codigo=$Codigo;LimiteSegundos=$LimiteSegundos} 'Mostrar-EstadoPainel';return}
    $s.data=$null;$ps=$null;$timer=$null
    try {
        $ps=[PowerShell]::Create()
        if ($Codigo) {[void]$ps.AddScript($Codigo.ToString())}
        elseif ($Tipo -eq 'Recursos') {
            [void]$ps.AddScript('$ErrorActionPreference="Stop"; [pscustomobject]@{itens=@(Get-WindowsOptionalFeature -Online -ErrorAction Stop)}')
        } elseif ($Tipo -eq 'Atualizacoes') {
            $fonte='function Tem-Atualizacoes {'+(Get-Command Tem-Atualizacoes -CommandType Function).ScriptBlock.ToString()+'}'+[Environment]::NewLine+'$ErrorActionPreference="Stop"; [pscustomobject]@{itens=@();politica=(Tem-Atualizacoes)}'
            [void]$ps.AddScript($fonte)
        } elseif ($Tipo -eq 'Historico') {
            $fonte='param([string]$Pasta)'+[Environment]::NewLine+'$ErrorActionPreference="Stop"; $global:PastaDesfazer=$Pasta'+[Environment]::NewLine
            foreach ($fn in @('Verificar-PastaPrivada','Listar-Sessoes','Ler-JSON','Obter-ContextoJournal','Confirmar-ContextoJournal','Confirmar-ACLArquivoPrivado','Confirmar-ArquivoJournal','Confirmar-FormatoJournal','Obter-SnapshotHistorico')) {
                $fonte+=('function '+$fn+' {'+(Get-Command $fn -CommandType Function).ScriptBlock.ToString()+'}'+[Environment]::NewLine)
            }
            $fonte+='Obter-SnapshotHistorico'
            [void]$ps.AddScript($fonte).AddArgument($global:PastaDesfazer)
        } else {
            $fonte='param([string]$CatalogoJson)'+[Environment]::NewLine+'$ErrorActionPreference="Stop"'+[Environment]::NewLine
            foreach ($fn in @('Converter-Hive','Obter-RaizRegistro','Converter-Kind','Ler-ValorRegistro','Verificar-Acao','Verificar-Tweak','Obter-ContextoAjustes','Obter-PlanoEnergiaAtivo','Carregar-CacheAppx','Appx-Instalado')) {
                $corpo=(Get-Command $fn -CommandType Function).ScriptBlock.ToString()
                $fonte+=("function "+$fn+" {"+$corpo+"}"+[Environment]::NewLine)
            }
            $fonte+='$ctx=Obter-ContextoAjustes; $catalogo=ConvertFrom-Json $CatalogoJson; $itens=@(foreach ($t in $catalogo.tweaks) {[pscustomobject]@{id=$t.id;estado=(Verificar-Tweak $t)}}); [pscustomobject]@{contexto=$ctx;itens=$itens}'
            [void]$ps.AddScript($fonte).AddArgument((ConvertTo-Json -InputObject $global:CatalogoTweaks -Depth 20 -Compress))
        }
        $timer=New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval=[TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({param($sender,$eventArgs) Concluir-ConsultaPainel $sender})
        $s.trabalho=@{ps=$ps;async=$ps.BeginInvoke();parada=$null;cancelado=$false;relogio=[Diagnostics.Stopwatch]::StartNew();limite=$LimiteSegundos}
        $global:TimersPaineis[$timer]=$s
        Mostrar-EstadoPainel $s 'carregando' 'Consultando em segundo plano. Voce pode trocar de aba.'
        $timer.Start()
    } catch {
        if ($s.trabalho) {Cancelar-ConsultaPainel $Tipo 'Falha ao iniciar consulta.';$timer.Start()}
        else {if ($timer) {$timer.Stop()};if ($ps) {$ps.Dispose()};Mostrar-EstadoPainel $s 'indisponivel' 'Nao foi possivel iniciar a consulta.'}
    }
}

# Encerra um worker de dialogo abandonado cujos handles ja completaram.
function Concluir-ConsultaDialogo {
    param([string]$Chave)
    $ref=$global:ConsultasDialogoAtivas[$Chave]
    if (-not $ref -or -not $ref.estado) { return }
    try { $global:ConsultasDialogoAtivas.Remove($Chave) } catch { }
    $tr=$ref.estado
    try { if ($tr.parada) { $tr.ps.EndStop($tr.parada) } } catch { }
    try { if ($tr.async) { [void]$tr.ps.EndInvoke($tr.async) } } catch { }
    try { $tr.ps.Dispose() } catch { }
}

# The window is already closed: drain completed workers without an unbounded wait.
# A provider that ignores cancellation cannot be forcibly disposed on the UI thread.
function Finalizar-ConsultasPendentes {
    param([int]$LimiteMs=2000)
    $grupos=@(
        @{nome='ConsultasUwpAtivas';funcao='Concluir-ConsultaUwp'},
        @{nome='ConsultasInicioAtivas';funcao='Concluir-ConsultaInicio'},
        @{nome='ConsultasProgramasAtivas';funcao='Concluir-ConsultaProgramas'},
        @{nome='TimersPaineis';funcao='Concluir-ConsultaPainel'}
    )
    $relogio=[Diagnostics.Stopwatch]::StartNew()
    do {
        $pendentes=0
        foreach ($grupo in $grupos) {
            $variavel=Get-Variable -Name $grupo.nome -Scope Global -ErrorAction SilentlyContinue
            if (-not $variavel -or -not $variavel.Value) {continue}
            $mapa=$variavel.Value
            foreach ($timer in @($mapa.Keys)) {
                $estado=$mapa[$timer]
                if (-not $estado -or -not $estado.fechada) {continue}
                $j=$estado.trabalho
                if ($j -and $j.async.IsCompleted -and (-not $j.parada -or $j.parada.IsCompleted)) {
                    & $grupo.funcao $timer
                } else {$pendentes++}
            }
        }
        $mapaDialogos=Get-Variable -Name 'ConsultasDialogoAtivas' -Scope Global -ErrorAction SilentlyContinue
        if ($mapaDialogos -and $mapaDialogos.Value) {
            foreach ($chave in @($mapaDialogos.Value.Keys)) {
                $tr=$mapaDialogos.Value[$chave].estado
                if ($tr -and $tr.async -and $tr.async.IsCompleted -and (-not $tr.parada -or $tr.parada.IsCompleted)) {
                    Concluir-ConsultaDialogo $chave
                } else {$pendentes++}
            }
        }
        if ($pendentes -eq 0) {return 0}
        if ($relogio.ElapsedMilliseconds -lt $LimiteMs) {Start-Sleep -Milliseconds 50}
    } while ($relogio.ElapsedMilliseconds -lt $LimiteMs)
    return $pendentes
}

# Capability preview is advisory. The executor always checks live context.
function Atualizar-CapacidadesOperacoes {
    $mapa=@{
        BotaoInstalarApps='winget'; BotaoAtualizarSelecionados='winget'; BotaoAtualizarTudo='consulta-winget'; BotaoMarcarPadroes='winget'
        BotaoApagarRastros='rastros'; BotaoMarcarRastros='rastros'; BotaoDesmarcarRastros='rastros'
        BotaoCriarRestore='restore'; BotaoBackupDrivers='exportar'; BotaoMedicoes='exportar'; BotaoCarga='exportar'; BotaoVerificarRelease='download'
        BotaoLimparTemp='temp'; BotaoLimparDns='dns'; BotaoSincronizarHora='hora'
        BotaoFixIntegridade='reparo'; BotaoLimpezaDism='reparo'; BotaoVerificarIntegridade='reparo'
        BotaoVerificarDisco='diagnostico-admin'; BotaoAnalisarComponentes='diagnostico-admin'; BotaoDiagnosticarIntegridade='diagnostico-admin'; BotaoConsultarEnergia='diagnostico-admin'
    }
    foreach ($nome in $mapa.Keys) {
        $b=$global:UI[$nome]
        if (-not $b) {continue}
        $d=Avaliar-PermissaoOperacao $mapa[$nome] -Previa
        if ($d.estado -ne 'permitido') {
            $b.IsEnabled=$false
            $b.ToolTip=$d.motivo+' '+$d.proximo
            [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($b,$true)
        }
    }
}

function Ligar-Tudo {
    Ajustar-TamanhoJanela
    $global:JanelaFechada=$false
    Inicializar-FilaConsultas
    Inicializar-ConsultaUwp
    Inicializar-ConsultaInicio
    Inicializar-ConsultaProgramas
    Inicializar-ConsultasPaineis
    $global:Janela.Add_Closed({ Cancelar-ConsultaUwp -Fechar; Cancelar-ConsultaInicio -Fechar; Cancelar-ConsultaProgramas -Fechar; Cancelar-ConsultaPainel 'Ajustes' -Fechar; Cancelar-ConsultaPainel 'Recursos' -Fechar; Cancelar-ConsultaPainel 'Atualizacoes' -Fechar; Cancelar-ConsultaPainel 'Historico' -Fechar; $global:TimerFilaConsultas.Stop(); $global:FilaConsultas.Clear(); $global:JanelaFechada=$true })
    $global:UI.BotaoAtualizarAjustes.Add_Click({ Verificar-EstadoAjustes -Forcar })
    $global:UI.BotaoCancelarAjustes.Add_Click({ Cancelar-ConsultaPainel 'Ajustes' })
    $global:UI.BotaoAtualizarRecursos.Add_Click({ Solicitar-ConsultaPainel 'Recursos' -Forcar })
    $global:UI.BotaoCancelarRecursos.Add_Click({ Cancelar-ConsultaPainel 'Recursos' })
    $global:UI.BotaoAtualizarAtualizacoes.Add_Click({ Solicitar-ConsultaPainel 'Atualizacoes' -Forcar })
    $global:UI.BotaoCancelarAtualizacoes.Add_Click({ Cancelar-ConsultaPainel 'Atualizacoes' })
    $global:UI.BotaoAtualizarHistorico.Add_Click({ Atualizar-ListaDesfazer -Forcar })
    $global:UI.BotaoCancelarHistorico.Add_Click({ Cancelar-ConsultaPainel 'Historico' })
    $global:UI.BotaoCancelarProgramas.Add_Click({ Cancelar-ConsultaProgramas })
    $global:UI.BotaoAtualizarInicio.Add_Click({ Solicitar-SnapshotInicio -Forcar })
    $global:UI.BotaoCancelarInicio.Add_Click({ Cancelar-ConsultaInicio })
    $global:UI.BotaoAtualizarUwp.Add_Click({ Verificar-EstadoUwp -Forcar })
    $global:UI.BotaoCancelarUwp.Add_Click({ Cancelar-ConsultaUwp })
    $global:Janela.Add_Closing({ param($sender,$eventArgs) if ($global:OperacaoUIAtiva) { $eventArgs.Cancel = $true } })
    # navegacao da barra lateral
    $global:UI.BotaoPreviaEssencial.Add_Click({ Avisar 'Previa essencial (somente leitura)' (Obter-PreviaEssencial $global:CatalogoTweaks (Eh-Win11)) })
    $global:UI.BotaoInicioStartup.Add_Click({ Start-Process 'ms-settings:startupapps' | Out-Null })
    $global:UI.BotaoInicioStorage.Add_Click({ Start-Process 'ms-settings:storagesense' | Out-Null })
    $global:UI.BotaoInicioUpdate.Add_Click({ Start-Process 'ms-settings:windowsupdate' | Out-Null })
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
        $permitidos=@('BotaoFixUpdate','BotaoFixRede','BotaoFixWinget','BotaoResetUpdate2','BotaoLimpezaDisco','BotaoRecuperarIcones','BotaoOtimizarVolume','BotaoAplicarAtualizacoes','BotaoPreviaEssencial','BotaoAnalisarArmazenamento','BotaoBuscarAtualizacoes','BotaoInicioStartup','BotaoInicioStorage','BotaoInicioUpdate','BotaoNavInicio','BotaoNavAjustes','BotaoNavDebloat','BotaoNavDesinstalar','BotaoNavInstalar','BotaoNavConfig','BotaoNavAtualizacoes','BotaoNavManutencao','BotaoNavDesfazer','BotaoInventario','BotaoMonitor','BotaoDiagnosticoAvancado','BotaoResumoBateria','BotaoGargalosLocais','BotaoResumoDriversPnP','BotaoAtualizarProgramas','BotaoDetalhesPrograma','BotaoAtualizarUwp','BotaoCancelarUwp','BotaoAtualizarInicio','BotaoCancelarInicio','BotaoCancelarProgramas','BotaoAtualizarAjustes','BotaoCancelarAjustes','BotaoAtualizarRecursos','BotaoCancelarRecursos','BotaoAtualizarAtualizacoes','BotaoCancelarAtualizacoes','BotaoAtualizarHistorico','BotaoCancelarHistorico')
        foreach ($nome in $global:UI.Keys) {
            $controle=$global:UI[$nome]
            if (($controle -is [System.Windows.Controls.Button] -and $nome -notin $permitidos) -or $controle -is [System.Windows.Controls.CheckBox]) {
                $controle.IsEnabled=$false
                $controle.ToolTip='Indisponivel no modo protegido.'
                [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($controle,$true)
            }
        }
        $global:UI.BotaoFixUpdate.Add_Click({ Resetar-WindowsUpdate })
        $global:UI.BotaoFixRede.Add_Click({ Resetar-Rede })
        $global:UI.BotaoFixWinget.Add_Click({ Instalar-Winget })
        $global:UI.BotaoResetUpdate2.Add_Click({ Resetar-WindowsUpdate })
        $global:UI.BotaoLimpezaDisco.Add_Click({ Limpeza-Disco })
        $global:UI.BotaoRecuperarIcones.Add_Click({ Recuperar-CacheIcones })
        $global:UI.BotaoOtimizarVolume.Add_Click({ Abrir-OtimizacaoVolume })
        $global:UI.BotaoAplicarAtualizacoes.Add_Click({ Clique-HistoricoAtualizacoes })
        $global:UI.BotaoAnalisarArmazenamento.Add_Click({ Clique-AnalisarArmazenamento })
        $global:UI.BotaoBuscarAtualizacoes.Add_Click({ Start-Process 'ms-settings:windowsupdate' | Out-Null })
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
        $global:UI.BotaoAtualizarProgramas.Add_Click({ Carregar-Programas -Forcar })
        Atualizar-DetalhePrograma
        Montar-PaginaAjustes
        Montar-PaginaInstalar
        Montar-PaineisLegados
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
    $global:UI.BotaoAplicarAjustes.Add_Click({ Executar-OperacaoUI -Id 'estado-local' -Acao { Clique-AplicarAjustes } })
    $global:UI.BotaoExportarPlano.Add_Click({ Clique-ExportarPlano })
    $global:UI.BotaoImportarPlano.Add_Click({ Clique-ImportarPlano })

    # pagina debloat
    $global:UI.BotaoRemoverUwp.Add_Click({ Executar-OperacaoUI -Id 'appx' -Acao { Clique-RemoverUwp } })

    # pagina desinstalar
    $global:UI.FiltroDesinstalar.Add_TextChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.CategoriaDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.OrdemDesinstalar.Add_SelectionChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.ListaProgramas.Add_SelectionChanged({ Atualizar-DetalhePrograma })
    $global:UI.BotaoDetalhesPrograma.Add_Click({ Clique-DetalhesPrograma })
    Atualizar-DetalhePrograma
    $global:UI.BotaoAtualizarProgramas.Add_Click({ Carregar-Programas -Forcar })
    $global:UI.BotaoDesinstalarProg.Add_Click({ Executar-OperacaoUI -Id 'desinstalar' -Acao { Clique-DesinstalarProg } })
    $global:UI.BotaoVarrerRastros.Add_Click({ Executar-OperacaoUI -Id 'rastros' -Acao { Clique-VarrerRastros } })
    $global:UI.BotaoMarcarRastros.Add_Click({ Marcar-Rastros $true })
    $global:UI.BotaoDesmarcarRastros.Add_Click({ Marcar-Rastros $false })
    $global:UI.BotaoApagarRastros.Add_Click({ Executar-OperacaoUI -Id 'rastros' -Acao { Clique-ApagarRastros } })

    # pagina instalar
    $global:UI.BotaoInstalarApps.Add_Click({ Executar-OperacaoUI -Id 'winget' -Acao { Clique-InstalarApps } })
    $global:UI.BotaoAtualizarTudo.Add_Click({ Executar-OperacaoUI -Id 'consulta-winget' -Acao { Atualizar-Tudo } })
    $global:UI.BotaoAtualizarSelecionados.Add_Click({ Executar-OperacaoUI -Id 'winget' -Acao { Clique-InstalarApps -Operacao upgrade } })
    $global:UI.BotaoMarcarPadroes.Add_Click({
        foreach ($cb in (Get-Checkboxes $global:UI.ListaApps)) { $cb.IsChecked = [bool]$cb.Tag.padrao }
        Log 'apps padroes marcados.'
    })

    # pagina config
    $global:UI.BotaoInstalarRecursos.Add_Click({ Executar-OperacaoUI -Id 'recurso' -Acao { Clique-InstalarRecursos } })
    $global:UI.BotaoFixUpdate.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Resetar-WindowsUpdate } })
    $global:UI.BotaoFixRede.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Resetar-Rede } })
    $global:UI.BotaoFixWinget.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Instalar-Winget } })
    $global:UI.BotaoTema.Add_Click({
        try {
            $novo=if ($global:TemaOtimizador -eq 'claro') { 'escuro' } else { 'claro' }
            Gravar-JSONAtomico -Arquivo (Join-Path $global:RaizEstado 'preferencias.json') -Objeto ([pscustomobject]@{tema=$novo})
            Avisar 'Tema salvo' ('Tema ' + $novo + ' sera usado quando reabrir o app.')
        } catch { Avisar 'Falha ao salvar tema' $_.Exception.Message }
    })

    # pagina atualizacoes
    $global:UI.BotaoAplicarAtualizacoes.Add_Click({ Clique-HistoricoAtualizacoes })
    $global:UI.BotaoFixIntegridade.Add_Click({ Executar-OperacaoUI -Id 'reparo' -Acao { Verificar-Integridade } })
    $global:UI.BotaoBuscarAtualizacoes.Add_Click({ Start-Process 'ms-settings:windowsupdate' | Out-Null })
    $global:UI.BotaoResetUpdate2.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Resetar-WindowsUpdate } })

    # pagina manutencao
    $global:UI.BotaoLimparTemp.Add_Click({ Executar-OperacaoUI -Id 'temp' -Acao { Limpar-Temporarios } })
    $global:UI.BotaoLimparDns.Add_Click({ Executar-OperacaoUI -Id 'dns' -Acao { Limpar-DNS } })
    $global:UI.BotaoSincronizarHora.Add_Click({ Executar-OperacaoUI -Id 'hora' -Acao { Sincronizar-Hora } })
    $global:UI.BotaoBackupDrivers.Add_Click({ Executar-OperacaoUI -Id 'exportar' -Acao { Clique-BackupDrivers } })
    $global:UI.BotaoAnalisarArmazenamento.Add_Click({ Clique-AnalisarArmazenamento })
    $global:UI.BotaoRecuperarIcones.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Recuperar-CacheIcones } })
    $global:UI.BotaoLimpezaDisco.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Limpeza-Disco } })
    $global:UI.BotaoVerificarDisco.Add_Click({ Executar-OperacaoUI -Id 'diagnostico-admin' -Acao { Verificar-Disco } })
    $global:UI.BotaoLimpezaDism.Add_Click({ Executar-OperacaoUI -Id 'reparo' -Acao { Manutencao-DISM } })
    $global:UI.BotaoAnalisarComponentes.Add_Click({ Executar-OperacaoUI -Id 'diagnostico-admin' -Acao { Analisar-ComponentesWindows } })
    $global:UI.BotaoDiagnosticarIntegridade.Add_Click({ Executar-OperacaoUI -Id 'diagnostico-admin' -Acao { Diagnosticar-Integridade } })
    $global:UI.BotaoConsultarEnergia.Add_Click({ Executar-OperacaoUI -Id 'diagnostico-admin' -Acao { Consultar-Energia } })
    $global:UI.BotaoOtimizarVolume.Add_Click({ Executar-OperacaoUI -Id 'nativo' -Acao { Abrir-OtimizacaoVolume } })
    $global:UI.BotaoVerificarIntegridade.Add_Click({ Executar-OperacaoUI -Id 'reparo' -Acao { Verificar-Integridade } })

    # pagina desfazer
    $global:UI.BotaoDesfazer.Add_Click({ Executar-OperacaoUI -Id 'estado-local' -Acao { Clique-Desfazer } })
    $global:UI.BotaoDesfazerUma.Add_Click({ Executar-OperacaoUI -Id 'estado-local' -Acao { Clique-Desfazer -UmaAcao } })
    $global:UI.BotaoConfirmarManual.Add_Click({ Executar-OperacaoUI -Id 'estado-local' -Acao { Clique-ConfirmarManual } })
    $global:UI.BotaoDetalhesSessao.Add_Click({ Clique-DetalhesSessao })


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
        Executar-OperacaoUI -Id 'restore' -Acao { Ocupado $true; try { [void](Criar-PontoRestauracao) } finally { Ocupado $false } }
    })

    # monta conteudo dinamico
    Montar-PaginaAjustes
    # Debloat consulta pacotes somente ao abrir a aba.
    Montar-PaginaInstalar
    Montar-PaineisLegados
    Atualizar-CapacidadesOperacoes
    Trocar-Pagina 'PaginaInicio'
}
