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
    param([string]$Titulo, [string]$Bloco)
    Confirmar-PermissaoAlteracao
    Status ('executando: ' + $Titulo)
    Ocupado $true
    $codigo = 1
    try {
        Log ('abrindo janela do powershell para: ' + $Titulo)
        $cmd = Montar-ComandoConsole -Bloco $Bloco
        $bytes = [Text.Encoding]::Unicode.GetBytes($cmd)
        $enc = [Convert]::ToBase64String($bytes)
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $proc = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$enc) -WindowStyle Normal -PassThru -ErrorAction Stop
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

function Resetar-WindowsUpdate {
    Confirmar-PermissaoAlteracao
    if (-not (Perguntar 'Reset do Windows Update' 'Recriar os caches do Windows Update? Os caches anteriores serao preservados com nome unico. Pode exigir reinicializacao e novo download.')) { return }
    $bloco = @'
Write-Host '== Resetando o Windows Update ==' -ForegroundColor Cyan
$servicos = @()
foreach ($nome in @('wuauserv','bits','cryptsvc','dosvc')) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { $servicos += $nome }
}
$parados = @()
try {
    foreach ($nome in $servicos) {
        Stop-Service -Name $nome -ErrorAction Stop
        $parados += $nome
    }
    $sufixo = '.otimizadorpc-' + [guid]::NewGuid().ToString('N')
    foreach ($pasta in @("$env:SystemRoot\SoftwareDistribution","$env:SystemRoot\System32\catroot2")) {
        if (Test-Path -LiteralPath $pasta) {
            $novo = (Split-Path -Leaf $pasta) + $sufixo
            Rename-Item -LiteralPath $pasta -NewName $novo -ErrorAction Stop
            Write-Host ('Cache preservado: ' + (Join-Path (Split-Path -Parent $pasta) $novo))
        }
    }
} finally {
    $falhas = @()
    foreach ($nome in $parados) {
        try { Start-Service -Name $nome -ErrorAction Stop }
        catch { $falhas += $nome; Write-Host $_.Exception.Message -ForegroundColor Red }
    }
    if ($falhas.Count -gt 0) { throw ('Servicos nao reiniciados: ' + ($falhas -join ', ')) }
}
Write-Host 'Caches antigos preservados. Verifique o Windows Update.'
'@
    Executar-NoConsole -Titulo 'Reset do Windows Update' -Bloco $bloco
}

function Resetar-Rede {
    Confirmar-PermissaoAlteracao
    if (-not (Perguntar 'Reset de rede' 'Esta operacao pode interromper a conexao e exigir reinicio. Nao use em acesso remoto ou sem saber a configuracao de rede. Continuar?')) { return }
    $bloco = @'
Write-Host '== Resetando a rede ==' -ForegroundColor Cyan
Executar-Nativo ipconfig.exe @('/flushdns')
Write-Host 'Resetando winsock...'
Executar-Nativo netsh.exe @('winsock','reset')
Write-Host 'Resetando pilha TCP/IP...'
Executar-Nativo netsh.exe @('int','ip','reset')
Write-Host 'Liberando e renovando IP...'
Executar-Nativo ipconfig.exe @('/release')
Executar-Nativo ipconfig.exe @('/renew')
Write-Host ''
Write-Host 'REINICIE O PC para completar a correcao.' -ForegroundColor Yellow
'@
    Executar-NoConsole -Titulo 'Reset da rede' -Bloco $bloco
}

function Verificar-Integridade {
    Confirmar-PermissaoAlteracao
    $bloco = @'
Write-Host '== Verificacao de integridade do sistema ==' -ForegroundColor Cyan
Write-Host '1/2 - DISM (pode demorar varios minutos)...' -ForegroundColor Cyan
Executar-Nativo Dism.exe @('/Online','/Cleanup-Image','/RestoreHealth') @(0,3010)
Write-Host '2/2 - SFC (varredura de arquivos de sistema)...' -ForegroundColor Cyan
Executar-Nativo sfc.exe @('/scannow')
'@
    Executar-NoConsole -Titulo 'Verificacao de integridade (DISM + SFC)' -Bloco $bloco
}

function Manutencao-DISM {
    Confirmar-PermissaoAlteracao
    $bloco = @'
Write-Host '== Limpeza do armazenamento de componentes ==' -ForegroundColor Cyan
Write-Host 'Isso apaga versoes antigas de atualizacoes do Windows. Pode demorar.'
Executar-Nativo Dism.exe @('/Online','/Cleanup-Image','/StartComponentCleanup') @(0,3010)
'@
    Executar-NoConsole -Titulo 'Limpeza DISM de componentes' -Bloco $bloco
}

function Verificar-Disco {
    Confirmar-PermissaoAlteracao
    $bloco = @'
Write-Host '== Verificacao do disco C: (online, sem interromper o uso) ==' -ForegroundColor Cyan
Executar-Nativo chkdsk.exe @($env:SystemDrive,'/scan')
'@
    Executar-NoConsole -Titulo 'Verificacao de disco (chkdsk /scan)' -Bloco $bloco
}

function Limpeza-Disco {
    Confirmar-PermissaoAlteracao
    $bloco = @'
Write-Host '== Limpeza de disco profunda no C: ==' -ForegroundColor Cyan
Write-Host 'Executando cleanmgr automatico...'
Executar-Nativo cleanmgr.exe @('/d',$env:SystemDrive,'/VERYLOWDISK')
Write-Host 'Limpeza de componentes obsoletos do Windows...'
Executar-Nativo Dism.exe @('/Online','/Cleanup-Image','/StartComponentCleanup') @(0,3010)
'@
    Executar-NoConsole -Titulo 'Limpeza de disco' -Bloco $bloco
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
    Confirmar-PermissaoAlteracao
    $pastas=@((Join-Path $env:LOCALAPPDATA 'Temp'),(Join-Path $env:SystemRoot 'Temp'))
    $plano=Obter-PlanoTemporarios $pastas
    if ($plano.itens.Count -eq 0) { Avisar 'Limpeza de temporarios' ('Nenhum arquivo elegivel nas pastas consultadas. '+($plano.avisos -join ' | ')); return }
    $msg=('Encontrados {0} arquivo(s), {1:N2} MB estimados. Somente arquivos na raiz das pastas Temp, modificados ha mais de 7 dias. Nao inclui subpastas, documentos ou links.' -f $plano.itens.Count,($plano.bytes/1MB))
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
                Remove-Item -LiteralPath $f.caminho -Force -ErrorAction Stop
                $apagados++; $bytes+=$f.bytes
            } catch { $ignorados++; Log ('temporario preservado: '+$f.caminho) }
        }
    } finally { Fechar-ProgressoLote $progresso; Ocupado $false }
    $res=('Removidos {0} arquivo(s), {1:N2} MB de tamanho logico; {2} ignorado(s).' -f $apagados,($bytes/1MB),$ignorados)
    if ($progresso.cancelado) { $res+=' Lote interrompido.' }
    Log $res; Status $res
}

function Limpar-DNS {
    Confirmar-PermissaoAlteracao
    ipconfig /flushdns | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao limpar DNS.' }
    Log 'cache do DNS limpo.'
}

function Sincronizar-Hora {
    Confirmar-PermissaoAlteracao
    Status 'sincronizando hora com a internet...'
    Ocupado $true
    W32tm /resync 2>&1 | ForEach-Object { Log ("  " + $_) }
    Ocupado $false
    Log 'comando de resync concluido (se falhar, veja a mensagem acima; da servico de hora).'
    Status 'pronto.'
}

function Recuperar-CacheIcones {
    Confirmar-PermissaoAlteracao
    Status 'reconstruindo cache de icones...'
    Ocupado $true
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    $icocache = "$env:LOCALAPPDATA\IconCache.db"
    if (Test-Path $icocache) { Remove-Item $icocache -Force -ErrorAction SilentlyContinue }
    $pasta = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    Get-ChildItem -Path $pasta -Filter 'iconcache*' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Ocupado $false
    Log 'cache de icones reconstruido.'
    Status 'pronto.'
}

# ---- atualizacoes ----

# Politicas de atualizacao sao apenas consultadas. Nao apagar valores que
# podem ter origem fora do app; journals antigos continuam recuperaveis.
function Configurar-Atualizacoes {
    param([bool]$BloquearDrivers,[bool]$AdiarRecursos)
    Confirmar-PermissaoAlteracao
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
    Confirmar-PermissaoAlteracao
    if (Perguntar 'App Installer' 'Abrir a pagina oficial do App Installer na Microsoft Store? O OtimizadorPC nao baixara nem executara instalador automaticamente.') {
        Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    }
}

function Obter-ArgumentosApp {
    param($App,[ValidateSet('install','upgrade')][string]$Operacao)
    if ([string]$App.id -notmatch '^[A-Za-z0-9._+\-]+$') { throw 'ID de aplicativo invalido.' }
    $fonte=if (-not $App.fonte -or $App.fonte -eq 'winget') {'winget'} elseif ($App.fonte -eq 'msstore') {'msstore'} else {throw 'Fonte nao permitida.'}
    $argsApp=@($Operacao,'--id',[string]$App.id,'--exact','--source',$fonte)
    if ($Operacao -eq 'install') { $argsApp+='--no-upgrade' }
    return $argsApp
}

function Instalar-Aplicativos {
    param($Selecionados,[ValidateSet('install','upgrade')][string]$Operacao='install')
    Confirmar-PermissaoAlteracao
    if (@($Selecionados).Count -eq 0) { Avisar 'Nada selecionado' 'Selecione aplicativos para a operacao.'; return }
    if (-not (Testar-Winget)) { Avisar 'WinGet indisponivel' 'Use o App Installer oficial em Config.'; return }
    $exe=Obter-WingetExe
    $exeSeguro=$exe.Replace("'","''")
    $linhas=New-Object System.Text.StringBuilder
    $plano=@()
    foreach ($app in $Selecionados) {
        $argsApp=@(Obter-ArgumentosApp $app $Operacao)
        $plano+=($app.nome+' | '+($argsApp -join ' '))
        $argsTexto=($argsApp | ForEach-Object { "'"+$_.Replace("'","''")+"'" }) -join ','
        [void]$linhas.AppendLine("Executar-Nativo '$exeSeguro' @($argsTexto)")
    }
    $titulo=if ($Operacao -eq 'install') {'Instalar selecionados'} else {'Atualizar selecionados'}
    if (-not (Perguntar $titulo (($plano -join "`n")+"`n`nA operacao pode instalar dependencias e solicitar aceite de licenca. Nao ha rollback automatico. Continuar?"))) { return }
    Executar-NoConsole -Titulo $titulo -Bloco $linhas.ToString()
}

function Atualizar-Tudo {
    Confirmar-PermissaoAlteracao
    if (-not (Testar-Winget)) { Avisar 'WinGet indisponivel' 'Use App Installer oficial em Config.'; return }
    if (-not (Perguntar 'Consultar atualizacoes' 'Consultar ofertas do WinGet nas fontes configuradas? Pode acessar a internet e pedir aceite de fonte. Nenhum upgrade sera executado.')) { return }
    $exeSeguro=(Obter-WingetExe).Replace("'","''")
    Executar-NoConsole -Titulo 'Consultar atualizacoes de aplicativos' -Bloco ("Executar-Nativo '$exeSeguro' @('upgrade')")
}
