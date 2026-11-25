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
        if ($CaminhoPS.StartsWith($par[0],[StringComparison]::OrdinalIgnoreCase)) {
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

# Bind new sessions to the actual identity and registry view, not a PC profile.
function Obter-ContextoJournal {
    $identidade=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $sid=$identidade.User.Value
        if (-not $sid) {throw 'SID do contexto indisponivel.'}
        $maquina=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        $id=[guid]::Empty
        if (-not [guid]::TryParse($maquina,[ref]$id) -or $id -eq [guid]::Empty) {throw 'Identidade local da maquina indisponivel.'}
        return [pscustomobject]@{usuarioSid=$sid;maquina=$id.ToString();registro64=[Environment]::Is64BitProcess}
    } finally {$identidade.Dispose()}
}

function Confirmar-ContextoJournal {
    param($Journal,$Atual)
    # Legacy journals remain readable; no identity assertion can be inferred.
    if (-not $Journal.PSObject.Properties['versaoEsquema']) {return}
    if ($Journal.versaoEsquema -ne 2 -or -not $Journal.contexto) {throw 'Esquema de journal desconhecido ou incompleto.'}
    if (-not $PSBoundParameters.ContainsKey('Atual')) {$Atual=Obter-ContextoJournal}
    $c=$Journal.contexto
    if (-not $c.usuarioSid -or -not $c.maquina -or $c.registro64 -isnot [bool] -or
        -not $Atual -or $Atual.registro64 -isnot [bool] -or $c.usuarioSid -ne $Atual.usuarioSid -or $c.maquina -ne $Atual.maquina -or $c.registro64 -ne $Atual.registro64) {
        throw 'Journal pertence a outro usuario, maquina ou visao de registro; reversao indisponivel neste contexto.'
    }
}

function Iniciar-Sessao {
    param([string]$Rotulo)
    Confirmar-PermissaoAlteracao 'estado-local'
    $global:ContextoSessaoJournal = Obter-ContextoJournal
    $global:SessaoItens = New-Object System.Collections.ArrayList
    $global:RotuloSessao = $Rotulo
    $global:ErrosSessao = 0
    $global:JournalFalhou=$false
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
    try {
    Confirmar-ContextoJournal ([pscustomobject]@{versaoEsquema=2;contexto=$global:ContextoSessaoJournal})
    $arquivo = Obter-ArquivoSessao
    $obj = [pscustomobject]@{
        versaoEsquema = 2
        contexto = $global:ContextoSessaoJournal
        criado = $global:SessaoCriado
        rotulo = $global:RotuloSessao
        itens  = @($global:SessaoItens)
    }
    Gravar-JournalSeguro -Arquivo $arquivo -Objeto $obj
    return $arquivo
    } catch {$global:JournalFalhou=$true;throw}
}

# Make the file ACL explicit: NTFS inheritance and File.Replace can differ by host.
function Nova-ACLJournal {
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    $admin=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $sistema=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $owner=[Security.Principal.SecurityIdentifier]::new('S-1-3-4')
    $acl.SetOwner($admin)
    foreach ($sid in @($admin,$sistema)) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))
    }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,[Security.AccessControl.FileSystemRights]::ReadPermissions,[Security.AccessControl.AccessControlType]::Allow))
    return $acl
}

function Gravar-JournalSeguro {
    param([string]$Arquivo,$Objeto)
    $pasta=[IO.Path]::GetFullPath($global:PastaDesfazer).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Arquivo)
    if ([IO.Path]::GetDirectoryName($full) -ine $pasta -or [IO.Path]::GetExtension($full) -ine '.json' -or [IO.Path]::GetFileName($full).Contains(':')) {throw 'Destino de journal invalido.'}
    Verificar-PastaPrivada $pasta
    Confirmar-FormatoJournal $Objeto
    if (Test-Path -LiteralPath $full) {[void](Confirmar-ArquivoJournal $full)}
    $backup=$full+'.bak'
    if (Test-Path -LiteralPath $backup) {
        $b=Get-Item -LiteralPath $backup -Force -ErrorAction Stop
        if ($b.PSIsContainer -or ($b.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Backup de journal redirecionado.'}
        Confirmar-ACLArquivoPrivado $backup
    }
    Gravar-JSONAtomico -Arquivo $full -Objeto $Objeto -AclJournal
    [void](Confirmar-ArquivoJournal $full)
    if (Test-Path -LiteralPath $backup) {Confirmar-ACLArquivoPrivado $backup}
}

function Gravar-JSONAtomico {
    param([string]$Arquivo, $Objeto,[switch]$AclJournal)
    Confirmar-PermissaoAlteracao $(if ($AclJournal -or $Arquivo -ieq (Join-Path $global:RaizEstado 'preferencias.json')) {'estado-local'} else {'exportar'})
    $json = ConvertTo-Json -InputObject $Objeto -Depth 12
    # Grava no mesmo volume e publica somente apos fechar e sincronizar.
    $temporario = $arquivo + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        if ($AclJournal -and $bytes.Length -gt 67108864) {throw 'Journal acima do limite de tamanho.'}
        $stream = [System.IO.File]::Open($temporario, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        if ($AclJournal) {[IO.File]::SetAccessControl($temporario,(Nova-ACLJournal))}
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

# Classification describes the recovery contract, not a promise of data recovery.
function Obter-TipoRecuperacao {
    param($Item)
    switch ($Item.tipo) {
        {$_ -in @('registro','energia','servico','tarefa','path-entrada')} {return 'por-snapshot'}
        {$_ -in @('quarantena-arquivo','quarantena-registro','recurso','appx')} {return 'condicional'}
        'instalacao-app' {
            $plano=@($Item.plano)
            if ($Item.PSObject.Properties['plano'] -and @($plano).Count -gt 0 -and @($plano | Where-Object { [string]$_.operacao -ne 'install' }).Count -eq 0) {return 'condicional'}
            return 'manual-sem-garantia'
        }
        default {return 'manual-sem-garantia'}
    }
}

# Keep the durable intent when the effect cannot be verified. Do not persist
# exception messages that may contain credentials or private paths.
function Registrar-FalhaOperacao {
    param([string]$Categoria='efeito-nao-confirmado')
    if ($global:JournalFalhou -or -not $global:SessaoItens -or $Categoria -notin @('efeito-nao-confirmado','interrompido')) {return}
    $item=$global:SessaoItens[$global:SessaoItens.Count-1]
    if ($item.estadoAplicacao -ne 'intencao') {return}
    $item.estadoAplicacao='falhou'
    $item | Add-Member -NotePropertyName falhouEm -NotePropertyValue (Get-Date -Format 'o') -Force
    $item | Add-Member -NotePropertyName erroAplicacao -NotePropertyValue $Categoria -Force
    try {[void](Gravar-SessaoArquivo)}
    catch {$item.estadoAplicacao='intencao';$item.PSObject.Properties.Remove('falhouEm');$item.PSObject.Properties.Remove('erroAplicacao');throw}
}

function Testar-SessaoInterrompida {
    return ([bool]$global:JournalFalhou -or @($global:SessaoItens | Where-Object {$_.estadoAplicacao -in @('intencao','falhou','pendente')}).Count -gt 0)
}

# A sanitized report is constructed from an allowlist, never by removing
# selected keys from the original journal. No IDs, paths, values, dates,
# names, SID, machine identifier, raw errors or arbitrary strings.
function Obter-RelatorioRecuperacao {
    param($Journal)
    Confirmar-ContextoJournal $Journal
    Confirmar-FormatoJournal $Journal
    $n=0
    $itens=@(foreach ($item in @($Journal.itens)) {
        $n++
        $tipo=if ($item.tipo -in @('registro','energia','servico','tarefa','path-entrada','quarantena-arquivo','quarantena-registro','recurso','appx','desinstalado-app','reg-import','comando','regra-firewall','firewall-estado','instalacao-app','temp','manutencao')) {[string]$item.tipo} else {'outro'}
        $aplicacao=if ($item.estadoAplicacao -in @('intencao','confirmado','pendente','falhou')) {[string]$item.estadoAplicacao} else {'nao-confirmado'}
        $reversao=if ($item.confirmadoManualEm) {'atestado-manual'} elseif ($item.reconciliadoEm) {'reconciliado'} elseif ($item.estadoReversao -in @('pendente','em_andamento','concluido','manual-sem-restauracao')) {[string]$item.estadoReversao} else {'pendente'}
        [pscustomobject]@{ordem=$n;tipo=$tipo;aplicacao=$aplicacao;reversao=$reversao;recuperacao=(Obter-TipoRecuperacao $item);backupRegistrado=[bool]($item.destino -or $item.arquivoReg -or $item.backupReg)}
    })
    [pscustomobject]@{formato='relatorio-recuperacao-sanitizado-v1';total=$itens.Count;itens=$itens;nota='Resumo de estados registrados, nao e journal importavel nem prova de integridade dos backups.'}
}

# Old schema 2 journals may omit later status fields. Validate structural
# invariants without manufacturing missing snapshots or identity.
function Confirmar-FormatoJournal {
    param($Journal)
    if (-not $Journal -or $null -eq $Journal.itens -or $Journal.itens -isnot [array] -or @($Journal.itens).Count -gt 10000) {throw 'Estrutura de journal invalida.'}
    $ids=@{}
    foreach ($item in @($Journal.itens)) {
        if (-not $item -or $item.tipo -isnot [string] -or -not $item.tipo) {throw 'Item de journal invalido.'}
        if ($item.PSObject.Properties['estadoAplicacao'] -and $item.estadoAplicacao -notin @('intencao','confirmado','pendente','falhou')) {throw 'Estado de aplicacao invalido.'}
        if ($item.PSObject.Properties['estadoReversao'] -and $item.estadoReversao -notin @('pendente','em_andamento','concluido','manual-sem-restauracao')) {throw 'Estado de reversao invalido.'}
        if ($item.PSObject.Properties['idOperacao']) {
            $id=[guid]::Empty
            if (-not [guid]::TryParse([string]$item.idOperacao,[ref]$id) -or $id -eq [guid]::Empty -or $ids.ContainsKey($id.ToString())) {throw 'Identidade de operacao invalida ou duplicada.'}
            $ids[$id.ToString()]=$true
        }
    }
}

function Registrar-Jornal {
    param($Item)
    Confirmar-PermissaoAlteracao 'estado-local'
    if ($null -eq $global:SessaoItens) { throw 'Sessao de journal nao iniciada.' }
    if ($global:JournalFalhou) {throw 'Persistencia do journal falhou; lote interrompido. Preserve os arquivos.'}
    if (@($global:SessaoItens | Where-Object {$_.estadoAplicacao -in @('intencao','falhou','pendente')}).Count) {throw 'Existe efeito nao confirmado nesta sessao; nao iniciar outra mutacao.'}
    $Item | Add-Member -NotePropertyName idOperacao -NotePropertyValue ([guid]::NewGuid().ToString('N')) -Force
    $Item | Add-Member -NotePropertyName estadoAplicacao -NotePropertyValue 'intencao' -Force
    $Item | Add-Member -NotePropertyName registradoEm -NotePropertyValue (Get-Date -Format 'o') -Force
    $Item | Add-Member -NotePropertyName reversibilidade -NotePropertyValue (Obter-TipoRecuperacao $Item) -Force
    $Item | Add-Member -NotePropertyName estadoReversao -NotePropertyValue 'pendente' -Force
    [void]$global:SessaoItens.Add($Item)
    try {
        [void](Gravar-SessaoArquivo)
    } catch {
        $global:SessaoItens.RemoveAt($global:SessaoItens.Count - 1)
        throw
    }
}

# An intent without verified effect is not proof that a change succeeded.
function Confirmar-EfeitoJournal {
    param($Item,[ValidateSet('confirmado','pendente')][string]$Estado='confirmado')
    if (-not $Item.PSObject.Properties['idOperacao']) {return}
    if ($global:JournalFalhou -or $Item.estadoAplicacao -ne 'intencao') {throw 'Transicao de journal indisponivel.'}
    $Item.estadoAplicacao=$Estado
    $Item | Add-Member -NotePropertyName verificadoEm -NotePropertyValue (Get-Date -Format 'o') -Force
    try {[void](Gravar-SessaoArquivo)} catch {$Item.estadoAplicacao='intencao';$Item.PSObject.Properties.Remove('verificadoEm');throw}
}

function Salvar-Sessao {
    if ($null -eq $global:SessaoItens -or $global:SessaoItens.Count -eq 0) { return $null }
    if ($global:JournalFalhou) {throw 'Journal nao confirmado; preserve a ultima copia duravel.'}
    if (@($global:SessaoItens | Where-Object {$_.estadoAplicacao -eq 'intencao'}).Count) {Registrar-FalhaOperacao 'interrompido'}
    return (Gravar-SessaoArquivo)
}

# Only summaries cross to WPF. Invalid or foreign journals are never selectable targets.
# Validate a recovery target at the point of reading or mutating the journal.
function Confirmar-ACLArquivoPrivado {
    param([string]$full)
    $acl=Get-Acl -LiteralPath $full -ErrorAction Stop
    $regras=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $esperados=@('S-1-5-32-544','S-1-5-18','S-1-3-4')
    foreach ($regra in $regras) {
        $sid=$regra.IdentityReference.Value
        if ($sid -notin $esperados -or $regra.AccessControlType -ne 'Allow') {throw 'ACL do journal contem acesso inesperado.'}
        $direitos=if ($sid -eq 'S-1-3-4') {[Security.AccessControl.FileSystemRights]::ReadPermissions -bor [Security.AccessControl.FileSystemRights]::Synchronize} else {[Security.AccessControl.FileSystemRights]::FullControl}
        if ($regra.FileSystemRights -ne $direitos) {throw 'Direitos do journal nao confirmados.'}
    }
    foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
        if (@($regras | Where-Object {$_.IdentityReference.Value -eq $sid}).Count -ne 1) {throw 'ACL do journal incompleta.'}
    }
    # Trusted owner needs no OWNER RIGHTS restriction; any other owner does.
    $dono=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $ownerRules=@($regras | Where-Object {$_.IdentityReference.Value -eq 'S-1-3-4'}).Count
    if ($ownerRules -gt 1 -or ($ownerRules -ne 1 -and $dono -notin @('S-1-5-32-544','S-1-5-18'))) {throw 'Proprietario do journal nao protegido.'}
}

function Confirmar-ArquivoJournal {
    param([string]$Arquivo,[switch]$PermitirArquivado)
    if (-not $global:PastaDesfazer -or $Arquivo -notmatch '^[A-Za-z]:\\' -or ($Arquivo -notmatch '\.json$' -and (-not $PermitirArquivado -or $Arquivo -notmatch '\.json\.revertido$'))) {throw 'Caminho de journal invalido.'}
    $pasta=[IO.Path]::GetFullPath($global:PastaDesfazer).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Arquivo)
    if ([IO.Path]::GetDirectoryName($full) -ine $pasta -or [IO.Path]::GetFileName($full).Contains(':')) {throw 'Journal fora da pasta de recuperacao.'}
    Verificar-PastaPrivada $pasta
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 67108864) {throw 'Journal redirecionado ou invalido.'}
    Confirmar-ACLArquivoPrivado $full
    return $full
}

function Obter-SnapshotHistorico {
    $arquivos=@(Listar-Sessoes)
    $itens=@(foreach ($s in $arquivos) {
        $rotulo=$s.BaseName
        $valido=$false
        try {
            $arquivo=Confirmar-ArquivoJournal $s.FullName -PermitirArquivado
            $json=Ler-JSON $arquivo
            if ($null -eq $json -or $null -eq $json.itens) {throw 'Journal invalido.'}
            Confirmar-ContextoJournal $json
            Confirmar-FormatoJournal $json
            $concluidos=@($json.itens | Where-Object {$_.estadoReversao -in @('concluido','manual-sem-restauracao')}).Count
            $incertos=@($json.itens | Where-Object {$_.estadoReversao -eq 'em_andamento'}).Count
            $intencoes=@($json.itens | Where-Object {$_.estadoAplicacao -eq 'intencao'}).Count
            $pendentes=@($json.itens | Where-Object {$_.estadoAplicacao -eq 'pendente'}).Count
            $rotulo+=(' - {0}/{1} encerradas: {2}' -f $concluidos,@($json.itens).Count,$json.rotulo)
            if ($incertos -gt 0) {$rotulo+=' [reversao incerta: verificar estado anterior]'}
            if ($intencoes -gt 0) {$rotulo+=(' [intencoes nao confirmadas: '+$intencoes+']')}
            if ($pendentes -gt 0) {$rotulo+=(' [efeitos pendentes: '+$pendentes+']')}
            $falhas=@($json.itens | Where-Object {$_.estadoAplicacao -eq 'falhou'}).Count
            if ($falhas) {$rotulo+=(' [efeitos nao confirmados apos falha: '+$falhas+']')}
            if ($s.Name -like '*.revertido') {$rotulo+=' [arquivado]'}
            if (-not $json.PSObject.Properties['versaoEsquema']) {$rotulo+=' [legado: identidade nao confirmada]'}
            $valido=$true
        } catch {$rotulo+=' [invalido ou contexto diferente]'}
        [pscustomobject]@{rotulo=$rotulo;arquivo=$s.FullName;valido=$valido;arquivado=($s.Name -like '*.revertido')}
    })
    [pscustomobject]@{itens=$itens}
}

function Listar-Sessoes {
    if (-not (Test-Path $global:PastaDesfazer)) { return @() }
    Verificar-PastaPrivada $global:PastaDesfazer
    return @(Get-ChildItem -LiteralPath $global:PastaDesfazer -File | Where-Object { $_.Name -match '\.json(?:\.revertido)?$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object LastWriteTime -Descending)
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
    Confirmar-PermissaoAlteracao 'servico'
    if ($Nome -notmatch '^[A-Za-z0-9_.-]+$' -or $Tipo -notin @('Automatic','Manual','Disabled')) { throw 'Configuracao de servico invalida.' }
    Confirmar-DependenciasServico $Nome $Tipo
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
    Confirmar-PermissaoAlteracao 'servico'
    Confirmar-DependenciasServico $Nome $Inicio
    $ant = Obter-EstadoServico $Nome
    if ($ant.tipo -eq $Inicio -and ($Inicio -ne 'Disabled' -or $ant.estado -eq 'Stopped')) { return }
    $depois = if ($Inicio -eq 'Disabled') { 'Stopped' } else { $ant.estado }
    $entrada=[pscustomobject]@{
        tipo='servico'; nome=$Nome; tipoAnterior=$ant.tipo; estadoAnterior=$ant.estado; atrasoAnterior=$ant.atraso
        tipoDepois=$Inicio; estadoDepois=$depois; atrasoDepois=$false
    }
    Registrar-Jornal $entrada
    Confirmar-PermissaoAlteracao 'servico'
    Confirmar-DependenciasServico $Nome $Inicio
    $releitura=Obter-EstadoServico $Nome
    if ($releitura.tipo -ne $ant.tipo -or $releitura.estado -ne $ant.estado -or $releitura.atraso -ne $ant.atraso) {throw 'Servico mudou durante preparacao; preservado.'}
    if ($Inicio -eq 'Disabled' -and $ant.estado -eq 'Running') {
        Stop-Service -Name $Nome -ErrorAction Stop
        (Get-Service -Name $Nome).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
    }
    Definir-InicioServico $Nome $Inicio $false
    $novo = Obter-EstadoServico $Nome
    if ($novo.tipo -ne $Inicio -or $novo.estado -ne $depois -or $novo.atraso) { throw 'Estado do servico diferente do esperado.' }
    Confirmar-EfeitoJournal $entrada
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

function Confirmar-AlvoTarefa {
    param([string]$Caminho,[string]$Nome)
    if (-not $Nome -or -not $Caminho.StartsWith('\') -or $Caminho.StartsWith('\Microsoft\',[StringComparison]::OrdinalIgnoreCase) -or $Caminho -ieq '\Microsoft') {throw 'Tarefa de sistema ou caminho invalido.'}
    if ($Nome -match '[*?\[\]\\]' -or $Caminho -match '[*?\[\]]' -or $Caminho -match '(^|\\)\.{1,2}(\\|$)') {throw 'Identificador ambiguo.'}
}

function Desativar-TarefaComJournal {
    param([string]$Caminho,[string]$Nome)
    Confirmar-PermissaoAlteracao 'tarefa'
    Confirmar-AlvoTarefa $Caminho $Nome
    $tarefas = @(Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop)
    if ($tarefas.Count -ne 1 -or $tarefas[0].TaskName -ne $Nome -or $tarefas[0].TaskPath -ne $Caminho) { throw 'Tarefa nao identificada unicamente.' }
    $atual = $tarefas[0]
    if ($atual.State -eq 'Disabled') { return }
    if ($atual.State -ne 'Ready') { throw 'Tarefa em execucao ou estado incerto; nao modificada.' }
    $assinatura = Obter-AssinaturaTarefa $Caminho $Nome
    $entrada=[pscustomobject]@{ tipo='tarefa'; tarefaPath=$Caminho; tarefaNome=$Nome; estadoAnterior='Ready'; estadoDepois='Disabled'; assinatura=$assinatura }
    Registrar-Jornal $entrada
    Confirmar-PermissaoAlteracao 'tarefa'
    if ((Obter-AssinaturaTarefa $Caminho $Nome) -ne $assinatura -or (Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop).State -ne 'Ready') {throw 'Tarefa mudou durante preparacao; preservada.'}
    Disable-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop | Out-Null
    if ((Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop).State -ne 'Disabled') { throw 'Desativacao nao confirmada.' }
    Confirmar-EfeitoJournal $entrada
}

function Testar-AppxProtegido {
    param($Pacote)
    return ([bool]($Pacote.IsFramework -or $Pacote.NonRemovable -or $Pacote.IsResourcePackage -or
        [string]$Pacote.Name -match '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|SecHealthUI|VCLibs|NET\.Native|UI\.Xaml)(\.|$)|MicrosoftWindows\.|Microsoft\.Windows\.|windows\.immersivecontrolpanel$)'))
}

# Dependencias declaradas do pacote no usuario atual. Nao e grafo de
# dependencias completo de Win32 nem de outros usuarios.
function Obter-DependentesAppx {
    param($Pacote,$Pacotes)
    if (-not $Pacote.PackageFullName) { return }
    foreach ($p in @($Pacotes)) {
        if ($p.PackageFullName -eq $Pacote.PackageFullName) { continue }
        foreach ($dep in @($p.Dependencies)) {
            $full=if ($dep -is [string]) {$dep} else {[string]$dep.PackageFullName}
            if ($full -eq $Pacote.PackageFullName) { [string]$p.Name; break }
        }
    }
}

function Testar-AppxCatalogado {
    param([string]$Nome)
    return (@($global:CatalogoUwp.pacotes | Where-Object { $_.pacote -eq $Nome -and -not $_.protegido -and -not $_.desconhecido }).Count -eq 1)
}

function Obter-PlanoEnergiaAtivo {
    $exe=Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $saida=(& $exe /getactivescheme 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $saida -notmatch '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') { throw 'Plano ativo indisponivel.' }
    return $Matches[1]
}

function Confirmar-PlanoEnergiaDisponivel {
    param([string]$Guid)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($Guid,[ref]$id) -or $id -eq [guid]::Empty) {throw 'GUID de energia invalido.'}
    $exe=Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $saida=(& $exe /list 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {throw 'Consulta de planos de energia indisponivel.'}
    if ($saida -notmatch [regex]::Escape($id.ToString())) {throw 'Plano de energia nao disponivel; nao criar automaticamente.'}
}

function Definir-PlanoEnergia {
    param([string]$Guid)
    Confirmar-PermissaoAlteracao 'energia'
    $id=[guid]::Empty
    if (-not [guid]::TryParse($Guid,[ref]$id) -or $id -eq [guid]::Empty) { throw 'GUID de energia invalido.' }
    Confirmar-PoliticaEnergiaLocal
    Confirmar-PlanoEnergiaDisponivel $Guid
    $exe=Join-Path $env:SystemRoot 'System32\powercfg.exe'
    & $exe /setactive $id.ToString() | Out-Null
    if ($LASTEXITCODE -ne 0 -or (Obter-PlanoEnergiaAtivo) -ne $id.ToString()) { throw 'Plano de energia nao confirmado.' }
}

# F2: barreira adicional, nao um detector completo de politica efetiva.
# A ausencia de bloqueio nesta etapa nunca significa autorizacao para alterar.
# Optional feature changes are constrained to the features exposed by the UI.
function Testar-RecursoCatalogado {
    param([string]$Nome)
    return ($Nome -in @('Microsoft-Hyper-V-All','VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux','Containers-DisposableClientVM','NetFx3','DirectPlay','WindowsMediaPlayer','TelnetClient'))
}

function Confirmar-PoliticaAppxLocal {
    foreach ($h in @('HKCU','HKLM')) {
        foreach ($k in @('SOFTWARE\Policies\Microsoft\WindowsStore','SOFTWARE\Policies\Microsoft\Windows\Appx','SOFTWARE\Policies\Microsoft\Windows\AppLocker')) {
            try {$existe=Test-Path -LiteralPath ($h+':\'+$k) -ErrorAction Stop}
            catch {throw 'Consulta de politica AppX inconclusiva.'}
            if ($existe) {throw 'Indicador de politica AppX/Store/AppLocker presente; use o procedimento autorizado.'}
        }
    }
}

function Confirmar-CompatibilidadeRecurso {
    param([string]$Nome,$Contexto)
    if (-not $Contexto -or -not $Contexto.cliente -or $Contexto.build -lt 10240 -or -not $Contexto.edicao) {throw 'Compatibilidade de recurso nao confirmada.'}
    if ($Nome -in @('Microsoft-Hyper-V-All','Containers-DisposableClientVM') -and $Contexto.edicao -notmatch '^(Professional|Enterprise|Education)') {throw 'Edicao sem suporte confirmado a virtualizacao/Sandbox.'}
    if ($Nome -eq 'Containers-DisposableClientVM' -and $Contexto.build -lt 18362) {throw 'Build sem suporte confirmado ao Sandbox.'}
}

function Confirmar-PoliticaRecursosLocal {
    foreach ($p in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Servicing','HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Servicing')) {
        try {$presente=Test-Path -LiteralPath $p -ErrorAction Stop}
        catch {throw 'Consulta de politica de componentes inconclusiva.'}
        if ($presente) {throw 'Indicador de politica de componentes encontrado; utilize o procedimento autorizado.'}
    }
}

function Avaliar-ProtecaoAlvo {
    param($Acao)
    $motivo=$null
    switch ([string]$Acao.tipo) {
        'registro' {
            $caminho=([string]$Acao.caminho).Trim()
            if ($caminho -notmatch '^(HKLM:|HKCU:|HKU:|HKCR:|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_USERS|HKEY_CLASSES_ROOT)\\[^\\]+(?:\\[^\\]+)*$' -or $caminho -match '(^|\\)\.{1,2}(\\|$)') {
                $motivo='Caminho de registro invalido ou ambiguo.'
            } elseif ($caminho -match '(?i)\\(?:Policies|PolicyManager|Group Policy)(\\|$)') {
                $motivo='Chave de politica: somente consulta nesta versao. Use a ferramenta administrativa autorizada.'
            } elseif ($caminho -match '(?i)\\(?:Windows Defender|Windows Defender Security Center|WindowsFirewall|BitLocker|FVE|Enrollments|EnterpriseResourceManager)(\\|$)' -or
                $caminho -match '(?i)\\SYSTEM\\(?:CurrentControlSet|ControlSet[0-9]+)\\(?:Services|Control\\(?:Lsa|SecurityProviders|SecureBoot))(\\|$)' -or
                $caminho -match '(?i)\\Microsoft\\Windows\\CurrentVersion\\(?:Authentication|WindowsUpdate)(\\|$)') {
                $motivo='Alvo sensivel de seguranca, servicos, identidade ou atualizacoes: escrita direta indisponivel.'
            }
        }
        'servico' {
            # Lista explicita de alvos existentes na V2; catalogo editado nao amplia permissao.
            $nomes=@('MapsBroker','StorSvc','SharedAccess','CscService','Fax','RemoteRegistry','RetailDemo','SysMain','WSearch','lfsvc','WSAIFabricSvc')
            if ([string]$Acao.nome -notin $nomes) { $motivo='Servico fora da lista de alvos revisados.' }
            elseif ([string]$Acao.inicio -notin @('Automatic','Manual','Disabled')) { $motivo='Tipo de inicio invalido.' }
        }
        'energia' {
            $id=[guid]::Empty
            if (-not [guid]::TryParse([string]$Acao.guid,[ref]$id) -or $id -eq [guid]::Empty) { $motivo='GUID de energia invalido.' }
        }
        'appx' { }
        'recurso' {
            if (-not (Testar-RecursoCatalogado ([string]$Acao.nome))) {$motivo='Recurso fora da lista revisada.'}
            elseif ($Acao.ativar -isnot [bool] -or -not $Acao.ativar) {$motivo='Somente habilitacao explicita de recurso catalogado e permitida.'}
        }
        default { $motivo='Tipo de acao nao suportado para nova aplicacao.' }
    }
    if ($motivo) { return [pscustomobject]@{estado='bloqueado';motivo=$motivo} }
    return [pscustomobject]@{estado='avaliacao-adicional';motivo='Nenhum bloqueio de alvo nesta etapa; permissoes, compatibilidade e politicas efetivas ainda precisam ser respeitadas.'}
}

function Confirmar-ProtecaoAlvo {
    param($Acao)
    $r=Avaliar-ProtecaoAlvo $Acao
    if ($r.estado -ne 'avaliacao-adicional') { throw $r.motivo }
}

# Restrict NEW writes independently of mutable catalog metadata. Existing recovery
# keeps its own target and snapshot checks so an old preference can be restored.
function Obter-BloqueioNovaAcao {
    param($Acao)
    if ($Acao.tipo -eq 'registro') {
        $c=Converter-Hive ([string]$Acao.caminho)
        $n=[string]$Acao.nome
        if ($Acao.remover -isnot [bool] -and $null -ne $Acao.remover) {return 'Indicador de remocao invalido.'}
        if (-not $Acao.remover -and $Acao.tipoValor -notin @('DWord','QWord','String','ExpandString','Binary','MultiString')) {return 'Tipo de registro invalido.'}
        # Reviewed user preference tuples, including exact desired value.
        $permitidos=@{
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt'='0'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarDa'='0'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|LaunchTo'='1'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Hidden'='1'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowTaskViewButton'='0'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search|SearchboxTaskbarMode'='0'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|AppsUseLightTheme'='0'
            'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|SystemUsesLightTheme'='0'
        }
        $chave=$c+'|'+$n
        if ($permitidos.ContainsKey($chave)) {
            if ($Acao.remover -or $Acao.tipoValor -ne 'DWord' -or [string]$Acao.dados -cne $permitidos[$chave]) {return 'Valor fora da preferencia revisada.'}
            return $null
        }
        # Dedicated startup cleanup is removal-only and requires an exact Run key.
        if ($Acao.remover -and $n -and $c -in @('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run','HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run','HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
            return $null
        }
        # Restricted local custom plans: non-reserved HKCU Software only.
        if ($c -match '(?i)^HKEY_CURRENT_USER\\Software\\[^\\]+(?:\\[^\\]+)*$' -and $c -notmatch '(?i)^HKEY_CURRENT_USER\\Software\\(?:Microsoft|Classes|Policies|Clients|RegisteredApplications|WOW6432Node)(?:\\|$)' -and $Acao.tipoValor -in @('String','DWord')) {return $null}
        return 'Alvo de escrita nova nao revisado; use configuracao nativa autorizada.'
    }
    if ($Acao.tipo -eq 'servico') {return 'Alteracoes de servicos pelo catalogo de tweaks indisponiveis; diagnostique individualmente.'}
    if ($Acao.tipo -eq 'energia' -and [string]$Acao.guid -ine '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') {return 'Plano fora do catalogo de ajustes.'}
    if ($Acao.tipo -eq 'appx' -and -not (Testar-AppxCatalogado $Acao.pacote)) {return 'Pacote fora do catalogo de remocao revisado.'}
    return $null
}

function Confirmar-NovaAcao {
    param($Acao)
    Confirmar-ProtecaoAlvo $Acao
    $motivo=Obter-BloqueioNovaAcao $Acao
    if ($motivo) {throw $motivo}
}

function Obter-BloqueioAjuste {
    param($Ajuste)
    if ($Ajuste.auditoria.decisao -eq 'consulta') {return ('Somente consulta nesta revisao: '+$Ajuste.auditoria.risco+' '+$Ajuste.auditoria.orientacao)}
    foreach ($acao in @($Ajuste.acoes)) {
        $r=Avaliar-ProtecaoAlvo $acao
        if ($r.estado -eq 'bloqueado') { return $r.motivo }
        $motivo=Obter-BloqueioNovaAcao $acao
        if ($motivo) {return $motivo}
    }
    return $null
}

function Confirmar-DependenciasServico {
    param([string]$Nome,[string]$Inicio)
    Confirmar-ProtecaoAlvo ([pscustomobject]@{tipo='servico';nome=$Nome;inicio=$Inicio})
    if ($Inicio -eq 'Disabled') {
        $svc=Get-Service -Name $Nome -ErrorAction Stop
        # Mesmo um dependente parado pode precisar iniciar posteriormente.
        if (@($svc.DependentServices | Where-Object {$_}).Count -gt 0) { throw 'Servico possui dependentes; desativacao recusada.' }
    }
}

# Conservative indicators; absence does not establish absence of effective policy.
function Confirmar-PoliticaPreferenciaLocal {
    param([string]$Caminho,[string]$Nome)
    $nativa=Converter-Hive $Caminho
    $grupos=@();$valores=@($Nome)
    if ($nativa -match '(?i)^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced(?:\\|$)') {
        $grupos=@('SOFTWARE\Policies\Microsoft\Windows\Explorer','SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer')
        $valores+=@('NoFolderOptions','NoSetTaskbar','LockedStartLayout')
    } elseif ($nativa -match '(?i)^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Search(?:\\|$)') {
        $grupos=@('SOFTWARE\Policies\Microsoft\Windows\Windows Search','SOFTWARE\Policies\Microsoft\Windows\Explorer')
        $valores+=@('DisableSearchBoxSuggestions','SearchboxTaskbarMode')
    } elseif ($nativa -match '(?i)^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize(?:\\|$)') {
        $grupos=@('SOFTWARE\Policies\Microsoft\Windows\Personalization','SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System')
        $valores+=@('NoChangingTheme','NoChangingColor')
    } else {return}
    foreach ($hive in @('HKCU','HKLM')) {
        foreach ($grupo in $grupos) {
            $p=$hive+':\'+$grupo
            try {
                if (-not (Test-Path -LiteralPath $p -ErrorAction Stop)) {continue}
                $v=Get-ItemProperty -LiteralPath $p -ErrorAction Stop
            } catch {throw 'Consulta de politica de preferencia inconclusiva; alteracao recusada.'}
            foreach ($nomePolitica in $valores) {
                if ($nomePolitica -and $v.PSObject.Properties[$nomePolitica]) {throw ('Indicador de politica de preferencia presente: '+$nomePolitica+'. Utilize o procedimento autorizado.')}
            }
        }
    }
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($escopo in @('device',$sid)) {
        foreach ($grupo in @('Start','Search','Personalization','Experience')) {
            $p='HKLM:\SOFTWARE\Microsoft\PolicyManager\current\'+$escopo+'\'+$grupo
            try {
                if (-not (Test-Path -LiteralPath $p -ErrorAction Stop)) {continue}
                $v=Get-ItemProperty -LiteralPath $p -ErrorAction Stop
            } catch {throw 'Consulta de politica MDM de preferencia inconclusiva.'}
            foreach ($nomePolitica in $valores) {
                if ($nomePolitica -and $v.PSObject.Properties[($nomePolitica+'_ProviderSet')] -and $v.($nomePolitica+'_ProviderSet') -eq 1) {throw 'Indicador MDM de preferencia presente; use procedimento autorizado.'}
            }
        }
    }
}

function Confirmar-PoliticaEnergiaLocal {
    # Indicadores conservadores: uma chave de politica presente, mesmo vazia,
    # exige revisao. Nao prova ausencia de GPO/MDM quando nao encontrada.
    foreach ($chave in @('HKLM:\SOFTWARE\Policies\Microsoft\Power','HKCU:\SOFTWARE\Policies\Microsoft\Power','HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Power')) {
        try { $presente=Test-Path -LiteralPath $chave -ErrorAction Stop }
        catch { throw 'Consulta de politica de energia inconclusiva; alteracao recusada.' }
        if ($presente) { throw 'Indicador de politica de energia presente; alteracao recusada.' }
    }
}

function Obter-IdOperacaoAcao {
    param($Acao)
    switch ($Acao.tipo) {
        'registro' {
            $c=Converter-Hive ([string]$Acao.caminho)
            if ($c -match '(?i)^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\(?:Explorer\\Advanced|Search|Themes\\Personalize)$') {return 'registro-usuario'}
            if ($c -match '(?i)^HKEY_CURRENT_USER\\') {return 'registro-local'}
            return 'registro-maquina'
        }
        {$_ -in @('servico','tarefa','energia','recurso','appx')} {return [string]$_}
        'path-entrada' {return 'path'}
        'quarantena-arquivo' {return 'rastros'}
        'quarantena-registro' {return 'rastros'}
        default {return 'nao-catalogado'}
    }
}

function Executar-Acao {
    param($Acao, [string]$Contexto, [switch]$Simular)

    $desc = $Contexto
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = $Acao.tipo }

    if ($Simular) {
        Log ('[SIMULAR] ' + $desc + ': ' + (Descrever-Acao $Acao))
        return
    }

    Confirmar-PermissaoAlteracao 'estado-local'
    $ErrorActionPreference = 'Stop'
    $antesItens=@($global:SessaoItens | Where-Object {$_}).Count
    try {
        if (Testar-SessaoInterrompida) {throw 'Lote interrompido por efeito anterior nao confirmado.'}
        Confirmar-NovaAcao $Acao
        Confirmar-PermissaoAlteracao (Obter-IdOperacaoAcao $Acao)
        switch ($Acao.tipo) {

            'registro' {
                Confirmar-PoliticaPreferenciaLocal $Acao.caminho $Acao.nome
                $leitura = Ler-ValorRegistro -CaminhoPS $Acao.caminho -Nome $Acao.nome
                # The durable per-value snapshot is the backup; do not export unrelated sibling values.
                $arqBackup=$null
                $kind = Converter-Kind $Acao.tipoValor
                $dados = $Acao.dados
                if (-not $Acao.remover) {
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $dados = [int]$Acao.dados }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $dados = [long]$Acao.dados }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $dados = [byte[]]@($Acao.dados) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $dados = [string[]]@($Acao.dados) }
                }
                $entrada=[pscustomobject]@{
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
                }
                Registrar-Jornal $entrada
                Confirmar-PermissaoAlteracao (Obter-IdOperacaoAcao $Acao)
                Confirmar-PoliticaPreferenciaLocal $Acao.caminho $Acao.nome
                if (-not (Registro-Corresponde (Ler-ValorRegistro $Acao.caminho $Acao.nome) ([bool]$leitura.existia) $leitura.tipo $leitura.valor)) {throw 'Valor mudou durante a preparacao; preservado.'}
                if ($Acao.remover) {
                    if ($leitura.existia) {
                        $partes = $leitura.rede -split '\\',2
                        $raiz = Obter-RaizRegistro $partes[0]
                        $chave = $raiz.OpenSubKey($partes[1],$true)
                        if (-not $chave) { throw 'Chave indisponivel para remocao.' }
                        try { $chave.DeleteValue([string]$Acao.nome,$true) } finally { $chave.Dispose() }
                    }
                    if ((Ler-ValorRegistro $Acao.caminho $Acao.nome).existia) { throw 'Remocao de valor nao confirmada.' }
                    Confirmar-EfeitoJournal $entrada
                    Log ('valor de registro removido: ' + $Acao.nome)
                    return
                }
                [Microsoft.Win32.Registry]::SetValue($leitura.rede, $Acao.nome, $dados, $kind) | Out-Null
                if (-not (Registro-Corresponde (Ler-ValorRegistro $Acao.caminho $Acao.nome) $true $kind.ToString() $dados)) { throw 'Gravacao de registro nao confirmada.' }
                Confirmar-EfeitoJournal $entrada
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
                Confirmar-PoliticaAppxLocal
                # Remocao apenas do usuario atual, sem afetar outros usuarios
                # nem o provisionamento. O nome deve ser exato.
                if (-not (Testar-AppxCatalogado $Acao.pacote)) { throw 'Pacote fora do catalogo de remocao.' }
                $todos=@(Get-AppxPackage -ErrorAction Stop)
                $pkgs=@($todos | Where-Object { $_.Name -eq $Acao.pacote })
                if (@($pkgs | Where-Object { Testar-AppxProtegido $_ }).Count -gt 0) { throw 'Pacote protegido; nenhum pacote removido.' }
                $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                foreach ($p in $pkgs) {
                    if (Testar-AppxProtegido $p) { throw ('Pacote protegido: ' + $p.Name) }
                    $dependentes=@(Obter-DependentesAppx $p $todos)
                    if ($dependentes.Count) { throw ('Pacote usado por dependentes declarados: '+($dependentes -join ', ')) }
                    $entrada=[pscustomobject]@{
                        tipo = 'appx'; pacote = $p.Name; completo = $p.PackageFullName
                        familia = $p.PackageFamilyName; usuarioSid = $sid
                    }
                    Registrar-Jornal $entrada
                    Confirmar-PermissaoAlteracao 'appx'
                    Confirmar-PoliticaAppxLocal
                    $frescos=@(Get-AppxPackage -ErrorAction Stop)
                    $alvos=@($frescos | Where-Object {$_.PackageFullName -eq $p.PackageFullName})
                    if ($alvos.Count -ne 1 -or (Testar-AppxProtegido $alvos[0]) -or @(Obter-DependentesAppx $alvos[0] $frescos).Count) {throw 'Pacote ou dependencias mudaram; preservado.'}
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                    if (@(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $p.PackageFullName }).Count -gt 0) { throw 'Pacote continua instalado.' }
                    Confirmar-EfeitoJournal $entrada
                    $global:CacheAppxCarregadoEm = $null
                    Log ('appx removido do usuario atual: ' + $p.Name)
                }
                if ($pkgs.Count -eq 0) { Log ("appx '{0}' nao esta instalado no usuario atual." -f $Acao.pacote) }
            }

            'recurso' {
                Confirmar-CompatibilidadeRecurso $Acao.nome (Obter-ContextoAjustes)
                Confirmar-PoliticaRecursosLocal
                $antes = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ nome=$_.FeatureName; estado=$_.State.ToString() } })
                $feat = @($antes | Where-Object { $_.nome -eq $Acao.nome })
                if ($feat.Count -ne 1) { throw 'Recurso nao encontrado.' }
                $alvo = if ($Acao.ativar) { 'Enabled' } else { 'Disabled' }
                if ($feat[0].estado -eq $alvo) { Log 'Recurso ja configurado.'; return }
                if ($feat[0].estado -notin @('Enabled','Disabled')) { throw 'Recurso em estado pendente ou payload removido; revise pelo Windows.' }
                $entrada = [pscustomobject]@{ tipo='recurso'; nome=$Acao.nome; estadoAnterior=$feat[0].estado; estadoDepois=$alvo; alteracoes=$null }
                Registrar-Jornal $entrada
                Confirmar-PermissaoAlteracao 'recurso'
                Confirmar-CompatibilidadeRecurso $Acao.nome (Obter-ContextoAjustes)
                Confirmar-PoliticaRecursosLocal
                if ((Get-WindowsOptionalFeature -Online -FeatureName $Acao.nome -ErrorAction Stop).State.ToString() -ne $feat[0].estado) {throw 'Estado do recurso mudou; preservado.'}
                if ($Acao.ativar) { $resultado = Enable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -All -NoRestart -ErrorAction Stop }
                else { $resultado = Disable-WindowsOptionalFeature -Online -FeatureName $Acao.nome -NoRestart -ErrorAction Stop }
                $depois = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop)
                $mapa = @{}
                foreach ($f in $depois) { $mapa[$f.FeatureName]=$f.State.ToString() }
                $entrada.alteracoes = @($antes | Where-Object { $mapa[$_.nome] -ne $_.estado } | ForEach-Object { [pscustomobject]@{ nome=$_.nome; antes=$_.estado; depois=$mapa[$_.nome] } })
                if ($resultado.RestartNeeded -or $mapa[$Acao.nome] -ne $alvo) { Confirmar-EfeitoJournal $entrada 'pendente'; Log 'Recurso processado; reinicio ou revisao necessarios.' }
                else { Confirmar-EfeitoJournal $entrada; Log ('recurso verificado: ' + $Acao.nome) }
            }

            'energia' {
                Confirmar-PoliticaEnergiaLocal
                $anterior=Obter-PlanoEnergiaAtivo
                $alvo=[guid]::Parse([string]$Acao.guid).ToString()
                if ($anterior -eq $alvo) { return }
                $entrada=[pscustomobject]@{tipo='energia';guidAnterior=$anterior;guidDepois=$alvo}
                Registrar-Jornal $entrada
                Definir-PlanoEnergia $alvo
                Confirmar-EfeitoJournal $entrada
                Log 'Plano de energia alterado e confirmado.'
            }

            default {
                Log ("tipo de acao desconhecido: {0}" -f $Acao.tipo) -Erro
            }
        }
    } catch {
        if (@($global:SessaoItens | Where-Object {$_}).Count -gt $antesItens) {try {Registrar-FalhaOperacao} catch {Log 'Falha ao persistir resultado; lote interrompido.' -Erro}}
        Log ("falha ao aplicar '{0}': {1}" -f $desc, $_.Exception.Message) -Erro
    }
}

# ---- desfazer ----

# Verify the direct child of a protected quarantine session before recovery.
# Bounded manifest of names, directory structure, lengths and default file streams.
# Reject links instead of traversing them. Does not attest ACLs or alternate streams.
function Obter-HashPastaQuarentena {
    param([string]$Pasta,[int]$LimiteItens=2000,[long]$LimiteBytes=536870912,[int]$LimiteSegundos=30)
    $root=[IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    $dir=Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (-not $dir.PSIsContainer -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Pasta invalida ou redirecionada.'}
    $fila=New-Object 'System.Collections.Generic.Stack[string]'
    $linhas=New-Object 'System.Collections.Generic.List[string]'
    $fila.Push($root)
    $bytes=0L;$n=0;$sw=[Diagnostics.Stopwatch]::StartNew()
    while ($fila.Count -gt 0) {
        $atual=$fila.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $atual -Force -ErrorAction Stop)) {
            $n++
            if ($n -gt $LimiteItens -or $sw.Elapsed.TotalSeconds -ge $LimiteSegundos) {throw 'Limite do manifesto de pasta atingido; preserve a pasta.'}
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Link ou ponto de redirecionamento dentro da pasta; preservado.'}
            $rel=$item.FullName.Substring($root.Length+1)
            if ($item.PSIsContainer) {
                $linhas.Add((ConvertTo-Json -Compress -InputObject @('D',$rel)))
                $fila.Push($item.FullName)
            } else {
                $bytes+=[long]$item.Length
                if ($bytes -gt $LimiteBytes) {throw 'Limite de bytes do manifesto atingido; preserve a pasta.'}
                $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($sw.Elapsed.TotalSeconds -ge $LimiteSegundos) {throw 'Tempo de manifesto excedido; preserve a pasta.'}
                $linhas.Add((ConvertTo-Json -Compress -InputObject @('F',$rel,[long]$item.Length,$hash)))
            }
        }
    }
    $ordenadas=$linhas.ToArray()
    [Array]::Sort($ordenadas,[StringComparer]::Ordinal)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $buf=[Text.Encoding]::UTF8.GetBytes(($ordenadas -join [char]10))
        return ([BitConverter]::ToString($sha.ComputeHash($buf))).Replace('-','')
    } finally {$sha.Dispose()}
}

function Confirmar-PastaSessaoQuarentena {
    param([string]$Pasta)
    if ($Pasta -notmatch '^[A-Za-z]:\\' -or -not $global:PastaQuarantena) {throw 'Pasta de quarentena invalida.'}
    $root=[IO.Path]::GetFullPath($global:PastaQuarantena).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ine $root -or [IO.Path]::GetFileName($full).Contains(':')) {throw 'Pasta fora da quarentena.'}
    Verificar-PastaPrivada $root
    Verificar-PastaPrivada $full
    return $full
}

# A .reg backup must be the export of exactly one reviewed subtree. Never
# accept key-deletion directives or a second unrelated key in an import.
function Confirmar-ConteudoBackupRegistro {
    param([string]$Arquivo,[string]$Chave)
    if (-not (Chave-RastroSegura $Chave)) {throw 'Chave de backup fora do escopo.'}
    $f=Get-Item -LiteralPath $Arquivo -Force -ErrorAction Stop
    if ($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 16777216) {throw 'Backup de registro invalido ou acima de 16 MiB.'}
    $linhas=@(Get-Content -LiteralPath $Arquivo -Encoding Unicode -ErrorAction Stop)
    if ($linhas.Count -lt 2 -or $linhas[0] -ne 'Windows Registry Editor Version 5.00') {throw 'Cabecalho .reg invalido.'}
    $raiz=$false;$continuacao=$false
    foreach ($linha in ($linhas | Select-Object -Skip 1)) {
        $s=$linha.Trim()
        if (-not $s) {if ($continuacao) {throw 'Continuacao .reg incompleta.'};continue}
        if ($continuacao) {
            if ($s -notmatch '^(?:[0-9a-fA-F]{2},)*[0-9a-fA-F]{2},?\\?$') {throw 'Continuacao .reg invalida.'}
            $continuacao=$s.EndsWith('\')
            continue
        }
        if ($s -match '^\[(.+)\]$') {
            $alvo=$Matches[1]
            if ($alvo -ieq $Chave) {$raiz=$true}
            elseif (-not $raiz -or -not $alvo.StartsWith($Chave+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Backup .reg contem alvo externo ou exclusao.'}
        } elseif ($raiz -and $s -match '^(?:@|"(?:[^"\\]|\\.)*")=(?:"(?:[^"\\]|\\.)*"|dword:[0-9a-fA-F]{8}|hex(?:\([0-9a-fA-F]+\))?:(?:[0-9a-fA-F]{2},)*[0-9a-fA-F]{0,2},?\\?)$') {
            $continuacao=$s.EndsWith('\')
        } else {throw 'Diretiva .reg fora do formato de exportacao revisado.'}
    }
    if (-not $raiz -or $continuacao) {throw 'Backup .reg incompleto.'}
}

function Confirmar-RegistroIgualAoBackup {
    param([string]$Chave,[string]$Backup,[string]$Hash)
    $pasta=Confirmar-PastaSessaoQuarentena (Split-Path -Parent $Backup)
    $temp=Join-Path $pasta ('verificacao-'+[guid]::NewGuid().ToString('N')+'.reg')
    try {
        Executar-RegNativo -Operacao export -Alvo $Chave -Arquivo $temp
        [IO.File]::SetAccessControl($temp,(Nova-ACLJournal))
        Confirmar-ACLArquivoPrivado $temp
        Confirmar-ConteudoBackupRegistro $temp $Chave
        if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256 -ErrorAction Stop).Hash -ine $Hash) {throw 'Conteudo da chave divergente do backup; preserve o estado.'}
    } finally {if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp -Force -ErrorAction Stop}}
}

# Do not change source permissions to make an object eligible.
function Confirmar-ArvorePrivadaQuarentena {
    param([string]$Caminho,[int]$Limite=2001)
    $fila=New-Object 'System.Collections.Generic.Stack[string]'
    $fila.Push($Caminho)
    $n=0
    while ($fila.Count) {
        $atual=$fila.Pop();$n++
        if ($n -gt $Limite) {throw 'Arvore acima do limite de verificacao ACL.'}
        $i=Get-Item -LiteralPath $atual -Force -ErrorAction Stop
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint -or $i.LinkType) {throw 'Link na arvore; preserve e revise manualmente.'}
        $acl=Get-Acl -LiteralPath $atual -ErrorAction Stop
        if (-not $acl.AreAccessRulesProtected) {throw 'ACL herdada ou nao privada; quarentena automatica indisponivel. Preserve e faca backup autorizado.'}
        Confirmar-ACLArquivoPrivado $atual
        if ($i.PSIsContainer) {
            foreach ($filho in @(Get-ChildItem -LiteralPath $atual -Force -ErrorAction Stop)) {$fila.Push($filho.FullName)}
        }
    }
}

function Confirmar-BackupQuarentena {
    param([string]$Arquivo,[string]$Hash,[switch]$PastaPermitida)
    if ($Arquivo -notmatch '^[A-Za-z]:\\' -or -not $global:PastaQuarantena) {throw 'Backup sem caminho local confirmado.'}
    $raiz=[IO.Path]::GetFullPath($global:PastaQuarantena).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Arquivo)
    $sessao=[IO.Path]::GetDirectoryName($full)
    if ([IO.Path]::GetDirectoryName($sessao) -ine $raiz -or [IO.Path]::GetFileName($full).Contains(':')) {throw 'Backup fora da pasta de quarentena.'}
    [void](Confirmar-PastaSessaoQuarentena $sessao)
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Backup redirecionado.'}
    if ($item.PSIsContainer) {
        if (-not $PastaPermitida -or $Hash -notmatch '^[0-9a-fA-F]{64}$') {throw 'Pasta sem manifesto confirmado; revise manualmente.'}
        if ((Obter-HashPastaQuarentena $full) -ine $Hash) {throw 'Manifesto da pasta divergente; preservado.'}
    } else {
        if ($Hash -notmatch '^[0-9a-fA-F]{64}$') {throw 'Backup sem hash confirmado; revise manualmente.'}
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash -ine $Hash) {throw 'Integridade do backup divergente; preservado.'}
    }
    return $full
}

# Recovery may restore a previous value (not necessarily the current catalog
# value), but cannot reopen arbitrary historical Windows registry targets.
function Confirmar-AlvoRegistroReversao {
    param($Item)
    $c=Converter-Hive ([string]$Item.caminho)
    $n=[string]$Item.nome
    Confirmar-ProtecaoAlvo ([pscustomobject]@{tipo='registro';caminho=$Item.caminho;nome=$n})
    if ($c -match '(?i)^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced$' -and $n -in @('HideFileExt','TaskbarDa','LaunchTo','Hidden','ShowTaskViewButton')) {return}
    if ($c -ieq 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search' -and $n -eq 'SearchboxTaskbarMode') {return}
    if ($c -ieq 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -and $n -in @('AppsUseLightTheme','SystemUsesLightTheme')) {return}
    if ($n -and $c -in @('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run','HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run','HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {return}
    if ($c -match '(?i)^HKEY_CURRENT_USER\\Software\\[^\\]+(?:\\[^\\]+)*$' -and $c -notmatch '(?i)^HKEY_CURRENT_USER\\Software\\(?:Microsoft|Classes|Policies|Clients|RegisteredApplications|WOW6432Node)(?:\\|$)') {return}
    throw 'Alvo historico fora da lista de recuperacao automatica; preserve o journal e revise manualmente.'
}

# Ausencia verificada contra catalogo local e inventarios reais.
# Falha de consulta nunca vira ausencia; sem nome catalogado nao ha verificacao.
function Testar-AppAusenteCatalogado {
    param([string]$Id,[string]$Fonte)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    $fonte=if ([string]::IsNullOrWhiteSpace($Fonte) -or $Fonte -eq 'winget') {'winget'} elseif ($Fonte -eq 'msstore') {'msstore'} else { return $false }
    if ($null -eq $global:CatalogoApps -or $null -eq $global:CatalogoApps.aplicativos) { return $false }
    $nomes=@($global:CatalogoApps.aplicativos | Where-Object {
        $f=if ($_.fonte) {[string]$_.fonte} else {'winget'}
        [string]$_.id -ceq $Id -and $f -ceq $fonte
    } | ForEach-Object {[string]$_.nome} | Sort-Object -Unique)
    if (@($nomes).Count -eq 0) { return $false }
    foreach ($raiz in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        try {
            if (-not (Test-Path -LiteralPath $raiz -ErrorAction Stop)) {continue}
            foreach ($k in @(Get-ChildItem -LiteralPath $raiz -ErrorAction Stop)) {
                $p=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ($nomes -contains [string]$p.DisplayName) { return $false }
            }
        } catch { return $false }
    }
    if ($fonte -eq 'msstore') {
        try { foreach ($q in @(Get-AppxPackage -ErrorAction Stop)) { if ($nomes -contains [string]$q.Name) { return $false } } }
        catch { return $false }
    }
    return $true
}

function Desfazer-Item {
    param($Item)
    Confirmar-PermissaoAlteracao 'estado-local'
    $ErrorActionPreference = 'Stop'
    try {
        if ($Item.tipo -in @('registro','servico','energia','recurso','appx','tarefa','path-entrada','quarantena-arquivo','quarantena-registro')) {
            $idReversao=if ($Item.tipo -eq 'tarefa') {'tarefa-reversao'} else {Obter-IdOperacaoAcao $Item}
            Confirmar-PermissaoAlteracao $idReversao
        }
        switch ($Item.tipo) {

            'registro' {
                if (-not $Item.PSObject.Properties['existiaDepois']) {throw 'Journal de registro sem snapshot posterior; revise manualmente.'}
                $rede = Converter-Hive $Item.caminho
                if ($rede -notmatch '^HKEY_(CURRENT_USER|LOCAL_MACHINE)\\') {throw 'Hive de reversao fora do escopo revisado.'}
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
                Confirmar-AlvoRegistroReversao $Item
                Confirmar-PoliticaPreferenciaLocal $Item.caminho $Item.nome
                Confirmar-PermissaoAlteracao (Obter-IdOperacaoAcao $Item)
                if (-not (Registro-Corresponde (Ler-ValorRegistro $Item.caminho $Item.nome) ([bool]$Item.existiaDepois) $Item.tipoDepois $Item.valorDepoisEstruturado.valor)) {throw 'Registro mudou durante preparacao da reversao.'}
                if ($Item.existia) {
                    $kind = Converter-Kind $Item.tipoAnterior
                    if ($null -ne $Item.valorAnteriorEstruturado) { $valor = $Item.valorAnteriorEstruturado.valor }
                    else { $valor = ($Item.valorAnterior | ConvertFrom-Json) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $valor = [int]$valor }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $valor = [long]$valor }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $valor = [byte[]]@($valor) }
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $valor = [string[]]@($valor) }
                    [Microsoft.Win32.Registry]::SetValue($rede, $Item.nome, $valor, $kind) | Out-Null
                    if (-not (Registro-Corresponde (Ler-ValorRegistro $Item.caminho $Item.nome) $true $kind.ToString() $valor)) {throw 'Restauracao do valor de registro nao confirmada.'}
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
                    if ((Ler-ValorRegistro $Item.caminho $Item.nome).existia) {throw 'Remocao do valor de registro nao confirmada.'}
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
                if (-not $Item.guidAnterior -or -not $Item.guidDepois) { throw 'Journal antigo de energia; revise manualmente.' }
                $atual=Obter-PlanoEnergiaAtivo
                if ($atual -eq $Item.guidAnterior) { return $true }
                if ($atual -ne $Item.guidDepois) { throw 'Plano de energia alterado depois da sessao; preservado.' }
                Definir-PlanoEnergia $Item.guidAnterior
                Log 'Plano de energia restaurado e confirmado.'
            }

            'recurso' {
                if ($null -eq $Item.alteracoes -or @($Item.alteracoes).Count -ne 1 -or $Item.alteracoes[0].nome -ne $Item.nome) { throw 'Dependencias ou estado incerto: revise os recursos do Windows manualmente.' }
                $atual = (Get-WindowsOptionalFeature -Online -FeatureName $Item.nome -ErrorAction Stop).State.ToString()
                if ($atual -eq $Item.estadoAnterior) { return $true }
                if ($atual -ne $Item.estadoDepois -or $atual -notin @('Enabled','Disabled')) { throw 'Recurso em estado pendente ou alterado posteriormente.' }
                if (-not (Testar-RecursoCatalogado $Item.nome)) {throw 'Recurso fora da lista revisada; recupere manualmente.'}
                Confirmar-CompatibilidadeRecurso $Item.nome (Obter-ContextoAjustes)
                Confirmar-PoliticaRecursosLocal
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
                Confirmar-PoliticaAppxLocal
                if (-not (Testar-AppxCatalogado $Item.pacote)) {throw 'Pacote fora do catalogo atual; reinstale manualmente.'}
                if (-not $Item.usuarioSid -or $Item.usuarioSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'A sessao AppX pertence a outro usuario.' }
                if (Testar-ItemJaRestaurado $Item) {Log 'Versao registrada do AppX presente; dados nao verificados.'; return $true}
                if (@(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -eq $Item.pacote }).Count -gt 0) {throw 'Outra versao do AppX presente; revise manualmente, sem substituir.'}
                $fez = $false
                if (-not [string]::IsNullOrWhiteSpace([string]$Item.familia) -and $Item.familia -match ('^'+[regex]::Escape([string]$Item.pacote)+'_[a-z0-9]{13}$')) {
                    try {
                        Add-AppxPackage -RegisterByFamilyName -MainPackage $Item.familia -ErrorAction Stop
                        $fez = (Testar-ItemJaRestaurado $Item)
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

            'instalacao-app' {
                $plano=@($Item.plano)
                if (-not $Item.PSObject.Properties['plano'] -or @($plano).Count -eq 0) { throw ('Instalacao via WinGet sem plano por aplicativo; execute a desinstalacao manualmente: ' + [string]$Item.nome) }
                $alvos=@()
                foreach ($p in @($plano)) {
                    if ([string]$p.operacao -ne 'install') { throw 'Plano com operacao de upgrade: sem desfazer automatico; revise manualmente.' }
                    if ([string]$p.id -notmatch '^[A-Za-z0-9._+\-]+$') { throw ('ID de aplicativo invalido no plano: ' + [string]$p.id) }
                    $fonte=if ([string]::IsNullOrWhiteSpace([string]$p.fonte) -or [string]$p.fonte -eq 'winget') {'winget'} elseif ([string]$p.fonte -eq 'msstore') {'msstore'} else { throw 'Fonte nao permitida no plano.' }
                    $alvos += [pscustomobject]@{id=[string]$p.id;fonte=$fonte}
                }
                Confirmar-PermissaoAlteracao 'winget'
                Confirmar-PoliticaWingetLocal
                $exe=Obter-WingetExe
                foreach ($alvo in @($alvos)) {
                    $exeSeguro=$exe.Replace("'","''")
                    $bloco=("Executar-Nativo '"+$exeSeguro+"' @('uninstall','--id','"+$alvo.id+"','--exact','--source','"+$alvo.fonte+"')")
                    $cmd=Montar-ComandoConsole -Bloco $bloco
                    $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
                    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                    Confirmar-PermissaoAlteracao 'winget'
                    if ((Obter-WingetExe) -cne $exe) {throw 'WinGet mudou durante a reversao; opere manualmente.'}
                    $proc=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-EncodedCommand',$enc) -WindowStyle Normal -PassThru -ErrorAction Stop
                    try {
                        while (-not $proc.WaitForExit(100)) { Atualizar-UI }
                        if ($proc.ExitCode -ne 0) { throw ('WinGet nao concluiu a desinstalacao de ' + $alvo.id + ' (codigo ' + $proc.ExitCode + '); revise manualmente.') }
                    } finally { $proc.Dispose() }
                }
                foreach ($alvo in @($alvos)) {
                    if (-not (Testar-AppAusenteCatalogado $alvo.id $alvo.fonte)) { throw ('Desinstalacao nao confirmada contra catalogo e registro: ' + $alvo.id + '; revise manualmente.') }
                }
                Log ('lote de instalacao revertido via WinGet em janela visivel; ausencia verificada contra catalogo e registro: ' + [string]$Item.nome)
            }

            'temp' {
                throw 'Limpeza de temporarios e definitiva; sem restauracao automatica.'
            }

            'manutencao' {
                $alvo=[string]$Item.operacao
                if ($alvo) {throw ('Efeito externo de manutencao (' + $alvo + ') sem desfazer automatico; revise manualmente.')}
                throw 'Efeito externo de manutencao sem desfazer automatico; revise manualmente.'
            }

            'tarefa' {
                Confirmar-AlvoTarefa $Item.tarefaPath $Item.tarefaNome
                if (-not $Item.assinatura -or (Obter-AssinaturaTarefa $Item.tarefaPath $Item.tarefaNome) -ne $Item.assinatura) { throw 'Definicao da tarefa incerta ou alterada; revise manualmente.' }
                $atual = (Get-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop).State
                if ($atual -eq 'Ready') { return $true }
                if ($atual -ne 'Disabled') { throw 'Estado da tarefa mudou.' }
                Confirmar-PermissaoAlteracao 'tarefa-reversao'
                Enable-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop | Out-Null
                if ((Get-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop).State -eq 'Disabled') { throw 'Reativacao nao confirmada.' }
                Log ('tarefa reativada: ' + $Item.tarefaNome)
            }

            'firewall-estado' { throw 'Reversao automatica de firewall indisponivel; revise manualmente com autorizacao.' }
            'regra-firewall' { throw 'Recriacao automatica de regra de firewall indisponivel; revise manualmente.' }

            'path-entrada' {
                if ($Item.escopo -notin @('Machine','User') -or -not $Item.PSObject.Properties['valorDepois'] -or $Item.tipoAnterior -notin @('String','ExpandString')) {throw 'Snapshot PATH invalido ou legado; revise manualmente.'}
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
                            if ($atual -ceq [string]$Item.valorAnterior -and $kind.ToString() -eq $Item.tipoAnterior) { return $true }
                            if ($atual -cne [string]$Item.valorDepois -or $kind.ToString() -ne $Item.tipoAnterior) { throw 'PATH mudou desde a limpeza; nao sobrescrevendo.' }
                        }
                        $ck2.SetValue('Path', [string]$Item.valorAnterior, $kind)
                        if ([string]$ck2.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne [string]$Item.valorAnterior -or $ck2.GetValueKind('Path').ToString() -ne $Item.tipoAnterior) {throw 'Restauracao PATH nao confirmada.'}
                    } finally { $ck2.Dispose() }
                    Log ("entrada restaurada no PATH {0}: {1}" -f [string]$Item.escopo, [string]$Item.entrada)
                }
            }

            'quarantena-arquivo' {
                if (Testar-ItemJaRestaurado $Item) {return $true}
                $backup=Confirmar-BackupQuarentena $Item.destino $Item.hashBackup -PastaPermitida:([bool]$Item.pasta)
                Confirmar-ArvorePrivadaQuarentena $backup
                if ([IO.Path]::GetPathRoot($backup) -ine [IO.Path]::GetPathRoot($Item.origem)) {throw 'Restauracao entre volumes nao suportada.'}
                if (-not (Caminho-RastroSeguro $Item.origem -PermitirAusente)) {throw 'Destino original fora dos locais revisados.'}
                if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $Item.origem)) {
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
                    Move-Item -LiteralPath $backup -Destination $Item.origem -ErrorAction Stop
                    Confirmar-ArvorePrivadaQuarentena $Item.origem
                    $hashRestaurado=if ($Item.pasta) {Obter-HashPastaQuarentena $Item.origem} else {(Get-FileHash -LiteralPath $Item.origem -Algorithm SHA256 -ErrorAction Stop).Hash}
                    if ($hashRestaurado -ine $Item.hashBackup) {throw 'Conteudo restaurado nao confirmado.'}
                    Log ("rastro restaurado da quarantena: " + $Item.origem)
                } else {
                    throw ("Backup ausente ou conflito no destino: " + $Item.origem)
                }
            }

            'quarantena-registro' {
                $backup=Confirmar-BackupQuarentena $Item.arquivoReg $Item.hashBackup
                if (-not (Chave-RastroSegura $Item.chave)) {throw 'Alvo de registro protegido; revise manualmente.'}
                Confirmar-ACLArquivoPrivado $backup
                Confirmar-ConteudoBackupRegistro $backup $Item.chave
                if (Test-Path -LiteralPath $backup) {
                    if (Test-Path -LiteralPath ('Registry::' + $Item.chave)) { throw 'Chave recriada desde a limpeza; nao sobrescrevendo.' }
                    Confirmar-PermissaoAlteracao 'rastros'
                    if (Test-Path -LiteralPath ('Registry::'+$Item.chave) -ErrorAction Stop) {throw 'Chave recriada durante preparacao.'}
                    Executar-RegNativo -Operacao import -Alvo $backup
                    Confirmar-RegistroIgualAoBackup $Item.chave $backup $Item.hashBackup
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

# Reconciliation is read-only for the target. Never repeat an uncertain write.
function Testar-RegistroJaRestaurado {
    param($Item)
    if ($Item.tipo -ne 'registro' -or -not $Item.idOperacao -or
        $Item.existia -isnot [bool] -or -not $Item.valorAnteriorEstruturado -or
        -not $Item.valorAnteriorEstruturado.PSObject.Properties['valor'] -or
        -not $Item.PSObject.Properties['existiaDepois'] -or $Item.existiaDepois -isnot [bool]) {return $false}
    if ($Item.existia -and $Item.tipoAnterior -notin @('DWord','QWord','String','ExpandString','Binary','MultiString')) {return $false}
    try {
        $atual=Ler-ValorRegistro $Item.caminho $Item.nome
        return (Registro-Corresponde $atual $Item.existia $Item.tipoAnterior $Item.valorAnteriorEstruturado.valor)
    } catch {return $false}
}

# Recognize only complete snapshots with the original state already present.
# This is a read-only check, not permission to repeat a mutation.
function Testar-ItemJaRestaurado {
    param($Item)
    if (-not $Item.idOperacao) {return $false}
    try {
        switch ($Item.tipo) {
            'registro' {return (Testar-RegistroJaRestaurado $Item)}
            'energia' {
                $ant=[guid]::Empty;$dep=[guid]::Empty
                if (-not [guid]::TryParse([string]$Item.guidAnterior,[ref]$ant) -or -not [guid]::TryParse([string]$Item.guidDepois,[ref]$dep) -or $ant -eq [guid]::Empty -or $dep -eq [guid]::Empty) {return $false}
                return ([guid](Obter-PlanoEnergiaAtivo) -eq $ant)
            }
            'servico' {
                if ($Item.tipoAnterior -notin @('Automatic','Manual','Disabled') -or $Item.tipoDepois -notin @('Automatic','Manual','Disabled') -or $Item.estadoAnterior -notin @('Running','Stopped') -or $Item.estadoDepois -notin @('Running','Stopped') -or $Item.atrasoAnterior -isnot [bool] -or $Item.atrasoDepois -isnot [bool]) {return $false}
                Confirmar-ProtecaoAlvo ([pscustomobject]@{tipo='servico';nome=$Item.nome;inicio=$Item.tipoAnterior})
                $atual=Obter-EstadoServico $Item.nome
                return ($atual.tipo -eq $Item.tipoAnterior -and $atual.estado -eq $Item.estadoAnterior -and $atual.atraso -eq $Item.atrasoAnterior)
            }
            'tarefa' {
                if ($Item.estadoAnterior -ne 'Ready' -or $Item.estadoDepois -ne 'Disabled' -or -not $Item.assinatura) {return $false}
                Confirmar-AlvoTarefa $Item.tarefaPath $Item.tarefaNome
                if ((Obter-AssinaturaTarefa $Item.tarefaPath $Item.tarefaNome) -ne $Item.assinatura) {return $false}
                $atual=@(Get-ScheduledTask -TaskPath $Item.tarefaPath -TaskName $Item.tarefaNome -ErrorAction Stop)
                return ($atual.Count -eq 1 -and $atual[0].TaskName -eq $Item.tarefaNome -and $atual[0].TaskPath -eq $Item.tarefaPath -and $atual[0].State -eq 'Ready')
            }
            'path-entrada' {
                if ($Item.escopo -notin @('Machine','User') -or $Item.tipoAnterior -notin @('String','ExpandString') -or -not $Item.PSObject.Properties['valorDepois']) {return $false}
                $bruto=Obter-PathBruto $Item.escopo
                return ($null -ne $bruto -and [string]$bruto.tipo -eq $Item.tipoAnterior -and [string]$bruto.valor -ceq [string]$Item.valorAnterior)
            }
            'recurso' {
                if (-not (Testar-RecursoCatalogado $Item.nome) -or $Item.estadoAnterior -notin @('Enabled','Disabled') -or $Item.estadoDepois -notin @('Enabled','Disabled') -or @($Item.alteracoes).Count -ne 1 -or $Item.alteracoes[0].nome -ne $Item.nome) {return $false}
                return ((Get-WindowsOptionalFeature -Online -FeatureName $Item.nome -ErrorAction Stop).State.ToString() -eq $Item.estadoAnterior)
            }
            'appx' {
                if (-not $Item.completo -or -not $Item.familia -or -not $Item.usuarioSid -or $Item.usuarioSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {return $false}
                return (@(Get-AppxPackage -ErrorAction Stop | Where-Object {$_.PackageFullName -eq $Item.completo -and $_.PackageFamilyName -eq $Item.familia}).Count -eq 1)
            }
            'instalacao-app' {
                $plano=@($Item.plano)
                if (-not $Item.PSObject.Properties['plano'] -or @($plano).Count -ne 1 -or [string]$plano[0].operacao -ne 'install') {return $false}
                return (Testar-AppAusenteCatalogado ([string]$plano[0].id) ([string]$plano[0].fonte))
            }
            'quarantena-arquivo' {
                if ($Item.pasta -isnot [bool] -or $Item.hashBackup -notmatch '^[0-9a-fA-F]{64}$' -or -not (Caminho-RastroSeguro $Item.origem)) {return $false}
                [void](Confirmar-PastaSessaoQuarentena (Split-Path -Parent $Item.destino))
                if (Test-Path -LiteralPath $Item.destino -ErrorAction Stop) {return $false}
                Confirmar-ArvorePrivadaQuarentena $Item.origem
                $atual=Get-Item -LiteralPath $Item.origem -Force -ErrorAction Stop
                if ([bool]$atual.PSIsContainer -ne $Item.pasta) {return $false}
                $hash=if ($Item.pasta) {Obter-HashPastaQuarentena $Item.origem} else {(Get-FileHash -LiteralPath $Item.origem -Algorithm SHA256 -ErrorAction Stop).Hash}
                return ($hash -ieq $Item.hashBackup)
            }
            default {return $false}
        }
    } catch {return $false}
}

function Reverter-Sessao {
    param([string]$Arquivo, [switch]$UmaAcao)
    Confirmar-PermissaoAlteracao 'estado-local'
    $ErrorActionPreference = 'Stop'
    try {
        $Arquivo=Confirmar-ArquivoJournal $Arquivo
        $json = Ler-JSON $Arquivo
        if ($null -eq $json -or $null -eq $json.itens) { throw 'Journal invalido.' }
        Confirmar-ContextoJournal $json
        Confirmar-FormatoJournal $json
        $itens = @($json.itens)
        $feitas = 0
        for ($i = $itens.Count - 1; $i -ge 0; $i--) {
            $item = $itens[$i]
            if ($item.estadoReversao -in @('concluido','manual-sem-restauracao')) { continue }
            if ($item.estadoReversao -eq 'em_andamento') {
                if ($json.versaoEsquema -ne 2 -or -not (Testar-ItemJaRestaurado $item)) {
                    throw ("Acao {0} com resultado incerto. Revise manualmente antes de continuar." -f $i)
                }
                $item.estadoReversao='concluido'
                $item | Add-Member -NotePropertyName reconciliadoEm -NotePropertyValue (Get-Date -Format 'o') -Force
                Gravar-JournalSeguro -Arquivo $Arquivo -Objeto $json
                $feitas++
                Log ('Acao '+$i+' reconciliada: estado anterior verificado sem repetir a alteracao.')
                if ($UmaAcao -and $feitas -ge 1) {break}
                continue
            }
            if ((Obter-TipoRecuperacao $item) -eq 'manual-sem-garantia' -and $item.tipo -in @('desinstalado-app','instalacao-app','temp','manutencao','reg-import','comando','regra-firewall','firewall-estado')) {throw ("Acao {0} ({1}) sem desfazer automatico. Use encerramento manual sem restauracao." -f $i, [string]$item.tipo)}
            $item | Add-Member -NotePropertyName estadoReversao -NotePropertyValue 'em_andamento' -Force
            Gravar-JournalSeguro -Arquivo $Arquivo -Objeto $json
            if (-not (Desfazer-Item $item)) {
                $item | Add-Member -NotePropertyName erroReversao -NotePropertyValue 'efeito-nao-confirmado-ou-conflito' -Force
                $item | Add-Member -NotePropertyName falhaReversaoEm -NotePropertyValue (Get-Date -Format 'o') -Force
                Gravar-JournalSeguro -Arquivo $Arquivo -Objeto $json
                throw ("Falha na acao {0}. Journal preservado; revisao manual necessaria." -f $i)
            }
            $item.estadoReversao = 'concluido'
            $item | Add-Member -NotePropertyName revertidoEm -NotePropertyValue (Get-Date -Format 'o') -Force
            Gravar-JournalSeguro -Arquivo $Arquivo -Objeto $json
            $feitas++
            Atualizar-UI
            if ($UmaAcao -and $feitas -ge 1) { break }
        }
        if (@($itens | Where-Object { $_.estadoReversao -notin @('concluido','manual-sem-restauracao') }).Count -gt 0) {
            Log 'Uma acao revertida. Restam itens nesta sessao.'
            return $true
        }
        $novoNome = (Split-Path -Leaf $Arquivo) + '.revertido'
        if (Test-Path -LiteralPath ($Arquivo+'.revertido') -ErrorAction Stop) {throw 'Arquivo de historico ja existe; journal preservado.'}
        Rename-Item -LiteralPath $Arquivo -NewName $novoNome -ErrorAction Stop
        Log 'Sessao arquivada. Itens manuais nao equivalem a restauracao; confira os detalhes.'
        return $true
    } catch {
        Log ('Reversao interrompida: ' + $_.Exception.Message) -Erro
        return $false
    }
}

# Atestado manual: registra a verificacao feita pelo usuario, sem repetir a acao.
function Confirmar-ReversaoManual {
    param([string]$Arquivo, [int]$Indice,[switch]$SemRestauracao)
    Confirmar-PermissaoAlteracao 'estado-local'
    $ErrorActionPreference = 'Stop'
    $Arquivo=Confirmar-ArquivoJournal $Arquivo
    $json = Ler-JSON $Arquivo
    if ($null -eq $json -or $null -eq $json.itens) {throw 'Journal invalido.'}
    Confirmar-ContextoJournal $json
    Confirmar-FormatoJournal $json
    $itens = @($json.itens)
    for ($i = $itens.Count - 1; $i -ge 0; $i--) {
        if ($itens[$i].estadoReversao -in @('concluido','manual-sem-restauracao')) { continue }
        if ($i -ne $Indice) {throw 'Somente a ultima acao pendente pode ser encerrada.'}
        if ($SemRestauracao) {
            if ((Obter-TipoRecuperacao $itens[$i]) -ne 'manual-sem-garantia' -and $itens[$i].estadoReversao -ne 'em_andamento') {throw 'Recuperacao ainda nao avaliada.'}
            $itens[$i] | Add-Member -NotePropertyName estadoReversao -NotePropertyValue 'manual-sem-restauracao' -Force
            $itens[$i] | Add-Member -NotePropertyName encerradoManualEm -NotePropertyValue (Get-Date -Format 'o') -Force
        } else {
            if ($itens[$i].estadoReversao -ne 'em_andamento') {throw 'Somente a ultima acao incerta pode ser confirmada.'}
            $itens[$i].estadoReversao='concluido'
            $itens[$i] | Add-Member -NotePropertyName confirmadoManualEm -NotePropertyValue (Get-Date -Format 'o') -Force
        }
        Gravar-JournalSeguro -Arquivo $Arquivo -Objeto $json
        Log ('Acao '+$i+' encerrada manualmente; consulte o estado registrado, sem repetir a operacao.')
        if (@($itens | Where-Object { $_.estadoReversao -notin @('concluido','manual-sem-restauracao') }).Count -eq 0) {
            if (Test-Path -LiteralPath ($Arquivo+'.revertido') -ErrorAction Stop) {throw 'Arquivo de historico ja existe; journal preservado.'}
            Rename-Item -LiteralPath $Arquivo -NewName ((Split-Path -Leaf $Arquivo) + '.revertido') -ErrorAction Stop
        }
        return
    }
    throw 'Nenhuma acao incerta encontrada.'
}

# ---- ponto de restauracao ----

function Criar-PontoRestauracao {
    Confirmar-PermissaoAlteracao 'restore'
    try {
        foreach ($p in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\SystemRestore')) {
            if (Test-Path -LiteralPath $p -ErrorAction Stop) {throw 'Indicador de politica de restauracao presente; use o procedimento autorizado.'}
        }
        $antes=@(Get-ComputerRestorePoint -ErrorAction Stop)
        $descricao='OtimizadorPC '+[guid]::NewGuid().ToString('N').Substring(0,12)
        Confirmar-PermissaoAlteracao 'restore'
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
        $global:CacheAppx = @(Get-AppxPackage -ErrorAction Stop | ForEach-Object { $_.Name })
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
                return ((Obter-PlanoEnergiaAtivo) -eq [string]$Acao.guid)
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
    if ($ativos -eq 0) {
        if ($verificaveis -lt @($Tweak.acoes).Count) {return 'desconhecido'}
        return 'nao'
    }
    return 'parcial'
}

# ---- presets via linha de comando (modo cli) ----

# aplica um preset de nivel (seguro/balanceado/agressivo) sem janela nenhuma.
# usado pelo modo cli: .\otimizadorpc.ps1 -Cli balanceado [-Simular]
# replica o fluxo do botao aplicar da gui: restore point, journal por acao e log em arquivo.
# Perfis conservadores: selecao explicita por ID, sem scripts customizados.
function Obter-PerfilRecomendado {
    # No device classification or evidence-free performance promise.
    return 'essencial'
}

# A matriz e um limite minimo, nao uma garantia de efetividade.
function Obter-ContextoAjustes {
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        if (-not $os.BuildNumber -or -not $cv.EditionID -or -not $os.ProductType) {throw 'Dados incompletos.'}
        return [pscustomobject]@{build=[int]$os.BuildNumber;edicao=[string]$cv.EditionID;cliente=($os.ProductType -eq 1)}
    } catch {return $null}
}

function Testar-CompatibilidadeAjuste {
    param($Ajuste,$Contexto)
    if (-not $Contexto -or $Contexto.build -lt 10240 -or -not $Contexto.cliente) {return $false}
    if ($Ajuste.so -eq 'win11' -and $Contexto.build -lt 22000) {return $false}
    if ($Ajuste.so -eq 'win10' -and $Contexto.build -ge 22000) {return $false}
    if ($Ajuste.buildMinima -and $Contexto.build -lt [int]$Ajuste.buildMinima) {return $false}
    if ($Ajuste.edicoes -and $Contexto.edicao -notin @($Ajuste.edicoes)) {return $false}
    return $true
}

function Selecionar-TweaksPreset {
    param([string]$Nivel, $Catalogo, [bool]$Win11, $Contexto)
    if ($Nivel -eq 'recomendado') { $Nivel = Obter-PerfilRecomendado }
    $perfis = @{
        essencial   = @('extensoes-de-arquivo')
        gamer       = @('extensoes-de-arquivo')
        notebook    = @('extensoes-de-arquivo')
        privacidade = @('extensoes-de-arquivo')
        corporativo = @('extensoes-de-arquivo')
    }
    $legado = @('seguro', 'balanceado', 'agressivo') -contains $Nivel
    if (-not $legado -and -not $perfis.ContainsKey($Nivel)) { throw ('Preset desconhecido: ' + $Nivel) }
    foreach ($t in $Catalogo.tweaks) {
        if ($t.id -like 'custom-*' -or $t.apenasManual -or (Obter-BloqueioAjuste $t)) { continue }
        if ($PSBoundParameters.ContainsKey('Contexto') -and -not (Testar-CompatibilidadeAjuste $t $Contexto)) {continue}
        if (($t.so -eq 'win11' -and -not $Win11) -or ($t.so -eq 'win10' -and $Win11)) { continue }
        if ($t.id -eq 'extensoes-de-arquivo' -and $t.auditoria.decisao -eq 'essencial' -and (($legado -and ($t.niveis -contains $Nivel)) -or (-not $legado -and ($perfis[$Nivel] -contains $t.id)))) {
            $t
        }
    }
}

# A typed decision for a complete tweak. This supplements the global guard.
# No state below grants permission to bypass administrative controls.
# Reject conflicting writes before any restore point, journal or mutation.
function Confirmar-LoteAjustes {
    param([object[]]$Ajustes)
    $alvos=@{}
    foreach ($t in $Ajustes) {
        foreach ($a in @($t.acoes)) {
            $alvo=$null;$valor=$null
            switch ($a.tipo) {
                'registro' {
                    $alvo='registro:'+(Converter-Hive ([string]$a.caminho)).ToLowerInvariant()+'|'+([string]$a.nome).ToLowerInvariant()
                    if ($a.remover) {$valor='remover'}
                    else {
                        $kind=(Converter-Kind $a.tipoValor).ToString()
                        $dados=switch ($kind) {
                            'DWord' {[int]$a.dados}
                            'QWord' {[long]$a.dados}
                            'Binary' {,([byte[]]@($a.dados))}
                            'MultiString' {,([string[]]@($a.dados))}
                            default {[string]$a.dados}
                        }
                        $valor=$kind+':'+(ConvertTo-Json -InputObject $dados -Depth 8 -Compress)
                    }
                }
                'servico' {$alvo='servico:'+([string]$a.nome).ToLowerInvariant();$valor=([string]$a.inicio).ToLowerInvariant()}
                'energia' {$alvo='energia:plano-ativo';$valor=([guid]$a.guid).ToString()}
                'recurso' {$alvo='recurso:'+([string]$a.nome).ToLowerInvariant();$valor=[string]$a.ativar}
            }
            if (-not $alvo) {continue}
            if ($alvos.ContainsKey($alvo) -and $alvos[$alvo].valor -cne $valor) {
                throw ('Ajustes conflitantes: '+$alvos[$alvo].nome+' / '+$t.nome+' ('+$alvo+'). Desmarque um deles.')
            }
            $alvos[$alvo]=@{valor=$valor;nome=[string]$t.nome}
        }
    }
}

function Avaliar-AutorizacaoAjuste {
    param($Ajuste,$Contexto,[bool]$Autorizado,[switch]$ConsultarPoliticas)
    $estado='permitido';$motivo='Precondicoes verificadas nesta etapa; revalidacao no executor obrigatoria.'
    $escopos=@()
    foreach ($acao in @($Ajuste.acoes)) {
        if ($acao.tipo -eq 'registro') {
            $escopos+=if ($acao.caminho -match '^(HKCU:|HKEY_CURRENT_USER)\\') {'usuario-atual'} else {'computador'}
        } elseif ($acao.tipo -eq 'appx') {$escopos+='usuario-atual'}
        else {$escopos+='computador'}
    }
    if (-not $Ajuste.id -or @($Ajuste.acoes).Count -eq 0) {$estado='desconhecido';$motivo='Ajuste sem identidade ou acoes.'}
    else {
        $bloqueio=Obter-BloqueioAjuste $Ajuste
        if ($bloqueio) {$estado='bloqueado';$motivo=$bloqueio}
        elseif (-not $Autorizado) {$estado='exige-autorizacao';$motivo='Alteracao indisponivel no contexto atual; consulte o administrador.'}
        elseif (-not $Contexto) {$estado='desconhecido';$motivo='Compatibilidade do Windows nao confirmada.'}
        elseif (-not (Testar-CompatibilidadeAjuste $Ajuste $Contexto)) {$estado='incompativel';$motivo='Build, edicao ou tipo de Windows nao atende aos requisitos.'}
        elseif ($ConsultarPoliticas) {
            try {
                foreach ($acao in @($Ajuste.acoes)) {
                    switch ($acao.tipo) {
                        'registro' {Confirmar-PoliticaPreferenciaLocal $acao.caminho $acao.nome}
                        'energia' {Confirmar-PoliticaEnergiaLocal; Confirmar-PlanoEnergiaDisponivel $acao.guid}
                        'recurso' {Confirmar-PoliticaRecursosLocal}
                        'servico' {Confirmar-DependenciasServico $acao.nome $acao.inicio}
                        'appx' {if (-not (Testar-AppxCatalogado $acao.pacote)) {throw 'Pacote fora do catalogo de remocao.'}}
                    }
                }
            } catch {
                $motivo=$_.Exception.Message
                $estado=if ($motivo -match 'inconclusiv|indisponivel|nao confirmad') {'desconhecido'} else {'conflitante'}
            }
        } else {$estado='avaliacao-adicional';$motivo='Compatibilidade inicial confirmada; consulte politicas antes de aplicar.'}
    }
    return [pscustomobject]@{id=[string]$Ajuste.id;estado=$estado;motivo=$motivo;escopos=@($escopos | Sort-Object -Unique);exigeElevacao=$true}
}

function Confirmar-AutorizacaoAjuste {
    param($Ajuste,$Contexto)
    Confirmar-PermissaoAlteracao 'estado-local'
    foreach ($acao in @($Ajuste.acoes)) {Confirmar-PermissaoAlteracao (Obter-IdOperacaoAcao $acao)}
    $decisao=Avaliar-AutorizacaoAjuste $Ajuste $Contexto $true -ConsultarPoliticas
    if ($decisao.estado -ne 'permitido') {throw ($Ajuste.nome+': '+$decisao.motivo)}
}

function Aplicar-Preset {
    param([string]$Nivel, [switch]$Simular)

    try {
        $ctx=Obter-ContextoAjustes
        if ($Simular) { $selecionados=@(Selecionar-TweaksPreset -Nivel $Nivel -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11)) }
        else { $selecionados=@(Selecionar-TweaksPreset -Nivel $Nivel -Catalogo $global:CatalogoTweaks -Win11 (Eh-Win11) -Contexto $ctx) }
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
            if (-not (Testar-CompatibilidadeAjuste $t $ctx)) { Log 'Simulacao hipotetica: compatibilidade minima nao confirmada neste ambiente.' }
            foreach ($acao in $t.acoes) { Executar-Acao $acao $t.nome -Simular }
        }
        Log 'SIMULACAO concluida: o pc NAO foi alterado.'
        return $true
    }

    Confirmar-PermissaoAlteracao 'estado-local'
    try {Confirmar-LoteAjustes $selecionados} catch {Log $_.Exception.Message -Erro;return $false}
    foreach ($t in $selecionados) {
        try {Confirmar-AutorizacaoAjuste $t $ctx} catch {Log ('Preset real interrompido: '+$_.Exception.Message) -Erro;return $false}
    }
    if (-not (Criar-PontoRestauracao)) { Log 'Preset real interrompido: ponto de restauracao novo nao confirmado.' -Erro; return $false }
    Iniciar-Sessao 'ajustes'
    $i = 0
    foreach ($t in $selecionados) {
        $i++
        Log ('aplicando {0}/{1}: {2}' -f $i, $selecionados.Count, $t.nome)
        try {Confirmar-AutorizacaoAjuste $t (Obter-ContextoAjustes)} catch {Log ('Ajuste preservado: '+$_.Exception.Message) -Erro;continue}
        foreach ($acao in $t.acoes) { Executar-Acao $acao $t.nome; if (Testar-SessaoInterrompida) {break} }
        if (Testar-SessaoInterrompida) {break}
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
