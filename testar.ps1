# ============================================================
#  testar.ps1 - bateria de testes offline do otimizadorpc
#  valida catalogos, xaml, controles, funcoes e encoding sem abrir a janela
#  rodar no terminal:  powershell -ExecutionPolicy Bypass -File .\testar.ps1
#  tudo verde = pronto pra usar; cada falha aponta arquivo e campo
# ============================================================

$raiz = $PSScriptRoot
$global:Ok = 0
$global:Erros = 0
# Somente o harness testa funcoes mutaveis em dados descartaveis/mocks.
$global:ModoProtegido=$false

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
    $tiposAcao = @('registro','servico','appx','recurso','energia')
    $tiposValor = @('DWord','QWord','String','ExpandString','Binary','MultiString')
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
                    if ($null -eq $a.nome) { $problemas += ($nome + ': acao de registro sem campo nome (vazio = valor padrao)') }
                    if ($null -eq $a.dados) { $problemas += ($nome + ': acao de registro sem dados') }
                    if ($tiposValor -notcontains [string]$a.tipoValor) { $problemas += ($nome + ': tipoValor invalido: ' + $a.tipoValor) }
                }
                'servico' {
                    if ([string]::IsNullOrWhiteSpace([string]$a.nome)) { $problemas += ($nome + ': acao de servico sem nome') }
                    if (@('Automatic','Manual','Disabled') -notcontains [string]$a.inicio) { $problemas += ($nome + ': inicio de servico invalido: ' + $a.inicio) }
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
    . (Join-Path $raiz 'src\modules\comum.ps1')
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
    $catalogoTeste = Get-Content -LiteralPath (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($perfil in @('essencial','gamer','notebook','privacidade','corporativo','seguro','balanceado','agressivo')) {
        foreach ($win11 in @($false,$true)) {
            $itensPerfil = @(Selecionar-TweaksPreset -Nivel $perfil -Catalogo $catalogoTeste -Win11 $win11)
            if ($itensPerfil.Count -eq 0 -or @($itensPerfil | Where-Object { $_.apenasManual -or $_.id -like 'custom-*' -or ($_.so -eq 'win11' -and -not $win11) -or ($_.so -eq 'win10' -and $win11) }).Count -gt 0) {
                throw ('Perfil vazio ou incompativel: ' + $perfil)
            }
        }
    }
    Passou 'presets e perfis respeitam compatibilidade e selecao manual'
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
        $um = Join-Path $testeJournal 'um.json'
        Gravar-JSONAtomico -Arquivo $um -Objeto @{ rotulo = 'teste'; itens = @(@{ tipo = 'primeira' }, @{ tipo = 'ultima' }) }
        if ((Reverter-Sessao $um -UmaAcao) -ne $true -or ($script:acoesTeste -join ',') -ne 'ultima' -or -not (Test-Path -LiteralPath $um)) {
            throw 'Reversao individual nao respeitou a ordem ou finalizou cedo.'
        }
        if ((Reverter-Sessao $um -UmaAcao) -ne $true -or ($script:acoesTeste -join ',') -ne 'ultima,primeira' -or -not (Test-Path ($um + '.revertido'))) {
            throw 'Reversao individual nao finalizou a sessao.'
        }
        Passou 'reversao individual respeita ordem inversa e finaliza sessao'
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
        $rejeitou = $false
        try { Confirmar-ReversaoManual -Arquivo $incerto -Indice 0 } catch { $rejeitou = $true }
        if (-not $rejeitou) { throw 'Confirmacao pulou a acao incerta.' }
        Confirmar-ReversaoManual -Arquivo $incerto -Indice 1
        $estado = Ler-JSON $incerto
        if (-not $estado.itens[1].confirmadoManualEm -or (Reverter-Sessao $incerto) -ne $true -or ($script:acoesTeste -join ',') -ne 'falha,pendente') {
            throw 'Confirmacao manual nao permitiu retomar sem repetir.'
        }
        Passou 'confirmacao manual registra atestado e permite retomada'
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

# ---- analise de armazenamento: pasta descartavel ----
Secao 'analise de armazenamento'
$testePasta = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-storage-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testePasta -ErrorAction Stop | Out-Null
    . (Join-Path $raiz 'src\modules\sistema.ps1')
    [IO.File]::WriteAllBytes((Join-Path $testePasta 'pequeno.bin'), [byte[]]@(1,2))
    [IO.File]::WriteAllBytes((Join-Path $testePasta 'grande.bin'), [byte[]]@(1,2,3,4))
    $resultado = Analisar-Armazenamento -Pasta $testePasta
    if ($resultado.arquivos -ne 2 -or $resultado.bytes -ne 6 -or $resultado.parcial -or $resultado.maiores[0].bytes -ne 4) { throw 'Contagem, tamanho ou ordenacao incorreta.' }
    Passou 'analise soma e ordena arquivos sem altera-los'
    $limitado = Analisar-Armazenamento -Pasta $testePasta -Limite 1
    if (-not $limitado.parcial -or $limitado.arquivos -ne 1) { throw 'Limite de itens nao respeitado.' }
    Passou 'analise sinaliza resultado parcial'
} catch { Falhou 'analise de armazenamento' $_.Exception.Message }
finally { if (Test-Path -LiteralPath $testePasta) { Remove-Item -LiteralPath $testePasta -Recurse -Force } }

# ---- journal deve impedir a movimentacao quando nao puder ser salvo ----
Secao 'quarentena e falhas de persistencia'
$testeQuarentena = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-quarentena-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testeQuarentena -ErrorAction Stop | Out-Null
    . (Join-Path $raiz 'src\modules\desinstalador.ps1')
    $origem = Join-Path $testeQuarentena 'origem.txt'
    [IO.File]::WriteAllText($origem, 'teste')
    & {
        function Registrar-Jornal { param($Item) throw 'Falha simulada de journal' }
        $falhou = $false
        try { Apagar-Rastro ([pscustomobject]@{ tipo='arquivo'; caminho=$origem }) $testeQuarentena 1 } catch { $falhou = $true }
        if (-not $falhou -or -not (Test-Path -LiteralPath $origem) -or (Test-Path -LiteralPath (Join-Path $testeQuarentena '01_origem.txt'))) {
            throw 'Arquivo foi movido sem journal.'
        }
    }
    Passou 'falha no journal preserva arquivo original'
} catch { Falhou 'quarentena segura' $_.Exception.Message }
finally { if (Test-Path -LiteralPath $testeQuarentena) { Remove-Item -LiteralPath $testeQuarentena -Recurse -Force } }

# ---- launcher sem instalar: montagem local e validacao sem abrir a GUI ----
Secao 'launcher portatil'
try {
    & (Join-Path $raiz 'iniciar.ps1') -FonteLocal $raiz -SomenteValidar
    Passou 'launcher monta e valida portatil sem instalar'
} catch { Falhou 'launcher portatil' $_.Exception.Message }

# No GitHub Actions, testa tambem o caminho publico de download.
if ($env:GITHUB_ACTIONS -eq 'true') {
    Secao 'launcher via github'
    try {
        $evento = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw -Encoding UTF8 | ConvertFrom-Json
        $refTeste = $env:GITHUB_SHA
        if ($evento.pull_request.head.sha) { $refTeste = $evento.pull_request.head.sha }
        & (Join-Path $raiz 'iniciar.ps1') -Ref $refTeste -SomenteValidar
        Passou 'launcher baixa commit publico, confere blobs e monta portatil'
    } catch { Falhou 'launcher via github' $_.Exception.Message }
}

# ---- script online: execucao real em memoria, sem abrir a janela ----
Secao 'distribuicao online'
$saidaOnline = 'dist-teste-' + [guid]::NewGuid().ToString('N')
$pastaOnline = Join-Path $raiz $saidaOnline
try {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $raiz 'montar-portatil.ps1') -PastaSaida $saidaOnline
    if ($LASTEXITCODE -ne 0) { throw 'Falha na montagem.' }
    $arquivoOnline = Join-Path $pastaOnline 'otimizadorpc.ps1'
    $codigoOnline = [IO.File]::ReadAllText($arquivoOnline)
    $null = [scriptblock]::Create($codigoOnline)
    $esperado = ((Get-Content -LiteralPath ($arquivoOnline + '.sha256') -Raw).Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $arquivoOnline -Algorithm SHA256).Hash -ne $esperado) { throw 'SHA256 divergente.' }
    Passou 'script online compilado e SHA256 valido'
    $modoAnterior=$global:ModoProtegido; $nomeModoAnterior=$global:ModoOtimizador; $ambienteAnterior=$global:AmbienteTrabalho
    $identidadeTeste = [Security.Principal.WindowsIdentity]::GetCurrent()
    $adminTeste = New-Object Security.Principal.WindowsPrincipal($identidadeTeste)
    try {
        & {
            $ErrorActionPreference = 'Stop'
            $estadoRaiz=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'otimizadorpc-v2'
            $existia=Test-Path -LiteralPath $estadoRaiz
            $antes=@()
            if ($existia) { $antes=@(Get-ChildItem -LiteralPath $estadoRaiz -File -Recurse -ErrorAction Stop | ForEach-Object { $_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks } | Sort-Object) }
            & ([scriptblock]::Create($codigoOnline)) -Cli essencial -Simular
            & ([scriptblock]::Create($codigoOnline)) -Diagnostico -ValidarInterface
            if (-not $global:ModoProtegido -or -not $global:UI.BotaoNavAjustes.IsEnabled -or $global:UI.BotaoCriarRestore.IsEnabled -or $global:UI.BotaoVerificarRelease.IsEnabled -or -not $global:UI.BotaoInventario.IsEnabled) { throw 'Interface protegida incorreta.' }
            if ((Test-Path -LiteralPath $estadoRaiz) -ne $existia) { throw 'Diagnostico criou pasta de estado.' }
            $depois=@()
            if ($existia) { $depois=@(Get-ChildItem -LiteralPath $estadoRaiz -File -Recurse -ErrorAction Stop | ForEach-Object { $_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks } | Sort-Object) }
            if (($antes -join "`n") -cne ($depois -join "`n")) { throw 'Diagnostico alterou arquivos de estado.' }
            Passou 'interface protegida e simulacao sem arquivos de estado'
        }
        Passou 'script em memoria simula perfil e carrega controles WPF'
    } finally { $global:ModoProtegido=$modoAnterior; $global:ModoOtimizador=$nomeModoAnterior; $global:AmbienteTrabalho=$ambienteAnterior }
} catch { Falhou 'distribuicao online' $_.Exception.Message }
finally { if (Test-Path -LiteralPath $pastaOnline) { Remove-Item -LiteralPath $pastaOnline -Recurse -Force } }

# ---- comparativo: dados sinteticos, sem depender da carga do runner ----
Secao 'comparacao de medicoes'
try {
    $a = [pscustomobject]@{ formato='otimizadorpc-medicao-v1'; amostras=3; maquina='ci'; build=1; unidade='C:'; ramTotalGB=16; discoTotalGB=100; cpuMedia=20; ramUsadaGB=8; processosMedia=100; discoLivreGB=30 }
    $b = $a.PSObject.Copy()
    $b.cpuMedia = 10
    $b.discoLivreGB = 35
    $comparado = @(Comparar-Medicoes $a $b)
    if ($comparado.Count -ne 4 -or $comparado[0].diferenca -ne -10 -or $comparado[3].diferenca -ne 5) { throw 'Diferencas incorretas.' }
    $b.maquina = 'outro-pc'
    $rejeitado = $false
    try { Comparar-Medicoes $a $b | Out-Null } catch { $rejeitado = $true }
    if (-not $rejeitado) { throw 'Computadores diferentes foram comparados.' }
    Passou 'comparacao de medicoes e validacao de compatibilidade'
} catch { Falhou 'comparacao de medicoes' $_.Exception.Message }

# ---- regressao das caixas de selecao (WPF real, sem apagar nada) ----
Secao 'selecao de programas e rastros'
$uiAnterior = $global:UI
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    & {
        . (Join-Path $raiz 'src\modules\desinstalador.ps1')
        function Status { param($Mensagem) }
        function Ocupado { param($Estado) }
        function Log { param($Mensagem) }
        function Avisar { param($Titulo,$Mensagem) throw ('Aviso inesperado: ' + $Titulo) }
        $script:confirmacaoTeste = ''
        function Perguntar { param($Titulo,$Mensagem) $script:confirmacaoTeste = $Mensagem; return $false }
        $script:progTeste = [pscustomobject]@{ nome='teste'; chavePs=('HKCU:\Software\OtimizadorPC-CI-Ausente-'+[guid]::NewGuid().ToString('N')) }
        $script:rastroTeste = [pscustomobject]@{ tipo='chave'; caminho='HKCU:\Software\Teste'; extra='teste' }
        function Varrer-Rastros { param($Prog) return $script:rastroTeste }
        $lb = New-Object System.Windows.Controls.ListBox
        $lb.SelectionMode = 'Extended'
        $global:UI = @{ ListaRastros = $lb; RotuloRastros = (New-Object System.Windows.Controls.TextBlock) }
        Executar-Varredura $script:progTeste
        $lb.SelectedIndex = 0
        if (@(Obter-RastrosMarcados $lb).Count -ne 0) { throw 'Realce sem caixa marcada nao deve apagar.' }
        $lb.Items[0].Content.IsChecked = $true
        $lb.UnselectAll()
        $selecionados = @(Obter-RastrosMarcados $lb)
        if ($selecionados.Count -ne 1 -or $selecionados[0].caminho -ne $script:rastroTeste.caminho) { throw 'Rastro unico nao reconhecido.' }
        Clique-ApagarRastros
        if ($script:confirmacaoTeste -notmatch 'Apagar 1 rastro') { throw 'Confirmacao de um rastro nao exibida.' }
        Passou 'caixa unica marcada chega a confirmacao sem apagar nada'
        Marcar-Rastros $false
        if (@(Obter-RastrosMarcados $lb).Count -ne 0) { throw 'Desmarcacao incorreta.' }
        $lb.Items.Clear()
        $itens = @([pscustomobject]@{ caminho='primeiro' }, [pscustomobject]@{ caminho='segundo' })
        foreach ($obj in $itens) {
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = 'mesmo texto'
            $item.Tag = $obj
            [void]$lb.Items.Add($item)
        }
        $lb.SelectedIndex = 1
        $selecionados = @(Obter-Selecionados $lb $itens)
        if ($selecionados.Count -ne 1 -or $selecionados[0].caminho -ne 'segundo') { throw 'Linhas iguais foram confundidas.' }
        $lb.Items.Clear()
        foreach ($obj in $itens) {
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Tag = $obj
            $item.Content = New-Object System.Windows.Controls.CheckBox
            [void]$lb.Items.Add($item)
        }
        Marcar-Rastros $true
        if (@(Obter-RastrosMarcados $lb).Count -ne 2) { throw 'Marcacao multipla incorreta.' }
        Passou 'marcacao independente do foco e objetos vinculados a cada linha'
    }
} catch { Falhou 'selecao WPF' $_.Exception.Message }
finally { $global:UI = $uiAnterior }

# ---- catalogo: nenhuma expressao executavel livre ----
Secao 'reversibilidade dos presets'
try {
    foreach ($ajuste in $tweaks.tweaks) {
        if (@($ajuste.acoes | Where-Object { $_.tipo -eq 'comando' }).Count -gt 0 -or $ajuste.verificar) {
            throw ('Expressao executavel livre no catalogo: ' + $ajuste.id)
        }
    }
    Passou 'catalogo nao contem comandos livres'
    & {
        function Log { param($Mensagem,[switch]$Erro) }
        $global:TesteComandoLivre = $false
        Executar-Acao ([pscustomobject]@{ tipo='comando'; executar='$global:TesteComandoLivre = $true' }) 'teste de seguranca'
        if ($global:TesteComandoLivre) { throw 'Comando livre de aplicacao executado.' }
        if ((Desfazer-Item ([pscustomobject]@{ tipo='comando'; reverter='$global:TesteComandoLivre = $true' })) -or $global:TesteComandoLivre) { throw 'Comando livre de reversao executado.' }
        Remove-Variable -Name TesteComandoLivre -Scope Global
    }
    Passou 'motor rejeita comandos livres na aplicacao e reversao'
} catch { Falhou 'reversibilidade dos presets' $_.Exception.Message }

# ---- propagacao de falhas do console, sem executar manutencao real ----
Secao 'resultado de comandos nativos'
try {
    . (Join-Path $raiz 'src\modules\consertos.ps1')
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($caso in @(@{ bloco = "Write-Host 'ok'"; esperado=0 }, @{ bloco = "throw 'falha simulada'"; esperado=1 }, @{ bloco = "Executar-Nativo cmd.exe @('/c','exit 7')"; esperado=1 })) {
        $cmd = Montar-ComandoConsole -Bloco $caso.bloco -SemPausa
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        & $psExe -NoProfile -NonInteractive -EncodedCommand $enc
        if ($LASTEXITCODE -ne $caso.esperado) { throw 'Codigo de saida nao preservado.' }
    }
    Passou 'console preserva falhas PowerShell e de executaveis nativos'
} catch { Falhou 'resultado de comandos nativos' $_.Exception.Message }

# ---- ACL do estado administrativo (apenas em console elevado) ----
Secao 'protecao do estado'
try {
    $ident = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($ident)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        & {
            . (Join-Path $raiz 'src\modules\comum.ps1')
            $tmpAcl = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-acl-' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $tmpAcl -ErrorAction Stop | Out-Null
                $recusou = $false
                try { Verificar-PastaPrivada $tmpAcl } catch { $recusou = $true }
                if (-not $recusou) { throw 'Pasta com ACL herdada foi aceita.' }
                Remove-Item -LiteralPath $tmpAcl -Force -ErrorAction Stop
                Garantir-PastaPrivada $tmpAcl
                Verificar-PastaPrivada $tmpAcl
                Garantir-PastaPrivada $tmpAcl
                Passou 'ACL privada aceita; pasta herdada recusada'
                $trava = Obter-TravaInstancia $tmpAcl
                try {
                    $recusou = $false
                    try { $segunda = Obter-TravaInstancia $tmpAcl; $segunda.Dispose() } catch { $recusou = $true }
                    if (-not $recusou) { throw 'Segunda instancia conseguiu a trava.' }
                } finally { $trava.Dispose() }
                $novaTrava = Obter-TravaInstancia $tmpAcl
                $novaTrava.Dispose()
                Passou 'trava impede segunda instancia e permite reabrir'
            } finally { if (Test-Path -LiteralPath $tmpAcl) { Remove-Item -LiteralPath $tmpAcl -Recurse -Force } }
            if (@(Get-ChildItem -LiteralPath $global:PastaDesfazer -File -Filter '*.json' -ErrorAction SilentlyContinue).Count -gt 0 -and $env:GITHUB_ACTIONS -eq 'true') { throw 'Simulacao criou journal no estado novo.' }
        }
    } else { Write-Host '  [info]   teste de ACL requer administrador.' }
} catch { Falhou 'protecao do estado' $_.Exception.Message }

# ---- filtros conservadores de rastros ----
Secao 'limites da varredura'
try {
    if (-not (Nome-RastroExato 'Meu App' 'meuapp') -or (Nome-RastroExato 'Meu App Backup' 'meuapp')) { throw 'Correspondencia de nome ampla demais.' }
    if (Chave-RastroSegura 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft' ) { throw 'Chave de sistema aceita.' }
    if (Chave-RastroSegura 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet') { throw 'Chave SYSTEM aceita.' }
    if (-not (Chave-RastroSegura 'HKEY_CURRENT_USER\Software\MeuApp')) { throw 'Chave de aplicativo recusada.' }
    if (Caminho-LocalAusente $env:SystemRoot) { throw 'Diretorio existente considerado ausente.' }
    if (Caminho-LocalAusente '\\servidor\pasta') { throw 'Rede considerada ausente.' }
    Passou 'varredura conservadora protege chaves e caminhos ambiguos'
} catch { Falhou 'limites da varredura' $_.Exception.Message }

# ---- AppX: simulacao de escopo, nenhum pacote real e removido ----
Secao 'debloat limitado ao usuario'
try {
    & {
        . (Join-Path $raiz 'src\modules\motor.ps1')
        $script:appxTeste = @(
            [pscustomobject]@{ Name='Microsoft.Example'; PackageFullName='Example_v1'; PackageFamilyName='Example_family' },
            [pscustomobject]@{ Name='Microsoft.ExampleExtra'; PackageFullName='ExampleExtra_v1'; PackageFamilyName='Extra_family' }
        )
        $script:appxJournal = @()
        function Log { param($Mensagem,[switch]$Erro) if ($Erro) { throw $Mensagem } }
        function Testar-AppxCatalogado { param($Nome) return ($Nome -eq 'Microsoft.Example') }
        function Get-AppxPackage { [CmdletBinding()] param() return $script:appxTeste }
        function Registrar-Jornal { param($Item) $script:appxJournal += $Item }
        function Remove-AppxPackage {
            [CmdletBinding()] param([string]$Package)
            if ($Package -ne 'Example_v1') { throw 'Pacote incorreto.' }
            $script:appxTeste = @($script:appxTeste | Where-Object { $_.PackageFullName -ne $Package })
        }
        function Remove-AppxProvisionedPackage { throw 'Provisionamento nao deve ser alterado.' }
        Executar-Acao ([pscustomobject]@{ tipo='appx'; pacote='Microsoft.Example' }) 'teste'
        if ($script:appxJournal.Count -ne 1 -or -not $script:appxJournal[0].usuarioSid -or $script:appxTeste.Count -ne 1 -or $script:appxTeste[0].Name -ne 'Microsoft.ExampleExtra') { throw 'Escopo ou correspondencia AppX incorreta.' }
        Passou 'debloat preserva pacotes semelhantes e provisionamento'
    }
} catch { Falhou 'debloat limitado ao usuario' $_.Exception.Message }

# ---- parser restrito de REGEDIT5 ----
Secao 'custom por valor'
try {
    $texto = @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\OtimizadorTeste]
"nome"="texto"
"numero"=dword:ffffffff
@=-
'@
    $acoes = @(Ler-PlanoRegRestrito $texto)
    if ($acoes.Count -ne 3 -or $acoes[1].dados -ne -1 -or -not $acoes[2].remover -or $acoes[2].nome -ne '') { throw 'Plano convertido incorretamente.' }
    foreach ($ruim in @('[HKEY_LOCAL_MACHINE\Software\Teste]','[-HKEY_CURRENT_USER\Software\Teste]','[HKEY_CURRENT_USER\Software\Policies\Teste]','"x"=hex:01,02')) {
        $recusou = $false
        try { $null = Ler-PlanoRegRestrito ($texto + "`n" + $ruim) } catch { $recusou=$true }
        if (-not $recusou) { throw ('Linha proibida aceita: ' + $ruim) }
    }
    Passou 'parser aceita valores simples e recusa arquivo inteiro invalido'
} catch { Falhou 'custom por valor' $_.Exception.Message }

# ---- recursos com dependencias nao podem ser revertidos automaticamente ----
Secao 'recursos com dependencias'
try {
    & {
        function Log { param($Mensagem,[switch]$Erro) }
        function Disable-WindowsOptionalFeature { throw 'Nao deveria chamar DISM.' }
        $item = [pscustomobject]@{ tipo='recurso'; nome='Teste'; estadoAnterior='Disabled'; estadoDepois='Enabled'; alteracoes=@([pscustomobject]@{nome='Teste'},[pscustomobject]@{nome='Dependencia'}) }
        if (Desfazer-Item $item) { throw 'Reversao de dependencias aceita.' }
    }
    Passou 'reversao de recursos com dependencias exige revisao manual'
} catch { Falhou 'recursos com dependencias' $_.Exception.Message }

# ---- filtros e rotulos de risco ----
Secao 'gerenciador e rotulos'
try {
    . (Join-Path $raiz 'src\modules\gui.ps1')
    $dados = @([pscustomobject]@{nome='Alpha';estado='Running'},[pscustomobject]@{nome='Beta';estado='Stopped'})
    if (@(Filtrar-Inventario $dados 'running').Count -ne 1 -or @(Filtrar-Inventario $dados '').Count -ne 2 -or @(Filtrar-Inventario $dados '[').Count -ne 0) { throw 'Filtro incorreto.' }
    if ((Classificar-RiscoAjuste ([pscustomobject]@{ categoria='Sistema'; acoes=@([pscustomobject]@{tipo='servico'}) })) -ne 'cautela alta') { throw 'Servico sem rotulo de cautela.' }
    Passou 'filtro literal e classificacao de cautela'
} catch { Falhou 'gerenciador e rotulos' $_.Exception.Message }

# ---- cancelamento cooperativo sem janela nem efeitos ----
Secao 'progresso em lote'
try {
    & {
        . (Join-Path $raiz 'src\modules\comum.ps1')
        $estado = @{ cancelado=$false; atual=0; total=2; janela=$null }
        if (-not (Continuar-ProgressoLote $estado 'primeiro') -or $estado.atual -ne 1) { throw 'Progresso inicial incorreto.' }
        $estado.cancelado=$true
        if ((Continuar-ProgressoLote $estado 'segundo') -or $estado.atual -ne 1) { throw 'Acao apos cancelamento aceita.' }
        Fechar-ProgressoLote $estado
    }
    Passou 'cancelamento impede proxima acao sem interromper a anterior'
} catch { Falhou 'progresso em lote' $_.Exception.Message }

# ---- tarefa: identidade da definicao ----
Secao 'assinatura de tarefas'
try {
    $a = '<Task><Settings><Enabled>true</Enabled></Settings><Actions><Exec><Command>teste.exe</Command></Exec></Actions></Task>'
    $b = $a.Replace('true','false')
    if ((Assinatura-TarefaXml $a) -ne (Assinatura-TarefaXml $b)) { throw 'Estado de habilitacao afetou assinatura.' }
    if ((Assinatura-TarefaXml $a) -eq (Assinatura-TarefaXml ($a.Replace('teste.exe','outro.exe')))) { throw 'Alteracao de definicao nao detectada.' }
    Passou 'assinatura detecta mudanca de definicao de tarefa'
} catch { Falhou 'assinatura de tarefas' $_.Exception.Message }

# ---- comparacao exige quantidade e cenario compativeis ----
Secao 'comparacao de amostras'
try {
    $a = [pscustomobject]@{ formato='otimizadorpc-medicao-v1'; amostras=10; cenario='teste'; maquina='ci'; build=1; unidade='C:'; ramTotalGB=16; discoTotalGB=100; cpuMedia=20; ramUsadaGB=8; processosMedia=100; discoLivreGB=30 }
    $b=$a.PSObject.Copy()
    if (@(Comparar-Medicoes $a $b).Count -ne 4) { throw 'Comparacao de dez amostras invalida.' }
    $b.cenario='outro'
    $rejeitou=$false
    try { $null=Comparar-Medicoes $a $b } catch { $rejeitou=$true }
    if (-not $rejeitou) { throw 'Cenarios diferentes aceitos.' }
    Passou 'comparacao valida amostras e cenario'
} catch { Falhou 'comparacao de amostras' $_.Exception.Message }

# ---- tema claro e escuro carregam o mesmo XAML ----
Secao 'temas'
try {
    & {
        . (Join-Path $raiz 'src\modules\comum.ps1')
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $texto=Get-Content -LiteralPath (Join-Path $raiz 'src\ui\principal.xaml') -Raw -Encoding UTF8
        foreach ($tema in @('escuro','claro')) {
            $convertido=Converter-TemaXaml $texto $tema
            $janela=[Windows.Markup.XamlReader]::Parse($convertido)
            if (-not $janela.FindName('BotaoTema')) { throw 'Controle de tema ausente.' }
            $janela.Close()
        }
        if ((Cor-Tema '#131316' 'claro') -ne '#f6f8fb' -or (Cor-Tema '#131316' 'escuro') -ne '#131316') { throw 'Paleta incorreta.' }
        Passou 'XAML de ambos os temas carrega'
    }
} catch { Falhou 'temas' $_.Exception.Message }

# ---- carga padronizada reduzida para CI ----
Secao 'teste de carga padronizada'
try {
    $med=Medir-CargaPadronizada -MiB 1 -Repeticoes 1
    if ($med.formato -ne 'otimizadorpc-carga-v1' -or @($med.rodadas).Count -ne 3 -or @($med.rodadas | Where-Object { $_.hashMs -lt 0 -or $_.copiaMemoriaMs -lt 0 }).Count -gt 0) { throw 'Resultado invalido.' }
    Passou 'carga fixa produz tres rodadas sem tocar arquivos'
} catch { Falhou 'teste de carga padronizada' $_.Exception.Message }

# ---- download de atualizacao: bytes e hash, sem rede e sem executar ----
Secao 'integridade de atualizacao'
try {
    & {
        . (Join-Path $raiz 'src\modules\sistema.ps1')
        $script:bytesTeste=[Text.Encoding]::UTF8.GetBytes('script de teste nao executado')
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $script:hashTeste=([BitConverter]::ToString($sha.ComputeHash($script:bytesTeste))).Replace('-','') } finally { $sha.Dispose() }
        function Invoke-WebRequest {
            [CmdletBinding()] param([string]$Uri,[switch]$UseBasicParsing,[int]$TimeoutSec)
            $prefixo='https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/v2.0.0-rc.5/otimizadorpc.ps1'
            if ($Uri -eq ($prefixo+'.sha256')) { $bytes=[Text.Encoding]::ASCII.GetBytes($script:hashTeste+'  otimizadorpc.ps1') }
            elseif ($Uri -eq $prefixo) { $bytes=$script:bytesTeste }
            else { throw 'URL nao permitida.' }
            return [pscustomobject]@{ RawContentStream=[IO.MemoryStream]::new([byte[]]$bytes) }
        }
        $res=Baixar-ReleaseVerificada 'v2.0.0-rc.5'
        if ($res.hash -ne $script:hashTeste -or [Text.Encoding]::UTF8.GetString($res.bytes) -ne 'script de teste nao executado') { throw 'Bytes verificados divergentes.' }
        $script:hashTeste='0'*64
        $recusou=$false
        try { $null=Baixar-ReleaseVerificada 'v2.0.0-rc.5' } catch { $recusou=$_.Exception.Message -match 'SHA256 divergente' }
        if (-not $recusou) { throw 'Hash invalido nao recusado.' }
    }
    Passou 'download aceita bytes corretos e recusa SHA256 divergente'
} catch { Falhou 'integridade de atualizacao' $_.Exception.Message }

# ---- classificacao de programas e bloqueio de operacoes ----
Secao 'classificacao do desinstalador'
try {
    & {
        . (Join-Path $raiz 'src\modules\desinstalador.ps1')
        $catalogoAnterior=$global:CatalogoApps
        try {
            $global:CatalogoApps=[pscustomobject]@{ aplicativos=@([pscustomobject]@{nome='Google Chrome';desc='Navegador'}) }
            $casos=@(
                @{nome='Google Chrome';editor='Google LLC';cat='Aplicativo';risco='Normal'},
                @{nome='Microsoft Edge';editor='Microsoft Corporation';cat='Sistema';risco='Bloqueado'},
                @{nome='Microsoft Edge WebView2 Runtime';editor='Microsoft Corporation';cat='Sistema';risco='Bloqueado'},
                @{nome='Microsoft Visual C++ 2015-2022 Redistributable (x64)';editor='Microsoft Corporation';cat='Dependencia';risco='Cautela'},
                @{nome='NVIDIA Graphics Driver';editor='NVIDIA';cat='Driver';risco='Cautela'},
                @{nome='Microsoft PowerToys';editor='Microsoft Corporation';cat='Opcional';risco='Normal'},
                @{nome='Norton Antivirus';editor='Norton';cat='Seguranca';risco='Cautela'},
                @{nome='Desconhecido';editor='Microsoft Corporation';cat='Desconhecido';risco='Revisar'}
            )
            $lista=@()
            foreach ($caso in $casos) {
                $pr=[pscustomobject]@{nome=$caso.nome;editor=$caso.editor;comando='teste.exe';quiet='';tamanhoKB=$null;dataInstalacao=$null}
                $info=Classificar-Programa $pr
                if ($info.categoria -ne $caso.cat -or $info.risco -ne $caso.risco) { throw ('Classificacao incorreta: ' + $pr.nome + ' -> ' + $info.categoria) }
                $pr | Add-Member -NotePropertyName classificacao -NotePropertyValue $info
                $lista += $pr
            }
            $oculto=[pscustomobject]@{nome='Componente oculto';componenteSistema=$true;comando='teste.exe'}
            $protegido=[pscustomobject]@{nome='Programa';naoRemover=$true;comando='teste.exe'}
            foreach ($pr in @($oculto,$protegido,$lista[1],$lista[2])) {
                if ((Classificar-Programa $pr).risco -ne 'Bloqueado') { throw 'Protecao nao aplicada.' }
                $recusou=$false
                try { Desinstalar-Programa $pr } catch { $recusou=$_.Exception.Message -match 'Componente protegido' }
                if (-not $recusou) { throw 'Desinstalador direto nao recusou componente.' }
                $recusou=$false
                try { $null=Validar-ProtecaoPrograma $pr } catch { $recusou=$true }
                if (-not $recusou) { throw 'Limpeza de componente protegido aceita.' }
            }
            if (@(Filtrar-Programas $lista 'runtime' 'Sistema' 'Nome').Count -ne 1 -or @(Filtrar-Programas $lista '[' 'Todos' 'Nome').Count -ne 0) { throw 'Filtro incorreto.' }
            $lista[0].tamanhoKB=200; $lista[3].tamanhoKB=500
            if (@(Filtrar-Programas $lista '' 'Todos' 'Tamanho')[0].nome -ne $lista[3].nome) { throw 'Ordenacao de tamanho incorreta.' }
            $lista[0].dataInstalacao=[datetime]'2025-01-01'; $lista[3].dataInstalacao=[datetime]'2026-01-01'
            if (@(Filtrar-Programas $lista '' 'Todos' 'Data')[0].nome -ne $lista[3].nome) { throw 'Ordenacao de data incorreta.' }
            $convertido=Converter-EntradaPrograma ([pscustomobject]@{DisplayName='Teste';EstimatedSize='1024';InstallDate='20260102';SystemComponent=1;NoRemove=1})
            if ($convertido.tamanhoKB -ne 1024 -or $convertido.dataInstalacao.Day -ne 2 -or -not $convertido.componenteSistema -or -not $convertido.naoRemover) { throw 'Metadados incorretos.' }
            Passou 'classificacao, protecao direta, filtros, ordenacao e metadados'
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            $uiAntes=$global:UI
            try {
                $lb=New-Object System.Windows.Controls.ListBox
                $lb.SelectionMode='Extended'
                $global:UI=@{
                    ListaProgramas=$lb
                    BotaoDetalhesPrograma=(New-Object System.Windows.Controls.Button)
                    BotaoDesinstalarProg=(New-Object System.Windows.Controls.Button)
                    BotaoVarrerRastros=(New-Object System.Windows.Controls.Button)
                    DetalhePrograma=(New-Object System.Windows.Controls.TextBlock)
                }
                foreach ($pr in @($lista[0],$lista[1])) {
                    $linha=New-Object System.Windows.Controls.ListBoxItem
                    $linha.Content=$pr.nome; $linha.Tag=$pr
                    [void]$lb.Items.Add($linha)
                }
                $lb.SelectedIndex=0
                Atualizar-DetalhePrograma
                if (-not $global:UI.BotaoDesinstalarProg.IsEnabled -or -not $global:UI.BotaoDetalhesPrograma.IsEnabled) { throw 'Aplicativo comum indisponivel.' }
                $lb.SelectedIndex=1
                Atualizar-DetalhePrograma
                if ($global:UI.BotaoDesinstalarProg.IsEnabled -or $global:UI.BotaoVarrerRastros.IsEnabled -or -not $global:UI.BotaoDetalhesPrograma.IsEnabled) { throw 'Componente protegido com acao habilitada.' }
                $lb.SelectAll()
                Atualizar-DetalhePrograma
                if ($global:UI.BotaoDesinstalarProg.IsEnabled -or $global:UI.BotaoVarrerRastros.IsEnabled) { throw 'Selecao mista permitiu remover componente.' }
                Passou 'WPF bloqueia componente protegido e selecao mista'
            } finally { $global:UI=$uiAntes }
        } finally { $global:CatalogoApps=$catalogoAnterior }
    }
} catch { Falhou 'classificacao do desinstalador' $_.Exception.Message }

# ---- guia de ajustes e protecao de pacotes ----
Secao 'otimizacao orientada'
try {
    $cat=Get-Content -LiteralPath (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($ajuste in $cat.tweaks) {
        $guia=Obter-GuiaAjuste $ajuste
        if (-not $ajuste.impacto -or $guia.texto -notmatch 'Recuperacao:' -or $guia.texto -notmatch 'Compatibilidade:') { throw ('Guia ausente: ' + $ajuste.id) }
        if (@($ajuste.acoes | Where-Object {$_.tipo -eq 'appx'}).Count) { throw 'Ajuste tenta remover pacote AppX.' }
    }
    foreach ($id in @('telemetria','sysmain','pesquisa-indexacao','energia-alto-desempenho','preferir-ipv4')) {
        if (-not ($cat.tweaks | Where-Object {$_.id -eq $id}).apenasManual) { throw ('Ajuste sensivel em preset: '+$id) }
    }
    foreach ($nome in @('Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','MicrosoftWindows.Client.WebExperience','Microsoft.VCLibs.140.00')) {
        if (-not (Testar-AppxProtegido ([pscustomobject]@{Name=$nome}))) { throw ('Pacote nao protegido: '+$nome) }
    }
    $p=[pscustomobject]@{Name='Microsoft.Example';IsFramework=$true}
    $entrada=[pscustomobject]@{pacote='Microsoft.Example';desc='teste';remover=$true}
    if ((Obter-GuiaUwp $entrada @($p)).permitido) { throw 'Framework catalogado permitido.' }
    $p.IsFramework=$false; $entrada | Add-Member -NotePropertyName desconhecido -NotePropertyValue $true
    if ((Obter-GuiaUwp $entrada @($p)).permitido) { throw 'Pacote desconhecido permitido.' }
    Passou 'guias completos, presets conservadores e AppX protegido'
    & {
        $script:consultaAppx=0; $script:removeuAppx=0; $script:errosAppx=0
        function Log { param($Mensagem,[switch]$Erro) if ($Erro) {$script:errosAppx++} }
        function Testar-AppxCatalogado { param($Nome) return ($Nome -eq 'Microsoft.WindowsStore') }
        function Get-AppxPackage { [CmdletBinding()] param() $script:consultaAppx++; [pscustomobject]@{Name='Microsoft.WindowsStore';PackageFullName='Store_teste'} }
        function Remove-AppxPackage { $script:removeuAppx++ }
        Executar-Acao ([pscustomobject]@{tipo='appx';pacote='Desconhecido'}) 'teste bloqueio'
        if ($script:consultaAppx -ne 0 -or $script:removeuAppx -ne 0 -or $script:errosAppx -ne 1) {throw 'Pacote fora do catalogo nao bloqueado.'}
        Executar-Acao ([pscustomobject]@{tipo='appx';pacote='Microsoft.WindowsStore'}) 'teste bloqueio'
        if ($script:consultaAppx -ne 1 -or $script:removeuAppx -ne 0 -or $script:errosAppx -ne 2) {throw 'Pacote protegido nao bloqueado.'}
    }
    Passou 'motor recusa AppX desconhecido e protegido antes de remover'
} catch { Falhou 'otimizacao orientada' $_.Exception.Message }

# ---- plano de temporarios somente leitura ----
Secao 'limpeza orientada'
try {
    . (Join-Path $raiz 'src\modules\consertos.ps1')
    $pasta=Join-Path $env:LOCALAPPDATA ('OtimizadorPC-CI-Temp-'+[guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $pasta | Out-Null
        $antigo=Join-Path $pasta 'antigo [teste].tmp'; $novo=Join-Path $pasta 'novo.tmp'
        [IO.File]::WriteAllText($antigo,'teste'); [IO.File]::WriteAllText($novo,'novo')
        [IO.File]::SetLastWriteTimeUtc($antigo,[datetime]::UtcNow.AddDays(-10))
        $sub=Join-Path $pasta 'sub'; New-Item -ItemType Directory -Path $sub | Out-Null
        $outro=Join-Path $sub 'antigo.tmp'; [IO.File]::WriteAllText($outro,'teste')
        [IO.File]::SetLastWriteTimeUtc($outro,[datetime]::UtcNow.AddDays(-10))
        $plano=Obter-PlanoTemporarios @($pasta)
        if ($plano.itens.Count -ne 1 -or $plano.itens[0].caminho -ne $antigo -or $plano.bytes -ne 5 -or -not (Test-Path -LiteralPath $antigo)) { throw 'Plano incorreto ou alterou arquivos.' }
        Passou 'plano de limpeza ignora recentes e subpastas sem alterar dados'
    } finally { if (Test-Path -LiteralPath $pasta) { Remove-Item -LiteralPath $pasta -Recurse -Force } }
} catch { Falhou 'limpeza orientada' $_.Exception.Message }

# ---- detalhes do journal nao alteram valores ----
Secao 'inspecao de recuperacao'
try {
    & {
        function Ler-ValorRegistro { param($Caminho,$Nome) [pscustomobject]@{existia=$true;tipo='String';valor='mudanca posterior'} }
        $item=[pscustomobject]@{tipo='registro';caminho='HKCU:\Software\Teste';nome='teste';existia=$true;tipoAnterior='String';valorAnteriorEstruturado=[pscustomobject]@{valor='original'};existiaDepois=$true;tipoDepois='String';valorDepoisEstruturado=[pscustomobject]@{valor='aplicado'}}
        $texto=(Obter-DetalheRecuperacao $item) -join ' '
        if ($texto -notmatch 'original' -or $texto -notmatch 'aplicado' -or $texto -notmatch 'mudanca posterior' -or $texto -notmatch 'Possivel conflito') {throw 'Comparacao incompleta.'}
    }
    Passou 'inspecao compara snapshot e estado atual sem alterar registro'
} catch { Falhou 'inspecao de recuperacao' $_.Exception.Message }

# ---- decisao conservadora e motor protegido ----
Secao 'modo corporativo'
try {
    if ((Resolver-ModoOtimizador $false $false @()) -ne 'Diagnostico' -or (Resolver-ModoOtimizador $true $true @()) -ne 'Diagnostico' -or (Resolver-ModoOtimizador $true $false @('Inconclusivo')) -notmatch '^Administrador' -or (Resolver-ModoOtimizador $true $false @()) -ne 'Administrador' -or (Resolver-ModoOtimizador $true $false @('MDM')) -notmatch '^Administrador') { throw 'Decisao de modo incorreta: admin deve liberar, sinais apenas informar, -Diagnostico e sem admin devem proteger.' }
    $modoAntes=$global:ModoProtegido
    try {
        $global:ModoProtegido=$true
        foreach ($acao in @(
            { Iniciar-Sessao 'bloqueado' },
            { Executar-Acao ([pscustomobject]@{tipo='registro';caminho='HKCU:\Software\NaoCriar';nome='x';dados=1;tipoValor='DWord'}) 'teste' },
            { Reverter-Sessao 'nao-existe.json' },
            { Criar-PontoRestauracao },
            { Limpar-Temporarios },
            { Executar-NoConsole 'teste' 'throw "nao executar"' },
            { Desinstalar-Programa ([pscustomobject]@{nome='teste'}) },
            { Apagar-Rastro ([pscustomobject]@{tipo='arquivo'}) 'nao-existe' 1 },
            { Alterar-ItemInventario 'servicos' $null }
        )) {
            $bloqueado=$false
            try { & $acao } catch { $bloqueado=$_.Exception.Message -match 'Modo protegido' }
            if (-not $bloqueado) { throw 'Operacao mutavel nao bloqueada no motor.' }
        }
        Executar-Acao ([pscustomobject]@{tipo='registro';caminho='HKCU:\Software\NaoCriar';nome='x';dados=1;tipoValor='DWord'}) 'teste' -Simular
    } finally { $global:ModoProtegido=$modoAntes }
    Passou 'modo protegido bloqueia mutacoes, permite simulacao'
} catch { Falhou 'modo corporativo' $_.Exception.Message }

# ---- restauracao: nao ativar protecao nem presumir sucesso ----
Secao 'ponto de restauracao confirmado'
try {
    & {
        function Log { param($Mensagem,[switch]$Erro) }
        function Get-ComputerRestorePoint { [CmdletBinding()] param() [pscustomobject]@{SequenceNumber=1;Description='anterior'} }
        function Enable-ComputerRestore { throw 'Nao deve ativar protecao.' }
        function Checkpoint-Computer { [CmdletBinding()] param($Description,$RestorePointType) }
        function Obter-ContextoAjustes {[pscustomobject]@{build=26100;edicao='Professional';cliente=$true}}
        if (Criar-PontoRestauracao) { throw 'Ponto inexistente foi aceito.' }
        $script:sessaoIniciada=$false
        function Iniciar-Sessao { $script:sessaoIniciada=$true }
        function Executar-Acao { throw 'Nao deve executar acao.' }
        $catalogoAntes=$global:CatalogoTweaks
        try {
            $global:CatalogoTweaks=[pscustomobject]@{tweaks=@([pscustomobject]@{id='extensoes-de-arquivo';nome='teste';so='ambos';acoes=@([pscustomobject]@{tipo='registro'})})}
            if ((Aplicar-Preset 'essencial') -or $script:sessaoIniciada) { throw 'Preset real continuou sem ponto.' }
        } finally { $global:CatalogoTweaks=$catalogoAntes }
    }
    Passou 'ponto nao confirmado interrompe preset antes do journal'
} catch { Falhou 'ponto de restauracao confirmado' $_.Exception.Message }

# ---- politicas apenas leitura ----
Secao 'politicas de atualizacao'
try {
    if ((Formatar-PoliticaAtualizacao 0) -notmatch 'Desativada' -or (Formatar-PoliticaAtualizacao 1) -notmatch 'Configurada' -or (Formatar-PoliticaAtualizacao $null) -notmatch 'Nao configurada') { throw 'Valores de politica confundidos.' }
    $bloqueou=$false
    try { Configurar-Atualizacoes $false $false } catch { $bloqueou=$_.Exception.Message -match 'Edicao de politicas indisponivel' }
    if (-not $bloqueou) { throw 'Edicao de politica permitida.' }
    Passou 'politicas somente leitura e diferenciam ausente/zero/um'
} catch { Falhou 'politicas de atualizacao' $_.Exception.Message }

# ---- plano WinGet e conflito de energia ----
Secao 'instalacao orientada'
try {
    $a=[pscustomobject]@{id='Microsoft.VCRedist.2015+.x64';nome='Runtime'}
    $argsApp=@(Obter-ArgumentosApp $a install)
    if (($argsApp -join ' ') -ne 'install --id Microsoft.VCRedist.2015+.x64 --exact --source winget --no-upgrade') {throw 'Plano de instalacao incorreto.'}
    $a | Add-Member -NotePropertyName fonte -NotePropertyValue 'msstore'
    if ((@(Obter-ArgumentosApp $a upgrade) -join ' ') -notmatch '--source msstore$') {throw 'Fonte Store nao explicitada.'}
    $a.fonte='outra'
    $recusou=$false
    try {$null=Obter-ArgumentosApp $a install} catch {$recusou=$true}
    if (-not $recusou) {throw 'Fonte desconhecida aceita.'}
    Passou 'WinGet: fonte explicita, instalacao sem upgrade e sem aceite automatico'
} catch { Falhou 'instalacao orientada' $_.Exception.Message }
Secao 'conflito energia'
try {
    & {
        function Log {param($Mensagem,[switch]$Erro)}
        function Obter-PlanoEnergiaAtivo {return '33333333-3333-3333-3333-333333333333'}
        function Definir-PlanoEnergia {throw 'Nao deve modificar plano em conflito.'}
        $it=[pscustomobject]@{tipo='energia';guidAnterior='11111111-1111-1111-1111-111111111111';guidDepois='22222222-2222-2222-2222-222222222222'}
        if (Desfazer-Item $it) {throw 'Conflito de energia aceito.'}
    }
    Passou 'reversao de energia preserva mudanca posterior'
} catch { Falhou 'conflito energia' $_.Exception.Message }

# ---- protecao de rastros quando registro permanece ----
Secao 'rastros de programa ainda registrado'
try {
    & {
        function Test-Path { [CmdletBinding()] param([string]$LiteralPath) return $true }
        function Validar-ProtecaoPrograma { param($Prog) [pscustomobject]@{risco='Normal'} }
        $recusou=$false
        try {$null=Confirmar-ProgramaAusenteParaLimpeza ([pscustomobject]@{nome='Teste';chavePs='HKCU:\Software\Teste'})} catch {$recusou=$_.Exception.Message -match 'ainda existe'}
        if (-not $recusou) {throw 'Limpeza de app registrado permitida.'}
    }
    Passou 'limpeza recusa registro original ainda existente'
} catch { Falhou 'rastros de programa ainda registrado' $_.Exception.Message }

# ---- dependencias AppX declaradas ----
Secao 'dependentes AppX'
try {
    $p=[pscustomobject]@{Name='Teste';PackageFullName='Teste_1'}
    $q=[pscustomobject]@{Name='Consumidor';PackageFullName='Consumidor_1';Dependencies=@('Teste_1')}
    if (@(Obter-DependentesAppx $p @($p,$q)).Count -ne 1) {throw 'Dependente nao detectado.'}
    if ((Obter-GuiaUwp ([pscustomobject]@{pacote='Teste';remover=$true;desc='teste'}) @($p,$q)).permitido) {throw 'Dependencia removivel na UI.'}
    & {
        $script:removeuDependente=$false
        $script:erroDependente=$false
        function Log {param($Mensagem,[switch]$Erro) if ($Erro -and $Mensagem -match 'dependentes declarados') {$script:erroDependente=$true}}
        function Testar-AppxCatalogado {return $true}
        function Get-AppxPackage {[CmdletBinding()]param() $p;$q}
        function Remove-AppxPackage {$script:removeuDependente=$true}
        Executar-Acao ([pscustomobject]@{tipo='appx';pacote='Teste'}) 'teste'
        if ($script:removeuDependente -or -not $script:erroDependente) {throw 'Motor aceitou dependencia declarada.'}
    }
    Passou 'dependencia AppX declarada bloqueada no motor e guia'
} catch { Falhou 'dependentes AppX' $_.Exception.Message }

# ---- WPF pessoal: montar e ligar sem executar acao administrativa ----
Secao 'interface pessoal'
try {
    & {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $uiAntes=$global:UI; $janelaAntes=$global:Janela; $modoAntes=$global:ModoProtegido
        $ctAntes=$global:CatalogoTweaks; $caAntes=$global:CatalogoApps
        try {
            $global:ModoProtegido=$false
            $global:CatalogoTweaks=Get-Content -LiteralPath (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $global:CatalogoApps=Get-Content -LiteralPath (Join-Path $raiz 'data\aplicativos.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            function Preencher-PaginaInicio { }
            function Obter-ContextoAjustes {[pscustomobject]@{build=26100;edicao='Professional';cliente=$true}}
            $global:Janela=[Windows.Markup.XamlReader]::Parse((Get-Content -LiteralPath (Join-Path $raiz 'src\ui\principal.xaml') -Raw -Encoding UTF8))
            $global:UI=@{}
            foreach ($nome in $nomesCtrl) {
                $global:UI[$nome]=$global:Janela.FindName($nome)
                if (-not $global:UI[$nome]) {throw ('Controle ausente: '+$nome)}
            }
            Ligar-Tudo
            if (-not $global:UI.BotaoNavAjustes.IsEnabled -or -not $global:UI.BotaoAtualizarSelecionados.IsEnabled) {throw 'Interface pessoal nao habilitada.'}
            if (@(Get-Checkboxes $global:UI.ListaApps | Where-Object {$_.IsChecked}).Count) {throw 'Apps preselecionados.'}
            if (@(Get-Checkboxes $global:UI.ListaApps).Count -ne @($global:CatalogoApps.aplicativos).Count) {throw 'Catalogo incompleto.'}
            Passou 'interface pessoal ligada, sem apps preselecionados'
            # Nova janela, mesmos controles, modo protegido e consultas locais substituidas.
            $global:Janela.Close()
            $global:ModoProtegido=$true
            $global:CatalogoUwp=Get-Content -LiteralPath (Join-Path $raiz 'data\uwp.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            function Verificar-EstadoAjustes { }
            function Verificar-EstadoUwp { }
            function Carregar-Programas { $global:ProgramasInstalados=@() }
            function Tem-Atualizacoes { return $null }
            $global:ProgramasInstalados=@()
            $global:Janela=[Windows.Markup.XamlReader]::Parse((Get-Content -LiteralPath (Join-Path $raiz 'src\ui\principal.xaml') -Raw -Encoding UTF8))
            $global:UI=@{}
            foreach ($nome in $nomesCtrl) { $global:UI[$nome]=$global:Janela.FindName($nome) }
            Ligar-Tudo
            foreach ($sufixo in @('Ajustes','Debloat','Desinstalar','Instalar','Config','Atualizacoes','Manutencao','Desfazer','Inicio')) {
                $botao=$global:UI['BotaoNav'+$sufixo]
                if (-not $botao.IsEnabled) {throw ('Navegacao bloqueada: '+$sufixo)}
                $botao.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                if ($global:PaginaAtual -ne ('Pagina'+$sufixo) -or $botao.Tag -ne 'ativo') {throw ('Clique nao mudou a aba: '+$sufixo)}
                foreach ($p in @('Inicio','Ajustes','Debloat','Desinstalar','Instalar','Config','Atualizacoes','Manutencao','Desfazer')) {
                    $esperada=if ($p -eq $sufixo) {'Visible'} else {'Collapsed'}
                    if ($global:Janela.FindName('Pagina'+$p).Visibility.ToString() -ne $esperada) {throw ('Visibilidade incorreta: '+$p)}
                }
            }
            foreach ($nome in @('BotaoAplicarAjustes','BotaoRemoverUwp','BotaoDesinstalarProg','BotaoVarrerRastros','BotaoInstalarApps','BotaoInstalarRecursos','BotaoFixRede','BotaoLimparTemp','BotaoDesfazer','BotaoCriarRestore','BotaoVerificarRelease','BotaoExportarPlano')) {
                if ($global:UI[$nome].IsEnabled) {throw ('Acao habilitada no modo protegido: '+$nome)}
            }
            Passou 'nove abas navegaveis no modo protegido e acoes bloqueadas'

        } finally {
            if ($global:Janela -and $global:Janela -ne $janelaAntes) {$global:Janela.Close()}
            $global:UI=$uiAntes; $global:Janela=$janelaAntes; $global:ModoProtegido=$modoAntes
            $global:CatalogoTweaks=$ctAntes; $global:CatalogoApps=$caAntes
        }
    }
} catch { Falhou 'interface pessoal' $_.Exception.Message }

# ---- politicas e diagnostico preservados no catalogo ----
Secao 'catalogo conservador'
try {
    $cat=Get-Content -LiteralPath (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($ajuste in $cat.tweaks) {
        if (-not $ajuste.compatibilidade) {throw ('Compatibilidade sem nota: '+$ajuste.id)}
        foreach ($acao in $ajuste.acoes) {
            if ($acao.caminho -match '\\PolicyManager\\' -or $acao.nome -in @('AllowTelemetry','DiagTrack','WerSvc')) {throw ('Acao de diagnostico/politica interna: '+$ajuste.id)}
            if ($acao.caminho -match '\\Policies\\' -and -not $ajuste.apenasManual) {throw ('Politica incluida em preset: '+$ajuste.id)}
        }
    }
    foreach ($perfil in @('essencial','gamer','notebook','privacidade','corporativo')) {
        if (@(Selecionar-TweaksPreset $perfil $cat $true).Count -lt 1) {throw ('Perfil vazio: '+$perfil)}
    }
    Passou 'presets sem politicas administrativas; diagnostico preservado'
} catch { Falhou 'catalogo conservador' $_.Exception.Message }

# ---- consultas de bateria e gargalos com dados sinteticos ----
Secao 'diagnosticos locais RC.8'
try {
    & {
        function Get-CimInstance {
            [CmdletBinding()] param([Parameter(Position=0)][string]$ClassName,[string]$Namespace,[string]$Filter)
            switch ($ClassName) {
                'Win32_Battery' {[pscustomobject]@{EstimatedChargeRemaining=55;BatteryStatus=2}}
                'BatteryStaticData' {[pscustomobject]@{InstanceName='interno';DesignedCapacity=50000}}
                'BatteryFullChargedCapacity' {[pscustomobject]@{InstanceName='interno';FullChargedCapacity=30000}}
                'Win32_PerfFormattedData_PerfOS_Processor' {[pscustomobject]@{PercentProcessorTime=95}}
                'Win32_OperatingSystem' {[pscustomobject]@{TotalVisibleMemorySize=100;FreePhysicalMemory=5}}
                'Win32_PerfFormattedData_PerfOS_Memory' {[pscustomobject]@{PageReadsPersec=7}}
                'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' {throw 'Contador indisponivel.'}
                default {throw 'Consulta inesperada.'}
            }
        }
        function Start-Sleep {param($Seconds)}
        $b=Obter-ResumoBateria
        if ($b -notmatch '30000' -or $b -notmatch '60%' -or $b -match 'interno') {throw 'Estimativa de bateria ou privacidade incorreta.'}
        $d=Medir-GargalosLocais 3
        if ($d.serie.Count -ne 3 -or $null -ne $d.serie[0].Fila_disco -or ($d.avisos -join ' ') -notmatch 'CPU elevada' -or ($d.avisos -join ' ') -notmatch 'Pouca RAM') {throw 'Diagnostico confundiu indisponibilidade ou amostras.'}
    }
    Passou 'bateria correlacionada e gargalos com contadores ausentes preservados'
} catch { Falhou 'diagnosticos locais RC.8' $_.Exception.Message }

# ---- matriz conservadora e identificacao MSI ----
Secao 'compatibilidade minima'
try {
    $cat=Get-Content -LiteralPath (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($a in $cat.tweaks) {if (-not $a.buildMinima -or -not $a.compatNivel) {throw ('Metadado ausente: '+$a.id)}}
    $a=$cat.tweaks | Where-Object {$_.id -eq 'caminhos-longos'}
    $ctx=[pscustomobject]@{build=10240;edicao='Professional';cliente=$true}
    if (Testar-CompatibilidadeAjuste $a $ctx) {throw 'Build antiga aceita.'}
    $ctx.build=14393
    if (-not (Testar-CompatibilidadeAjuste $a $ctx)) {throw 'Build minima recusada.'}
    $ctx.cliente=$false
    if (Testar-CompatibilidadeAjuste $a $ctx) {throw 'Servidor aceito.'}
    if (Testar-CompatibilidadeAjuste $a $null) {throw 'Contexto ausente aceito.'}
    $a=[pscustomobject]@{so='ambos';buildMinima=10240;edicoes=@('Enterprise')}
    $ctx.cliente=$true
    if (Testar-CompatibilidadeAjuste $a $ctx) {throw 'Edicao nao permitida aceita.'}
    $ctx.edicao='Enterprise'
    if (-not (Testar-CompatibilidadeAjuste $a $ctx)) {throw 'Edicao permitida recusada.'}
    Passou 'matriz recusa build/edicao/contexto incompativeis'
    $pr=Converter-EntradaPrograma ([pscustomobject]@{DisplayName='Teste';WindowsInstaller=1;PSChildName='{11111111-1111-1111-1111-111111111111}'})
    if (-not $pr.msi -or -not $pr.codigoMsi -or (Obter-ResumoMsi 'invalido') -notmatch 'indisponivel') {throw 'Identificacao MSI incorreta.'}
    Passou 'metadados MSI sem usar Win32_Product'
} catch { Falhou 'compatibilidade minima/MSI' $_.Exception.Message }

# ---- associacao de dispositivos e drivers sem expor identificadores ----
Secao 'inventario PnP'
try {
    & {
        function Get-PnpDevice {[CmdletBinding()]param([switch]$PresentOnly) if (-not $PresentOnly) {throw 'Esperava apenas presentes.'}; [pscustomobject]@{FriendlyName='Audio';InstanceId='ID-INTERNO';Status='Error';ConfigManagerErrorCode=28};[pscustomobject]@{FriendlyName='Video';InstanceId='ID-OUTRO';Status='OK'}}
        function Get-CimInstance {[CmdletBinding()]param([Parameter(Position=0)]$ClassName) [pscustomobject]@{DeviceID='ID-INTERNO';DriverProviderName='Fornecedor';DriverVersion='1.2';IsSigned=$true}}
        $msg=Obter-ResumoDriversPnP
        if ($msg -notmatch 'presentes: 2' -or $msg -notmatch 'OK: 1' -or $msg -notmatch 'Fornecedor' -or $msg -match 'ID-INTERNO|ID-OUTRO' -or $msg -notmatch 'associacao unica a driver: 1') {throw 'Correlacao PnP ou privacidade incorreta.'}
    }
    Passou 'dispositivos presentes correlacionados sem expor identificadores'
} catch {Falhou 'inventario PnP' $_.Exception.Message}

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
