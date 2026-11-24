# ============================================================
#  montar-portatil.ps1 - gera o otimizadorpc em arquivo unico
#  monta dist\otimizadorpc-portatil.ps1 com os modulos, os 3
#  catalogos json e a janela xaml EMBUTIDOS no corpo do script.
#  com isso, da pra levar o app pra outro pc copiando 2 arquivos
#  (o ps1 unico e o bat de atalho gerado junto).
#  como usar (nao precisa de admin): .\montar-portatil.ps1
#  obs: o arquivo final e gravado em utf8 com bom, pois o xaml
#  embutido tem acentos (powershell 5.1 exige bom pra ler certo).
#  o arquivo final suporta o modo cli igual ao original:
#  .\otimizadorpc-portatil.ps1 -Cli seguro -Simular
# ============================================================

param(
    # pasta de destino relativa a raiz do app
    [string]$PastaSaida = 'dist'
)

$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$pastaModulos = Join-Path $raiz 'src\modules'
$destino = Join-Path $raiz $PastaSaida
$arquivoFinal = Join-Path $destino 'otimizadorpc-portatil.ps1'

if (-not (Test-Path (Join-Path $raiz 'otimizadorpc.ps1'))) {
    Write-Host 'rode este script na raiz do app (ao lado do otimizadorpc.ps1).' -ForegroundColor Red
    exit 1
}

# ---- leitura das pecas ----

$principal = Get-Content -Path (Join-Path $raiz 'otimizadorpc.ps1') -Raw
$xaml      = Get-Content -Path (Join-Path $raiz 'src\ui\principal.xaml') -Raw -Encoding UTF8
$tweaks    = Get-Content -Path (Join-Path $raiz 'data\tweaks.json') -Raw -Encoding UTF8
$apps      = Get-Content -Path (Join-Path $raiz 'data\aplicativos.json') -Raw -Encoding UTF8
$uwp       = Get-Content -Path (Join-Path $raiz 'data\uwp.json') -Raw -Encoding UTF8

$modulos = @('comum.ps1', 'motor.ps1', 'consertos.ps1', 'desinstalador.ps1', 'sistema.ps1', 'gui.ps1')

# corta o otimizadorpc.ps1 nos pontos certos:
#   cabecalho ..... inicio ate '# ---- modulos do app ----' (param, elevacao, wpf)
#   bloco cli ..... de '# ---- modo cli' ate '# ---- janela ----'
#   cauda ......... de '# ---- liga todos os controles nomeados ----' ate o fim
# (os dot-sources viram modulos embutidos; catalogos e janela
#  ganham versao embutida escrita por este script)

$mModulos = $principal.IndexOf('# ---- modulos do app ----')
$mCli     = $principal.IndexOf('# ---- modo cli')
$mJanela  = $principal.IndexOf('# ---- janela ----')
$mCauda   = $principal.IndexOf('# ---- liga todos os controles nomeados ----')

$marcadores = @{
    'modulos' = $mModulos
    'cli'     = $mCli
    'janela'  = $mJanela
    'cauda'   = $mCauda
}
foreach ($nome in $marcadores.Keys) {
    if ($marcadores[$nome] -lt 0) {
        Write-Host ('nao achei o marcador do bloco ' + $nome + ' no otimizadorpc.ps1; o script mudou?') -ForegroundColor Red
        exit 1
    }
}

$cabecalho = $principal.Substring(0, $mModulos)
$blocoCli  = $principal.Substring($mCli, $mJanela - $mCli)
$cauda     = $principal.Substring($mCauda)

# sanity: a cauda precisa do array de controles e do ShowDialog
if ($cauda -notmatch '\$controles = @\(' -or $cauda -notmatch 'ShowDialog') {
    Write-Host 'a cauda do otimizadorpc.ps1 nao parece completa (faltam $controles ou ShowDialog).' -ForegroundColor Red
    exit 1
}

# here-string nao pode conter linha iniciando com aspas+arroba
$cheques = @{
    'xaml'   = $xaml
    'tweaks' = $tweaks
    'apps'   = $apps
    'uwp'    = $uwp
}
foreach ($nome in $cheques.Keys) {
    if ($cheques[$nome] -match "(?m)^'@") {
        Write-Host ('conteudo de ' + $nome + ' tem linha iniciando com aspas+arroba; here-string nao suporta.') -ForegroundColor Red
        exit 1
    }
}

# ---- montagem (em memoria) ----

$sb = New-Object System.Text.StringBuilder
function Add-Texto { param([string]$Texto) [void]$script:sb.AppendLine($Texto) }

Add-Texto '# ============================================================'
Add-Texto '#  otimizadorpc-portatil.ps1 - ARQUIVO GERADO por montar-portatil.ps1'
Add-Texto '#  nao edite aqui: edite os fontes e mande montar de novo.'
Add-Texto '# ============================================================'
Add-Texto ''
Add-Texto $cabecalho.TrimEnd()
Add-Texto ''

foreach ($m in $modulos) {
    $caminho = Join-Path $pastaModulos $m
    if (-not (Test-Path $caminho)) {
        Write-Host ('modulo nao encontrado: ' + $caminho) -ForegroundColor Red
        exit 1
    }
    Add-Texto '# ------------------------------------------------------------'
    Add-Texto ('# modulo embutido: ' + $m)
    Add-Texto '# ------------------------------------------------------------'
    $textoModulo = (Get-Content -Path $caminho -Raw).TrimEnd()
    if ($m -eq 'comum.ps1') {
        $textoModulo = $textoModulo.Replace('$global:PastaApp      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)', '$global:PastaApp = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:ProgramData ''otimizadorpc'' }')
    }
    Add-Texto $textoModulo
    Add-Texto ''
}

# arquivo unico: nao existe src\ ao redor; define as pastas pelo local do ps1
Add-Texto '# ---- pastas do app (arquivo unico) ----'
Add-Texto '$global:PastaDados = $global:PastaApp'
Add-Texto '$travaInstancia = $null'
Add-Texto 'try {'
Add-Texto '    Inicializar-ModoOtimizador -Diagnostico:($Diagnostico -or ($Cli -and $Simular))'
Add-Texto '    if ($Cli -and -not $Simular -and $global:ModoProtegido) { throw ''Preset real indisponivel no modo protegido. Use -Cli essencial -Simular.'' }'
Add-Texto '    if (-not $global:ModoProtegido) {'
Add-Texto '        Garantir-Pastas'
Add-Texto '        $travaInstancia = Obter-TravaInstancia'
Add-Texto '    }'
Add-Texto ''

# catalogos embutidos (nao precisa da pasta data ao lado)
Add-Texto '# ---- catalogos embutidos ----'
Add-Texto '$jsonTweaks = @'''
Add-Texto $tweaks.TrimEnd()
Add-Texto "'@"
Add-Texto ''
Add-Texto '$jsonApps = @'''
Add-Texto $apps.TrimEnd()
Add-Texto "'@"
Add-Texto ''
Add-Texto '$jsonUwp = @'''
Add-Texto $uwp.TrimEnd()
Add-Texto "'@"
Add-Texto ''
Add-Texto 'try {'
Add-Texto '    $global:CatalogoTweaks = $jsonTweaks | ConvertFrom-Json'
Add-Texto '    $global:CatalogoApps   = $jsonApps | ConvertFrom-Json'
Add-Texto '    $global:CatalogoUwp    = $jsonUwp | ConvertFrom-Json'
Add-Texto '} catch {'
Add-Texto '    $msg = ''Falha ao ler os catalogos embutidos: '' + $_.Exception.Message'
Add-Texto '    if ($Cli) { Write-Host $msg -ForegroundColor Red } else {'
Add-Texto '        [System.Windows.MessageBox]::Show($msg, ''OtimizadorPC'')'
Add-Texto '    }'
Add-Texto '    exit 1'
Add-Texto '}'
Add-Texto ''
Add-Texto '# ---- tweaks custom (arquivos .reg na pasta custom\ ao lado do app) ----'
Add-Texto '$tweaksCustom = if ($global:ModoProtegido) { @() } else { @(Carregar-TweaksCustom) }'
Add-Texto '$global:CatalogoTweaks.tweaks = @($global:CatalogoTweaks.tweaks) + $tweaksCustom'
Add-Texto ''
Add-Texto $blocoCli.TrimEnd()
Add-Texto ''

# janela embutida (o xaml via junto, dentro do arquivo)
Add-Texto '# ---- janela embutida ----'
Add-Texto '$xamlTexto = @'''
Add-Texto $xaml.TrimEnd()
Add-Texto "'@"
Add-Texto 'try {'
Add-Texto '    Ler-TemaOtimizador'
Add-Texto '    $xamlTexto = Converter-TemaXaml $xamlTexto $global:TemaOtimizador'
Add-Texto '    $leitor = New-Object System.IO.StringReader($xamlTexto)'
Add-Texto '    $leitorXml = [System.Xml.XmlReader]::Create($leitor)'
Add-Texto '    $global:Janela = [Windows.Markup.XamlReader]::Load($leitorXml)'
Add-Texto '    $leitorXml.Close()'
Add-Texto '    $leitor.Close()'
Add-Texto '} catch {'
Add-Texto '    $msg = ''Falha ao montar a janela (XAML embutido): '' + $_.Exception.Message'
Add-Texto '    [System.Windows.MessageBox]::Show($msg, ''OtimizadorPC'') | Out-Null'
Add-Texto '    exit 1'
Add-Texto '}'
Add-Texto ''
Add-Texto $cauda.TrimEnd()

# grava o arquivo final em utf8 (com bom: powershell 5.1 le os acentos do xaml)
if (-not (Test-Path $destino)) { New-Item -Path $destino -ItemType Directory -Force | Out-Null }
$final = $sb.ToString()
Set-Content -Path $arquivoFinal -Value $final -Encoding UTF8
$kb = [math]::Round((Get-Item $arquivoFinal).Length / 1KB, 1)
Write-Host ('OK: ' + $arquivoFinal + ' (' + $kb + ' KB)') -ForegroundColor Green

# Script unico para distribuicao online. Nao depende de caminho fisico.
$memoria = $final
$inicioElev = $memoria.IndexOf('# ---- auto-elevacao para administrador ----')
$fimElev = $memoria.IndexOf('# ---- assemblies do wpf ----')
if ($inicioElev -lt 0 -or $fimElev -le $inicioElev) { throw 'Marcadores de elevacao ausentes.' }
$novoCabecalho = @'
# ---- execucao em memoria: sem elevacao automatica ----
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use Windows PowerShell 5.1.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Use Windows PowerShell em modo STA.' }
$ErrorActionPreference = 'Continue'

'@
$memoria = $memoria.Substring(0, $inicioElev) + $novoCabecalho + $memoria.Substring($fimElev)
$memoria = $memoria.Replace('$global:PastaApp = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:ProgramData ''otimizadorpc'' }', '$global:PastaApp = Join-Path $env:ProgramData ''otimizadorpc''')
$memoria = $memoria -replace '(\[switch\]\$Simular)\s*\r?\n\)', ('$1,' + [Environment]::NewLine + '    [switch]$ValidarInterface' + [Environment]::NewLine + ')')
$memoria = $memoria.Replace('if ($ok) { exit 0 } else { exit 1 }', 'if (-not $ok) { throw ''Preset terminou com erros.'' }; return')
$memoria = $memoria.Replace('exit 1', 'throw ''Falha na inicializacao do OtimizadorPC.''')
$memoria = $memoria.Replace('# ---- monta a interface e mostra ----', 'if ($ValidarInterface) { Ligar-Tudo; $global:Janela.Close(); Write-Host ''Interface WPF e ligacoes validadas.''; return }' + [Environment]::NewLine + '# ---- monta a interface e mostra ----')
# O modo remoto nao carrega arquivos .reg locais; use o portatil para custom.
$memoria = $memoria.Replace('$tweaksCustom = if ($global:ModoProtegido) { @() } else { @(Carregar-TweaksCustom) }', '$tweaksCustom = @()')
$arquivoOnline = Join-Path $destino 'otimizadorpc.ps1'
[IO.File]::WriteAllText($arquivoOnline, $memoria, (New-Object Text.UTF8Encoding($false)))
$errosOnline = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($arquivoOnline, [ref]$null, [ref]$errosOnline)
if (@($errosOnline).Count -gt 0) { throw ('Script online invalido: ' + ($errosOnline.Message -join '; ')) }
$hashOnline = (Get-FileHash -LiteralPath $arquivoOnline -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($arquivoOnline + '.sha256'), ($hashOnline + '  otimizadorpc.ps1' + [Environment]::NewLine), [Text.Encoding]::ASCII)
Write-Host ('OK: ' + $arquivoOnline + ' (execucao em memoria)')

# bat de atalho: dois cliques e o app abre (pede uac e abre a janela)
$bat = Join-Path $destino 'rodar-portatil.bat'
$batConteudo = "@echo off`r`npowershell.exe -NoProfile -File ""%~dp0otimizadorpc-portatil.ps1""`r`nif errorlevel 1 pause`r`n"
Set-Content -Path $bat -Value $batConteudo -Encoding ASCII
Write-Host ('OK: ' + $bat) -ForegroundColor Green
Write-Host ''
Write-Host 'copie esses 2 arquivos pra qualquer pasta e rode o bat (ou chame o ps1 direto).'
Write-Host 'modo cli continua funcionando: otimizadorpc-portatil.ps1 -Cli balanceado -Simular'
