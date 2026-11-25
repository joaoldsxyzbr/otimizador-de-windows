# consertos.ps1 - manutencao, limpezas e correcoes comuns
# operacoes pesadas rodam numa janela de powershell visivel (transparencia total pro joao)

# roda um bloco numa janela de powershell visivel e espera terminar
# codifica em base64 para evitar qualquer problema de aspas
# Compoe o bloco com tratamento explicito de falhas e codigo de saida preservado.
function Montar-ComandoConsole {
    param([string]$Bloco, [switch]$SemPausa)
    $inicio = @'
$ErrorActionPreference = 'Stop'
function Executar-Nativo {
    param([string]$Exe, [string[]]$Argumentos, [int[]]$CodigosOk = @(0))
    & $Exe @Argumentos
    $codigo = $LASTEXITCODE
    if ($codigo -notin $CodigosOk) { throw ('Falha de ' + $Exe + ' (codigo ' + $codigo + ')') }
}
$codigoFinal = 0
try {
'@
    $fim = @'
}
catch {
    $codigoFinal = 1
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
}
if ($codigoFinal -eq 0) { Write-Host 'Comandos concluidos; confira a saida e os avisos.' -ForegroundColor Green }
else { Write-Host 'Operacao interrompida com erro.' -ForegroundColor Yellow }
'@
    $pausa = ''
    if (-not $SemPausa) { $pausa = "Read-Host 'pressione Enter para fechar esta janela' | Out-Null" }
    return ($inicio + [Environment]::NewLine + $Bloco + [Environment]::NewLine + $fim + [Environment]::NewLine + $pausa + [Environment]::NewLine + 'exit $codigoFinal')
}

function Executar-NoConsole {
    param([string]$Titulo, [string]$Bloco,[string]$Operacao)
    Confirmar-PermissaoAlteracao $Operacao
    if ($Operacao -notin @('diagnostico-admin','reparo','winget','consulta-winget')) {throw 'Console fora do catalogo de operacoes.'}
    if ($Operacao -eq 'reparo') {Confirmar-PoliticaRecursosLocal}
    if ($Operacao -in @('winget','consulta-winget')) {Confirmar-PoliticaWingetLocal}
    Status ('executando: ' + $Titulo)
    Ocupado $true
    $codigo = 1
    try {
        Log ('abrindo janela do powershell para: ' + $Titulo)
        $cmd = Montar-ComandoConsole -Bloco $Bloco
        $bytes = [Text.Encoding]::Unicode.GetBytes($cmd)
        $enc = [Convert]::ToBase64String($bytes)
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Confirmar-PermissaoAlteracao $Operacao
        $proc = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-EncodedCommand',$enc) -WindowStyle Normal -PassThru -ErrorAction Stop
        try {
            while (-not $proc.WaitForExit(100)) { Atualizar-UI }
            $codigo = $proc.ExitCode
        } finally { $proc.Dispose() }
    } catch { Log ('falha ao abrir console: ' + $_.Exception.Message) -Erro }
    finally { Ocupado $false }
    if ($codigo -eq 0) { Log ('comandos concluidos: ' + $Titulo); Status 'pronto; confira os avisos.' }
    else { Log ('operacao com falha: ' + $Titulo + ' (codigo ' + $codigo + ')') -Erro; Status 'falha; consulte o log.' }
    return $codigo
}

# Compatibility entrypoint: route troubleshooting to Windows, never reset services.
function Resetar-WindowsUpdate {
    Confirmar-PermissaoAlteracao 'nativo'
    if (-not (Perguntar 'Diagnosticar Windows Update' 'Abrir Windows Update para revisar erros, historico e opcoes permitidas? O OtimizadorPC nao vai parar servicos nem renomear caches.')) {return}
    Start-Process -FilePath 'ms-settings:windowsupdate' -ErrorAction Stop | Out-Null
    Log 'Windows Update aberto; nenhuma politica ou cache alterado pelo aplicativo.'
}


# Network reset can break VPN, static IP and remote access. Do not run a generic reset.
function Resetar-Rede {
    Confirmar-PermissaoAlteracao 'nativo'
    if (-not (Perguntar 'Diagnosticar rede' 'Abrir configuracoes de rede para revisar conexao e solucionar problemas? O OtimizadorPC nao vai resetar Winsock, TCP/IP, VPN ou liberar enderecos IP.')) {return}
    Start-Process -FilePath 'ms-settings:network-status' -ErrorAction Stop | Out-Null
    Log 'Configuracoes de rede abertas; nenhuma configuracao de rede alterada pelo aplicativo.'
}


function Diagnosticar-Integridade {
    Confirmar-PermissaoAlteracao 'diagnostico-admin'
    if (-not (Perguntar 'Diagnosticar integridade' 'Executar DISM ScanHealth e SFC verifyonly? Consultas podem demorar e gravar logs do Windows, mas nao solicitam reparo.')) { return }
    $bloco=@'
Executar-Nativo (Join-Path $env:SystemRoot 'System32\Dism.exe') @('/Online','/Cleanup-Image','/ScanHealth')
Executar-Nativo (Join-Path $env:SystemRoot 'System32\sfc.exe') @('/verifyonly')
'@
    Executar-NoConsole -Operacao 'diagnostico-admin' -Titulo 'Diagnosticar integridade' -Bloco $bloco
}

function Analisar-ComponentesWindows {
    Confirmar-PermissaoAlteracao 'diagnostico-admin'
    $bloco=@'
Executar-Nativo (Join-Path $env:SystemRoot 'System32\Dism.exe') @('/Online','/Cleanup-Image','/AnalyzeComponentStore')
'@
    Executar-NoConsole -Operacao 'diagnostico-admin' -Titulo 'Analisar armazenamento de componentes' -Bloco $bloco
}

function Abrir-OtimizacaoVolume {
    Confirmar-PermissaoAlteracao 'nativo'
    if (-not (Perguntar 'Otimizar unidades do Windows' 'Abrir a ferramenta nativa Otimizar Unidades? Ela analisa volumes e seleciona a operacao apropriada ao tipo de midia. Revise o estado e escolha manualmente. O OtimizadorPC nao forca desfragmentacao nem TRIM.')) {return}
    $exe=Join-Path $env:SystemRoot 'System32\dfrgui.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {throw 'Ferramenta nativa indisponivel.'}
    Start-Process -FilePath $exe -ErrorAction Stop | Out-Null
}

function Consultar-Energia {
    Confirmar-PermissaoAlteracao 'diagnostico-admin'
    $bloco=@'
$exe=Join-Path $env:SystemRoot 'System32\powercfg.exe'
Executar-Nativo $exe @('/getactivescheme')
Executar-Nativo $exe @('/requests')
Executar-Nativo $exe @('/lastwake')
Executar-Nativo $exe @('/waketimers')
'@
    Executar-NoConsole -Operacao 'diagnostico-admin' -Titulo 'Diagnostico de energia e suspensao' -Bloco $bloco
}

function Verificar-Integridade {
    Confirmar-PermissaoAlteracao 'reparo'
    if (-not (Perguntar 'Reparar integridade' 'DISM RestoreHealth e SFC scannow podem alterar arquivos de sistema e usar Windows Update. Use para corrupcao ou falhas confirmadas. Nao ha journal de rollback. Continuar?')) { return }
    $bloco = @'
Write-Host '== Verificacao de integridade do sistema ==' -ForegroundColor Cyan
Write-Host '1/2 - DISM (pode demorar varios minutos)...' -ForegroundColor Cyan
Executar-Nativo (Join-Path $env:SystemRoot 'System32\Dism.exe') @('/Online','/Cleanup-Image','/RestoreHealth') @(0,3010)
Write-Host '2/2 - SFC (varredura de arquivos de sistema)...' -ForegroundColor Cyan
Executar-Nativo (Join-Path $env:SystemRoot 'System32\sfc.exe') @('/scannow')
'@
    Executar-NoConsole -Operacao 'reparo' -Titulo 'Verificacao de integridade (DISM + SFC)' -Bloco $bloco
}

function Manutencao-DISM {
    Confirmar-PermissaoAlteracao 'reparo'
    if (-not (Perguntar 'Limpar componentes' 'Analise primeiro o armazenamento de componentes. DISM StartComponentCleanup remove componentes substituidos; nao possui desfazer pelo app. Continuar?')) { return }
    $bloco = @'
Write-Host '== Limpeza do armazenamento de componentes ==' -ForegroundColor Cyan
Write-Host 'Isso apaga versoes antigas de atualizacoes do Windows. Pode demorar.'
Executar-Nativo (Join-Path $env:SystemRoot 'System32\Dism.exe') @('/Online','/Cleanup-Image','/StartComponentCleanup') @(0,3010)
'@
    Executar-NoConsole -Operacao 'reparo' -Titulo 'Limpeza DISM de componentes' -Bloco $bloco
}

function Verificar-Disco {
    Confirmar-PermissaoAlteracao 'diagnostico-admin'
    if (-not (Perguntar 'Verificar volume do sistema' 'Executar CHKDSK sem parametros de reparo? Pode demorar. Em um volume em uso, resultados podem exigir nova verificacao; nenhuma correcao sera solicitada.')) {return}
    $bloco=@'
Write-Host ('== Verificacao sem reparo solicitado: '+$env:SystemDrive+' ==') -ForegroundColor Cyan
Executar-Nativo (Join-Path $env:SystemRoot 'System32\chkdsk.exe') @($env:SystemDrive)
'@
    Executar-NoConsole -Operacao 'diagnostico-admin' -Titulo 'Verificacao de disco sem reparo solicitado' -Bloco $bloco
}


function Limpeza-Disco {
    Confirmar-PermissaoAlteracao 'nativo'
    if (-not (Perguntar 'Limpeza de disco' 'Abrir ferramenta nativa para revisar categorias antes da exclusao? Nao selecionaremos categorias automaticamente.')) { return }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cleanmgr.exe') -ArgumentList @('/d',$env:SystemDrive) -ErrorAction Stop | Out-Null
}

# ---- rapidas (rodam direto, sem console) ----

# Limpeza rapida limitada a arquivos antigos na raiz do Temp local.
# Nunca percorre diretorios, segue links ou limpa documentos do usuario.
function Testar-RaizTemporarios {
    param([string]$Pasta)
    try {
        if ($Pasta -notmatch '^[A-Za-z]:\\') { return $false }
        $atual=[IO.Path]::GetFullPath($Pasta)
        while ($atual) {
            $item=Get-Item -LiteralPath $atual -Force -ErrorAction Stop
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
            $pai=Split-Path -Parent $atual
            if (-not $pai -or $pai -eq $atual) { break }
            $atual=$pai
        }
        return $true
    } catch { return $false }
}

function Obter-PlanoTemporarios {
    param([string[]]$Pastas,[datetime]$Agora=[datetime]::UtcNow,[int]$Limite=5000)
    $itens=@(); $avisos=@(); $bytes=0L; $limitado=$false
    foreach ($pasta in @($Pastas | Sort-Object -Unique)) {
        if (-not (Testar-RaizTemporarios $pasta)) { $avisos += ('Pasta indisponivel ou redirecionada: '+$pasta); continue }
        try {
            $restantes=$Limite-$itens.Count
            if ($restantes -le 0) { $limitado=$true; break }
            $candidatos=@(Get-ChildItem -LiteralPath $pasta -File -Force -ErrorAction Stop |
                Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $_.LastWriteTimeUtc -lt $Agora.AddDays(-7) } |
                Select-Object -First ($restantes+1))
            if ($candidatos.Count -gt $restantes) { $limitado=$true }
            foreach ($f in @($candidatos | Select-Object -First $restantes)) {
                $itens += [pscustomobject]@{ caminho=$f.FullName; pasta=$pasta; bytes=[long]$f.Length; modificado=$f.LastWriteTimeUtc; criado=$f.CreationTimeUtc }
                $bytes += $f.Length
            }
        } catch { $avisos += ('Falha ao consultar: '+$pasta) }
    }
    return [pscustomobject]@{ itens=$itens; bytes=$bytes; avisos=$avisos; limitado=$limitado }
}

function Limpar-Temporarios {
    Confirmar-PermissaoAlteracao 'temp'
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $local -or $local -ine $env:LOCALAPPDATA) {throw 'Perfil local do usuario nao confirmado; temporarios preservados.'}
    $pastas=@((Join-Path $local 'Temp'))
    $plano=Obter-PlanoTemporarios $pastas
    if ($plano.itens.Count -eq 0) { Avisar 'Limpeza de temporarios' ('Nenhum arquivo elegivel nas pastas consultadas. '+($plano.avisos -join ' | ')); return }
    $msg=('Encontrados {0} arquivo(s), {1:N2} MB estimados. Somente arquivos na raiz do Temp do usuario atual, modificados ha mais de 7 dias. O Temp do Windows nao sera limpo por esta rotina. Nao inclui subpastas, documentos ou links.' -f $plano.itens.Count,($plano.bytes/1MB))
    if ($plano.limitado) { $msg += ' Lista limitada; outros arquivos podem existir.' }
    $msg += "`n" + ($plano.avisos -join "`n") + "`nAmostra:`n" + (($plano.itens | Select-Object -First 8 | ForEach-Object {$_.caminho}) -join "`n")
    $msg += "`n`nExclusao definitiva, sem journal de recuperacao. Arquivos em uso ou alterados serao ignorados. Continuar?"
    if (-not (Perguntar 'Revisar limpeza de temporarios' $msg)) { return }
    Status 'limpando arquivos temporarios...'
    Ocupado $true
    $apagados=0; $ignorados=0; $bytes=0L
    $progresso=Iniciar-ProgressoLote 'Limpeza de temporarios' $plano.itens.Count
    try {
        foreach ($f in $plano.itens) {
            if (-not (Continuar-ProgressoLote $progresso $f.caminho)) { break }
            try {
                if (-not (Testar-RaizTemporarios $f.pasta) -or (Split-Path -Parent $f.caminho) -ne $f.pasta) { throw 'Pasta mudou.' }
                $atual=Get-Item -LiteralPath $f.caminho -Force -ErrorAction Stop
                if ($atual.PSIsContainer -or ($atual.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $atual.Length -ne $f.bytes -or $atual.LastWriteTimeUtc -ne $f.modificado -or $atual.CreationTimeUtc -ne $f.criado) { throw 'Arquivo mudou.' }
                Confirmar-PermissaoAlteracao 'temp'
                Remove-Item -LiteralPath $f.caminho -Force -ErrorAction Stop
                if (Test-Path -LiteralPath $f.caminho -ErrorAction Stop) {throw 'Exclusao nao confirmada.'}
                $apagados++; $bytes+=$f.bytes
            } catch { $ignorados++; Log ('temporario preservado: '+$f.caminho) }
        }
    } finally { Fechar-ProgressoLote $progresso; Ocupado $false }
    $res=('Removidos {0} arquivo(s), {1:N2} MB de tamanho logico; {2} ignorado(s).' -f $apagados,($bytes/1MB),$ignorados)
    if ($progresso.cancelado) { $res+=' Lote interrompido.' }
    Log $res; Status $res
}

function Limpar-DNS {
    Confirmar-PermissaoAlteracao 'dns'
    if (-not (Perguntar 'Limpar cache DNS' 'Limpar apenas o cache local de resolucao de nomes? Nao altera servidores DNS, VPN ou configuracao de rede. Use somente em problema de resolucao.')) {return}
    Confirmar-PermissaoAlteracao 'dns'
    & (Join-Path $env:SystemRoot 'System32\ipconfig.exe') /flushdns | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Falha ao limpar DNS.'}
    Log 'cache local do DNS limpo.'
}


function Sincronizar-Hora {
    Confirmar-PermissaoAlteracao 'hora'
    if (-not (Perguntar 'Sincronizar hora' 'Solicitar sincronizacao pela fonte de hora ja configurada no Windows? Nao altera servidor, servico ou politicas de hora.')) {return}
    Status 'solicitando sincronizacao de hora...'
    Ocupado $true
    try {
        Confirmar-PermissaoAlteracao 'hora'
        $saida=& (Join-Path $env:SystemRoot 'System32\w32tm.exe') /resync 2>&1
        $codigo=$LASTEXITCODE
        foreach ($linha in $saida) {Log ('  '+$linha)}
        if ($codigo -ne 0) {throw ('Sincronizacao nao confirmada; codigo '+$codigo)}
        Log 'Solicitacao de sincronizacao aceita; confira a hora do Windows.'
        Status 'solicitacao concluida.'
    } finally {Ocupado $false}
}


function Recuperar-CacheIcones {
    Confirmar-PermissaoAlteracao 'nativo'
    if (-not (Perguntar 'Icones e Explorer' 'Abrir configuracoes de personalizacao? Salve o trabalho e encerre a sessao pelo Windows se os icones continuarem incorretos. Nenhum processo sera encerrado nem cache excluido automaticamente.')) {return}
    Start-Process 'ms-settings:personalization' -ErrorAction Stop | Out-Null
    Log 'Personalizacao aberta; cache e processos preservados.'
}

# ---- atualizacoes ----

function Configurar-Atualizacoes {
    param([bool]$BloquearDrivers,[bool]$AdiarRecursos)
    Confirmar-PermissaoAlteracao 'nao-catalogado'
    throw 'Edicao de politicas indisponivel nesta versao. Use configuracoes oficiais do Windows.'
}

function Tem-Atualizacoes {
    $p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path -LiteralPath $p -ErrorAction Stop) { return (Get-ItemProperty -LiteralPath $p -ErrorAction Stop) }
}

function Formatar-PoliticaAtualizacao {
    param($Valor)
    if ($null -eq $Valor) { return 'Nao configurada no registro consultado' }
    if ($Valor -eq 1) { return 'Configurada (1)' }
    if ($Valor -eq 0) { return 'Desativada (0)' }
    return 'Valor nao reconhecido'
}

function Obter-HistoricoAtualizacoes {
    $linhas=@()
    $sessao=$null; $busca=$null; $sistema=$null
    try {
        $sistema=New-Object -ComObject Microsoft.Update.SystemInfo -ErrorAction Stop
        $linhas+=('Reinicio requerido por Windows Update: '+$sistema.RebootRequired)
        $sessao=New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $busca=$sessao.CreateUpdateSearcher()
        $total=$busca.GetTotalHistoryCount()
        $linhas+=('Historico local: '+$total+' entradas; ultimas 20. Sem busca online.')
        if ($total -gt 0) {
            foreach ($h in $busca.QueryHistory(0,[Math]::Min(20,$total))) {
                $resultado=switch ([int]$h.ResultCode) { 2 {'Sucesso'} 3 {'Sucesso com erros'} 4 {'Falha'} 5 {'Abortado'} default {'Outro/pendente'} }
                $linhas+=('{0:dd/MM/yyyy HH:mm} | {1} | {2}' -f $h.Date,$resultado,$h.Title)
            }
        }
    } catch { $linhas+='Historico ou estado de reinicio indisponivel.' }
    finally {
        foreach ($obj in @($busca,$sessao,$sistema)) {
            if ($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj) }
        }
    }
    return ($linhas -join [Environment]::NewLine)
}

# ---- winget ----

function Obter-WingetExe {
    # Nao executar alias de PATH ou executavel arbitrario de pasta do usuario
    # em contexto administrativo. Exige pacote registrado no WindowsApps.
    $root=[IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')+'\'
    $pacotes=@(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop | Where-Object {
        $_.Name -eq 'Microsoft.DesktopAppInstaller' -and $_.PublisherId -eq '8wekyb3d8bbwe' -and $_.InstallLocation
    })
    foreach ($p in $pacotes) {
        $exe=[IO.Path]::GetFullPath((Join-Path $p.InstallLocation 'winget.exe'))
        if (-not $exe.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $sig=Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop
        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') { return $exe }
    }
    throw 'WinGet registrado e com assinatura Microsoft valida nao localizado. Use o App Installer oficial.'
}

function Testar-Winget {
    try { $exe=Obter-WingetExe; $null=& $exe --version 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Instalar-Winget {
    Confirmar-PermissaoAlteracao 'nativo'
    if (Perguntar 'App Installer' 'Abrir a pagina oficial do App Installer na Microsoft Store? O OtimizadorPC nao baixara nem executara instalador automaticamente.') {
        Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    }
}

function Confirmar-PoliticaWingetLocal {
    foreach ($chave in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller','HKCU:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller','HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DesktopAppInstaller')) {
        try {$presente=Test-Path -LiteralPath $chave -ErrorAction Stop}
        catch {throw 'Consulta de politica WinGet inconclusiva.'}
        if ($presente) {throw 'Indicador de politica do App Installer presente; use o procedimento autorizado.'}
    }
}

function Confirmar-AppCatalogado {
    param($App)
    $fonte=if ($App.fonte) {[string]$App.fonte} else {'winget'}
    $itens=@($global:CatalogoApps.aplicativos | Where-Object {
        $f=if ($_.fonte) {[string]$_.fonte} else {'winget'}
        $_.id -ceq $App.id -and $f -ceq $fonte -and [string]$_.versao -ceq [string]$App.versao
    })
    if ($itens.Count -ne 1) {throw 'Aplicativo, fonte ou versao fora do catalogo atual.'}
}

function Obter-ArgumentosApp {
    param($App,[ValidateSet('install','upgrade')][string]$Operacao)
    if ([string]$App.id -notmatch '^[A-Za-z0-9._+\-]+$') { throw 'ID de aplicativo invalido.' }
    $fonte=if (-not $App.fonte -or $App.fonte -eq 'winget') {'winget'} elseif ($App.fonte -eq 'msstore') {'msstore'} else {throw 'Fonte nao permitida.'}
    $argsApp=@($Operacao,'--id',[string]$App.id,'--exact','--source',$fonte)
    if ($App.versao) {
        if ([string]$App.versao -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]{0,63}$') {throw 'Versao invalida.'}
        $argsApp+=@('--version',[string]$App.versao)
    }
    if ($Operacao -eq 'install') { $argsApp+='--no-upgrade' }
    return $argsApp
}

function Instalar-Aplicativos {
    param($Selecionados,[ValidateSet('install','upgrade')][string]$Operacao='install')
    Confirmar-PermissaoAlteracao 'winget'
    Confirmar-PoliticaWingetLocal
    if (@($Selecionados).Count -eq 0) { Avisar 'Nada selecionado' 'Selecione aplicativos para a operacao.'; return }
    if (-not (Testar-Winget)) { Avisar 'WinGet indisponivel' 'Use o App Installer oficial em Config.'; return }
    $exe=Obter-WingetExe
    $exeSeguro=$exe.Replace("'","''")
    $linhas=New-Object System.Text.StringBuilder
    $plano=@()
    foreach ($app in $Selecionados) {
        Confirmar-AppCatalogado $app
        $argsApp=@(Obter-ArgumentosApp $app $Operacao)
        $plano+=($app.nome+' | '+($argsApp -join ' '))
        $argsTexto=($argsApp | ForEach-Object { "'"+$_.Replace("'","''")+"'" }) -join ','
        [void]$linhas.AppendLine("Executar-Nativo '$exeSeguro' @($argsTexto)")
    }
    $titulo=if ($Operacao -eq 'install') {'Instalar selecionados'} else {'Atualizar selecionados'}
    if (-not (Perguntar $titulo (($plano -join "`n")+"`n`nA operacao pode instalar dependencias e solicitar aceite de licenca. Nao ha rollback automatico. Continuar?"))) { return }
    Confirmar-PermissaoAlteracao 'winget'
    Confirmar-PoliticaWingetLocal
    foreach ($app in $Selecionados) {Confirmar-AppCatalogado $app}
    if ((Obter-WingetExe) -cne $exe) {throw 'WinGet mudou durante a confirmacao; refaca a operacao.'}
    Executar-NoConsole -Operacao 'winget' -Titulo $titulo -Bloco $linhas.ToString()
}

function Atualizar-Tudo {
    Confirmar-PermissaoAlteracao 'consulta-winget'
    Confirmar-PoliticaWingetLocal
    if (-not (Testar-Winget)) { Avisar 'WinGet indisponivel' 'Use App Installer oficial em Config.'; return }
    if (-not (Perguntar 'Consultar atualizacoes' 'Consultar ofertas do WinGet nas fontes configuradas? Pode acessar a internet e pedir aceite de fonte. Nenhum upgrade sera executado.')) { return }
    Confirmar-PermissaoAlteracao 'consulta-winget'
    Confirmar-PoliticaWingetLocal
    $exeSeguro=(Obter-WingetExe).Replace("'","''")
    Executar-NoConsole -Operacao 'consulta-winget' -Titulo 'Consultar atualizacoes de aplicativos' -Bloco ("Executar-Nativo '$exeSeguro' @('upgrade')")
}
