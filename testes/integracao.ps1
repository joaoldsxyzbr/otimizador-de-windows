# ============================================================
#  testes\integracao.ps1 - teste de integracao real do motor
#  SO pra ambiente descartavel (runner do github actions):
#  aplica o preset seguro DE VERDADE, confere o journal
#  crash-safe gravado a cada acao, desfaz a sessao inteira
#  pelo caminho real do app (Reverter-Sessao) e confere que o
#  registro voltou exatamente ao estado anterior.
#  NAO rode na sua maquina pessoal: ele altera e desfaz.
# ============================================================

param([switch]$ConfirmarAmbienteDescartavel)

if ($env:GITHUB_ACTIONS -ne 'true' -and -not $ConfirmarAmbienteDescartavel) {
    throw 'Teste altera o Windows. Execute somente em runner descartavel ou VM com -ConfirmarAmbienteDescartavel.'
}
$ErrorActionPreference = 'Continue'
# Teste de integracao ja exige VM/runner descartavel. Nao altera o entrypoint.
$global:ModoProtegido=$false

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
. (Join-Path $raiz 'testes\contexto-autorizacao.ps1')
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

# Nunca apague journals reais para preparar um teste.
if (@(Get-ChildItem -LiteralPath $global:PastaDesfazer -Filter '*.json' -ErrorAction Stop).Count -gt 0) { throw 'Existem journals pendentes; use uma VM limpa.' }

Log ('CI integracao: pasta do journal = ' + $global:PastaDesfazer)

# ---- 1. aplica o preset seguro de verdade ----
Log 'CI: aplicando preset seguro DE VERDADE...'
# Windows Server dos runners nao suporta System Restore. O stub e local
# a este teste descartavel; o produto continua exigindo ponto confirmado.
$ok = & {
    function Criar-PontoRestauracao { Log 'CI: stub de ponto de restauracao; teste apenas do motor e journal.'; return $true }
    function Obter-ContextoAjustes {[pscustomobject]@{build=26100;edicao='Professional';cliente=$true}}
    Aplicar-Preset -Nivel 'seguro'
}
if (-not $ok) { throw 'Preset do teste descartavel terminou com falhas.' }
Log 'CI: preset aplicado; verificando journal e reversao reais.'

# ---- 2. journal crash-safe gravado a cada acao ----
$journals = @(Get-ChildItem -Path $global:PastaDesfazer -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($journals.Count -eq 0) { Log 'FALHOU: nenhum journal gravado apos aplicar o preset' -Erro; exit 1 }
$arquivo = $journals[0].FullName
$json = Ler-JSON $arquivo
if ($json.versaoEsquema -ne 2 -or -not $json.contexto.usuarioSid -or -not $json.contexto.maquina) {throw 'Journal sem esquema ou identidade.'}
Confirmar-ContextoJournal $json
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
if (-not (Reverter-Sessao $arquivo)) { Log 'FALHOU: reversao do preset' -Erro; exit 1 }

# ---- 5. confere todos os valores originais (primeiro snapshot de cada valor) ----
$vistos = @{}
foreach ($it in $itens) {
    if ($it.tipo -eq 'servico') {
        $svc = Obter-EstadoServico $it.nome
        if ($svc.tipo -ne $it.tipoAnterior -or $svc.estado -ne $it.estadoAnterior -or $svc.atraso -ne $it.atrasoAnterior) { throw ('Servico nao restaurado: ' + $it.nome) }
        Log ('CI ok: servico restaurado: ' + $it.nome)
    }
    if ($it.tipo -ne 'registro') { continue }
    $id = $it.caminho + '|' + $it.nome
    if ($vistos.ContainsKey($id)) { continue }
    $vistos[$id] = $true
    $atual = Ler-ValorRegistro -CaminhoPS $it.caminho -Nome $it.nome
    if (-not (Registro-Corresponde $atual ([bool]$it.existia) $it.tipoAnterior $it.valorAnteriorEstruturado.valor)) {
        Log ('FALHOU: valor original nao restaurado: ' + $id) -Erro
        exit 1
    }
}
Log ('CI ok: ' + $vistos.Count + ' valores distintos do preset restaurados')

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
        $chave.SetValue('', 'valor padrao', [Microsoft.Win32.RegistryValueKind]::String)
    } finally { $chave.Dispose() }
    Iniciar-Sessao 'ci-tipos-registro'
    foreach ($nome in @('expand','multi','bin','')) {
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
    if ((Ler-ValorRegistro $caminhoTeste '').valor -cne 'valor padrao') { throw 'Valor padrao nao restaurado.' }
    Log 'CI ok: tipos reais e valor padrao do registro preservados'
} catch {
    Log ('FALHOU: ' + $_.Exception.Message) -Erro
    exit 1
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeChave, $false)
}

# ---- 8. remover e restaurar chave de teste pelo fluxo real da aba Desinstalar ----
. (Join-Path $raiz 'src\modules\desinstalador.ps1')
$nomeQuar = 'Software\OtimizadorPC-CI-Quar-' + [guid]::NewGuid().ToString('N')
$nomeRegistroOriginal='Software\Microsoft\Windows\CurrentVersion\Uninstall\OtimizadorPC-CI-'+[guid]::NewGuid().ToString('N')
$quarTeste = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-quar-ci-' + [guid]::NewGuid().ToString('N'))
$quarAnterior = $global:PastaQuarantena
try {
    $global:PastaQuarantena = $quarTeste
    $chave = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomeQuar)
    try { $chave.SetValue('teste','preservar') } finally { $chave.Dispose() }
    $caminhoQuar = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\' + $nomeQuar
    $lb = New-Object System.Windows.Controls.ListBox
    $linha = New-Object System.Windows.Controls.ListBoxItem
    $linha.Tag = [pscustomobject]@{ tipo='chave'; caminho=$caminhoQuar }
    $marca = New-Object System.Windows.Controls.CheckBox
    $marca.IsChecked = $true
    $linha.Content = $marca
    [void]$lb.Items.Add($linha)
    $global:UI = @{ ListaRastros=$lb; RotuloRastros=(New-Object System.Windows.Controls.TextBlock) }
    $entrada=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomeRegistroOriginal)
    try { $entrada.SetValue('DisplayName','teste descartavel'); $entrada.SetValue('UninstallString','nao-executar.exe') } finally { $entrada.Dispose() }
    $global:ProgVarredura=Converter-EntradaPrograma (Get-ItemProperty -LiteralPath ('HKCU:\'+$nomeRegistroOriginal) -ErrorAction Stop)
    $recusou=$false
    try { $null=Confirmar-ProgramaAusenteParaLimpeza $global:ProgVarredura } catch { $recusou=$_.Exception.Message -match 'ainda existe' }
    if (-not $recusou -or -not (Test-Path -LiteralPath $caminhoQuar)) { throw 'Limpeza de programa registrado nao recusada.' }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeRegistroOriginal,$false)
    Log 'CI ok: limpeza bloqueada enquanto registro de desinstalacao existe'
    & {
        function Perguntar { param($Titulo,$Mensagem) return ($Titulo -eq 'Apagar rastros') }
        function Avisar { param($Titulo,$Mensagem) throw ('Aviso inesperado: ' + $Titulo) }
        Clique-ApagarRastros
    }
    if (Test-Path -LiteralPath $caminhoQuar) { throw 'Chave descartavel nao foi removida.' }
    $journalQuar = Salvar-Sessao
    $jsonQuar = Ler-JSON $journalQuar
    if (@($jsonQuar.itens).Count -ne 1 -or $jsonQuar.itens[0].tipo -ne 'quarantena-registro' -or -not (Test-Path -LiteralPath $jsonQuar.itens[0].arquivoReg)) { throw 'Backup ou journal de quarentena invalido.' }
    if (-not (Reverter-Sessao $journalQuar)) { throw 'Nao reverteu a quarentena.' }
    if ((Get-ItemProperty -LiteralPath $caminhoQuar -Name teste -ErrorAction Stop).teste -ne 'preservar') { throw 'Dado restaurado incorreto.' }
    Log 'CI ok: caixa marcada, exportacao, remocao real, journal e restauracao de chave'
    if ((Get-ItemProperty -LiteralPath $caminhoQuar -Name teste -ErrorAction Stop).teste -ne 'preservar') { throw 'Falha de verificacao apos importacao.' }
} catch {
    Log ('FALHOU: quarentena real: ' + $_.Exception.Message) -Erro
    exit 1
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeRegistroOriginal,$false)
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeQuar, $false)
    if (Test-Path -LiteralPath $quarTeste) { Remove-Item -LiteralPath $quarTeste -Recurse -Force }
    $global:PastaQuarantena = $quarAnterior
    $global:UI = @{}
}

# ---- 9. conflito com alteracao posterior nao deve sobrescrever dados ----
$nomeConflito = 'Software\OtimizadorPC-CI-Conflito-' + [guid]::NewGuid().ToString('N')
$caminhoConflito = 'HKCU:\' + $nomeConflito
try {
    $chave = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomeConflito)
    try { $chave.SetValue('teste','original') } finally { $chave.Dispose() }
    Iniciar-Sessao 'ci-conflito'
    Executar-Acao ([pscustomobject]@{ tipo='registro'; caminho=$caminhoConflito; nome='teste'; tipoValor='String'; dados='aplicado' }) 'teste conflito'
    $journalConflito = Salvar-Sessao
    Set-ItemProperty -LiteralPath $caminhoConflito -Name teste -Value 'mudanca posterior' -ErrorAction Stop
    if (Reverter-Sessao $journalConflito) { throw 'Conflito foi tratado como sucesso.' }
    if ((Get-ItemProperty -LiteralPath $caminhoConflito -Name teste).teste -ne 'mudanca posterior') { throw 'Mudanca posterior sobrescrita.' }
    if ((Ler-JSON $journalConflito).itens[0].estadoReversao -ne 'em_andamento') { throw 'Journal de conflito nao preservado.' }
    Log 'CI ok: conflito no registro preserva mudanca posterior'
    if (Reverter-Sessao $journalConflito) {throw 'Reversao incerta repetiu ou ignorou conflito.'}
    Set-ItemProperty -LiteralPath $caminhoConflito -Name teste -Value 'original' -ErrorAction Stop
    if (-not (Reverter-Sessao $journalConflito)) {throw 'Nao reconciliou estado anterior confirmado.'}
    $reconciliado=Ler-JSON ($journalConflito+'.revertido')
    if (-not $reconciliado.itens[0].reconciliadoEm -or $reconciliado.itens[0].estadoReversao -ne 'concluido' -or (Ler-ValorRegistro $caminhoConflito 'teste').valor -ne 'original') {throw 'Reconciliacao nao registrada ou alterou alvo.'}
    Log 'CI ok: reversao incerta reconciliada sem repetir escrita'
} catch {
    Log ('FALHOU: conflito no registro: ' + $_.Exception.Message) -Erro
    exit 1
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeConflito, $false)
}

# ---- 10. arquivo real: quarentena, hash e conflito no destino ----
$dirArquivo = Join-Path $env:LOCALAPPDATA ('OtimizadorPC-CI-Arquivo-' + [guid]::NewGuid().ToString('N'))
$dirBackup = Join-Path $global:PastaQuarantena ('ci-arquivo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $dirArquivo -ItemType Directory -ErrorAction Stop | Out-Null
    Garantir-PastaPrivada $dirBackup
    $origem = Join-Path $dirArquivo 'dados [teste].bin'
    [IO.File]::WriteAllBytes($origem,[byte[]]@(0,1,2,255))
    $hash = (Get-FileHash -LiteralPath $origem -Algorithm SHA256).Hash
    Iniciar-Sessao 'ci-arquentena-arquivo'
    Apagar-Rastro ([pscustomobject]@{ tipo='arquivo'; caminho=$origem }) $dirBackup 1
    $arq = Salvar-Sessao
    $item = (Ler-JSON $arq).itens[0]
    if ($item.hashBackup -ine $hash -or $item.estadoAplicacao -ne 'confirmado' -or -not $item.idOperacao) {throw 'Journal sem hash ou efeito confirmado.'}
    if ((Test-Path -LiteralPath $origem) -or (Get-FileHash -LiteralPath $item.destino -Algorithm SHA256).Hash -ne $hash) { throw 'Movimentacao incorreta.' }
    if (-not (Reverter-Sessao $arq) -or (Get-FileHash -LiteralPath $origem -Algorithm SHA256).Hash -ne $hash) { throw 'Arquivo nao restaurado byte a byte.' }
    Log 'CI ok: arquivo com caracteres especiais restaurado byte a byte'
    Iniciar-Sessao 'ci-conflito-arquivo'
    Apagar-Rastro ([pscustomobject]@{ tipo='arquivo'; caminho=$origem }) $dirBackup 2
    $arq = Salvar-Sessao
    [IO.File]::WriteAllText($origem,'arquivo novo')
    if (Reverter-Sessao $arq) { throw 'Conflito de arquivo aceito.' }
    if ([IO.File]::ReadAllText($origem) -cne 'arquivo novo') { throw 'Arquivo novo sobrescrito.' }
    $item = (Ler-JSON $arq).itens[0]
    if ((Get-FileHash -LiteralPath $item.destino -Algorithm SHA256).Hash -ne $hash) { throw 'Backup perdido no conflito.' }
    Log 'CI ok: conflito preserva arquivo novo e backup'
    $origem2=Join-Path $dirArquivo 'integridade.bin'
    [IO.File]::WriteAllText($origem2,'original')
    Iniciar-Sessao 'ci-integridade'
    Apagar-Rastro ([pscustomobject]@{tipo='arquivo';caminho=$origem2}) $dirBackup 3
    $arq2=Salvar-Sessao
    $item2=(Ler-JSON $arq2).itens[0]
    [IO.File]::WriteAllText($item2.destino,'alterado')
    if ((Reverter-Sessao $arq2) -or (Test-Path -LiteralPath $origem2)) {throw 'Backup alterado foi restaurado.'}
    Log 'CI ok: hash divergente impede restauracao'
    # Folder manifest covers nested content and empty directories, and detects tampering.
    $pasta=Join-Path $dirArquivo 'pasta [teste]'
    New-Item -ItemType Directory -Path (Join-Path $pasta 'vazia') -Force -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText((Join-Path $pasta 'dados.txt'),'original')
    $manifesto=Obter-HashPastaQuarentena $pasta
    Iniciar-Sessao 'ci-pasta'
    Apagar-Rastro ([pscustomobject]@{tipo='pasta';caminho=$pasta}) $dirBackup 4
    $arq3=Salvar-Sessao
    $item3=(Ler-JSON $arq3).itens[0]
    if ($item3.hashBackup -ne $manifesto -or $item3.estadoAplicacao -ne 'confirmado' -or (Test-Path -LiteralPath $pasta)) {throw 'Movimentacao de pasta nao confirmada.'}
    if (-not (Reverter-Sessao $arq3) -or (Obter-HashPastaQuarentena $pasta) -ne $manifesto) {throw 'Pasta nao restaurada conforme manifesto.'}
    Iniciar-Sessao 'ci-pasta-alterada'
    Apagar-Rastro ([pscustomobject]@{tipo='pasta';caminho=$pasta}) $dirBackup 5
    $arq4=Salvar-Sessao
    $item4=(Ler-JSON $arq4).itens[0]
    [IO.File]::WriteAllText((Join-Path $item4.destino 'dados.txt'),'alterado')
    if ((Reverter-Sessao $arq4) -or (Test-Path -LiteralPath $pasta)) {throw 'Pasta alterada restaurada.'}
    Log 'CI ok: manifesto de pasta verifica estrutura e recusa divergencia'

} catch {
    Log ('FALHOU: quarentena de arquivo: ' + $_.Exception.Message) -Erro
    exit 1
} finally {
    foreach ($pasta in @($dirArquivo,$dirBackup)) {
        if (Test-Path -LiteralPath $pasta) { Remove-Item -LiteralPath $pasta -Recurse -Force }
    }
}

# ---- 11. tarefa real descartavel, sem gatilhos ----
$nomeTarefa = 'OtimizadorPC-CI-' + [guid]::NewGuid().ToString('N')
try {
    $acaoTarefa = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\cmd.exe') -Argument '/c exit 0'
    Register-ScheduledTask -TaskName $nomeTarefa -TaskPath '\' -Action $acaoTarefa -ErrorAction Stop | Out-Null
    Iniciar-Sessao 'ci-tarefa'
    $recusou=$false
    try {Desativar-TarefaComJournal '\' $nomeTarefa} catch {$recusou=$_.Exception.Message -match 'Tarefa sem identidade'}
    if (-not $recusou -or (Get-ScheduledTask -TaskName $nomeTarefa -TaskPath '\').State -ne 'Ready' -or $global:SessaoItens.Count) {throw 'Tarefa desconhecida alterada pelo app.'}
    $entrada=[pscustomobject]@{tipo='tarefa';tarefaPath='\';tarefaNome=$nomeTarefa;estadoAnterior='Ready';estadoDepois='Disabled';assinatura=(Obter-AssinaturaTarefa '\' $nomeTarefa)}
    Registrar-Jornal $entrada
    Disable-ScheduledTask -TaskName $nomeTarefa -TaskPath '\' -ErrorAction Stop | Out-Null
    Confirmar-EfeitoJournal $entrada
    $arq=Salvar-Sessao
    if ((Get-ScheduledTask -TaskName $nomeTarefa -TaskPath '\').State -ne 'Disabled') {throw 'Fixture de tarefa nao desativada.'}
    if (-not (Reverter-Sessao $arq)) { throw 'Tarefa nao revertida.' }
    if ((Get-ScheduledTask -TaskName $nomeTarefa -TaskPath '\').State -ne 'Ready') { throw 'Tarefa nao reativada.' }
    Log 'CI ok: nova desativacao de tarefa desconhecida recusada e snapshot anterior restaurado'
    Iniciar-Sessao 'ci-tarefa-incerta'
    $entrada=[pscustomobject]@{tipo='tarefa';tarefaPath='\';tarefaNome=$nomeTarefa;estadoAnterior='Ready';estadoDepois='Disabled';assinatura=(Obter-AssinaturaTarefa '\' $nomeTarefa)}
    Registrar-Jornal $entrada
    Disable-ScheduledTask -TaskName $nomeTarefa -TaskPath '\' -ErrorAction Stop | Out-Null
    Confirmar-EfeitoJournal $entrada
    $arq=Salvar-Sessao
    $j=Ler-JSON $arq
    $j.itens[0] | Add-Member -NotePropertyName estadoReversao -NotePropertyValue 'em_andamento' -Force
    Gravar-JournalSeguro -Arquivo $arq -Objeto $j
    if (Reverter-Sessao $arq) {throw 'Tarefa ainda desativada reconciliada.'}
    Enable-ScheduledTask -TaskName $nomeTarefa -TaskPath '\' -ErrorAction Stop | Out-Null
    if (-not (Reverter-Sessao $arq) -or -not (Ler-JSON ($arq+'.revertido')).itens[0].reconciliadoEm) {throw 'Tarefa original nao reconciliada.'}
    Log 'CI ok: tarefa incerta reconciliada apenas depois de estado original confirmado'
} catch { Log ('FALHOU: tarefa: ' + $_.Exception.Message) -Erro; exit 1 }
finally { Unregister-ScheduledTask -TaskName $nomeTarefa -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue }

# ---- 12. plano .reg restrito com remocao de valor padrao ----
$nomePlano = 'Software\OtimizadorPC-CI-Plano-' + [guid]::NewGuid().ToString('N')
try {
    $chave = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomePlano)
    try { $chave.SetValue('','original'); $chave.SetValue('numero',23) } finally { $chave.Dispose() }
    $texto = "Windows Registry Editor Version 5.00`n`n[HKEY_CURRENT_USER\$nomePlano]`n@=-`n" + '"numero"=dword:0000002a'
    $plano = @(Ler-PlanoRegRestrito $texto)
    Iniciar-Sessao 'ci-plano'
    foreach ($acao in $plano) { Executar-Acao $acao 'plano descartavel' }
    $arq = Salvar-Sessao
    $ck = 'HKCU:\' + $nomePlano
    if ($global:ErrosSessao -ne 0 -or (Ler-ValorRegistro $ck '').existia -or (Ler-ValorRegistro $ck 'numero').valor -ne 42) { throw 'Plano nao aplicado corretamente.' }
    if (-not (Reverter-Sessao $arq)) { throw 'Plano nao revertido.' }
    if ((Ler-ValorRegistro $ck '').valor -cne 'original' -or (Ler-ValorRegistro $ck 'numero').valor -ne 23) { throw 'Valores nao restaurados.' }
    Log 'CI ok: plano restrito e remocao de valor padrao restaurados'
} catch { Log ('FALHOU: plano restrito: ' + $_.Exception.Message) -Erro; exit 1 }
finally { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomePlano,$false) }

# ---- 13. metadados do desinstalador mudam apos a listagem ----
$nomeEntrada='Software\OtimizadorPC-CI-Entrada-' + [guid]::NewGuid().ToString('N')
$ck='HKCU:\'+$nomeEntrada
try {
    $chave=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($nomeEntrada)
    try { $chave.SetValue('DisplayName','Aplicativo descartavel'); $chave.SetValue('UninstallString','nao-executar.exe') } finally { $chave.Dispose() }
    $pr=Converter-EntradaPrograma (Get-ItemProperty -LiteralPath $ck -ErrorAction Stop)
    [void](Validar-ProtecaoPrograma $pr -Desinstalar)
    Set-ItemProperty -LiteralPath $ck -Name NoRemove -Value 1 -ErrorAction Stop
    foreach ($modo in @($true,$false)) {
        $recusou=$false
        try { $null=Validar-ProtecaoPrograma $pr -Desinstalar:$modo } catch { $recusou=$_.Exception.Message -match 'agora protegida' }
        if (-not $recusou) { throw 'Entrada alterada para protegida nao bloqueada.' }
    }
    Remove-ItemProperty -LiteralPath $ck -Name NoRemove -ErrorAction Stop
    Set-ItemProperty -LiteralPath $ck -Name UninstallString -Value 'outro.exe' -ErrorAction Stop
    $recusou=$false
    try { $null=Validar-ProtecaoPrograma $pr -Desinstalar } catch { $recusou=$_.Exception.Message -match 'mudou desde a listagem' }
    if (-not $recusou) { throw 'Comando alterado nao bloqueado.' }
    Log 'CI ok: metadados protegidos e comandos alterados bloqueados sem executar desinstalador'
} catch { Log ('FALHOU: protecao desinstalador: ' + $_.Exception.Message) -Erro; exit 1 }
finally { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($nomeEntrada,$false) }

Log 'CI INTEGRACAO: todos os testes passaram'
exit 0
