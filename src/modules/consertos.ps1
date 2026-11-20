# consertos.ps1 - manutencao, limpezas e correcoes comuns
# operacoes pesadas rodam numa janela de powershell visivel (transparencia total pro joao)

# roda um bloco numa janela de powershell visivel e espera terminar
# codifica em base64 para evitar qualquer problema de aspas
function Executar-NoConsole {
    param([string]$Titulo, [string]$Bloco)
    Status ("executando: " + $Titulo)
    Ocupado $true
    Log ("abrindo janela do powershell para: {0}" -f $Titulo)
    $cmd = $Bloco + "`n`$" + "ok = `$?`nif (`$ok) { Write-Host '' -ForegroundColor Green; Write-Host '## CONCLUIDO COM SUCESSO ##' -ForegroundColor Green } else { Write-Host '' -ForegroundColor Yellow; Write-Host '## CONCLUIDO COM ERROS ##' -ForegroundColor Yellow }`nWrite-Host ''`nRead-Host 'pressione Enter para fechar esta janela'"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($cmd)
    $enc = [Convert]::ToBase64String($bytes)
    $proc = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) -WindowStyle Normal -PassThru -Wait
    Ocupado $false
    if ($proc.ExitCode -eq 0) {
        Log ("concluido: {0}" -f $Titulo)
        Status 'pronto.'
    } else {
        Log ("a janela de '{0}' terminou com codigo {1} - veja a saida acima." -f $Titulo, $proc.ExitCode) -Erro
    }
    return $proc.ExitCode
}

function Resetar-WindowsUpdate {
    $bloco = @'
Write-Host '== Resetando o Windows Update ==' -ForegroundColor Cyan
Write-Host 'Parando servicos...'
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
Stop-Service -Name cryptsvc -Force -ErrorAction SilentlyContinue
Stop-Service -Name dosvc -Force -ErrorAction SilentlyContinue
Write-Host 'Renomeando pastas de cache...'
$sd = "$env:SystemRoot\SoftwareDistribution"
$dst = "$env:SystemRoot\SoftwareDistribution.old"
$bt = "$env:SystemRoot\System32\catroot2"
if (Test-Path $sd) { Rename-Item -Path $sd -NewName 'SoftwareDistribution.old' -Force -ErrorAction SilentlyContinue }
if (Test-Path $bt) { Rename-Item -Path $bt -NewName 'catroot2.old' -Force -ErrorAction SilentlyContinue }
if (Test-Path $dst) { Remove-Item -Path $dst -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Reiniciando servicos...'
Start-Service -Name cryptsvc -ErrorAction SilentlyContinue
Start-Service -Name bits -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Start-Service -Name dosvc -ErrorAction SilentlyContinue
Write-Host 'Windows Update resetado. Se os downloads voltarem a falhar, reinicie o PC.'
'@
    Executar-NoConsole -Titulo 'Reset do Windows Update' -Bloco $bloco
}

function Resetar-Rede {
    $bloco = @'
Write-Host '== Resetando a rede ==' -ForegroundColor Cyan
ipconfig /flushdns
Write-Host 'Resetando winsock...'
netsh winsock reset
Write-Host 'Resetando pilha TCP/IP...'
netsh int ip reset
Write-Host 'Liberando e renovando IP...'
ipconfig /release
ipconfig /renew
Write-Host ''
Write-Host 'REINICIE O PC para completar a correcao.' -ForegroundColor Yellow
'@
    Executar-NoConsole -Titulo 'Reset da rede' -Bloco $bloco
}

function Verificar-Integridade {
    $bloco = @'
Write-Host '== Verificacao de integridade do sistema ==' -ForegroundColor Cyan
Write-Host '1/2 - DISM (pode demorar varios minutos)...' -ForegroundColor Cyan
Dism.exe /Online /Cleanup-Image /RestoreHealth
if (-not $?) { Write-Host 'DISM reportou problemas ou nao conseguiu concluir.' -ForegroundColor Yellow }
Write-Host '2/2 - SFC (varredura de arquivos de sistema)...' -ForegroundColor Cyan
sfc /scannow
'@
    Executar-NoConsole -Titulo 'Verificacao de integridade (DISM + SFC)' -Bloco $bloco
}

function Manutencao-DISM {
    $bloco = @'
Write-Host '== Limpeza do armazenamento de componentes ==' -ForegroundColor Cyan
Write-Host 'Isso apaga versoes antigas de atualizacoes do Windows. Pode demorar.'
Dism.exe /Online /Cleanup-Image /StartComponentCleanup
'@
    Executar-NoConsole -Titulo 'Limpeza DISM de componentes' -Bloco $bloco
}

function Verificar-Disco {
    $bloco = @'
Write-Host '== Verificacao do disco C: (online, sem interromper o uso) ==' -ForegroundColor Cyan
chkdsk C: /scan
if ($LASTEXITCODE -eq 0) { Write-Host 'Nenhum erro encontrado.' -ForegroundColor Green }
'@
    Executar-NoConsole -Titulo 'Verificacao de disco (chkdsk /scan)' -Bloco $bloco
}

function Limpeza-Disco {
    $bloco = @'
Write-Host '== Limpeza de disco profunda no C: ==' -ForegroundColor Cyan
Write-Host 'Executando cleanmgr automatico...'
cleanmgr.exe /d C: /VERYLOWDISK
Write-Host 'Limpeza de componentes obsoletos do Windows...'
Dism.exe /Online /Cleanup-Image /StartComponentCleanup
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
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $apagados++
            }
    }
    Ocupado $false
    Log ("temporarios limpos ({0} itens; alguns em uso sao ignorados). " -f $apagados)
    Status 'pronto.'
}

function Limpar-DNS {
    ipconfig /flushdns | Out-Null
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
        Executar-Acao ([pscustomobject]@{ tipo = 'comando'; executar = "Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriverInQualityUpdate' -ErrorAction SilentlyContinue"; reverter = ''; contexto = '' }) 'desbloquear drivers'
    }
    if ($AdiarRecursos) {
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'DeferFeatureUpdates'; tipoValor = 'DWord'; dados = '1' }) 'adiar recursos'
        Executar-Acao ([pscustomobject]@{ tipo = 'registro'; caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; nome = 'DeferFeatureUpdatesPeriodInDays'; tipoValor = 'DWord'; dados = '180' }) 'adiar recursos - periodo'
    } else {
        Executar-Acao ([pscustomobject]@{ tipo = 'comando'; executar = "Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DeferFeatureUpdates','DeferFeatureUpdatesPeriodInDays' -ErrorAction SilentlyContinue" }) 'adiar recursos - remover'
    }
    $arq = Salvar-Sessao
    if ($arq) { Log ("sessao de atualizacoes salva para desfazer: {0}" -f (Split-Path -Leaf $arq)) }
    Status 'atualizacoes configuradas. reinicie para aplicar de vez.'
}

function Tem-Atualizacoes {
    $r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    return $r
}

# ---- winget ----

function Testar-Winget {
    try { $null = & winget --version 2>$null; return $true } catch { return $false }
}

function Instalar-Winget {
    $bloco = @'
Write-Host '== Instalando o winget (App Installer) ==' -ForegroundColor Cyan
Add-AppxPackage 'https://aka.ms/getwinget'
winget --version
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
        [void]$linhas.AppendLine("Write-Host ('### ' + '$($app.nome)') -ForegroundColor Cyan")
        [void]$linhas.AppendLine("winget install --id $($app.id) -e $fonte --silent --accept-package-agreements --accept-source-agreements")
    }
    Executar-NoConsole -Titulo 'Instalacao de aplicativos' -Bloco $linhas.ToString()
}

function Atualizar-Tudo {
    if (-not (Testar-Winget)) { Log 'winget nao encontrado; use a instalacao do winget na aba Config.' -Erro; return }
    $blocovo = @'
Write-Host '== Atualizando todos os aplicativos ==' -ForegroundColor Cyan
winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
'@
    Executar-NoConsole -Titulo 'Atualizar todos os apps (winget)' -Bloco $blocovo
}
