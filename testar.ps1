# ============================================================
#  testar.ps1 - bateria de testes offline do otimizadorpc
#  valida catalogos, xaml, controles, funcoes e encoding sem abrir a janela
#  rodar no terminal:  powershell -ExecutionPolicy Bypass -File .\testar.ps1
#  tudo verde = pronto pra usar; cada falha aponta arquivo e campo
# ============================================================

$raiz = $PSScriptRoot
$global:Ok = 0
$global:Erros = 0

function Passou {
    param([string]$Nome)
    $global:Ok++
    Write-Host ('  [ok]     ' + $Nome) -ForegroundColor Green
}

function Falhou {
    param([string]$Nome, [string]$Detalhe)
    $global:Erros++
    Write-Host ('  [falhou] ' + $Nome) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detalhe)) {
        Write-Host ('           ' + $Detalhe) -ForegroundColor DarkYellow
    }
}

function Secao {
    param([string]$Titulo)
    Write-Host ''
    Write-Host ('-- ' + $Titulo + ' --') -ForegroundColor Cyan
}

# ---- 1. arquivos esperados ----
Secao 'arquivos'
$arquivos = @(
    'rodar-como-admin.bat', 'leia-me.md', 'testar.ps1', 'otimizadorpc.ps1', 'montar-portatil.ps1',
    'src\ui\principal.xaml',
    'src\modules\comum.ps1', 'src\modules\motor.ps1', 'src\modules\consertos.ps1',
    'src\modules\desinstalador.ps1', 'src\modules\sistema.ps1', 'src\modules\gui.ps1',
    'data\tweaks.json', 'data\aplicativos.json', 'data\uwp.json'
)
$faltando = @()
foreach ($a in $arquivos) {
    if (-not (Test-Path (Join-Path $raiz $a))) { $faltando += $a }
}
if ($faltando.Count -eq 0) { Passou ('os ' + $arquivos.Count + ' arquivos esperados existem') }
else { Falhou 'arquivos esperados' ('faltando: ' + ($faltando -join ', ')) }

# ---- 2. encoding: todo .ps1 tem que ser ascii puro (powershell 5.1) ----
Secao 'encoding dos scripts (powershell 5.1)'
$scripts = @(Get-ChildItem -Path (Join-Path $raiz 'src') -Recurse -Filter '*.ps1')
$scripts += @(Get-Item (Join-Path $raiz 'otimizadorpc.ps1'))
$scripts += @(Get-Item (Join-Path $raiz 'testar.ps1'))
foreach ($f in $scripts) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $tem = $false
    foreach ($b in $bytes) { if ($b -gt 127) { $tem = $true; break } }
    if ($tem) { Falhou ('ascii puro: ' + $f.Name) 'byte fora do ascii (mojibake no powershell 5.1); ache e tire o acento/caractere especial' }
    else { Passou ('ascii puro: ' + $f.Name) }
}

# ---- sintaxe PowerShell de todos os scripts fonte ----
Secao 'sintaxe powershell'
foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notlike '*\dist\*' })) {
    $errosParse = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errosParse)
    if (@($errosParse).Count -eq 0) { Passou ('sintaxe: ' + $f.Name) }
    else { Falhou ('sintaxe: ' + $f.Name) (($errosParse | ForEach-Object { $_.Message }) -join '; ') }
}

# ---- 3. catalogo de tweaks ----
Secao 'data/tweaks.json'
$tweaks = $null
try {
    $tweaks = Get-Content -Raw -Encoding UTF8 (Join-Path $raiz 'data\tweaks.json') | ConvertFrom-Json
    Passou 'json valido'
} catch { Falhou 'json valido' $_.Exception.Message }

if ($null -ne $tweaks) {
    $problemas = @()
    $tiposAcao = @('registro','servico','comando','appx','recurso','energia')
    $tiposValor = @('DWord','QWord','String','ExpandString','Binary')
    foreach ($t in $tweaks.tweaks) {
        $nome = [string]$t.nome
        if ([string]::IsNullOrWhiteSpace($nome)) { $problemas += 'tweak sem nome'; $nome = '(sem nome)' }
        if ([string]::IsNullOrWhiteSpace([string]$t.desc)) { $problemas += ($nome + ': sem descricao') }
        if ([string]::IsNullOrWhiteSpace([string]$t.categoria)) { $problemas += ($nome + ': sem categoria') }
        if ($null -eq $t.niveis -or @($t.niveis).Count -eq 0) { $problemas += ($nome + ': sem niveis') }
        foreach ($n in @($t.niveis)) {
            if (@('seguro','balanceado','agressivo') -notcontains [string]$n) { $problemas += ($nome + ': nivel desconhecido: ' + $n) }
        }
        if ($null -ne $t.so -and @('ambos','win10','win11') -notcontains [string]$t.so) {
            $problemas += ($nome + ': campo so invalido: ' + $t.so)
        }
        if ($null -eq $t.acoes -or @($t.acoes).Count -eq 0) { $problemas += ($nome + ': sem acoes') }
        foreach ($a in @($t.acoes)) {
            $tipo = [string]$a.tipo
            if ($tiposAcao -notcontains $tipo) { $problemas += ($nome + ': tipo de acao desconhecido: ' + $tipo); continue }
            switch ($tipo) {
                'registro' {
                    if (-not ([string]$a.caminho).StartsWith('HK')) { $problemas += ($nome + ': caminho de registro estranho: ' + $a.caminho) }
                    if ([string]::IsNullOrWhiteSpace([string]$a.nome)) { $problemas += ($nome + ': acao de registro sem nome de valor') }
                    if ($null -eq $a.dados) { $problemas += ($nome + ': acao de registro sem dados') }
                    if ($tiposValor -notcontains [string]$a.tipoValor) { $problemas += ($nome + ': tipoValor invalido: ' + $a.tipoValor) }
                }
                'servico' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.nome)) { $problemas += ($nome + ': acao de servico sem nome') }
                    if (@('Automatic','Manual','Disabled') -notcontains [string]$a.inicio) { $problemas += ($nome + ': inicio de servico invalido: ' + $a.inicio) }
                }
                'comando' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.executar)) { $problemas += ($nome + ': acao de comando sem campo executar') }
                }
                'appx' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.pacote)) { $problemas += ($nome + ': acao appx sem pacote') }
                }
                'recurso' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.nome)) { $problemas += ($nome + ': acao de recurso sem nome') }
                }
                'energia' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.guid)) { $problemas += ($nome + ': acao de energia sem guid') }
                }
            }
        }
    }
    if ($problemas.Count -eq 0) { Passou ('estrutura dos ' + @($tweaks.tweaks).Count + ' tweaks') }
    else {
        $amostra = ($problemas | Select-Object -First 8) -join ' | '
        Falhou 'estrutura dos tweaks' ($problemas.Count.ToString() + ' problema(s): ' + $amostra)
    }

    $dups = @($tweaks.tweaks | ForEach-Object { [string]$_.nome } | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dups.Count -eq 0) { Passou 'nenhum tweak com nome repetido' }
    else { Falhou 'tweaks com nome repetido' (($dups | ForEach-Object { $_.Name }) -join ', ') }
}

# ---- 4. catalogo de aplicativos ----
Secao 'data/aplicativos.json'
$apps = $null
try {
    $apps = Get-Content -Raw -Encoding UTF8 (Join-Path $raiz 'data\aplicativos.json') | ConvertFrom-Json
    Passou 'json valido'
} catch { Falhou 'json valido' $_.Exception.Message }

if ($null -ne $apps) {
    $problemas = @()
    foreach ($a in $apps.aplicativos) {
        $nome = [string]$a.nome
        if ([string]::IsNullOrWhiteSpace($nome)) { $problemas += 'app sem nome'; $nome = '(sem nome)' }
        $id = [string]$a.id
        if ([string]::IsNullOrWhiteSpace($id)) { $problemas += ($nome + ': sem id winget') }
        elseif ($id -notmatch '^[A-Za-z0-9]+\+?([._\-][A-Za-z0-9]+\+?)*$') { $problemas += ($nome + ': id winget com cara estranha: ' + $id) }
        if ([string]::IsNullOrWhiteSpace([string]$a.categoria)) { $problemas += ($nome + ': sem categoria') }
    }
    if ($problemas.Count -eq 0) { Passou ('estrutura dos ' + @($apps.aplicativos).Count + ' apps') }
    else {
        $amostra = ($problemas | Select-Object -First 8) -join ' | '
        Falhou 'estrutura dos apps' ($problemas.Count.ToString() + ' problema(s): ' + $amostra)
    }

    $dups = @($apps.aplicativos | ForEach-Object { [string]$_.id } | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dups.Count -eq 0) { Passou 'nenhum id winget repetido' }
    else { Falhou 'ids winget repetidos' (($dups | ForEach-Object { $_.Name }) -join ', ') }
}

# ---- 5. catalogo uwp ----
Secao 'data/uwp.json'
$uwp = $null
try {
    $uwp = Get-Content -Raw -Encoding UTF8 (Join-Path $raiz 'data\uwp.json') | ConvertFrom-Json
    Passou 'json valido'
} catch { Falhou 'json valido' $_.Exception.Message }

if ($null -ne $uwp) {
    $problemas = @()
    foreach ($p in $uwp.pacotes) {
        $nome = [string]$p.nome
        if ([string]::IsNullOrWhiteSpace($nome)) { $problemas += 'pacote sem nome'; $nome = '(sem nome)' }
        $pacote = [string]$p.pacote
        if ([string]::IsNullOrWhiteSpace($pacote)) { $problemas += ($nome + ': sem pacote') }
        if ($null -ne $p.so -and @('ambos','win10','win11') -notcontains [string]$p.so) {
            $problemas += ($nome + ': campo so invalido: ' + $p.so)
        }
    }
    if ($problemas.Count -eq 0) { Passou ('estrutura dos ' + @($uwp.pacotes).Count + ' pacotes uwp') }
    else {
        $amostra = ($problemas | Select-Object -First 8) -join ' | '
        Falhou 'estrutura dos pacotes uwp' ($problemas.Count.ToString() + ' problema(s): ' + $amostra)
    }

    $dups = @($uwp.pacotes | ForEach-Object { [string]$_.pacote } | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dups.Count -eq 0) { Passou 'nenhum pacote uwp repetido' }
    else { Falhou 'pacotes uwp repetidos' (($dups | ForEach-Object { $_.Name }) -join ', ') }
}

# ---- 6. xaml ----
Secao 'src/ui/principal.xaml'
$xamlTexto = Get-Content -Raw -Encoding UTF8 (Join-Path $raiz 'src\ui\principal.xaml')
try {
    $null = [xml]$xamlTexto
    Passou 'xaml e xml valido'
} catch { Falhou 'xaml e xml valido' $_.Exception.Message }

$nomesXaml = @([regex]::Matches($xamlTexto, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$dups = @($nomesXaml | Group-Object | Where-Object { $_.Count -gt 1 })
if ($dups.Count -eq 0) { Passou ('os ' + $nomesXaml.Count + ' x:Name sao unicos') }
else { Falhou 'x:Name repetidos no xaml' (($dups | ForEach-Object { $_.Name }) -join ', ') }

$guiTexto = Get-Content -Raw (Join-Path $raiz 'src\modules\gui.ps1')
$paginas = @([regex]::Matches($guiTexto, "'(Pagina[A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$faltam = @()
foreach ($p in $paginas) {
    if ($nomesXaml -notcontains $p) { $faltam += $p }
}
if ($faltam.Count -eq 0) { Passou ('as ' + $paginas.Count + ' paginas usadas no gui existem no xaml') }
else { Falhou 'paginas sem x:Name no xaml' ($faltam -join ', ') }

$entradaTexto = Get-Content -Raw (Join-Path $raiz 'otimizadorpc.ps1')
$m = [regex]::Match($entradaTexto, '\$controles = @\((.*?)\)', 'Singleline')
if (-not $m.Success) { Falhou 'array $controles do otimizadorpc.ps1' 'nao achei o array no entrypoint' }
else {
    $nomesCtrl = [regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
    $faltam = @()
    foreach ($n in $nomesCtrl) {
        if ($nomesXaml -notcontains $n) { $faltam += $n }
    }
    if ($faltam.Count -eq 0) { Passou ('os ' + $nomesCtrl.Count + ' controles do entrypoint existem no xaml') }
    else { Falhou 'controles registrados sem x:Name no xaml' ($faltam -join ', ') }
}

# ---- 7. funcoes: tudo que o gui/entrypoint chama tem que existir ----
Secao 'funcoes dos modulos'
$defs = @{}
$dupsFun = @()
foreach ($f in (Get-ChildItem -Path (Join-Path $raiz 'src\modules') -Filter '*.ps1')) {
    $t = Get-Content -Raw $f.FullName
    foreach ($mm in [regex]::Matches($t, '(?m)^function ([A-Za-z][A-Za-z0-9-]+)')) {
        $nomeFun = $mm.Groups[1].Value
        if ($defs.ContainsKey($nomeFun)) { $dupsFun += ($nomeFun + ' (' + $defs[$nomeFun] + ' e ' + $f.Name + ')') }
        else { $defs[$nomeFun] = $f.Name }
    }
}
if ($dupsFun.Count -eq 0) { Passou 'nenhuma funcao definida duas vezes' }
else { Falhou 'funcoes duplicadas' ($dupsFun -join ', ') }

$alvoRegex = '\b(Clique|Montar|Preencher|Atualizar|Verificar|Trocar|Aplicar|Instalar|Carregar|Garantir|Ligar|Obter|Criar|Reverter|Salvar|Listar|Executar|Varrer|Desinstalar|Apagar|Resetar|Limpar|Analisar|Bater|Medir)-[A-Za-z0-9]+\b'
$chamadas = @([regex]::Matches(($guiTexto + ' ' + $entradaTexto), $alvoRegex) | ForEach-Object { $_.Value } | Sort-Object -Unique)
$faltam = @()
foreach ($c in $chamadas) {
    if (-not $defs.ContainsKey($c)) { $faltam += $c }
}
if ($faltam.Count -eq 0) { Passou ('as ' + $chamadas.Count + ' funcoes chamadas por gui/entrypoint existem nos modulos') }
else { Falhou 'funcoes chamadas mas nao definidas' ($faltam -join ', ') }

# ---- 8. persistencia e recuperacao (sem alterar o Windows) ----
Secao 'journal atomico e recuperacao'
$testeJournal = Join-Path ([System.IO.Path]::GetTempPath()) ('otimizadorpc-teste-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testeJournal -ErrorAction Stop | Out-Null
    . (Join-Path $raiz 'src\modules\motor.ps1')
    $arquivoTeste = Join-Path $testeJournal 'sessao.json'
    Gravar-JSONAtomico -Arquivo $arquivoTeste -Objeto @{ itens = @(@{ tipo = 'teste'; estadoReversao = 'em_andamento' }) }
    Gravar-JSONAtomico -Arquivo $arquivoTeste -Objeto @{ itens = @(@{ tipo = 'teste'; estadoReversao = 'concluido' }) }
    $atual = Get-Content -LiteralPath $arquivoTeste -Raw | ConvertFrom-Json
    $anterior = Get-Content -LiteralPath ($arquivoTeste + '.bak') -Raw | ConvertFrom-Json
    if ($atual.itens[0].estadoReversao -ne 'concluido' -or $anterior.itens[0].estadoReversao -ne 'em_andamento') {
        throw 'Estado atual ou backup incorreto.'
    }
    Passou 'journal atomico preserva estado atual e anterior'
    # Usa executor simulado: nenhum ajuste real de registro ou servico.
    & {
        function Log { param([string]$Mensagem, [switch]$Erro) }
        function Atualizar-UI {}
        function Ler-JSON { param([string]$Caminho) Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json }
        $script:acoesTeste = @()
        function Desfazer-Item { param($Item) $script:acoesTeste += $Item.tipo; return ($Item.tipo -ne 'falha') }
        $retomar = Join-Path $testeJournal 'retomar.json'
        Gravar-JSONAtomico -Arquivo $retomar -Objeto @{ rotulo = 'teste'; itens = @(@{ tipo = 'pendente' }, @{ tipo = 'ja-feita'; estadoReversao = 'concluido' }) }
        if ((Reverter-Sessao $retomar) -ne $true -or ($script:acoesTeste -join ',') -ne 'pendente' -or -not (Test-Path ($retomar + '.revertido'))) {
            throw 'Retomada repetiu acao concluida ou nao finalizou.'
        }
        Passou 'retomada pula acoes concluidas'
        $script:acoesTeste = @()
        $incerto = Join-Path $testeJournal 'incerto.json'
        Gravar-JSONAtomico -Arquivo $incerto -Objeto @{ rotulo = 'teste'; itens = @(@{ tipo = 'pendente' }, @{ tipo = 'falha' }) }
        if ((Reverter-Sessao $incerto) -ne $false) { throw 'Falha foi tratada como sucesso.' }
        if ((Reverter-Sessao $incerto) -ne $false -or ($script:acoesTeste -join ',') -ne 'falha') {
            throw 'Acao incerta foi repetida ou sequencia continuou.'
        }
        $estado = Ler-JSON $incerto
        if ($estado.itens[1].estadoReversao -ne 'em_andamento') { throw 'Estado incerto nao preservado.' }
        Passou 'falha preserva journal e bloqueia repeticao'
    }

    $falha = $false
    try {
        Gravar-JSONAtomico -Arquivo (Join-Path $testeJournal 'ausente\sessao.json') -Objeto @{ itens = @() }
    } catch { $falha = $true }
    if ($falha) { Passou 'falha de persistencia propagada' }
    else { Falhou 'falha de persistencia propagada' 'gravacao invalida nao gerou erro' }
} catch {
    Falhou 'journal atomico' $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $testeJournal) { Remove-Item -LiteralPath $testeJournal -Recurse -Force }
}

# ---- resumo ----
Write-Host ''
Write-Host '============================================================'
if ($global:Erros -eq 0) {
    Write-Host ('  tudo certo: ' + $global:Ok + ' teste(s) passaram, 0 falhas.') -ForegroundColor Green
    Write-Host '  pode abrir o app com rodar-como-admin.bat'
} else {
    Write-Host ('  ' + $global:Erros + ' teste(s) falharam, ' + $global:Ok + ' passaram.') -ForegroundColor Red
    Write-Host '  corrija as linhas em vermelho antes de usar o app.'
    Write-Host '  (se eu estiver editando os arquivos agora, rode de novo depois)'
}
Write-Host '============================================================'
if ($global:Erros -gt 0) { exit 1 }
exit 0
