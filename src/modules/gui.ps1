# gui.ps1 - monta as paginas a partir dos catalogos e liga todos os botoes

# ---- criacao de controles ----

function Nova-Checkbox {
    param([string]$Texto, $Tag, [string]$Dica, [bool]$Marcado = $false)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $Texto
    $cb.Tag = $Tag
    $cb.Margin = '2,3,0,3'
    $cb.Foreground = '#e5e7eb'
    $cb.FontSize = 13
    $cb.IsChecked = $Marcado
    if (-not [string]::IsNullOrWhiteSpace($Dica)) {
        $cb.ToolTip = $Dica
    }
    return $cb
}

function Nova-Categoria {
    param([string]$Titulo)
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = $Titulo
    $gb.Foreground = '#93c5fd'
    $gb.BorderBrush = '#374151'
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

function Montar-PaginaAjustes {
    $win11 = Eh-Win11
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
        $nome = $t.nome
        if ($t.apenasManual) { $nome += ' [somente manual - cautela]' }
        [void]$grupos[$t.categoria].Content.Children.Add((Nova-Checkbox -Texto $nome -Tag $t -Dica $t.desc))
    }
}

function Montar-PaginaDebloat {
    $win11 = Eh-Win11
    $painel = $global:UI.ListaUwp
    $painel.Children.Clear()
    $grupos = @{}
    $grupoSeguroNome = 'seguros de remover (marcados)'
    $grupoCautelaNome = 'com cautela (leia as descricoes)'
    foreach ($p in $global:CatalogoUwp.pacotes) {
        if ($p.so -eq 'win11' -and -not $win11) { continue }
        if ($p.so -eq 'win10' -and $win11) { continue }
        $titulo = $grupoCautelaNome
        $marcado = $false
        if ($p.remover) { $titulo = $grupoSeguroNome; $marcado = $true }
        if (-not $grupos.ContainsKey($titulo)) {
            $grupos[$titulo] = Nova-Categoria $titulo
            [void]$painel.Children.Add($grupos[$titulo])
        }
        [void]$grupos[$titulo].Content.Children.Add((Nova-Checkbox -Texto $p.nome -Tag $p -Dica $p.desc -Marcado $marcado))
    }
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
        [void]$grupos[$a.categoria].Content.Children.Add((Nova-Checkbox -Texto $a.nome -Tag $a -Dica $a.desc -Marcado ([bool]$a.padrao)))
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
    foreach ($r in $recursos) {
        [void]$painel.Children.Add((Nova-Checkbox -Texto $r.nome -Tag $r -Dica $r.desc))
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
            $ok = ($f -eq '') -or ($nome.ToLower().Contains($f)) -or ($desc.ToLower().Contains($f))
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
        switch ($estado) {
            'aplicado' { $cb.Foreground = '#86efac'; $cb.Content = $t.nome + '  (ja aplicado)' }
            'parcial'  { $cb.Foreground = '#fde047'; $cb.Content = $t.nome + '  (parcial)' }
            default    { $cb.Foreground = '#e5e7eb'; $cb.Content = $t.nome }
        }
        Atualizar-UI
    }
    Ocupado $false
    Log ('estado verificado: {0} ajuste(s) ja aplicado(s), {1} parcial(is), {2} nao aplicado(s), {3} sem verificacao automatica.' -f $contagens['aplicado'], $contagens['parcial'], $contagens['nao'], $contagens['desconhecido'])
    Status 'estado verificado.'
}

function Verificar-EstadoUwp {
    Status 'verificando apps pre-instalados...'
    Ocupado $true
    foreach ($cb in (Get-Checkboxes $global:UI.ListaUwp)) {
        $p = $cb.Tag
        if (Appx-Instalado $p.pacote) {
            $cb.Foreground = '#e5e7eb'
            $cb.Content = $p.nome
        } else {
            $cb.Foreground = '#6b7280'
            $cb.Content = $p.nome + '  (nao instalado)'
            $cb.IsChecked = $false
        }
        Atualizar-UI
    }
    Ocupado $false
    Status 'apps verificados.'
}

# ---- navegacao ----

$global:PaginaAtual = 'PaginaInicio'

function Trocar-Pagina {
    param([string]$Nome)
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
    if ($Nome -eq 'PaginaDesfazer') { Atualizar-ListaDesfazer }
    if ($Nome -eq 'PaginaDesinstalar') {
        if ($null -eq $global:ProgramasInstalados) { Carregar-Programas }
        Atualizar-ListaProgramas
    }
    if ($Nome -eq 'PaginaAtualizacoes') {
        $atual = Tem-Atualizacoes
        $global:UI.ChkBloquearDrivers.IsChecked = ($null -ne $atual -and $null -ne $atual.ExcludeWUDriverInQualityUpdate)
        $global:UI.ChkAdiarRecursos.IsChecked = ($null -ne $atual -and $null -ne $atual.DeferFeatureUpdates)
    }
}

# ---- cliques ----

function Clique-AplicarAjustes {
    $selecionados = @(Get-Checkboxes $global:UI.ListaAjustes | Where-Object { $_.IsChecked })
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
    $nomes = ($selecionados | ForEach-Object { $_.Tag.nome }) -join ', '
    $conf = Perguntar 'Aplicar ajustes' ("Aplicar {0} ajuste(s):`n`n{1}`n`nContinuar?" -f $selecionados.Count, $nomes)
    if (-not $conf) { return }
    Status 'preparando ajustes...'
    Ocupado $true
    if ($global:UI.ChkPontoRestore.IsChecked) { [void](Criar-PontoRestauracao) }
    Iniciar-Sessao 'ajustes'
    $i = 0
    foreach ($cb in $selecionados) {
        $i++
        $t = $cb.Tag
        Status ('aplicando {0}/{1}: {2}' -f $i, $selecionados.Count, $t.nome)
        Log ('== ajuste: ' + $t.nome)
        foreach ($acao in $t.acoes) {
            Executar-Acao $acao $t.nome
            Atualizar-UI
        }
    }
    $arq = Salvar-Sessao
    Ocupado $false
    if ($global:ErrosSessao -gt 0) {
        Log ('ajustes concluidos com ' + $global:ErrosSessao + ' erro(s); veja as linhas [ERRO] acima.') -Erro
    } else {
        Log ('todos os ' + $selecionados.Count + ' ajustes foram aplicados sem erros.')
    }
    if ($arq) { Log ('salvei o journal desta sessao para desfazer depois: ' + (Split-Path -Leaf $arq)) }
    Status 'ajustes aplicados. alguns exigem relogar no windows.'
    if (Perguntar 'Explorador de Arquivos' 'Reiniciar o Explorador agora para aplicar as mudancas visuais? (aquivos abertos em janelas do explorer fecham)') {
        Reiniciar-Explorer
    }
}

function Clique-RemoverUwp {
    $selecionados = @(Get-Checkboxes $global:UI.ListaUwp | Where-Object { $_.IsChecked })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os aplicativos que quer remover.'
        return
    }
    $nomes = ($selecionados | ForEach-Object { $_.Tag.nome }) -join ', '
    $conf = Perguntar 'Remover aplicativos' ("Remover {0} aplicativo(s) pre-instalado(s):`n`n{1}`n`nIsso remove da Store; da para reinstalar depois. Continuar?" -f $selecionados.Count, $nomes)
    if (-not $conf) { return }
    Status 'removendo aplicativos...'
    Ocupado $true
    if ($global:UI.ChkPontoRestoreUwp.IsChecked) { [void](Criar-PontoRestauracao) }
    Iniciar-Sessao 'debloat'
    $i = 0
    foreach ($cb in $selecionados) {
        $i++
        $p = $cb.Tag
        Status ('removendo {0}/{1}: {2}' -f $i, $selecionados.Count, $p.nome)
        Executar-Acao ([pscustomobject]@{ tipo = 'appx'; pacote = $p.pacote }) $p.nome
        Atualizar-UI
    }
    $arq = Salvar-Sessao
    Ocupado $false
    Log ('debloat concluido' + $(if ($arq) { ' - journal: ' + (Split-Path -Leaf $arq) } else { ' (nada foi removido)' }))
    Status 'aplicativos removidos. relogar pode ser necessario.'
}

function Clique-InstalarApps {
    $selecionados = @(Get-Checkboxes $global:UI.ListaApps | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    Instalar-Aplicativos -Selecionados $selecionados
}

function Clique-InstalarRecursos {
    $selecionados = @(Get-Checkboxes $global:UI.ListaRecursos | Where-Object { $_.IsChecked })
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque os recursos do Windows que quer habilitar.'
        return
    }
    $conf = Perguntar 'Habilitar recursos' ('Habilitar {0} recurso(s) do Windows? Alguns pedem reinicializacao e internet.' -f $selecionados.Count)
    if (-not $conf) { return }
    Status 'habilitando recursos...'
    Ocupado $true
    Iniciar-Sessao 'recursos'
    foreach ($cb in $selecionados) {
        $r = $cb.Tag
        Executar-Acao ([pscustomobject]@{ tipo = 'recurso'; nome = $r.feat; ativar = $true }) $r.nome
        Atualizar-UI
    }
    $arq = Salvar-Sessao
    Ocupado $false
    Log ('recursos habilitados. reinicie o windows se algum pedir.' + $(if ($arq) { ' - journal: ' + (Split-Path -Leaf $arq) } else { '' }))
    Status 'recursos habilitados.'
}

function Clique-Preset {
    param([string]$Nivel)
    $cbs = Get-Checkboxes $global:UI.ListaAjustes
    try {
        $ids = @(Selecionar-TweaksPreset -Nivel $Nivel -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11) | ForEach-Object { $_.id })
    } catch {
        Avisar 'Preset invalido' $_.Exception.Message
        return
    }
    foreach ($cb in $cbs) { $cb.IsChecked = ($ids -contains $cb.Tag.id) }
    Log ('preset marcado: ' + $Nivel + ' (' + @(($cbs | Where-Object { $_.IsChecked })).Count + ' ajustes). confira a lista e clique em aplicar.')
}

# exporta os ajustes marcados num .json (pra repetir depois ou levar pra outro pc)
function Clique-ExportarPlano {
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
        $cb.IsChecked = ($ids -contains [string]$cb.Tag.id)
        if ($cb.IsChecked) { $marcados++ }
    }
    Log ('plano importado: marquei ' + $marcados + ' ajuste(s) na lista. confira e clique em aplicar (ou em simular primeiro).')
    Status ('plano importado: ' + $marcados + ' ajuste(s) marcados.')
}

function Clique-Desfazer {
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
    $conf = Perguntar 'Desfazer sessao' ('Desfazer todas as acoes da sessao selecionada?' + "`n" + $lb.SelectedItem)
    if (-not $conf) { return }
    Status 'revertendo sessao...'
    Ocupado $true
    $global:Janela.IsEnabled = $false
    try {
        $resultado = Reverter-Sessao -Arquivo $caminho
    } finally {
        $global:Janela.IsEnabled = $true
        Ocupado $false
    }
    Atualizar-ListaDesfazer
    if ($resultado -eq $true) {
        Status 'sessao revertida.'
    } else {
        Status 'reversao incompleta - consulte o log.'
        Cor-Status 'vermelho'
        Avisar 'Reversao incompleta' 'O journal foi preservado. Consulte o log e revise a acao incerta antes de continuar.'
    }
}

# ---- ligacao geral (chamada pelo script principal) ----

# Consulta sob demanda; nenhuma alteracao automatica em servicos ou tarefas.
function Clique-InventarioLocal {
    try {
        Status 'coletando inventario local...'
        $global:Janela.IsEnabled = $false
        try { $dados = Obter-InventarioLocal }
        finally { $global:Janela.IsEnabled = $true }
        $dlg = New-Object System.Windows.Window
        $dlg.Title = 'Inventario local - OtimizadorPC'
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
        [void]$barra.Children.Add($salvar)
        foreach ($atalho in @(
            @{ nome='Inicializacao'; comando='taskmgr.exe' },
            @{ nome='Servicos'; comando='services.msc' },
            @{ nome='Tarefas'; comando='taskschd.msc' }
        )) {
            $botao = New-Object System.Windows.Controls.Button
            $botao.Content = $atalho.nome
            $botao.Tag = $atalho.comando
            $botao.Padding = '10,6'
            $botao.Margin = '0,0,8,8'
            $botao.Add_Click({
                try { Start-Process -FilePath ([string]$this.Tag) -ErrorAction Stop | Out-Null }
                catch { Avisar 'Falha ao abrir ferramenta' $_.Exception.Message }
            })
            [void]$barra.Children.Add($botao)
        }
        $caixa = New-Object System.Windows.Controls.TextBox
        $caixa.IsReadOnly = $true
        $caixa.AcceptsReturn = $true
        $caixa.VerticalScrollBarVisibility = 'Auto'
        $caixa.HorizontalScrollBarVisibility = 'Auto'
        $caixa.FontFamily = 'Consolas'
        $linhas = @('Inventario local (somente leitura). Revise antes de compartilhar.', '')
        foreach ($grupo in @('inicializacao','servicos','tarefas','discos','rede')) {
            $linhas += ('--- {0} ({1}) ---' -f $grupo, @($dados.$grupo).Count)
            $linhas += (($dados.$grupo | Format-Table -AutoSize | Out-String -Width 220).Trim())
            $linhas += ''
        }
        $linhas += @($dados.avisos)
        $caixa.Text = ($linhas -join [Environment]::NewLine)
        [void]$painel.Children.Add($caixa)
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
            $drivers = @(Export-WindowsDriver -Online -Destination $pasta -ErrorAction Stop)
            Log ('exportacao de drivers: ' + $pasta + ' (' + $drivers.Count + ' pacote(s) informado(s)).')
            Status 'exportacao de drivers concluida.'
        } finally {
            $global:Janela.IsEnabled = $true
            Ocupado $false
        }
        Avisar 'Backup concluido' ('Confira os arquivos em: ' + $pasta + '. O backup nao inclui todos os drivers nativos do Windows.')
    } catch {
        Log ('falha no backup de drivers: ' + $_.Exception.Message) -Erro
        Status 'backup de drivers incompleto.'
        Avisar 'Falha no backup' 'Confira o log. Arquivos parcialmente exportados foram preservados.'
    }
}

function Ligar-Tudo {

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
    $global:UI.BotaoAplicarAjustes.Add_Click({ Clique-AplicarAjustes })
    $global:UI.BotaoExportarPlano.Add_Click({ Clique-ExportarPlano })
    $global:UI.BotaoImportarPlano.Add_Click({ Clique-ImportarPlano })

    # pagina debloat
    $global:UI.BotaoRemoverUwp.Add_Click({ Clique-RemoverUwp })

    # pagina desinstalar
    $global:UI.FiltroDesinstalar.Add_TextChanged({ if ($null -ne $global:ProgramasInstalados) { Atualizar-ListaProgramas } })
    $global:UI.BotaoAtualizarProgramas.Add_Click({ Carregar-Programas; Atualizar-ListaProgramas })
    $global:UI.BotaoDesinstalarProg.Add_Click({ Clique-DesinstalarProg })
    $global:UI.BotaoVarrerRastros.Add_Click({ Clique-VarrerRastros })
    $global:UI.BotaoMarcarRastros.Add_Click({ $global:UI.ListaRastros.SelectAll() })
    $global:UI.BotaoApagarRastros.Add_Click({ Clique-ApagarRastros })

    # pagina instalar
    $global:UI.BotaoInstalarApps.Add_Click({ Clique-InstalarApps })
    $global:UI.BotaoAtualizarTudo.Add_Click({ Atualizar-Tudo })
    $global:UI.BotaoMarcarPadroes.Add_Click({
        foreach ($cb in (Get-Checkboxes $global:UI.ListaApps)) { $cb.IsChecked = [bool]$cb.Tag.padrao }
        Log 'apps padroes marcados.'
    })

    # pagina config
    $global:UI.BotaoInstalarRecursos.Add_Click({ Clique-InstalarRecursos })
    $global:UI.BotaoFixUpdate.Add_Click({ Resetar-WindowsUpdate })
    $global:UI.BotaoFixRede.Add_Click({ Resetar-Rede })
    $global:UI.BotaoFixWinget.Add_Click({ Instalar-Winget })

    # pagina atualizacoes
    $global:UI.BotaoAplicarAtualizacoes.Add_Click({
        Configurar-Atualizacoes -BloquearDrivers ([bool]$global:UI.ChkBloquearDrivers.IsChecked) -AdiarRecursos ([bool]$global:UI.ChkAdiarRecursos.IsChecked)
    })
    $global:UI.BotaoBuscarAtualizacoes.Add_Click({ Start-Process 'ms-settings:windowsupdate' | Out-Null })
    $global:UI.BotaoResetUpdate2.Add_Click({ Resetar-WindowsUpdate })

    # pagina manutencao
    $global:UI.BotaoLimparTemp.Add_Click({ Limpar-Temporarios })
    $global:UI.BotaoLimparDns.Add_Click({ Limpar-DNS; Status 'dns limpo.' })
    $global:UI.BotaoSincronizarHora.Add_Click({ Sincronizar-Hora })
    $global:UI.BotaoBackupDrivers.Add_Click({ Clique-BackupDrivers })
    $global:UI.BotaoRecuperarIcones.Add_Click({ Recuperar-CacheIcones })
    $global:UI.BotaoLimpezaDisco.Add_Click({ Limpeza-Disco })
    $global:UI.BotaoVerificarDisco.Add_Click({ Verificar-Disco })
    $global:UI.BotaoLimpezaDism.Add_Click({ Manutencao-DISM })
    $global:UI.BotaoVerificarIntegridade.Add_Click({ Verificar-Integridade })

    # pagina desfazer
    $global:UI.BotaoDesfazer.Add_Click({ Clique-Desfazer })
    $global:UI.BotaoAtualizarListaSessoes.Add_Click({ Atualizar-ListaDesfazer; Log 'lista de sessoes atualizada.' })

    # pagina inicio
    $global:UI.BotaoInventario.Add_Click({ Clique-InventarioLocal })
    $global:UI.BotaoCriarRestore.Add_Click({
        Ocupado $true
        [void](Criar-PontoRestauracao)
        Ocupado $false
        Preencher-PaginaInicio
    })

    # monta conteudo dinamico
    Montar-PaginaAjustes
    Montar-PaginaDebloat
    Montar-PaginaInstalar
    Montar-PaginaRecursos
    Montar-PaineisLegados
    Preencher-PaginaInicio
    Trocar-Pagina 'PaginaInicio'
}
