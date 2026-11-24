# ============================================================
#  testes\integracao.ps1 - teste de integracao real do motor
#  SO pra ambiente descartavel (runner do github actions):
#  aplica o preset seguro DE VERDADE, confere o journal
#  crash-safe gravado a cada acao, desfaz a sessao inteira
#  pelo caminho real do app (Reverter-Sessao) e confere que o
#  registro voltou exatamente ao estado anterior.
#  NAO rode na sua maquina pessoal: ele altera e desfaz.
# ============================================================

$ErrorActionPreference = 'Continue'

# raiz do repo (este script vive em testes\)
$raiz = Split-Path -Parent $PSScriptRoot

# assemblies do wpf antes de carregar os modulos: comum.ps1
# usa o Dispatcher do WPF dentro do Atualizar-UI
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
} catch {
    Write-Host ('FALHOU: nao carregou WPF: ' + $_.Exception.Message)
    exit 1
}

# comum.ps1 define as pastas ($global:PastaApp e cia) a partir
# do PROPRIO local dele (src\modules -> raiz), entao da pra
# carregar de qualquer lugar. motor traz o executor e o desfazer.
. (Join-Path $raiz 'src\modules\comum.ps1')
. (Join-Path $raiz 'src\modules\motor.ps1')

Garantir-Pastas

# mesmo override de log do modo cli: console + arquivo
function global:Log {
    param([string]$Mensagem, [switch]$Erro)
    $prefixo = ''
    if ($Erro) { $prefixo = '[ERRO] '; $global:ErrosSessao++ }
    $linha = ("{0}[{1}] {2}" -f $prefixo, (Get-Date -Format 'HH:mm:ss'), $Mensagem)
    Write-Host $linha
    try { Add-Content -Path $global:ArquivoLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { }
}

try {
    $global:CatalogoTweaks = Ler-JSON (Join-Path $global:PastaDados 'tweaks.json')
} catch {
    Log ('FALHOU: nao leu o catalogo de tweaks: ' + $_.Exception.Message) -Erro
    exit 1
}

# runner comeca limpo; se sobrou journal de outro teste, apaga
Get-ChildItem -Path $global:PastaDesfazer -Filter '*.json' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Log ('CI integracao: pasta do journal = ' + $global:PastaDesfazer)

# ---- 1. aplica o preset seguro de verdade ----
Log 'CI: aplicando preset seguro DE VERDADE...'
$ok = Aplicar-Preset -Nivel 'seguro'
Log ('CI: Aplicar-Preset terminou com retorno = ' + $ok + ' (ponto de restauracao costuma nao existir em runner; nao e falha deste teste)')

# ---- 2. journal crash-safe gravado a cada acao ----
$journals = @(Get-ChildItem -Path $global:PastaDesfazer -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($journals.Count -eq 0) { Log 'FALHOU: nenhum journal gravado apos aplicar o preset' -Erro; exit 1 }
$arquivo = $journals[0].FullName
$json = Ler-JSON $arquivo
$itens = @($json.itens)
Log ('CI: journal ' + (Split-Path -Leaf $arquivo) + ' com ' + $itens.Count + ' item(ns)')
if ($itens.Count -eq 0) { Log 'FALHOU: journal vazio' -Erro; exit 1 }

$tiposOk = @('registro','reg-import','servico','comando','appx','recurso','energia','tarefa','regra-firewall','path-entrada','quarantena-arquivo','quarantena-registro')
foreach ($it in $itens) {
    if ($tiposOk -notcontains [string]$it.tipo) { Log ('FALHOU: item com tipo desconhecido: ' + [string]$it.tipo) -Erro; exit 1 }
}
Log 'CI ok: journal com itens de tipos validos'

# ---- 3. acha uma acao de registro no journal ----
$alvo = $null
foreach ($it in $itens) {
    if ([string]$it.tipo -eq 'registro') { $alvo = $it; break }
}
if ($null -eq $alvo) { Log 'FALHOU: nenhuma acao de registro no journal do preset seguro' -Erro; exit 1 }
Log ('CI alvo do teste: ' + [string]$alvo.caminho + '\' + [string]$alvo.nome)

# o valor aplicado tem que existir agora
$aplicado = Ler-ValorRegistro -CaminhoPS ([string]$alvo.caminho) -Nome ([string]$alvo.nome)
if (-not $aplicado.existia) { Log 'FALHOU: valor de registro nao existe depois de aplicar' -Erro; exit 1 }
Log 'CI ok: valor existe depois de aplicar'

# ---- 4. desfaz a sessao inteira pelo caminho real do app ----
Log 'CI: revertendo a sessao inteira...'
Reverter-Sessao $arquivo

# ---- 5. o registro voltou exatamente ao estado original? ----
$dps = Ler-ValorRegistro -CaminhoPS ([string]$alvo.caminho) -Nome ([string]$alvo.nome)
if ($alvo.existia) {
    $original = ($alvo.valorAnterior | ConvertFrom-Json)
    $tipoAnterior = [string]$alvo.tipoAnterior
    if (-not $dps.existia) { Log 'FALHOU: o valor sumiu depois do desfazer' -Erro; exit 1 }
    $iguais = $false
    if ($tipoAnterior -eq 'DWord') { $iguais = ([int]$dps.valor -eq [int]$original) }
    elseif ($tipoAnterior -eq 'QWord') { $iguais = ([long]$dps.valor -eq [long]$original) }
    else { $iguais = ([string]$dps.valor -eq [string]$original) }
    if (-not $iguais) { Log ('FALHOU: valor nao voltou ao original: atual=' + $dps.valor + ' original=' + $original) -Erro; exit 1 }
    Log 'CI ok: valor voltou exatamente ao original'
} else {
    if ($dps.existia) { Log 'FALHOU: valor que nao existia antes ficou existindo' -Erro; exit 1 }
    Log 'CI ok: valor criado pelo preset foi removido pelo desfazer'
}

# ---- 6. journal marcado como revertido ----
if (-not (Test-Path ($arquivo + '.revertido'))) { Log 'FALHOU: journal nao foi renomeado para .revertido' -Erro; exit 1 }
Log 'CI ok: journal renomeado para .revertido'

# ---- 7. preserva tipos reais do registro, inclusive variaveis nao expandidas ----
$nomeChave = 'Software\OtimizadorPC-CI-' + [guid]::NewGuid().ToString('N')
$caminhoTeste = 'HKCU:\' + $nomeChave
try {
    $chave = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomeChave)
    try {
        $chave.SetValue('expand', '%TEMP%\arquivo', [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $chave.SetValue('multi', [string[]]@('um','dois'), [Microsoft.Win32.RegistryValueKind]::MultiString)
        $chave.SetValue('bin', [byte[]]@(0,255,12), [Microsoft.Win32.RegistryValueKind]::Binary)
    } finally { $chave.Dispose() }
    Iniciar-Sessao 'ci-tipos-registro'
    foreach ($nome in @('expand','multi','bin')) {
        Executar-Acao ([pscustomobject]@{ tipo='registro'; caminho=$caminhoTeste; nome=$nome; tipoValor='String'; dados='alterado' }) 'teste de tipo'
    }
    $journalTipos = Salvar-Sessao
    if (-not $journalTipos -or -not (Reverter-Sessao $journalTipos)) { throw 'Nao reverteu journal de tipos.' }
    $expand = Ler-ValorRegistro $caminhoTeste 'expand'
    $multi = Ler-ValorRegistro $caminhoTeste 'multi'
    $bin = Ler-ValorRegistro $caminhoTeste 'bin'
    if ($expand.tipo -ne 'ExpandString' -or $expand.valor -ne '%TEMP%\arquivo' -or
        $multi.tipo -ne 'MultiString' -or ($multi.valor -join ',') -ne 'um,dois' -or
        $bin.tipo -ne 'Binary' -or ($bin.valor -join ',') -ne '0,255,12') {
        throw 'Tipos ou dados originais nao foram preservados.'
    }
    Log 'CI ok: tipos reais do registro preservados'
} catch {
    Log ('FALHOU: ' + $_.Exception.Message) -Erro
    exit 1
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeChave, $false)
}

Log 'CI INTEGRACAO: todos os testes passaram'
exit 0
