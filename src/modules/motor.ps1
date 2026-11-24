# motor.ps1 - motor de acoes: registro, servicos, comandos, appx, recursos e energia
# cada acao executada e registrada no journal da sessao para poder ser desfeita depois

# ---- helpers de registro ----

function Converter-Hive {
    # "HKLM:\SOFTWARE\Foo" -> "HKEY_LOCAL_MACHINE\SOFTWARE\Foo" (formato da API .NET)
    param([string]$CaminhoPS)
    $mapa = @(
        , @('HKLM:', 'HKEY_LOCAL_MACHINE')
        , @('HKCU:', 'HKEY_CURRENT_USER')
        , @('HKU:',  'HKEY_USERS')
        , @('HKCR:', 'HKEY_CLASSES_ROOT')
    )
    foreach ($par in $mapa) {
        if ($CaminhoPS.StartsWith($par[0])) {
            return ($par[1] + $CaminhoPS.Substring($par[0].Length))
        }
    }
    return $CaminhoPS
}

function Obter-RaizRegistro {
    param([string]$NomeRaiz)
    switch ($NomeRaiz) {
        'HKEY_LOCAL_MACHINE' { return [Microsoft.Win32.Registry]::LocalMachine }
        'HKEY_CURRENT_USER'  { return [Microsoft.Win32.Registry]::CurrentUser }
        'HKEY_USERS'         { return [Microsoft.Win32.Registry]::Users }
        'HKEY_CLASSES_ROOT'  { return [Microsoft.Win32.Registry]::ClassesRoot }
    }
    return $null
}

function Converter-Kind {
    param([string]$NomeTipo)
    switch ($NomeTipo) {
        'DWord'      { return [Microsoft.Win32.RegistryValueKind]::DWord }
        'QWord'      { return [Microsoft.Win32.RegistryValueKind]::QWord }
        'String'     { return [Microsoft.Win32.RegistryValueKind]::String }
        'ExpandString' { return [Microsoft.Win32.RegistryValueKind]::ExpandString }
        'Binary'     { return [Microsoft.Win32.RegistryValueKind]::Binary }
    }
    return [Microsoft.Win32.RegistryValueKind]::String
}

# infere o kind de um valor lido do registro
function Inferir-Kind {
    param($Valor)
    if ($null -eq $Valor) { return 'DWord' }
    if ($Valor -is [int] -or $Valor -is [uint32]) { return 'DWord' }
    if ($Valor -is [long]) { return 'QWord' }
    if ($Valor -is [byte[]]) { return 'Binary' }
    return 'String'
}

function Ler-ValorRegistro {
    # le um valor do registro pela notacao PS (HKLM:\...) e devolve hashtable com valor + existia
    param([string]$CaminhoPS, [string]$Nome)
    $rede = Converter-Hive $CaminhoPS
    $atual = [Microsoft.Win32.Registry]::GetValue($rede, $Nome, $null)
    return @{
        valor    = $atual
        existia  = ($null -ne $atual)
        tipo     = (Inferir-Kind $atual)
        rede     = $rede
    }
}

# ---- journal da sessao ----

function Iniciar-Sessao {
    param([string]$Rotulo)
    $global:SessaoItens = New-Object System.Collections.ArrayList
    $global:RotuloSessao = $Rotulo
    $global:ErrosSessao = 0
    $global:CarimboSessao = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $global:SessaoCriado = (Get-Date -Format 'o')
    $global:BackupN = 0
    $global:SessaoArquivo = $null
}

# caminho do journal desta sessao (criado so na primeira acao, pra nao gerar
# arquivo vazio quando o usuario cancela antes de mexer em nada)
function Obter-ArquivoSessao {
    if (-not [string]::IsNullOrWhiteSpace($global:SessaoArquivo)) { return $global:SessaoArquivo }
    $global:SessaoArquivo = Join-Path $global:PastaDesfazer ("{0}_{1}.json" -f $global:CarimboSessao, ($global:RotuloSessao -replace '[^a-z0-9-]', ''))
    return $global:SessaoArquivo
}

# grava o journal inteiro no arquivo (chamado a CADA acao: se o pc ou o app
# morrer no meio, o que ja foi feito continua desfazivel)
function Gravar-SessaoArquivo {
    $arquivo = Obter-ArquivoSessao
    $obj = [pscustomobject]@{
        criado = $global:SessaoCriado
        rotulo = $global:RotuloSessao
        itens  = @($global:SessaoItens)
    }
    Gravar-JSONAtomico -Arquivo $arquivo -Objeto $obj
    return $arquivo
}

function Gravar-JSONAtomico {
    param([string]$Arquivo, $Objeto)
    $json = ConvertTo-Json -InputObject $Objeto -Depth 12
    # Grava no mesmo volume e publica somente apos fechar e sincronizar.
    $temporario = $arquivo + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stream = [System.IO.File]::Open($temporario, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        if ([System.IO.File]::Exists($arquivo)) {
            [System.IO.File]::Replace($temporario, $arquivo, $arquivo + '.bak')
        } else {
            [System.IO.File]::Move($temporario, $arquivo)
        }
    } finally {
        if ([System.IO.File]::Exists($temporario)) {
            [System.IO.File]::Delete($temporario)
        }
    }
}

function Registrar-Jornal {
    param($Item)
    if ($null -eq $global:SessaoItens) { throw 'Sessao de journal nao iniciada.' }
    [void]$global:SessaoItens.Add($Item)
    try {
        [void](Gravar-SessaoArquivo)
    } catch {
        $global:SessaoItens.RemoveAt($global:SessaoItens.Count - 1)
        throw
    }
}

function Salvar-Sessao {
    if ($null -eq $global:SessaoItens -or $global:SessaoItens.Count -eq 0) { return $null }
    return (Gravar-SessaoArquivo)
}

function Listar-Sessoes {
    if (-not (Test-Path $global:PastaDesfazer)) { return @() }
    return @(Get-ChildItem -Path $global:PastaDesfazer -Filter '*.json' | Sort-Object LastWriteTime -Descending)
}

# descreve em texto o que uma acao faria (usado no modo simulacao)
function Descrever-Acao {
    param($Acao)
    switch ($Acao.tipo) {
        'registro' { return ('registro: {0}\{1} = {2} ({3})' -f $Acao.caminho, $Acao.nome, $Acao.dados, $Acao.tipoValor) }
        'servico'  { return ('servico: {0} -> inicio {1}' -f $Acao.nome, $Acao.inicio) }
        'comando'  { return ('comando: {0}' -f $Acao.executar) }
        'appx'     { return ('appx: remover {0}' -f $Acao.pacote) }
        'recurso'  { return ('recurso do windows: {0} -> {1}' -f $Acao.nome, $Acao.ativar) }
        'energia'  { return ('plano de energia: {0}' -f $Acao.guid) }
        'reg-import' { return ('importar arquivo .reg do usuario: {0}' -f $Acao.arquivo) }
    }
    return ('acao: ' + $Acao.tipo)
}

# ---- executor de acoes ----

function Executar-Acao {
    param($Acao, [string]$Contexto, [switch]$Simular)

    $desc = $Contexto
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = $Acao.tipo }

    if ($Simular) {
        Log ('[SIMULAR] ' + $desc + ': ' + (Descrever-Acao $Acao))
        return
    }

    try {
        switch ($Acao.tipo) {

            'registro' {
                $leitura = Ler-ValorRegistro -CaminhoPS $Acao.caminho -Nome $Acao.nome
                # cinto e suspensorios: exporta a chave inteira em .reg antes de mexer
                $arqBackup = $null
                try {
                    $global:BackupN++
                    $folha = ($leitura.rede -replace '\\', '_')
                    if ($folha.Length -gt 60) { $folha = $folha.Substring($folha.Length - 60) }
                    $arqBackup = Join-Path $global:PastaDesfazer ('{0}_reg_{1:00}_{2}.reg' -f $global:CarimboSessao, $global:BackupN, $folha)
                    reg.exe export $leitura.rede $arqBackup /y 2>$null | Out-Null
                    if (-not (Test-Path $arqBackup)) { $arqBackup = $null }
                } catch { $arqBackup = $null }
                Registrar-Jornal ([pscustomobject]@{
                    tipo         = 'registro'
                    caminho      = $Acao.caminho
                    nome         = $Acao.nome
                    existia      = $leitura.existia
                    valorAnterior = ($leitura.valor | ConvertTo-Json -Compress)
                    tipoAnterior = $leitura.tipo
                    backupReg    = $arqBackup
                })
                $kind = Converter-Kind $Acao.tipoValor
                $dados = $Acao.dados
                if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $dados = [int]$Acao.dados }
                if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $dados = [long]$Acao.dados }
                [Microsoft.Win32.Registry]::SetValue($leitura.rede, $Acao.nome, $dados, $kind) | Out-Null
                Log ("registro: {0} -> {1} = {2}" -f $Acao.caminho, $Acao.nome, $Acao.dados)
            }

            'reg-import' {
                # tweak custom do usuario: importa um arquivo .reg inteiro.
                # antes de importar, exporta backup .reg de cada chave que o
                # arquivo toca; chaves que ainda nao existiam sao apagadas no
                # desfazer (revive via backup nas outras).
                if (-not (Test-Path $Acao.arquivo)) {
                    Log ("arquivo .reg nao encontrado: {0}, pulando." -f $Acao.arquivo)
                    return
                }
                $conteudo = Get-Content -Path $Acao.arquivo -Raw
                $chaves = @([regex]::Matches($conteudo, '(?m)^\[\-?(HKEY_[^\]]+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
                if ($chaves.Count -eq 0) {
                    Log ("o arquivo .reg {0} nao declara nenhuma chave [HKEY_...]; nada a fazer." -f (Split-Path -Leaf $Acao.arquivo))
                    return
                }
                $backups = @()
                $novas = @()
                foreach ($chave in $chaves) {
                    $global:BackupN++
                    $folha = ($chave -replace '[\\/:*?"<>|]', '_')
                    if ($folha.Length -gt 60) { $folha = $folha.Substring($folha.Length - 60) }
                    $arqBackup = Join-Path $global:PastaDesfazer ('{0}_regimp_{1:00}_{2}.reg' -f $global:CarimboSessao, $global:BackupN, $folha)
                    reg.exe export $chave $arqBackup /y 2>$null | Out-Null
                    if (Test-Path $arqBackup) { $backups += $arqBackup } else { $novas += $chave }
                }
                Registrar-Jornal ([pscustomobject]@{
                    tipo        = 'reg-import'
                    arquivo     = $Acao.arquivo
                    backups     = @($backups)
                    chavesNovas = @($novas)
                    contexto    = $desc
                })
                $saidaImp = reg.exe import $Acao.arquivo 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw ('reg import falhou (codigo {0}): {1}' -f $LASTEXITCODE, $saidaImp.Trim()) }
                Log ("registro: .reg importado ({0} chave(s), {1} com backup): {2}" -f $chaves.Count, @($backups).Count, $Acao.arquivo)
            }

            'servico' {
                $svc = Get-Service -Name $Acao.nome -ErrorAction SilentlyContinue
                if ($null -eq $svc) {
                    Log ("servico '{0}' nao existe neste windows, pulando." -f $Acao.nome)
                    return
                }
                Registrar-Jornal ([pscustomobject]@{
                    tipo            = 'servico'
                    nome            = $Acao.nome
                    tipoAnterior    = $svc.StartType.ToString()
                    estadoAnterior  = $svc.Status.ToString()
                })
                Set-Service -Name $Acao.nome -StartupType $Acao.inicio -ErrorAction Stop
                if ($Acao.inicio -eq 'Disabled' -and $svc.Status -eq 'Running') {
                    Stop-Service -Name $Acao.nome -Force -ErrorAction SilentlyContinue
                }
                Log ("servico: {0} -> {1}" -f $Acao.nome, $Acao.inicio)
            }

            'comando' {
                Registrar-Jornal ([pscustomobject]@{
                    tipo     = 'comando'
                    contexto = $desc
                    reverter = $Acao.reverter
                })
                $saida = (Invoke-Expression $Acao.executar 2>&1 | Out-String).Trim()
                if ($saida.Length -gt 0) {
                    $resumo = $saida.Substring(0, [Math]::Min(220, $saida.Length))
                    Log ("  saida: " + $resumo)
                }
                Log ("comando: {0}" -f $desc)
            }

            'appx' {
                $achou = $false
                $pkgs = @(Get-AppxPackage | Where-Object { $_.Name -like ($Acao.pacote + '*') })
                foreach ($p in $pkgs) {
                    $achou = $true
                    Registrar-Jornal ([pscustomobject]@{
                        tipo     = 'appx'
                        pacote   = $p.Name
                        completo = $p.PackageFullName
                        familia  = $p.PackageFamilyName
                    })
                    try {
                        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                    } catch {
                        try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { throw }
                    }
                    Log ("appx removido: {0}" -f $p.Name)
                }
                try {
                    $prov = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like ($Acao.pacote + '*') -or $_.PackageName -like ($Acao.pacote + '*') })
                    foreach ($pr in $prov) {
                        Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction Stop | Out-Null
                        Log ("appx desprovisionado (novos usuarios nao receberao): {0}" -f $pr.DisplayName)
                    }
                } catch { }
                if (-not $achou) { Log ("appx '{0}' nao esta instalado, nada a fazer." -f $Acao.pacote) }
            }

            'recurso' {
                $feat = Get-WindowsOptionalFeature -Online -FeatureName $Acao.nome -ErrorAction SilentlyContinue
                if ($null -eq $feat) {
                    Log ("recurso do windows '{0}' nao encontrado, pulando." -f $Acao.nome)
                    return
                }
                Registrar-Jornal ([pscustomobject]@{
                    tipo           = 'recurso'
                    nome           = $Acao.nome
                    estadoAnterior = $feat.State.ToString()
                })
                if ($Acao.ativar) {
                    Enable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -All -NoRestart -ErrorAction Stop | Out-Null
                    Log ("recurso habilitado: {0}" -f $Acao.nome)
                } else {
                    Disable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -NoRestart -ErrorAction Stop | Out-Null
                    Log ("recurso desabilitado: {0}" -f $Acao.nome)
                }
            }

            'energia' {
                $saida = (powercfg /getactivescheme) 2>&1 | Out-String
                $guidAnterior = $null
                if ($saida -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') { $guidAnterior = $Matches[1] }
                Registrar-Jornal ([pscustomobject]@{
                    tipo         = 'energia'
                    guidAnterior = $guidAnterior
                })
                powercfg /setactive $Acao.guid | Out-Null
                Log ("plano de energia alterado (anterior: {0})" -f $guidAnterior)
            }

            default {
                Log ("tipo de acao desconhecido: {0}" -f $Acao.tipo) -Erro
            }
        }
    } catch {
        Log ("falha ao aplicar '{0}': {1}" -f $desc, $_.Exception.Message) -Erro
    }
}

# ---- desfazer ----

function Desfazer-Item {
    param($Item)
    $ErrorActionPreference = 'Stop'
    try {
        switch ($Item.tipo) {

            'registro' {
                $rede = Converter-Hive $Item.caminho
                if ($Item.existia) {
                    $kind = Converter-Kind $Item.tipoAnterior
                    $valor = ($Item.valorAnterior | ConvertFrom-Json)
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $valor = [int]$valor }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $valor = [long]$valor }
                    [Microsoft.Win32.Registry]::SetValue($rede, $Item.nome, $valor, $kind) | Out-Null
                    Log ("registro restaurado: {0}\{1}" -f $Item.caminho, $Item.nome)
                } else {
                    $partes = $rede -split '\\', 2
                    if ($partes.Count -eq 2) {
                        $raiz = Obter-RaizRegistro $partes[0]
                        $chave = $raiz.OpenSubKey($partes[1], $true)
                        if ($chave) {
                            $chave.DeleteValue($Item.nome, $false)
                            $chave.Close()
                        }
                    }
                    Log ("registro removido: {0}\{1}" -f $Item.caminho, $Item.nome)
                }
            }

            'reg-import' {
                foreach ($arq in @($Item.backups)) {
                    if (-not [string]::IsNullOrWhiteSpace($arq) -and (Test-Path $arq)) {
                        reg.exe import $arq 2>$null | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw 'Falha ao importar backup do registro.' }
                        Log ('registro restaurado do backup: ' + (Split-Path -Leaf $arq))
                    } else { throw 'Backup custom ausente.' }
                }
                foreach ($chave in @($Item.chavesNovas)) {
                    if (-not [string]::IsNullOrWhiteSpace($chave)) {
                        reg.exe delete $chave /f 2>$null | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw 'Falha ao remover chave custom.' }
                        Log ('chave que nao existia antes foi removida: ' + $chave)
                    }
                }
                Log ('tweak custom revertido: ' + $Item.arquivo)
            }

            'servico' {
                $tipoOk = $Item.tipoAnterior
                if (@('Automatic', 'Manual', 'Disabled') -notcontains $tipoOk) { $tipoOk = 'Manual' }
                Set-Service -Name $Item.nome -StartupType $tipoOk -ErrorAction Stop
                if ($Item.estadoAnterior -eq 'Running') {
                    Start-Service -Name $Item.nome -ErrorAction Stop
                } elseif ($Item.estadoAnterior -eq 'Stopped') {
                    Stop-Service -Name $Item.nome -ErrorAction Stop
                }
                Log ("servico restaurado: {0} -> {1}" -f $Item.nome, $tipoOk)
            }

            'comando' {
                if (-not [string]::IsNullOrWhiteSpace($Item.reverter)) {
                    Invoke-Expression $Item.reverter 2>&1 | Out-Null
                    Log ("comando revertido: {0}" -f $Item.contexto)
                }
            }

            'energia' {
                if ($Item.guidAnterior) {
                    powercfg /setactive $Item.guidAnterior | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'Falha ao restaurar plano de energia.' }
                    Log ("plano de energia restaurado: {0}" -f $Item.guidAnterior)
                }
            }

            'recurso' {
                if ($Item.estadoAnterior -eq 'Enabled') {
                    Enable-WindowsOptionalFeature -Online -FeatureName $Item.nome -All -NoRestart -ErrorAction Stop | Out-Null
                } else {
                    Disable-WindowsOptionalFeature -Online -FeatureName $Item.nome -NoRestart -ErrorAction Stop | Out-Null
                }
                Log ("recurso restaurado: {0}" -f $Item.nome)
            }

            'appx' {
                # tenta reinstalar pro usuario atual; quando a remocao foi
                # por usuario (o pacote continua staged na maquina), volta
                # na hora; quando foi -AllUsers, so pela Store mesmo
                $fez = $false
                if (-not [string]::IsNullOrWhiteSpace([string]$Item.familia)) {
                    try {
                        Add-AppxPackage -RegisterByFamilyName -MainPackage $Item.familia -ErrorAction Stop
                        $fez = $true
                    } catch { $fez = $false }
                }
                if ($fez) {
                    Log ("appx '{0}' reinstalado pelo desfazer (familia: {1})." -f $Item.pacote, $Item.familia)
                } else {
                    throw ('Reinstalacao manual necessaria pela Microsoft Store: ' + $Item.pacote)
                }
            }

            'desinstalado-app' {
                throw ('Reinstalacao manual necessaria: ' + $Item.nome)." -f $Item.nome)
            }

            'tarefa' {
                Enable-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop | Out-Null
                Log ("tarefa reativada: {0}{1}" -f [string]$Item.tarefaPath, [string]$Item.tarefaNome)
            }

            'regra-firewall' {
                $p = @{ DisplayName = [string]$Item.displayName; Direction = [string]$Item.dir; Action = [string]$Item.acao; Enabled = [string]$Item.ativada }
                $perfis = @(([string]$Item.perfil -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                if ($perfis.Count -gt 0) { $p['Profile'] = $perfis }
                if (-not [string]::IsNullOrWhiteSpace([string]$Item.programa)) { $p['Program'] = [string]$Item.programa }
                if (-not [string]::IsNullOrWhiteSpace([string]$Item.servico)) { $p['Service'] = [string]$Item.servico }
                $proto = [string]$Item.protocolo
                if ($proto -ne '' -and $proto -ne 'Any') { $p['Protocol'] = $proto }
                $pls = @(([string]$Item.portasLocais -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne 'Any' })
                if ($pls.Count -gt 0) { $p['LocalPort'] = $pls }
                $prs = @(([string]$Item.portasRemotas -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne 'Any' })
                if ($prs.Count -gt 0) { $p['RemotePort'] = $prs }
                $ils = @(([string]$Item.ipLocal -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne 'Any' })
                if ($ils.Count -gt 0) { $p['LocalAddress'] = $ils }
                $irs = @(([string]$Item.ipRemoto -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne 'Any' })
                if ($irs.Count -gt 0) { $p['RemoteAddress'] = $irs }
                New-NetFirewallRule @p | Out-Null
                Log ("regra de firewall recriada: {0}" -f [string]$Item.displayName)
            }

            'path-entrada' {
                $ck2 = $null
                if ([string]$Item.escopo -eq 'Machine') {
                    $ck2 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
                } else {
                    $ck2 = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
                }
                if ($null -eq $ck2) {
                    throw ("Chave do PATH ausente: " + [string]$Item.escopo)
                } else {
                    $kind = $ck2.GetValueKind('Path')
                    $ck2.SetValue('Path', [string]$Item.valorAnterior, $kind)
                    $ck2.Close()
                    Log ("entrada restaurada no PATH {0}: {1}" -f [string]$Item.escopo, [string]$Item.entrada)
                }
            }

            'quarantena-arquivo' {
                if ((Test-Path $Item.destino) -and -not (Test-Path $Item.origem)) {
                    $pai = Split-Path -Parent $Item.origem
                    if (-not (Test-Path $pai)) { New-Item -Path $pai -ItemType Directory -Force | Out-Null }
                    Move-Item -Path $Item.destino -Destination $Item.origem -Force
                    Log ("rastro restaurado da quarantena: " + $Item.origem)
                } else {
                    throw ("Backup ausente ou conflito no destino: " + $Item.origem)
                }
            }

            'quarantena-registro' {
                if (Test-Path $Item.arquivoReg) {
                    reg.exe import $Item.arquivoReg 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'Falha ao importar registro da quarentena.' }
                    Log ("chave de registro restaurada: " + $Item.chave)
                } else {
                    throw ("Backup do registro nao encontrado: " + $Item.arquivoReg)
                }
            }
            default { throw ('Tipo de reversao desconhecido: ' + $Item.tipo) }
        }
        return $true
    } catch {
        Log ("falha ao desfazer item '{0}': {1}" -f $Item.tipo, $_.Exception.Message) -Erro
        return $false
    }
}

function Reverter-Sessao {
    param([string]$Arquivo)
    $ErrorActionPreference = 'Stop'
    try {
        $json = Ler-JSON $Arquivo
        if ($null -eq $json -or $null -eq $json.itens) { throw 'Journal invalido.' }
        $itens = @($json.itens)
        for ($i = $itens.Count - 1; $i -ge 0; $i--) {
            $item = $itens[$i]
            if ($item.estadoReversao -eq 'concluido') { continue }
            if ($item.estadoReversao -eq 'em_andamento') {
                throw ("Acao {0} com resultado incerto. Revise manualmente antes de continuar." -f $i)
            }
            $item | Add-Member -NotePropertyName estadoReversao -NotePropertyValue 'em_andamento' -Force
            Gravar-JSONAtomico -Arquivo $Arquivo -Objeto $json
            if (-not (Desfazer-Item $item)) {
                throw ("Falha na acao {0}. Journal preservado; revisao manual necessaria." -f $i)
            }
            $item.estadoReversao = 'concluido'
            Gravar-JSONAtomico -Arquivo $Arquivo -Objeto $json
            Atualizar-UI
        }
        $novoNome = (Split-Path -Leaf $Arquivo) + '.revertido'
        Rename-Item -LiteralPath $Arquivo -NewName $novoNome -ErrorAction Stop
        Log 'sessao revertida. algumas mudancas podem exigir relogar no windows.'
    } catch {
        Log ('Reversao interrompida: ' + $_.Exception.Message) -Erro
    }
}

# ---- ponto de restauracao ----

function Criar-PontoRestauracao {
    try {
        try { $temPonto = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { $temPonto = @() }
        if ($temPonto.Count -eq 0) {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        }
        Checkpoint-Computer -Description "OtimizadorPC - antes de aplicar ajustes" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'ponto de restauracao criado.'
        return $true
    } catch {
        Log ("nao foi possivel criar ponto de restauracao: {0}" -f $_.Exception.Message) -Erro
        Log 'voce pode ativar a protecao do sistema em: este computador > propriedades > protecao do sistema.'
        return $false
    }
}

# ---- verificacao de estado (o que ja esta aplicado) ----

# cache dos pacotes appx instalados (Get-AppxPackage e lento pra chamar toda hora)
function Carregar-CacheAppx {
    $vencido = $true
    if ($null -ne $global:CacheAppxCarregadoEm) {
        if (((Get-Date) - $global:CacheAppxCarregadoEm).TotalSeconds -lt 120) { $vencido = $false }
    }
    if ($vencido) {
        $global:CacheAppx = @(Get-AppxPackage | ForEach-Object { $_.Name })
        $global:CacheAppxCarregadoEm = Get-Date
    }
}

function Appx-Instalado {
    param([string]$Pacote)
    Carregar-CacheAppx
    foreach ($n in $global:CacheAppx) {
        if ($n -like ($Pacote + '*')) { return $true }
    }
    return $false
}

# verifica uma acao do catalogo: $true = em vigor, $false = nao, $null = nao verificavel
function Verificar-Acao {
    param($Acao)
    try {
        switch ($Acao.tipo) {
            'registro' {
                $leitura = Ler-ValorRegistro -CaminhoPS $Acao.caminho -Nome $Acao.nome
                if (-not $leitura.existia) { return $false }
                if ($leitura.tipo -eq 'DWord') { return ([int]$leitura.valor -eq [int]$Acao.dados) }
                if ($leitura.tipo -eq 'QWord') { return ([long]$leitura.valor -eq [long]$Acao.dados) }
                return ([string]$leitura.valor -eq [string]$Acao.dados)
            }
            'servico' {
                $svc = Get-Service -Name $Acao.nome -ErrorAction SilentlyContinue
                if ($null -eq $svc) { return $null }
                return ($svc.StartType.ToString() -eq $Acao.inicio)
            }
            'appx' {
                return (-not (Appx-Instalado $Acao.pacote))
            }
            'energia' {
                $saida = (powercfg /getactivescheme) 2>&1 | Out-String
                return $saida.Contains($Acao.guid)
            }
            default { return $null }
        }
    } catch { return $null }
}

# estado de um tweak: 'aplicado', 'parcial', 'nao' ou 'desconhecido'
function Verificar-Tweak {
    param($Tweak)
    if (-not [string]::IsNullOrWhiteSpace($Tweak.verificar)) {
        try {
            if (Invoke-Expression $Tweak.verificar) { return 'aplicado' }
            return 'nao'
        } catch { return 'desconhecido' }
    }
    $verificaveis = 0
    $ativos = 0
    foreach ($acao in $Tweak.acoes) {
        $r = Verificar-Acao $acao
        if ($null -ne $r) {
            $verificaveis++
            if ($r) { $ativos++ }
        }
    }
    if ($verificaveis -eq 0) { return 'desconhecido' }
    if ($ativos -eq $verificaveis) { return 'aplicado' }
    if ($ativos -eq 0) { return 'nao' }
    return 'parcial'
}

# ---- presets via linha de comando (modo cli) ----

# aplica um preset de nivel (seguro/balanceado/agressivo) sem janela nenhuma.
# usado pelo modo cli: .\otimizadorpc.ps1 -Cli balanceado [-Simular]
# replica o fluxo do botao aplicar da gui: restore point, journal por acao e log em arquivo.
function Aplicar-Preset {
    param([string]$Nivel, [switch]$Simular)

    $validos = @('seguro', 'balanceado', 'agressivo')
    if ($validos -notcontains $Nivel) {
        Log ('nivel de preset desconhecido: ' + $Nivel + '. use: seguro, balanceado ou agressivo.') -Erro
        return $false
    }

    # mesmo filtro da gui: respeita tweaks exclusivos de win10/win11
    $win11 = Eh-Win11
    $selecionados = @($global:CatalogoTweaks.tweaks | Where-Object {
        ($_.niveis -contains $Nivel) -and
        -not (($_.so -eq 'win11') -and (-not $win11)) -and
        -not (($_.so -eq 'win10') -and $win11)
    })
    if ($selecionados.Count -eq 0) {
        Log ('nenhum ajuste encontrado para o nivel ' + $Nivel + '.') -Erro
        return $false
    }

    Log ('==== preset ' + $Nivel + ': ' + $selecionados.Count + ' ajuste(s) ====')
    if ($Simular) {
        Log '==== SIMULACAO: nada sera alterado ===='
        foreach ($t in $selecionados) {
            Log ('== ajuste: ' + $t.nome + ' (simulado)')
            foreach ($acao in $t.acoes) { Executar-Acao $acao $t.nome -Simular }
        }
        Log 'SIMULACAO concluida: o pc NAO foi alterado.'
        return $true
    }

    [void](Criar-PontoRestauracao)
    Iniciar-Sessao 'ajustes'
    $i = 0
    foreach ($t in $selecionados) {
        $i++
        Log ('aplicando {0}/{1}: {2}' -f $i, $selecionados.Count, $t.nome)
        foreach ($acao in $t.acoes) { Executar-Acao $acao $t.nome }
    }
    $arq = Salvar-Sessao
    if ($global:ErrosSessao -gt 0) {
        Log ('preset ' + $Nivel + ' concluido com ' + $global:ErrosSessao + ' erro(s); detalhes no arquivo de log.') -Erro
        return $false
    }
    Log ('preset ' + $Nivel + ' aplicado sem erros.')
    if ($arq) { Log ('salvei o journal desta sessao para desfazer depois: ' + (Split-Path -Leaf $arq)) }
    Log 'alguns ajustes exigem relogar no windows.'
    return $true
}

# ---- tweaks custom do usuario (arquivos .reg na pasta custom\) ----

# le cada .reg da pasta custom\ e devolve um tweak por arquivo.
# os customs aparecem na aba ajustes (categoria Customizadas), nunca entram
# em preset nenhum (niveis vazio) e tem journal/desfazer como qualquer outro.
function Carregar-TweaksCustom {
    $pasta = Join-Path $global:PastaApp 'custom'
    $lista = @()
    if (-not (Test-Path $pasta)) {
        # cria a pasta vazia pra ficar visivel onde jogar os arquivos
        try { New-Item -Path $pasta -ItemType Directory -Force | Out-Null } catch { }
        return @()
    }
    $arqs = @(Get-ChildItem -Path $pasta -Filter '*.reg' -ErrorAction SilentlyContinue)
    foreach ($a in $arqs) {
        $id = 'custom-' + ($a.BaseName.ToLower() -replace '[^a-z0-9-]', '-')
        $lista += [pscustomobject]@{
            id       = $id
            nome     = ('Custom: ' + $a.BaseName)
            desc     = 'arquivo .reg seu em custom\. ao aplicar, o app exporta backup de cada chave tocada; o desfazer restaura os backups (chaves que nao existiam voltam a ser apagadas). este ajuste e manual: preset nenhum aplica sozinho.'
            categoria= 'Customizadas'
            niveis   = @()
            so       = 'ambos'
            acoes    = @([pscustomobject]@{ tipo = 'reg-import'; arquivo = $a.FullName })
        }
    }
    return $lista
}
