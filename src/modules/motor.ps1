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
        'MultiString' { return [Microsoft.Win32.RegistryValueKind]::MultiString }
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
    param([string]$CaminhoPS, [string]$Nome)
    $rede = Converter-Hive $CaminhoPS
    $partes = $rede -split '\\', 2
    $raiz = Obter-RaizRegistro $partes[0]
    if ($null -eq $raiz -or $partes.Count -ne 2) { throw ('Caminho de registro invalido: ' + $CaminhoPS) }
    $resultado = @{ valor = $null; existia = $false; tipo = 'DWord'; rede = $rede }
    $chave = $raiz.OpenSubKey($partes[1], $false)
    if ($null -eq $chave) { return $resultado }
    try {
        if ($chave.GetValueNames() -contains $Nome) {
            $resultado.existia = $true
            $resultado.tipo = $chave.GetValueKind($Nome).ToString()
            if (@('DWord','QWord','String','ExpandString','Binary','MultiString') -notcontains $resultado.tipo) {
                throw ('Tipo de registro nao suportado: ' + $resultado.tipo)
            }
            $resultado.valor = $chave.GetValue($Nome, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        return $resultado
    } finally { $chave.Dispose() }
}

# Compara o tipo e o conteudo sem expandir variaveis nem confundir arrays.
function Registro-Corresponde {
    param($Leitura, [bool]$Existe, [string]$Tipo, $Valor)
    if ([bool]$Leitura.existia -ne $Existe) { return $false }
    if (-not $Existe) { return $true }
    if ($Leitura.tipo -ne $Tipo) { return $false }
    if ($Tipo -eq 'DWord') { return ([int]$Leitura.valor -eq [int]$Valor) }
    if ($Tipo -eq 'QWord') { return ([long]$Leitura.valor -eq [long]$Valor) }
    if ($Tipo -in @('Binary','MultiString')) {
        $a = @($Leitura.valor); $b = @($Valor)
        if ($a.Count -ne $b.Count) { return $false }
        for ($i=0; $i -lt $a.Count; $i++) { if ([string]$a[$i] -cne [string]$b[$i]) { return $false } }
        return $true
    }
    return ([string]$Leitura.valor -ceq [string]$Valor)
}

# ---- journal da sessao ----

function Iniciar-Sessao {
    param([string]$Rotulo)
    Confirmar-PermissaoAlteracao
    $global:SessaoItens = New-Object System.Collections.ArrayList
    $global:RotuloSessao = $Rotulo
    $global:ErrosSessao = 0
    $global:CarimboSessao = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
    $global:SessaoCriado = (Get-Date -Format 'o')
    $global:BackupN = 0
    $global:SessaoArquivo = $null
}

# caminho do journal desta sessao (criado so na primeira acao, pra nao gerar
# arquivo vazio quando o usuario cancela antes de mexer em nada)
function Obter-ArquivoSessao {
    if (-not [string]::IsNullOrWhiteSpace($global:SessaoArquivo)) { return $global:SessaoArquivo }
    Verificar-PastaPrivada $global:PastaDesfazer
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
    Confirmar-PermissaoAlteracao
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
    Confirmar-PermissaoAlteracao
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
    Verificar-PastaPrivada $global:PastaDesfazer
    return @(Get-ChildItem -LiteralPath $global:PastaDesfazer -File -Filter '*.json' | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object LastWriteTime -Descending)
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

# Servicos: nao presumir tipo anterior, nem mexer em estados transitorios.
function Obter-EstadoServico {
    param([string]$Nome)
    if ($Nome -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Nome de servico invalido.' }
    $svc = Get-Service -Name $Nome -ErrorAction Stop
    $tipo = $svc.StartType.ToString()
    $estado = $svc.Status.ToString()
    if ($tipo -notin @('Automatic','Manual','Disabled') -or $estado -notin @('Running','Stopped')) { throw 'Servico em estado nao suportado; tente mais tarde.' }
    $delay = Ler-ValorRegistro ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $Nome) 'DelayedAutoStart'
    return [pscustomobject]@{ tipo=$tipo; estado=$estado; atraso=($tipo -eq 'Automatic' -and $delay.existia -and [int]$delay.valor -eq 1) }
}

function Definir-InicioServico {
    param([string]$Nome,[string]$Tipo,[bool]$Atraso)
    Confirmar-PermissaoAlteracao
    if ($Nome -notmatch '^[A-Za-z0-9_.-]+$' -or $Tipo -notin @('Automatic','Manual','Disabled')) { throw 'Configuracao de servico invalida.' }
    $modo = switch ($Tipo) {
        'Automatic' { if ($Atraso) { 'delayed-auto' } else { 'auto' } }
        'Manual' { 'demand' }
        'Disabled' { 'disabled' }
    }
    $exe = Join-Path $env:SystemRoot 'System32\sc.exe'
    $proc = Start-Process -FilePath $exe -ArgumentList @('config',$Nome,'start=',$modo) -NoNewWindow -Wait -PassThru -ErrorAction Stop
    try { if ($proc.ExitCode -ne 0) { throw ('sc.exe falhou: ' + $proc.ExitCode) } } finally { $proc.Dispose() }
}

function Alterar-ServicoComJournal {
    param([string]$Nome,[string]$Inicio)
    Confirmar-PermissaoAlteracao
    $ant = Obter-EstadoServico $Nome
    if ($Inicio -notin @('Automatic','Manual','Disabled')) { throw 'Tipo de inicio invalido.' }
    if ($ant.tipo -eq $Inicio -and ($Inicio -ne 'Disabled' -or $ant.estado -eq 'Stopped')) { return }
    $depois = if ($Inicio -eq 'Disabled') { 'Stopped' } else { $ant.estado }
    Registrar-Jornal ([pscustomobject]@{
        tipo='servico'; nome=$Nome; tipoAnterior=$ant.tipo; estadoAnterior=$ant.estado; atrasoAnterior=$ant.atraso
        tipoDepois=$Inicio; estadoDepois=$depois; atrasoDepois=$false
    })
    if ($Inicio -eq 'Disabled' -and $ant.estado -eq 'Running') {
        Stop-Service -Name $Nome -ErrorAction Stop
        (Get-Service -Name $Nome).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
    }
    Definir-InicioServico $Nome $Inicio $false
    $novo = Obter-EstadoServico $Nome
    if ($novo.tipo -ne $Inicio -or $novo.estado -ne $depois -or $novo.atraso) { throw 'Estado do servico diferente do esperado.' }
}

# Importacao restrita: apenas valores simples em HKCU Software, sem apagar chaves.
# Arquivos completos sao analisados antes de qualquer efeito.
function Ler-PlanoRegRestrito {
    param([string]$Texto)
    $linhas = @($Texto -split '\r?\n')
    if ($linhas.Count -gt 1000 -or $linhas[0].Trim([char]0xFEFF).Trim() -ne 'Windows Registry Editor Version 5.00') { throw 'Formato REGEDIT5 esperado, ate 1000 linhas.' }
    $chave = ''
    $acoes = @()
    foreach ($linha in ($linhas | Select-Object -Skip 1)) {
        $l = $linha.Trim()
        if (-not $l -or $l.StartsWith(';')) { continue }
        if ($l -match '^\[HKEY_CURRENT_USER\\Software\\([^\]]+)\]$') {
            $sub = $Matches[1]
            if ($sub -match '^(Microsoft|Classes|Policies|Clients|RegisteredApplications)(\\|$)' -or $sub.Contains('..')) { throw 'Chave reservada; importacao recusada.' }
            $chave = 'HKCU:\Software\' + $sub
            continue
        }
        if (-not $chave -or $l -notmatch '^(@|"[^"\\]*")\s*=\s*(.+)$') { throw 'Linha .reg nao suportada: somente valores simples em HKCU Software.' }
        $nome = if ($Matches[1] -eq '@') { '' } else { $Matches[1].Trim('"') }
        $dado = $Matches[2]
        $acao = [ordered]@{ tipo='registro'; caminho=$chave; nome=$nome; tipoValor='String'; dados=''; remover=$false }
        if ($dado -eq '-') { $acao.remover=$true }
        elseif ($dado -match '^dword:([0-9a-fA-F]{8})$') {
            $acao.tipoValor='DWord'
            $acao.dados=[Convert]::ToInt32($Matches[1],16)
        } elseif ($dado -match '^"((?:[^"\\]|\\["\\])*)"$') {
            $acao.dados=[regex]::Replace($Matches[1],'\\(["\\])','$1')
        } else { throw 'Tipo .reg nao suportado. Use string, DWORD ou exclusao de valor.' }
        $acoes += [pscustomobject]$acao
    }
    if ($acoes.Count -eq 0) { throw 'Nenhum valor suportado no arquivo.' }
    return $acoes
}

# Assinatura de definicao da tarefa, ignorando somente Settings/Enabled.
function Assinatura-TarefaXml {
    param([string]$Texto)
    $doc = New-Object Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.LoadXml($Texto)
    foreach ($node in @($doc.SelectNodes("/*[local-name()='Task']/*[local-name()='Settings']/*[local-name()='Enabled']"))) {
        [void]$node.ParentNode.RemoveChild($node)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($doc.OuterXml)))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Obter-AssinaturaTarefa {
    param([string]$Caminho,[string]$Nome)
    return (Assinatura-TarefaXml (Export-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop))
}

function Desativar-TarefaComJournal {
    param([string]$Caminho,[string]$Nome)
    Confirmar-PermissaoAlteracao
    if (-not $Caminho.StartsWith('\') -or $Caminho.StartsWith('\Microsoft\',[StringComparison]::OrdinalIgnoreCase) -or $Caminho -ieq '\Microsoft') { throw 'Tarefa de sistema ou caminho invalido.' }
    if ($Nome -match '[*?\[\]]' -or $Caminho -match '[*?\[\]]') { throw 'Identificador ambiguo.' }
    $tarefas = @(Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop)
    if ($tarefas.Count -ne 1 -or $tarefas[0].TaskName -ne $Nome -or $tarefas[0].TaskPath -ne $Caminho) { throw 'Tarefa nao identificada unicamente.' }
    $atual = $tarefas[0]
    if ($atual.State -eq 'Disabled') { return }
    if ($atual.State -ne 'Ready') { throw 'Tarefa em execucao ou estado incerto; nao modificada.' }
    $assinatura = Obter-AssinaturaTarefa $Caminho $Nome
    Registrar-Jornal ([pscustomobject]@{ tipo='tarefa'; tarefaPath=$Caminho; tarefaNome=$Nome; estadoAnterior='Ready'; estadoDepois='Disabled'; assinatura=$assinatura })
    Disable-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop | Out-Null
    if ((Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop).State -ne 'Disabled') { throw 'Desativacao nao confirmada.' }
}

function Testar-AppxProtegido {
    param($Pacote)
    return ([bool]($Pacote.IsFramework -or $Pacote.NonRemovable -or $Pacote.IsResourcePackage -or
        [string]$Pacote.Name -match '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|SecHealthUI|VCLibs|NET\.Native|UI\.Xaml)(\.|$)|MicrosoftWindows\.|Microsoft\.Windows\.|windows\.immersivecontrolpanel$)'))
}

function Testar-AppxCatalogado {
    param([string]$Nome)
    return (@($global:CatalogoUwp.pacotes | Where-Object { $_.pacote -eq $Nome -and -not $_.protegido -and -not $_.desconhecido }).Count -eq 1)
}

function Executar-Acao {
    param($Acao, [string]$Contexto, [switch]$Simular)

    $desc = $Contexto
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = $Acao.tipo }

    if ($Simular) {
        Log ('[SIMULAR] ' + $desc + ': ' + (Descrever-Acao $Acao))
        return
    }

    Confirmar-PermissaoAlteracao
    $ErrorActionPreference = 'Stop'
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
                    Executar-RegNativo -Operacao export -Alvo $leitura.rede -Arquivo $arqBackup
                    if (-not (Test-Path $arqBackup)) { $arqBackup = $null }
                } catch { $arqBackup = $null }
                $kind = Converter-Kind $Acao.tipoValor
                $dados = $Acao.dados
                if (-not $Acao.remover) {
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $dados = [int]$Acao.dados }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $dados = [long]$Acao.dados }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $dados = [byte[]]@($Acao.dados) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $dados = [string[]]@($Acao.dados) }
                }
                Registrar-Jornal ([pscustomobject]@{
                    tipo         = 'registro'
                    caminho      = $Acao.caminho
                    nome         = $Acao.nome
                    existia      = $leitura.existia
                    valorAnterior = (ConvertTo-Json -InputObject $leitura.valor -Compress)
                    valorAnteriorEstruturado = [pscustomobject]@{ valor = $leitura.valor }
                    tipoAnterior = $leitura.tipo
                    existiaDepois = (-not [bool]$Acao.remover)
                    tipoDepois = $kind.ToString()
                    valorDepoisEstruturado = [pscustomobject]@{ valor = $dados }
                    backupReg    = $arqBackup
                })
                if ($Acao.remover) {
                    if ($leitura.existia) {
                        $partes = $leitura.rede -split '\\',2
                        $raiz = Obter-RaizRegistro $partes[0]
                        $chave = $raiz.OpenSubKey($partes[1],$true)
                        if (-not $chave) { throw 'Chave indisponivel para remocao.' }
                        try { $chave.DeleteValue([string]$Acao.nome,$true) } finally { $chave.Dispose() }
                    }
                    if ((Ler-ValorRegistro $Acao.caminho $Acao.nome).existia) { throw 'Remocao de valor nao confirmada.' }
                    Log ('valor de registro removido: ' + $Acao.nome)
                    return
                }
                [Microsoft.Win32.Registry]::SetValue($leitura.rede, $Acao.nome, $dados, $kind) | Out-Null
                if (-not (Registro-Corresponde (Ler-ValorRegistro $Acao.caminho $Acao.nome) $true $kind.ToString() $dados)) { throw 'Gravacao de registro nao confirmada.' }
                Log ("registro: {0} -> {1} = {2}" -f $Acao.caminho, $Acao.nome, $Acao.dados)
            }

            'reg-import' { throw 'Importacao integral de .reg desativada; carregue um plano restrito por valor.' }

            'servico' {
                if (-not (Get-Service -Name $Acao.nome -ErrorAction SilentlyContinue)) { Log ('servico ausente: ' + $Acao.nome); return }
                Alterar-ServicoComJournal $Acao.nome $Acao.inicio
                Log ('configuracao de servico verificada: ' + $Acao.nome)
            }

            'comando' {
                throw 'Comandos livres nao sao suportados nesta versao.'
            }

            'appx' {
                # Remocao apenas do usuario atual, sem afetar outros usuarios
                # nem o provisionamento. O nome deve ser exato.
                if (-not (Testar-AppxCatalogado $Acao.pacote)) { throw 'Pacote fora do catalogo de remocao.' }
                $pkgs = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -eq $Acao.pacote })
                if (@($pkgs | Where-Object { Testar-AppxProtegido $_ }).Count -gt 0) { throw 'Pacote protegido; nenhum pacote removido.' }
                $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                foreach ($p in $pkgs) {
                    if (Testar-AppxProtegido $p) { throw ('Pacote protegido: ' + $p.Name) }
                    Registrar-Jornal ([pscustomobject]@{
                        tipo = 'appx'; pacote = $p.Name; completo = $p.PackageFullName
                        familia = $p.PackageFamilyName; usuarioSid = $sid
                    })
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                    if (@(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $p.PackageFullName }).Count -gt 0) { throw 'Pacote continua instalado.' }
                    $global:CacheAppxCarregadoEm = $null
                    Log ('appx removido do usuario atual: ' + $p.Name)
                }
                if ($pkgs.Count -eq 0) { Log ("appx '{0}' nao esta instalado no usuario atual." -f $Acao.pacote) }
            }

            'recurso' {
                $antes = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ nome=$_.FeatureName; estado=$_.State.ToString() } })
                $feat = @($antes | Where-Object { $_.nome -eq $Acao.nome })
                if ($feat.Count -ne 1) { throw 'Recurso nao encontrado.' }
                $alvo = if ($Acao.ativar) { 'Enabled' } else { 'Disabled' }
                if ($feat[0].estado -eq $alvo) { Log 'Recurso ja configurado.'; return }
                if ($feat[0].estado -notin @('Enabled','Disabled')) { throw 'Recurso em estado pendente ou payload removido; revise pelo Windows.' }
                $entrada = [pscustomobject]@{ tipo='recurso'; nome=$Acao.nome; estadoAnterior=$feat[0].estado; estadoDepois=$alvo; alteracoes=$null }
                Registrar-Jornal $entrada
                if ($Acao.ativar) { $resultado = Enable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -All -NoRestart -ErrorAction Stop }
                else { $resultado = Disable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -NoRestart -ErrorAction Stop }
                $depois = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop)
                $mapa = @{}
                foreach ($f in $depois) { $mapa[$f.FeatureName]=$f.State.ToString() }
                $entrada.alteracoes = @($antes | Where-Object { $mapa[$_.nome] -ne $_.estado } | ForEach-Object { [pscustomobject]@{ nome=$_.nome; antes=$_.estado; depois=$mapa[$_.nome] } })
                [void](Gravar-SessaoArquivo)
                if ($resultado.RestartNeeded -or $mapa[$Acao.nome] -ne $alvo) { Log 'Recurso processado; reinicio ou revisao necessarios.' }
                else { Log ('recurso verificado: ' + $Acao.nome) }
            }

            'energia' {
                $saida = (powercfg /getactivescheme) 2>&1 | Out-String
                $guidAnterior = $null
                if ($saida -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') { $guidAnterior = $Matches[1] }
                Registrar-Jornal ([pscustomobject]@{
                    tipo         = 'energia'
                    guidAnterior = $guidAnterior
                })
                if (-not $guidAnterior) { throw 'Plano de energia original indisponivel.' }
                powercfg /setactive $Acao.guid | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Falha ao alterar plano de energia.' }
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
    Confirmar-PermissaoAlteracao
    $ErrorActionPreference = 'Stop'
    try {
        switch ($Item.tipo) {

            'registro' {
                $rede = Converter-Hive $Item.caminho
                if ($Item.PSObject.Properties['existiaDepois']) {
                    $atual = Ler-ValorRegistro -CaminhoPS $Item.caminho -Nome $Item.nome
                    if (Registro-Corresponde $atual ([bool]$Item.existia) $Item.tipoAnterior $Item.valorAnteriorEstruturado.valor) {
                        Log ('registro ja esta no estado anterior: ' + $Item.nome)
                        return $true
                    }
                    if (-not (Registro-Corresponde $atual ([bool]$Item.existiaDepois) $Item.tipoDepois $Item.valorDepoisEstruturado.valor)) {
                        throw ('Conflito: valor mudou desde a aplicacao. Preservado: ' + $Item.caminho + '\\' + $Item.nome)
                    }
                }
                if ($Item.existia) {
                    $kind = Converter-Kind $Item.tipoAnterior
                    if ($null -ne $Item.valorAnteriorEstruturado) { $valor = $Item.valorAnteriorEstruturado.valor }
                    else { $valor = ($Item.valorAnterior | ConvertFrom-Json) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $valor = [int]$valor }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $valor = [long]$valor }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $valor = [byte[]]@($valor) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $valor = [string[]]@($valor) }
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

            'reg-import' { throw 'Importacao integral antiga: recupere manualmente para evitar sobrescrever valores posteriores.' }

            'servico' {
                if (-not $Item.PSObject.Properties['tipoDepois']) { throw 'Journal antigo de servico sem snapshot posterior; revise manualmente.' }
                $atual = Obter-EstadoServico $Item.nome
                if ($atual.tipo -eq $Item.tipoAnterior -and $atual.estado -eq $Item.estadoAnterior -and $atual.atraso -eq $Item.atrasoAnterior) { return $true }
                if ($atual.tipo -ne $Item.tipoDepois -or $atual.estado -ne $Item.estadoDepois -or $atual.atraso -ne $Item.atrasoDepois) { throw 'Servico alterado depois da sessao; preservado.' }
                Definir-InicioServico $Item.nome $Item.tipoAnterior ([bool]$Item.atrasoAnterior)
                if ($Item.estadoAnterior -eq 'Running' -and $atual.estado -ne 'Running') {
                    Start-Service -Name $Item.nome -ErrorAction Stop
                    (Get-Service -Name $Item.nome).WaitForStatus('Running',[TimeSpan]::FromSeconds(20))
                } elseif ($Item.estadoAnterior -eq 'Stopped' -and $atual.estado -ne 'Stopped') {
                    Stop-Service -Name $Item.nome -ErrorAction Stop
                    (Get-Service -Name $Item.nome).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
                }
                $final = Obter-EstadoServico $Item.nome
                if ($final.tipo -ne $Item.tipoAnterior -or $final.estado -ne $Item.estadoAnterior -or $final.atraso -ne $Item.atrasoAnterior) { throw 'Servico nao retornou ao estado original.' }
                Log ('servico restaurado e verificado: ' + $Item.nome)
            }

            'comando' {
                throw 'Journal antigo com comando livre: recupere manualmente e registre a confirmacao.'
            }

            'energia' {
                if ($Item.guidAnterior) {
                    powercfg /setactive $Item.guidAnterior | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'Falha ao restaurar plano de energia.' }
                    Log ("plano de energia restaurado: {0}" -f $Item.guidAnterior)
                }
            }

            'recurso' {
                if ($null -eq $Item.alteracoes -or @($Item.alteracoes).Count -ne 1 -or $Item.alteracoes[0].nome -ne $Item.nome) { throw 'Dependencias ou estado incerto: revise os recursos do Windows manualmente.' }
                $atual = (Get-WindowsOptionalFeature -Online -FeatureName $Item.nome -ErrorAction Stop).State.ToString()
                if ($atual -eq $Item.estadoAnterior) { return $true }
                if ($atual -ne $Item.estadoDepois -or $atual -notin @('Enabled','Disabled')) { throw 'Recurso em estado pendente ou alterado posteriormente.' }
                if ($Item.estadoAnterior -eq 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $Item.nome -NoRestart -ErrorAction Stop | Out-Null }
                elseif ($Item.estadoAnterior -eq 'Disabled') { Disable-WindowsOptionalFeature -Online -FeatureName $Item.nome -NoRestart -ErrorAction Stop | Out-Null }
                else { throw 'Estado anterior nao suportado.' }
                if ((Get-WindowsOptionalFeature -Online -FeatureName $Item.nome -ErrorAction Stop).State.ToString() -ne $Item.estadoAnterior) { throw 'Reversao pendente; confira apos reiniciar.' }
                Log ('recurso restaurado e verificado: ' + $Item.nome)
            }

            'appx' {
                # tenta reinstalar pro usuario atual; quando a remocao foi
                # por usuario (o pacote continua staged na maquina), volta
                # na hora; quando foi -AllUsers, so pela Store mesmo
                if ($Item.usuarioSid -and $Item.usuarioSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'A sessao AppX pertence a outro usuario.' }
                if (@(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -eq $Item.pacote }).Count -gt 0) { Log 'appx ja esta instalado no usuario atual.'; return $true }
                $fez = $false
                if (-not [string]::IsNullOrWhiteSpace([string]$Item.familia)) {
                    try {
                        Add-AppxPackage -RegisterByFamilyName -MainPackage $Item.familia -ErrorAction Stop
                        $fez = (@(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -eq $Item.pacote }).Count -gt 0)
                    } catch { $fez = $false }
                }
                if ($fez) {
                    $global:CacheAppxCarregadoEm = $null
                    Log ("appx '{0}' reinstalado pelo desfazer (familia: {1})." -f $Item.pacote, $Item.familia)
                } else {
                    throw ('Reinstalacao manual necessaria pela Microsoft Store: ' + $Item.pacote)
                }
            }

            'desinstalado-app' {
                throw ('Reinstalacao manual necessaria: ' + $Item.nome)
            }

            'tarefa' {
                if (-not $Item.assinatura -or (Obter-AssinaturaTarefa $Item.tarefaPath $Item.tarefaNome) -ne $Item.assinatura) { throw 'Definicao da tarefa incerta ou alterada; revise manualmente.' }
                $atual = (Get-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop).State
                if ($atual -eq 'Ready') { return $true }
                if ($atual -ne 'Disabled') { throw 'Estado da tarefa mudou.' }
                Enable-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop | Out-Null
                if ((Get-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop).State -eq 'Disabled') { throw 'Reativacao nao confirmada.' }
                Log ('tarefa reativada: ' + $Item.tarefaNome)
            }

            'firewall-estado' {
                Set-NetFirewallRule -PolicyStore PersistentStore -Name $Item.nome -Enabled $Item.ativada -ErrorAction Stop | Out-Null
                Log ('estado da regra de firewall restaurado: ' + $Item.nome)
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
                    try {
                        $kind = $ck2.GetValueKind('Path')
                        if ($Item.PSObject.Properties['valorDepois']) {
                            $atual = [string]$ck2.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                            if ($atual -ceq [string]$Item.valorAnterior) { return $true }
                            if ($atual -cne [string]$Item.valorDepois -or $kind.ToString() -ne $Item.tipoAnterior) { throw 'PATH mudou desde a limpeza; nao sobrescrevendo.' }
                        }
                        $ck2.SetValue('Path', [string]$Item.valorAnterior, $kind)
                    } finally { $ck2.Dispose() }
                    Log ("entrada restaurada no PATH {0}: {1}" -f [string]$Item.escopo, [string]$Item.entrada)
                }
            }

            'quarantena-arquivo' {
                if ((Test-Path -LiteralPath $Item.destino) -and -not (Test-Path -LiteralPath $Item.origem)) {
                    $pai = Split-Path -Parent $Item.origem
                    if (-not (Test-Path -LiteralPath $pai -PathType Container)) { throw 'Pasta original ausente; revise antes de restaurar.' }
                    $atual = $pai
                    while ($atual) {
                        $dir = Get-Item -LiteralPath $atual -Force -ErrorAction Stop
                        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Caminho de restauracao redirecionado.' }
                        $superior = Split-Path -Parent $atual
                        if (-not $superior -or $superior -eq $atual) { break }
                        $atual = $superior
                    }
                    Move-Item -LiteralPath $Item.destino -Destination $Item.origem -ErrorAction Stop
                    Log ("rastro restaurado da quarantena: " + $Item.origem)
                } else {
                    throw ("Backup ausente ou conflito no destino: " + $Item.origem)
                }
            }

            'quarantena-registro' {
                if (Test-Path $Item.arquivoReg) {
                    if (Test-Path -LiteralPath ('Registry::' + $Item.chave)) { throw 'Chave recriada desde a limpeza; nao sobrescrevendo.' }
                    Executar-RegNativo -Operacao import -Alvo $Item.arquivoReg
                    if (-not (Test-Path -LiteralPath ('Registry::' + $Item.chave))) { throw 'Importacao terminou sem restaurar a chave.' }
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
    param([string]$Arquivo, [switch]$UmaAcao)
    Confirmar-PermissaoAlteracao
    $ErrorActionPreference = 'Stop'
    try {
        $json = Ler-JSON $Arquivo
        if ($null -eq $json -or $null -eq $json.itens) { throw 'Journal invalido.' }
        $itens = @($json.itens)
        $feitas = 0
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
            $feitas++
            Atualizar-UI
            if ($UmaAcao -and $feitas -ge 1) { break }
        }
        if (@($itens | Where-Object { $_.estadoReversao -ne 'concluido' }).Count -gt 0) {
            Log 'Uma acao revertida. Restam itens nesta sessao.'
            return $true
        }
        $novoNome = (Split-Path -Leaf $Arquivo) + '.revertido'
        Rename-Item -LiteralPath $Arquivo -NewName $novoNome -ErrorAction Stop
        Log 'sessao revertida. algumas mudancas podem exigir relogar no windows.'
        return $true
    } catch {
        Log ('Reversao interrompida: ' + $_.Exception.Message) -Erro
        return $false
    }
}

# Atestado manual: registra a verificacao feita pelo usuario, sem repetir a acao.
function Confirmar-ReversaoManual {
    param([string]$Arquivo, [int]$Indice)
    Confirmar-PermissaoAlteracao
    $ErrorActionPreference = 'Stop'
    $json = Ler-JSON $Arquivo
    $itens = @($json.itens)
    for ($i = $itens.Count - 1; $i -ge 0; $i--) {
        if ($itens[$i].estadoReversao -eq 'concluido') { continue }
        if ($i -ne $Indice -or $itens[$i].estadoReversao -ne 'em_andamento') { throw 'Somente a ultima acao incerta pode ser confirmada.' }
        $itens[$i].estadoReversao = 'concluido'
        $itens[$i] | Add-Member -NotePropertyName confirmadoManualEm -NotePropertyValue (Get-Date -Format 'o') -Force
        Gravar-JSONAtomico -Arquivo $Arquivo -Objeto $json
        Log ('Acao ' + $i + ' confirmada manualmente pelo usuario, sem repetir a operacao.')
        if (@($itens | Where-Object { $_.estadoReversao -ne 'concluido' }).Count -eq 0) {
            Rename-Item -LiteralPath $Arquivo -NewName ((Split-Path -Leaf $Arquivo) + '.revertido') -ErrorAction Stop
        }
        return
    }
    throw 'Nenhuma acao incerta encontrada.'
}

# ---- ponto de restauracao ----

function Criar-PontoRestauracao {
    Confirmar-PermissaoAlteracao
    try {
        $antes=@(Get-ComputerRestorePoint -ErrorAction Stop)
        $descricao='OtimizadorPC '+[guid]::NewGuid().ToString('N').Substring(0,12)
        Checkpoint-Computer -Description $descricao -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $novos=@(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $descricao -and $_.SequenceNumber -notin @($antes | ForEach-Object {$_.SequenceNumber}) })
        if ($novos.Count -ne 1) { throw 'Novo ponto nao confirmado (limite diario ou protecao indisponivel).' }
        Log 'novo ponto de restauracao confirmado.'
        return $true
    } catch {
        Log ('Ponto de restauracao nao confirmado: '+$_.Exception.Message) -Erro
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
        if ($n -eq $Pacote) { return $true }
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
                if ($Acao.remover) { return (-not $leitura.existia) }
                if (-not $leitura.existia) { return $false }
                if ($leitura.tipo -ne (Converter-Kind $Acao.tipoValor).ToString()) { return $false }
                if ($leitura.tipo -eq 'DWord') { return ([int]$leitura.valor -eq [int]$Acao.dados) }
                if ($leitura.tipo -eq 'QWord') { return ([long]$leitura.valor -eq [long]$Acao.dados) }
                if ($leitura.tipo -eq 'Binary' -or $leitura.tipo -eq 'MultiString') {
                    $a = @($leitura.valor); $b = @($Acao.dados)
                    if ($a.Count -ne $b.Count) { return $false }
                    for ($i=0; $i -lt $a.Count; $i++) { if ([string]$a[$i] -cne [string]$b[$i]) { return $false } }
                    return $true
                }
                return ([string]$leitura.valor -ceq [string]$Acao.dados)
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
    if ($ativos -eq $verificaveis -and $verificaveis -eq @($Tweak.acoes).Count) { return 'aplicado' }
    if ($ativos -eq 0) { return 'nao' }
    return 'parcial'
}

# ---- presets via linha de comando (modo cli) ----

# aplica um preset de nivel (seguro/balanceado/agressivo) sem janela nenhuma.
# usado pelo modo cli: .\otimizadorpc.ps1 -Cli balanceado [-Simular]
# replica o fluxo do botao aplicar da gui: restore point, journal por acao e log em arquivo.
# Perfis conservadores: selecao explicita por ID, sem scripts customizados.
function Obter-PerfilRecomendado {
    if (@($global:AmbienteTrabalho | Where-Object { $_ }).Count -gt 0) { return 'corporativo' }
    try {
        if (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0) { return 'notebook' }
    } catch { }
    return 'essencial'
}

function Selecionar-TweaksPreset {
    param([string]$Nivel, $Catalogo, [bool]$Win11)
    if ($Nivel -eq 'recomendado') { $Nivel = Obter-PerfilRecomendado }
    $perfis = @{
        essencial   = @('extensoes-de-arquivo', 'apps-sugeridos')
        gamer       = @('extensoes-de-arquivo', 'mouse-precisao', 'finalizar-tarefa-barra')
        notebook    = @('extensoes-de-arquivo', 'bateria-porcentagem', 'apps-sugeridos')
        privacidade = @('extensoes-de-arquivo', 'historico-atividades', 'apps-sugeridos', 'bing-no-menu-iniciar')
        corporativo = @('extensoes-de-arquivo')
    }
    $legado = @('seguro', 'balanceado', 'agressivo') -contains $Nivel
    if (-not $legado -and -not $perfis.ContainsKey($Nivel)) { throw ('Preset desconhecido: ' + $Nivel) }
    foreach ($t in $Catalogo.tweaks) {
        if ($t.id -like 'custom-*' -or $t.apenasManual) { continue }
        if (($t.so -eq 'win11' -and -not $Win11) -or ($t.so -eq 'win10' -and $Win11)) { continue }
        if (($legado -and ($t.niveis -contains $Nivel)) -or (-not $legado -and ($perfis[$Nivel] -contains $t.id))) {
            $t
        }
    }
}

function Aplicar-Preset {
    param([string]$Nivel, [switch]$Simular)

    try {
        $selecionados = @(Selecionar-TweaksPreset -Nivel $Nivel -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11))
    } catch {
        Log $_.Exception.Message -Erro
        return $false
    }
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

    Confirmar-PermissaoAlteracao
    if (-not (Criar-PontoRestauracao)) { Log 'Preset real interrompido: ponto de restauracao novo nao confirmado.' -Erro; return $false }
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
    if (-not (Test-Path -LiteralPath $pasta -PathType Container)) { return }
    foreach ($arq in @(Get-ChildItem -LiteralPath $pasta -File -Filter '*.reg' -ErrorAction SilentlyContinue)) {
        try {
            if ($arq.Length -gt 128KB -or ($arq.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Arquivo grande ou redirecionado.' }
            $acoes = @(Ler-PlanoRegRestrito ([IO.File]::ReadAllText($arq.FullName)))
            [pscustomobject]@{ id=('custom-' + ($arq.BaseName.ToLower() -replace '[^a-z0-9-]','-')); nome=('Custom: ' + $arq.BaseName); desc='Plano local restrito: valores simples HKCU Software com journal individual. Revise antes de aplicar.'; categoria='Customizadas'; niveis=@(); so='ambos'; apenasManual=$true; acoes=$acoes }
        } catch { Log ('Custom ignorado: ' + $arq.Name + ' - ' + $_.Exception.Message) }
    }
}
