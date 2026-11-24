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
    Status ('executando: ' + $Titulo)
    Ocupado $true
    $codigo = 1
    try {
        Log ('abrindo janela do powershell para: ' + $Titulo)
        $cmd = Montar-ComandoConsole -Bloco $Bloco
        $bytes = [Text.Encoding]::Unicode.GetBytes($cmd)
        $enc = [Convert]::ToBase64String($bytes)
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $proc = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$enc) -WindowStyle Normal -PassThru -Wait -ErrorAction Stop
        try { $codigo = $proc.ExitCode } finally { $proc.Dispose() }
    } catch { Log ('falha ao abrir console: ' + $_.Exception.Message) -Erro }
    finally { Ocupado $false }
    if ($codigo -eq 0) { Log ('comandos concluidos: ' + $Titulo); Status 'pronto; confira os avisos.' }
    else { Log ('operacao com falha: ' + $Titulo + ' (codigo ' + $codigo + ')') -Erro; Status 'falha; consulte o log.' }
    return $codigo
}

function Resetar-WindowsUpdate {
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
    $bloco = @'
Write-Host '== Limpeza do armazenamento de componentes ==' -ForegroundColor Cyan
Write-Host 'Isso apaga versoes antigas de atualizacoes do Windows. Pode demorar.'
Executar-Nativo Dism.exe @('/Online','/Cleanup-Image','/StartComponentCleanup') @(0,3010)
'@
    Executar-NoConsole -Titulo 'Limpeza DISM de componentes' -Bloco $bloco
}

function Verificar-Disco {
    $bloco = @'
Write-Host '== Verificacao do disco C: (online, sem interromper o uso) ==' -ForegroundColor Cyan
Executar-Nativo chkdsk.exe @($env:SystemDrive,'/scan')
'@
    Executar-NoConsole -Titulo 'Verificacao de disco (chkdsk /scan)' -Bloco $bloco
}

function Limpeza-Disco {
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

function Limpar-Temporarios {
    Status 'limpando arquivos temporarios...'
    Ocupado $true
    $alvos = @("$env:TEMP\*", "$env:SystemRoot\Temp\*")
    $apagados = 0
    foreach ($a in $alvos) {
        Get-ChildItem -Path $a -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
                try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $apagados++ }
                catch { Log ('temporario ignorado: ' + $_.FullName) }
            }
    }
    Ocupado $false
    Log ("temporarios limpos ({0} itens; alguns em uso sao ignorados). " -f $apagados)
    Status 'pronto.'
}

function Limpar-DNS {
    ipconfig /flushdns | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao limpar DNS.' }
    Log 'cache do DNS limpo.'
}

function Sincronizar-Hora {
    Status 'sincronizando hora com a internet...'
    Ocupado $true
    W32tm /resync 2>&1 | ForEach-Object { Log ("  " + $_) }
    Ocupado $false
    Log 'comando de resync concluido (se falhar, veja a mensagem acima; da servico de hora).'
    Status 'pronto.'
}

function Recuperar-CacheIcones {
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

function Configurar-Atualizacoes {
    param([bool]$BloquearDrivers, [bool]$AdiarRecursos)
    Iniciar-Sessao 'atualizacoes'
    if ($BloquearDrivers) {
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'ExcludeWUDriverInQualityUpdate'; tipoValor = 'DWord'; dados = '1' }) 'bloquear drivers'
    } else {
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'ExcludeWUDriverInQualityUpdate'; remover = $true }) 'desbloquear drivers'
    }
    if ($AdiarRecursos) {
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'DeferFeatureUpdates'; tipoValor = 'DWord'; dados = '1' }) 'adiar recursos'
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'DeferFeatureUpdatesPeriodInDays'; tipoValor = 'DWord'; dados = '180' }) 'adiar recursos - periodo'
    } else {
        foreach ($nome in @('DeferFeatureUpdates','DeferFeatureUpdatesPeriodInDays')) {
            Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = $nome; remover = $true }) 'adiar recursos - remover'
        }
    }
    $arq = Salvar-Sessao
    if ($arq) { Log ("sessao de atualizacoes salva para desfazer: {0}" -f (Split-Path -Leaf $arq)) }
    if ($global:ErrosSessao -gt 0) { Status 'configuracao parcial; consulte o log.' }
    else { Status 'atualizacoes configuradas. reinicie para aplicar de vez.' }
}

function Tem-Atualizacoes {
    $r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    return $r
}

# ---- winget ----

function Testar-Winget {
    try { $null = & winget --version 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Instalar-Winget {
    $bloco = @'
Write-Host '== Instalando o winget (App Installer) ==' -ForegroundColor Cyan
Add-AppxPackage 'https://aka.ms/getwinget'
Executar-Nativo winget.exe @('--version')
'@
    Executar-NoConsole -Titulo 'Instalar winget' -Bloco $bloco
}

function Instalar-Aplicativos {
    param($Selecionados)
    if ($Selecionados.Count -eq 0) { Avisar 'Nada selecionado' 'Marque pelo menos um aplicativo na lista antes de instalar.'; return }
    if (-not (Testar-Winget)) {
        Log 'winget nao encontrado nesta maquina.' -Erro
        $resp = Perguntar 'Winget ausente' 'O winget (App Installer) nao foi encontrado. Instalar agora?'
        if ($resp) { Instalar-Winget }
        if (-not (Testar-Winget)) { Log 'winget continua indisponivel; instale manualmente pela Store ("Instalador de Aplicativo").' -Erro; return }
    }
    $linhas = New-Object System.Text.StringBuilder
    [void]$linhas.AppendLine("Write-Host '== Instalando $($Selecionados.Count) aplicativos ==' -ForegroundColor Cyan")
    foreach ($app in $Selecionados) {
        $fonte = ''
        if ($app.fonte -eq 'msstore') { $fonte = '-s msstore' }
        [void]$linhas.AppendLine("Write-Host ''")
        if ([string]$app.id -notmatch '^[A-Za-z0-9._-]+
    }
    Executar-NoConsole -Titulo 'Instalacao de aplicativos' -Bloco $linhas.ToString()
}

function Atualizar-Tudo {
    if (-not (Testar-Winget)) { Log 'winget nao encontrado; use a instalacao do winget na aba Config.' -Erro; return }
    $blocovo = @'
Write-Host '== Atualizando todos os aplicativos ==' -ForegroundColor Cyan
Executar-Nativo winget.exe @('upgrade','--all','--silent','--accept-package-agreements','--accept-source-agreements')
'@
    Executar-NoConsole -Titulo 'Atualizar todos os apps (winget)' -Bloco $blocovo
}
) { throw 'ID de aplicativo invalido.' }
        $nomeSeguro = ([string]$app.nome).Replace("'","''")
        [void]$linhas.AppendLine("Write-Host ('### ' + '$nomeSeguro') -ForegroundColor Cyan")
        $argsFonte = ''
        if ($fonte) { $argsFonte = ",'-s','msstore'" }
        [void]$linhas.AppendLine("Executar-Nativo winget.exe @('install','--id','$($app.id)','-e','--silent','--accept-package-agreements','--accept-source-agreements'$argsFonte)")
    }
    Executar-NoConsole -Titulo 'Instalacao de aplicativos' -Bloco $linhas.ToString()
}

function Atualizar-Tudo {
    if (-not (Testar-Winget)) { Log 'winget nao encontrado; use a instalacao do winget na aba Config.' -Erro; return }
    $blocovo = @'
Write-Host '== Atualizando todos os aplicativos ==' -ForegroundColor Cyan
Executar-Nativo winget.exe @('upgrade','--all','--silent','--accept-package-agreements','--accept-source-agreements')
'@
    Executar-NoConsole -Titulo 'Atualizar todos os apps (winget)' -Bloco $blocovo
}
