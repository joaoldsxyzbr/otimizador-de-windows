# desinstalador.ps1 - aba Desinstalar: lista programas instalados, desinstala e varre os rastros que sobram
# rastros apagados vao para uma pasta de quarantena (arquivos movidos, registro exportado em .reg);
# a aba Desfazer tudo restaura a partir do journal da sessao

$global:PastaQuarantena = Join-Path $env:ProgramData 'otimizadorpc\quarantena'

# ---- listagem dos programas instalados ----

function Carregar-Programas {
    Status 'procurando programas instalados...'
    Ocupado $true
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $vistos = @{}
    $lista = New-Object System.Collections.ArrayList
    foreach ($c in $chaves) {
        foreach ($p in @(Get-ItemProperty -Path $c -ErrorAction SilentlyContinue)) {
            $nome = [string]$p.DisplayName
            $comando = [string]$p.UninstallString
            if ([string]::IsNullOrWhiteSpace($nome)) { continue }
            if ([string]::IsNullOrWhiteSpace($comando)) { continue }
            if ($p.SystemComponent -eq 1) { continue }
            if ($nome -match '^(KB[0-9]+|(Security |Critical )?Update for|Hotfix|Language (Pack|Interface)|Windows Driver Package)') { continue }
            if ($nome -like 'Microsoft Edge*') { continue }
            $id = $nome.ToLower()
            if ($vistos.ContainsKey($id)) { continue }
            $vistos[$id] = $true
            [void]$lista.Add([pscustomobject]@{
                nome        = $nome
                versao      = [string]$p.DisplayVersion
                editor      = [string]$p.Publisher
                comando     = $comando
                quiet       = [string]$p.QuietUninstallString
                chavePs     = [string]$p.PSPath
                instaladoEm = [string]$p.InstallLocation
            })
        }
    }
    $global:ProgramasInstalados = @($lista | Sort-Object -Property nome)
    $global:ProgramasExibidos = @()
    Ocupado $false
    Log ('aba desinstalar: {0} programa(s) encontrados no registro (updates do windows e edge ficam de fora).' -f $global:ProgramasInstalados.Count)
    Status ('{0} programa(s) na lista.' -f $global:ProgramasInstalados.Count)
}

function Atualizar-ListaProgramas {
    $lb = $global:UI.ListaProgramas
    $filtro = ''
    if ($null -ne $global:UI.FiltroDesinstalar.Text) { $filtro = $global:UI.FiltroDesinstalar.Text.Trim().ToLower() }
    $lb.Items.Clear()
    $global:ProgramasExibidos = @()
    if ($null -eq $global:ProgramasInstalados) { return }
    foreach ($pr in $global:ProgramasInstalados) {
        $versao = ''
        if (-not [string]::IsNullOrWhiteSpace($pr.versao)) { $versao = ' v' + $pr.versao }
        $linha = ('{0}  |  {1}{2}' -f $pr.nome, $pr.editor, $versao)
        if ($filtro -ne '' -and -not $linha.ToLower().Contains($filtro)) { continue }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $linha
        [void]$lb.Items.Add($item)
        $global:ProgramasExibidos += $pr
    }
    if ($lb.Items.Count -eq 0) {
        $vazio = New-Object System.Windows.Controls.ListBoxItem
        $vazio.Content = '(nenhum programa casa com esse filtro)'
        $vazio.IsEnabled = $false
        [void]$lb.Items.Add($vazio)
    }
}

# devolve os objetos por tras das linhas selecionadas de uma listbox
function Obter-Selecionados {
    param($ListBox, [object[]]$Exibidos)
    $res = @()
    foreach ($linha in $ListBox.SelectedItems) {
        $idx = $ListBox.Items.IndexOf($linha)
        if ($idx -ge 0 -and $idx -lt $Exibidos.Count) { $res += $Exibidos[$idx] }
    }
    return @($res)
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

function Desinstalar-Programa {
    param($Prog)
    $nome = [string]$Prog.nome
    $linha = [string]$Prog.quiet
    if ([string]::IsNullOrWhiteSpace($linha)) { $linha = [string]$Prog.comando }
    $linha = $linha.Trim()
    Log ('desinstalando: ' + $nome)

    # sem comando de desinstalacao no registro? tenta o winget antes de desistir
    if ([string]::IsNullOrWhiteSpace($linha)) {
        Log ('sem linha de desinstalacao no registro; tentando winget pelo nome: ' + $nome)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $argNome = '--name="' + $nome + '"'
            $proc = Start-Process -FilePath 'winget.exe' -ArgumentList @('uninstall', $argNome, '--silent', '--accept-source-agreements', '--disable-interactivity') -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -eq 0) {
                Log ('winget desinstalou com sucesso: ' + $nome)
                return
            }
            Log ('winget nao conseguiu (codigo de saida ' + $proc.ExitCode + ')')
        } else {
            Log ('winget nao encontrado no sistema; sem linha de desinstalacao para rodar.')
        }
        return
    }

    # pacote msi: refaz na mao em modo silencioso
    if ($linha -match 'msiexec') {
        $m = [regex]::Match($linha, '(\{[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\})')
        if ($m.Success) {
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $m.Groups[1].Value, '/qn', '/norestart') -Wait -PassThru
            Log ('msi finalizado, codigo de saida: ' + $proc.ExitCode + ' (0 = ok, 3010 = ok com reinicio pendente)')
            return
        }
        Log ('msiexec sem guid reconhecido; tentando a linha original: ' + $linha)
    }

    $an = Analisar-LinhaComando $linha
    if ($null -eq $an -or -not (Test-Path $an.exe)) {
        Log ('linha de desinstalacao nao padrao, executando via cmd: ' + $linha)
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $linha) -Wait -PassThru
        Log ('desinstalador finalizado, codigo de saida: ' + $proc.ExitCode)
        return
    }

    $argsLista = @()
    if ($an.args -ne '') { $argsLista += $an.args }
    $folha = (Split-Path -Leaf $an.exe).ToLower()
    $modo = 'o desinstalador pode abrir janelas proprias; siga as telas dele'
    if ($folha -match '^unins\d*\.exe$') {
        $argsLista += @('/VERYSILENT', '/NORESTART')
        $modo = 'inno setup: silencioso'
    } elseif ($folha -match '^(uninstall|uninst)[a-z0-9]*\.exe$') {
        $argsLista += '/S'
        $modo = 'nsis: silencioso na maioria dos casos'
    }
    Log ('executando: ' + $an.exe + ' ' + ($argsLista -join ' ') + '  (' + $modo + ')')
    $proc = Start-Process -FilePath $an.exe -ArgumentList $argsLista -Wait -PassThru
    Log ('desinstalador finalizado, codigo de saida: ' + $proc.ExitCode)
}

# apps que pedem confirmacao extra antes de desinstalar: drivers, runtimes
# e seguranca. remover errado quebra video, audio, jogos ou a protecao do pc.
# devolve o motivo quando o nome parece arriscado, ou $null quando e seguro.
function Eh-AppArriscado {
    param([string]$Nome)
    $n = $Nome.ToLower()
    $padroes = @(
        @('visual c++',      'runtime exigido por jogos e programas'),
        @('redistributable', 'runtime exigido por jogos e programas'),
        @('directx',         'componente de video/jogos do windows'),
        @('xna',             'runtime de jogos'),
        @('physx',           'fisica de jogos'),
        @('openal',          'audio de jogos'),
        @('.net',            'plataforma usada por varios programas'),
        @('driver',          'driver de hardware'),
        @('nvidia',          'driver de video'),
        @('geforce',         'driver de video'),
        @('radeon',          'driver de video'),
        @('realtek',         'driver de audio/rede'),
        @('conexant',        'driver de audio'),
        @('graphics driver', 'driver de video'),
        @('antivirus',       'protecao do pc'),
        @('internet security', 'protecao do pc'),
        @('firewall',        'protecao do pc'),
        @('mcafee',          'antivirus'),
        @('norton',          'antivirus'),
        @('kaspersky',       'antivirus'),
        @('avast',           'antivirus'),
        @('avg antivirus',   'antivirus'),
        @('windows defender', 'antivirus do proprio windows')
    )
    foreach ($p in $padroes) {
        if ($n.Contains($p[0])) { return ('{0} -> {1}' -f $Nome, $p[1]) }
    }
    return $null
}

function Clique-DesinstalarProg {
    $selecionados = @(Obter-Selecionados $global:UI.ListaProgramas $global:ProgramasExibidos)
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Escolha na lista o(s) programa(s) que quer desinstalar.'
        return
    }
    $nomes = ($selecionados | ForEach-Object { $_.nome }) -join "`n"
    $msg = ("Desinstalar {0} programa(s):`n`n{1}`n`nAlguns desinstaladores abrem janelas proprias; siga as telas se aparecerem. Continuar?" -f $selecionados.Count, $nomes)
    if (-not (Perguntar 'Desinstalar programas' $msg)) { return }

    # confirmacao extra pra driver, runtime ou seguranca (estilo win11debloat)
    $arriscados = @($selecionados | ForEach-Object { Eh-AppArriscado $_.nome } | Where-Object { $_ })
    if ($arriscados.Count -gt 0) {
        $msgRisco = ("ATENCAO: estes itens parecem criticos:`n`n{0}`n`nDesinstalar pode quebrar video, audio, jogos ou a protecao do pc. Se nao tiver certeza, cancele e pergunte antes. Confirmar mesmo assim?" -f ($arriscados -join "`n"))
        if (-not (Perguntar 'Programas de risco' $msgRisco)) { return }
        Log ('confirmado com aviso: ' + $arriscados.Count + ' programa(s) de risco na lista.')
    }

    Status 'desinstalando...'
    Ocupado $true
    if ($global:UI.ChkPontoRestoreDesinstalar.IsChecked) { [void](Criar-PontoRestauracao) }
    Iniciar-Sessao 'desinstalar'
    $i = 0
    foreach ($pr in $selecionados) {
        $i++
        Status ('desinstalando {0}/{1}: {2}' -f $i, $selecionados.Count, $pr.nome)
        Registrar-Jornal ([pscustomobject]@{ tipo = 'desinstalado-app'; nome = $pr.nome })
        try {
            Desinstalar-Programa $pr
        } catch {
            Log ('falha ao desinstalar {0}: {1}' -f $pr.nome, $_.Exception.Message) -Erro
        }
        Atualizar-UI
    }
    $arq = Salvar-Sessao
    Ocupado $false
    $resumo = 'desinstalacao concluida.'
    if ($arq) { $resumo = $resumo + ' journal: ' + (Split-Path -Leaf $arq) }
    Log $resumo
    Status 'desinstalacao concluida.'
    Carregar-Programas
    Atualizar-ListaProgramas
    foreach ($pr in $selecionados) {
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

function Medir-Pasta {
    param([string]$Caminho)
    try {
        $m = Get-ChildItem -Path $Caminho -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        return ('{0} arquivo(s), {1} mb' -f $m.Count, [math]::Round($m.Sum / 1MB, 1))
    } catch { return 'tamanho desconhecido' }
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
        if (-not [string]::IsNullOrWhiteSpace($Prog.chavePs) -and (Test-Path $Prog.chavePs)) {
            [void]$achados.Add([pscustomobject]@{ tipo = 'chave'; caminho = $Prog.chavePs; extra = 'entrada de desinstalacao que sobrou' })
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
            if (Bater-Nome $d.Name $alvoBase $compacto) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'pasta'; caminho = $d.FullName; extra = (Medir-Pasta $d.FullName) })
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
            if (-not (Bater-Nome $f.Name $alvoBase $compacto)) { continue }
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
            if (Bater-Nome $k.PSChildName $alvoBase $compacto) {
                [void]$achados.Add([pscustomobject]@{ tipo = 'chave'; caminho = $k.PSPath; extra = 'chave de registro' })
            }
        }
        Atualizar-UI
    }

    # 5. servicos que apontam pro programa (vao ficar orfaos)
    try {
        $servicos = @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | Where-Object { Bater-Nome ([string]$_.PathName) $alvoBase $compacto })
        foreach ($s in $servicos) {
            if ([string]::IsNullOrWhiteSpace([string]$s.Name)) { continue }
            [void]$achados.Add([pscustomobject]@{ tipo = 'servico'; caminho = [string]$s.Name; extra = ('servico orfao: ' + [string]$s.State + ' - ' + [string]$s.PathName) })
        }
    } catch { }
    Atualizar-UI

    # 6. tarefas agendadas que executam o programa
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            $exe = ''
            $casou = $false
            foreach ($a in @($t.Actions)) {
                if ($null -eq $a) { continue }
                if (Bater-Nome ([string]$a.Execute) $alvoBase $compacto) { $casou = $true }
                if (Bater-Nome ([string]$a.Arguments) $alvoBase $compacto) { $casou = $true }
                if ($exe -eq '' -and -not [string]::IsNullOrWhiteSpace([string]$a.Execute)) { $exe = [string]$a.Execute }
            }
            if (-not $casou) { continue }
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
                if (Bater-Nome $prog $alvoBase $compacto) {
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
            if ((Bater-Nome $vn $alvoBase $compacto) -or (Bater-Nome $dado $alvoBase $compacto)) {
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
            if (Bater-Nome $ent $alvoBase $compacto) {
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
    return @($finais)
}

function Executar-Varredura {
    param($Prog)
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
        $item.Content = ('[{0}]  {1}{2}' -f $r.tipo, $mostro, $extra)
        [void]$lb.Items.Add($item)
    }
    if ($rastros.Count -eq 0) {
        $global:UI.RotuloRastros.Text = ('varredura de "{0}": nenhum rastro encontrado (limpo!).' -f $Prog.nome)
        Log ('varredura de "' + $Prog.nome + '": nenhum rastro encontrado.')
        Status 'nenhum rastro encontrado.'
    } else {
        $global:UI.RotuloRastros.Text = ('rastros de "{0}": {1} achado(s). marquei tudo; desmarque o que quiser manter e clique em apagar.' -f $Prog.nome, $rastros.Count)
        $lb.SelectAll()
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

    # servico orfao: para e desativa (nunca apaga; desfazer restaura tipo e estado)
    if ($Rastro.tipo -eq 'servico') {
        $svc = Get-Service -Name $Rastro.caminho -ErrorAction Stop
        $estadoAnt = [string]$svc.Status
        $tipoAnt = [string]$svc.StartType
        Registrar-Jornal ([pscustomobject]@{ tipo = 'servico'; nome = $Rastro.caminho; tipoAnterior = $tipoAnt; estadoAnterior = $estadoAnt; contexto = 'varredura de rastros' })
        if ($estadoAnt -eq 'Running') { Stop-Service -Name $Rastro.caminho -ErrorAction Stop }
        Set-Service -Name $Rastro.caminho -StartupType Disabled -ErrorAction Stop
        Log ('servico orfao parado e desativado (desfazer restaura): ' + $Rastro.caminho)
        return
    }

    # tarefa agendada: so desativa (nunca apaga; desfazer reativa)
    if ($Rastro.tipo -eq 'tarefa') {
        $t = Get-ScheduledTask -TaskPath $Rastro.tarefaPath -TaskName $Rastro.tarefaNome -ErrorAction Stop
        $estadoAnt = [string]$t.State
        Registrar-Jornal ([pscustomobject]@{ tipo = 'tarefa'; tarefaPath = $Rastro.tarefaPath; tarefaNome = $Rastro.tarefaNome; estadoAnterior = $estadoAnt })
        Disable-ScheduledTask -TaskPath $Rastro.tarefaPath -TaskName $Rastro.tarefaNome -ErrorAction Stop | Out-Null
        Log ('tarefa agendada desativada (desfazer reativa): ' + $Rastro.caminho)
        return
    }

    # Desativa a regra local pelo ID; preserva todos os filtros e propriedades.
    if ($Rastro.tipo -eq 'firewall') {
        $regras = @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Rastro.caminho })
        foreach ($regra in $regras) {
            $app = $regra | Get-NetFirewallApplicationFilter -ErrorAction Stop
            if ([string]$app.Program -ne $Rastro.programa) { continue }
            if ([string]$regra.Enabled -ne 'True') { continue }
            # Nao desative bloqueios: isso poderia enfraquecer a protecao.
            if ([string]$regra.Action -ne 'Allow') { continue }
            Registrar-Jornal ([pscustomobject]@{ tipo = 'firewall-estado'; nome = [string]$regra.Name; ativada = [string]$regra.Enabled })
            $regra | Disable-NetFirewallRule -ErrorAction Stop | Out-Null
            Log ('regra local de permissao desativada: ' + $regra.DisplayName)
        }
        return
    }

    # Run: preserva somente o valor removido, nao sobrescreve os outros.
    if ($Rastro.tipo -eq 'run') {
        $leitura = Ler-ValorRegistro -CaminhoPS $Rastro.chave -Nome $Rastro.valor
        if (-not $leitura.existia) { Log ('ja sumiu: ' + $Rastro.caminho); return }
        Registrar-Jornal ([pscustomobject]@{
            tipo = 'registro'; caminho = $Rastro.chave; nome = $Rastro.valor
            existia = $true; tipoAnterior = $leitura.tipo
            valorAnterior = (ConvertTo-Json -InputObject $leitura.valor -Compress)
            valorAnteriorEstruturado = [pscustomobject]@{ valor = $leitura.valor }
        })
        Remove-ItemProperty -LiteralPath $Rastro.chave -Name $Rastro.valor -ErrorAction Stop
        Log ('entrada de inicializacao removida com journal: ' + $Rastro.caminho)
        return
    }

    # entrada do PATH: tira so a entrada morta, mantendo o resto e o tipo do valor
    if ($Rastro.tipo -eq 'path') {
        $bruto = Obter-PathBruto $Rastro.escopo
        if ($null -eq $bruto -or $null -eq $bruto.valor) { Log ('nao consegui ler o PATH ' + $Rastro.escopo); return }
        $lista = @($bruto.valor -split ';')
        if ($lista -notcontains $Rastro.entrada) { Log ('ja saiu do PATH: ' + $Rastro.entrada); return }
        Registrar-Jornal ([pscustomobject]@{ tipo = 'path-entrada'; escopo = $Rastro.escopo; entrada = $Rastro.entrada; valorAnterior = $bruto.valor })
        $nova = @(($bruto.valor -split ';') | Where-Object { $_ -ne $Rastro.entrada }) -join ';'
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
        $nativa = ($Rastro.caminho -split '::')[-1]
        if (-not (Test-Path $Rastro.caminho)) { Log ('ja sumiu: ' + $nativa); return }
        $folha = ($nativa -replace '\\', '_')
        $folha = ($folha -replace '[^a-zA-Z0-9_.{}-]', '')
        if ($folha.Length -gt 70) { $folha = $folha.Substring($folha.Length - 70) }
        $arqReg = Join-Path $PastaSessao ('{0:00}_registro_{1}.reg' -f $Num, $folha)
        reg.exe export $nativa $arqReg /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $arqReg -PathType Leaf)) { throw 'Backup do registro falhou; chave preservada.' }
        Registrar-Jornal ([pscustomobject]@{ tipo = 'quarantena-registro'; chave = $nativa; arquivoReg = $arqReg })
        Remove-Item -LiteralPath $Rastro.caminho -Recurse -Force -ErrorAction Stop
        Log ('chave apagada (backup .reg na quarantena): ' + $nativa)
    } else {
        if (-not (Test-Path $Rastro.caminho)) { Log ('ja sumiu: ' + $Rastro.caminho); return }
        $folha = Split-Path -Leaf $Rastro.caminho
        $destino = Join-Path $PastaSessao ('{0:00}_{1}' -f $Num, $folha)
        if (Test-Path -LiteralPath $destino) { throw 'Destino da quarentena ja existe.' }
        Registrar-Jornal ([pscustomobject]@{ tipo = 'quarantena-arquivo'; origem = $Rastro.caminho; destino = $destino })
        Move-Item -LiteralPath $Rastro.caminho -Destination $destino -ErrorAction Stop
        Log ('rastro movido pra quarantena: ' + $Rastro.caminho)
    }
}

function Clique-ApagarRastros {
    $lb = $global:UI.ListaRastros
    $selecionados = @(Obter-Selecionados $lb $global:RastrosExibidos)
    if ($selecionados.Count -eq 0) {
        Avisar 'Nada selecionado' 'Marque na lista de rastros o que quer apagar (ou use "marcar todos").'
        return
    }
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
    $msg = $msg + ("`n`n" + $resumo + "`n`nArquivos e chaves selecionados recebem journal antes da alteracao; servicos, tarefas e regras locais de permissao podem ser desativados. A recuperacao pode exigir revisao manual. Continuar?")
    if (-not (Perguntar 'Apagar rastros' $msg)) { return }

    if (-not (Test-Path $global:PastaQuarantena)) { New-Item -Path $global:PastaQuarantena -ItemType Directory -Force | Out-Null }
    $pastaSessao = Join-Path $global:PastaQuarantena ((Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,12))
    New-Item -Path $pastaSessao -ItemType Directory -Force | Out-Null

    Status 'limpando rastros...'
    Ocupado $true
    Iniciar-Sessao 'limpar-rastros'
    $apagados = 0
    $i = 0
    foreach ($r in $selecionados) {
        $i++
        Status ('limpando {0}/{1}...' -f $i, $selecionados.Count)
        try {
            Apagar-Rastro $r $pastaSessao $i
            $apagados++
        } catch {
            Log ('falha ao apagar {0}: {1}' -f $r.caminho, $_.Exception.Message) -Erro
        }
        Atualizar-UI
    }
    $arq = Salvar-Sessao
    Ocupado $false
    $res = ('limpeza: {0} rastro(s) processado(s) sem excecao; consulte o log para confirmar as alteracoes.' -f $apagados)
    if ($arq) { $res = $res + ' journal: ' + (Split-Path -Leaf $arq) }
    Log $res
    if ($global:ErrosSessao -gt 0) { Status 'limpeza com falhas; consulte o log.' } else { Status 'limpeza processada; confira o log.' }
    if (Perguntar 'Conferir' 'Varrer de novo para conferir se sobrou algo?') {
        if ($null -ne $global:ProgVarredura) { Executar-Varredura $global:ProgVarredura }
    } else {
        $lb.Items.Clear()
        $global:RastrosExibidos = @()
        $global:UI.RotuloRastros.Text = 'rastros: selecione um programa e clique em varrer.'
    }
}
