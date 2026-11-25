# comum.ps1 - log, status e utilidades do otimizadorPC
# tudo em minusculas sem acento, na convencao do joao

$global:PastaApp      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$global:PastaDados    = Join-Path $global:PastaApp 'data'
$global:RaizEstado = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'otimizadorpc-v2'
$global:PastaLog = Join-Path $global:RaizEstado 'logs'
$global:PastaDesfazer = Join-Path $global:RaizEstado 'desfazer'
$global:PastaQuarantena = Join-Path $global:RaizEstado 'quarentena'
$global:ArquivoLog    = Join-Path $global:PastaLog ("otimizadorpc-" + (Get-Date -Format 'yyyy-MM-dd') + ".log")
$global:VersaoOtimizador = '2.0.0-rc.9'
$global:ErrosSessao   = 0
$global:UI            = @{}

# A protecao e uma regra do app, nao uma fronteira de seguranca do Windows.
# O entrypoint inicializa o modo antes de qualquer operacao de estado.
# Application authorization contract. Windows ACL/UAC/GPO/MDM remain authoritative.
# Unknown operation IDs are denied. The user's explicit consent is not a policy bypass.
function Obter-DescritorOperacao {
    param([string]$Id)
    $mapa=@{
        'estado-local'=@('aplicativo','baixo','estado privado e trava','nao se aplica','ACL e identidade')
        'exportar'=@('usuario','cautela','destino escolhido','manual','politicas de dados nao confirmadas')
        'download'=@('usuario','cautela','destino escolhido','manual','politicas de origem nao confirmadas')
        'registro-usuario'=@('usuario','cautela','journal de valor','por snapshot','preferencias e GPO/MDM')
        'registro-local'=@('usuario','cautela','journal de valor','por snapshot','gerenciamento e escopo restrito')
        'registro-maquina'=@('computador','alto','journal de valor','por snapshot','politica efetiva nao confirmada')
        'servico'=@('computador','alto','journal de servico','por snapshot','dependentes e gerenciamento')
        'tarefa'=@('computador','alto','nenhuma escrita nova','manual','dependencias e identidade funcional nao confirmadas')
        'tarefa-reversao'=@('computador','alto','journal e assinatura','por snapshot','definicao e gerenciamento')
        'energia'=@('computador','cautela','journal de plano','por snapshot','politica e plano disponivel')
        'recurso'=@('computador','alto','journal de dependencias','condicional','servicing e build')
        'appx'=@('usuario','alto','journal de pacote','parcial/manual','dependencias, Store e gerenciamento')
        'winget'=@('misto','alto','consentimento','manual','App Installer e origem')
        'desinstalar'=@('misto','alto','journal de identidade','manual','identidade, assinatura e gerenciamento')
        'rastros'=@('misto','alto','quarentena/journal','condicional','identidade e gerenciamento')
        'path'=@('misto','alto','journal de valor','por snapshot','escopo e gerenciamento')
        'restore'=@('computador','cautela','ponto confirmado','Windows','protecao de sistema')
        'temp'=@('usuario','cautela','previa e consentimento','irreversivel','identidade e caminhos')
        'dns'=@('computador','cautela','consentimento','nao se aplica','rede e gerenciamento')
        'hora'=@('computador','cautela','consentimento','manual','fonte configurada e gerenciamento')
        'reparo'=@('computador','alto','consentimento','manual','servicing e gerenciamento')
        'diagnostico-admin'=@('consulta','baixo','consentimento quando aplicavel','nao se aplica','comando nativo sem reparo')
        'consulta-winget'=@('consulta','cautela','consentimento','nao se aplica','fontes e App Installer')
        'nativo'=@('consulta','baixo','nenhuma alteracao automatica','nao se aplica','permissoes nativas')
    }
    if (-not $Id -or -not $mapa.ContainsKey($Id)) {return $null}
    $v=$mapa[$Id]
    [pscustomobject]@{id=$Id;escopo=$v[0];risco=$v[1];backup=$v[2];reversao=$v[3];politica=$v[4];exigeElevacao=($Id -notin @('nativo'));buildMin=10240;edicoes=@('cliente');precondicao='identidade, permissao, contexto e verificacoes do alvo';verificacao='executor especifico; confirmar efeito ou informar limites'}
}

function Resolver-AutorizacaoOperacao {
    param([string]$Id,$Contexto)
    $d=Obter-DescritorOperacao $Id
    $estado='permitido';$motivo='Precondicoes gerais confirmadas; verificacoes do alvo continuam obrigatorias.'
    $proximo='Revisar previa e confirmar a operacao.'
    if (-not $d) {$estado='bloqueado';$motivo='Operacao nao catalogada.'}
    elseif ($Id -eq 'tarefa') {$estado='bloqueado';$motivo='Tarefa sem identidade funcional revisada; alteracao nova somente pela ferramenta nativa.'}
    elseif ($Id -eq 'nativo') {$motivo='Somente abertura da ferramenta nativa; Windows controla qualquer acao.'}
    elseif (-not $Contexto -or $Contexto.admin -isnot [bool] -or $Contexto.diagnostico -isnot [bool] -or $Contexto.consentiu -isnot [bool]) {$estado='desconhecido';$motivo='Contexto de autorizacao indisponivel.'}
    elseif (-not $Contexto.admin -or $Contexto.diagnostico -or -not $Contexto.consentiu) {$estado='exige-autorizacao';$motivo='Exige elevacao e autorizacao explicita; diagnostico permanece disponivel.'}
    elseif (-not $Contexto.identidade -or $Contexto.identidade -ne $Contexto.sidInicial -or $Contexto.visaoCorreta -ne $true) {$estado='desconhecido';$motivo='Identidade ou arquitetura da sessao nao confirmada.'}
    elseif (-not $Contexto.windows -or $Contexto.windows.cliente -isnot [bool] -or -not $Contexto.windows.edicao -or -not $Contexto.windows.build) {$estado='desconhecido';$motivo='Build/edicao indisponivel.'}
    elseif (-not $Contexto.windows.cliente -or $Contexto.windows.build -lt $d.buildMin) {$estado='incompativel';$motivo='Windows cliente compativel exigido.'}
    elseif ($d.escopo -in @('usuario','misto') -and $Contexto.usuarioCorreto -ne $true) {$estado='desconhecido';$motivo='Usuario interativo nao confirmado; nao alterar HKCU, AppX ou dados de outro usuario.'}
    elseif ($Id -notin @('estado-local','diagnostico-admin')) {
        if ($Contexto.sinaisConfirmados -ne $true) {$estado='desconhecido';$motivo='Consulta de politicas/gerenciamento necessaria indisponivel.'}
        else {
            $sinais=@($Contexto.sinais | Where-Object {$_})
            if ($Id -in @('registro-usuario','restore')) {
                # Update-source and proxy policy do not decide an Explorer preference.
                # Device join, enrollment, security management and unknown core state still do.
                $sinais=@($sinais | Where-Object {$_ -notmatch '^Sinal de politica de (atualizacao organizacional|proxy)\.$' -and $_ -notmatch '^Inconclusivo: consulta de politica de (atualizacao|proxy) indisponivel\.$'})
            }
            if ($sinais.Count -gt 0) {
                $estado=if (@($sinais | Where-Object {$_ -match '^Inconclusivo:'}).Count) {'desconhecido'} else {'conflitante'}
                $motivo='Indicadores relevantes exigem revisao autorizada: '+($sinais -join '; ')
            }
        }
    }
    if ($estado -ne 'permitido') {$proximo='Use consulta ou ferramenta nativa autorizada; consulte o administrador/TI. Nao contorne a politica.'}
    [pscustomobject]@{id=$Id;estado=$estado;motivo=$motivo;proximo=$proximo;descritor=$d}
}

function Obter-IdentidadeAutorizacao {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($id)
        [pscustomobject]@{sid=$id.User.Value;admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);visaoCorreta=(-not [Environment]::Is64BitOperatingSystem -or [Environment]::Is64BitProcess)}
    } finally {$id.Dispose()}
}

function Testar-UsuarioInterativo {
    param([string]$Sid)
    try {
        $sessao=[Diagnostics.Process]::GetCurrentProcess().SessionId
        if ($sessao -eq 0) {return $false}
        $p=@(Get-CimInstance -ClassName Win32_Process -Filter ("Name='explorer.exe' AND SessionId="+$sessao) -OperationTimeoutSec 8 -ErrorAction Stop)
        if (-not $p.Count) {return $false}
        $sids=@(foreach ($proc in $p) {
            $dono=Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid -OperationTimeoutSec 8 -ErrorAction Stop
            if ($dono.ReturnValue -ne 0 -or -not $dono.Sid) {throw 'SID indisponivel.'}
            $dono.Sid
        })
        return (@($sids | Sort-Object -Unique).Count -eq 1 -and $sids[0] -eq $Sid)
    } catch {return $false}
}

function Obter-ContextoAutorizacaoAtual {
    param([string]$Id,[switch]$Previa)
    $cfg=$global:ContextoAutorizacaoInicial
    if (-not $cfg) {return $null}
    $d=Obter-DescritorOperacao $Id
    try {
        $ident=if ($Previa) {$cfg.identidade} else {Obter-IdentidadeAutorizacao}
        $sinais=$cfg.sinais
        $confirmados=$cfg.sinaisConfirmados
        if (-not $Previa -and $Id -notin @('estado-local','diagnostico-admin','nativo')) {
            try {$sinais=@(Detectar-AmbienteTrabalho);$confirmados=$true}
            catch {$sinais=@('Inconclusivo: consulta de gerenciamento indisponivel.');$confirmados=$false}
        }
        $usuario=$cfg.usuarioCorreto
        if (-not $Previa -and $d.escopo -in @('usuario','misto')) {$usuario=Testar-UsuarioInterativo $ident.sid}
        $windows=if ($Previa -or $Id -eq 'estado-local') {$cfg.windows} else {Obter-ContextoAjustes}
        [pscustomobject]@{admin=$ident.admin;diagnostico=([bool]$cfg.diagnostico -or $global:ModoProtegido -ne $false);consentiu=[bool]$cfg.consentiu;identidade=$ident.sid;sidInicial=$cfg.identidade.sid;visaoCorreta=($ident.visaoCorreta -and $cfg.identidade.visaoCorreta);windows=$windows;usuarioCorreto=$usuario;sinais=$sinais;sinaisConfirmados=$confirmados}
    } catch {return $null}
}

function Avaliar-PermissaoOperacao {
    param([string]$Id,[switch]$Previa)
    if ($Id -in @('nativo','tarefa') -or -not (Obter-DescritorOperacao $Id)) {return (Resolver-AutorizacaoOperacao $Id $null)}
    Resolver-AutorizacaoOperacao $Id (Obter-ContextoAutorizacaoAtual $Id -Previa:$Previa)
}

function Confirmar-PermissaoAlteracao {
    param([string]$Id)
    if ($global:ModoProtegido -ne $false -and $Id -ne 'nativo') {throw 'Modo protegido: sessao somente leitura ou sem autorizacao explicita.'}
    $decisao=Avaliar-PermissaoOperacao $Id
    if ($decisao.estado -ne 'permitido') {throw ('Operacao recusada ['+$decisao.estado+']: '+$decisao.motivo)}
}

function Testar-PermissaoPrevia {
    param([string]$Id)
    return ((Avaliar-PermissaoOperacao $Id -Previa).estado -eq 'permitido')
}


# Estado novo com ACL explicita. Nao confia retroativamente em journals antigos.
function Nova-ACLPrivada {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $admin = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $sistema = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $ownerRights = [Security.Principal.SecurityIdentifier]::new('S-1-3-4')
    $acl.SetOwner($admin)
    $heranca = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @($admin,$sistema)) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$heranca,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    }
    # OWNER RIGHTS restringe o WRITE_DAC implicito do proprietario individual.
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($ownerRights,[Security.AccessControl.FileSystemRights]::ReadPermissions,$heranca,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    return $acl
}

function Verificar-PastaPrivada {
    param([string]$Pasta)
    $item = Get-Item -LiteralPath $Pasta -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Pasta de estado invalida: ' + $Pasta) }
    $acl = Get-Acl -LiteralPath $Pasta -ErrorAction Stop
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-32-544','S-1-5-18') -or -not $acl.AreAccessRulesProtected) {
        throw ('Proprietario ou heranca insegura na pasta de estado: ' + $Pasta)
    }
    $regras = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $esperados = @('S-1-5-32-544','S-1-5-18','S-1-3-4')
    foreach ($regra in $regras) {
        $sid = $regra.IdentityReference.Value
        if ($sid -notin $esperados -or $regra.AccessControlType -ne 'Allow') { throw ('ACL inesperada na pasta de estado: ' + $Pasta) }
        if ($regra.InheritanceFlags -ne [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' -or $regra.PropagationFlags -ne 'None') { throw 'Heranca de ACL insegura.' }
        $direitos = if ($sid -eq 'S-1-3-4') { [Security.AccessControl.FileSystemRights]::ReadPermissions -bor [Security.AccessControl.FileSystemRights]::Synchronize } else { [Security.AccessControl.FileSystemRights]::FullControl }
        if ($regra.FileSystemRights -ne $direitos) { throw ('Direitos inesperados na pasta de estado: ' + $Pasta) }
    }
    foreach ($sid in $esperados) {
        if (@($regras | Where-Object { $_.IdentityReference.Value -eq $sid }).Count -ne 1) { throw ('ACL incompleta: ' + $Pasta) }
    }
}

function Garantir-PastaPrivada {
    param([string]$Pasta)
    Confirmar-PermissaoAlteracao 'estado-local'
    if (-not (Test-Path -LiteralPath $Pasta)) {
        [void][IO.Directory]::CreateDirectory($Pasta,(Nova-ACLPrivada))
    }
    Verificar-PastaPrivada $Pasta
}

function Garantir-Pastas {
    Confirmar-PermissaoAlteracao 'estado-local'
    Garantir-PastaPrivada $global:RaizEstado
    foreach ($p in @($global:PastaLog, $global:PastaDesfazer, $global:PastaQuarantena)) {
        Garantir-PastaPrivada $p
    }
}

# Lock exclusivo no volume local, compartilhado entre GUI, CLI e portatil.
# O arquivo permanece; o handle e liberado ao fechar ou morrer o processo.
function Obter-TravaInstancia {
    param([string]$Pasta = $global:RaizEstado)
    Confirmar-PermissaoAlteracao 'estado-local'
    Verificar-PastaPrivada $Pasta
    $arquivo = Join-Path $Pasta 'instancia.lock'
    if (Test-Path -LiteralPath $arquivo) {
        $item = Get-Item -LiteralPath $arquivo -Force -ErrorAction Stop
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Arquivo de trava invalido.' }
    }
    try {
        return [IO.File]::Open($arquivo,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch [IO.IOException] {
        throw 'Outra instancia pode estar em execucao, ou a trava esta indisponivel. Feche a outra instancia e tente novamente.'
    }
}

# Preferencia visual local; nao altera o tema do Windows.
function Cor-Tema {
    param([string]$Cor,[string]$Tema=$global:TemaOtimizador)
    if ($Tema -ne 'claro') { return $Cor }
    $mapa = @{
        '#131316'='#f6f8fb'; '#22222a'='#ffffff'; '#e5e7eb'='#243247'; '#2c2c36'='#cbd5e1'
        '#4b5563'='#64748b'; '#9ca3af'='#475569'; '#1c1c24'='#e7eef7'; '#20202a'='#dbeafe'
        '#f3f4f6'='#0f172a'; '#3a3a45'='#94a3b8'; '#23232d'='#e2e8f0'; '#1c2f52'='#c7ddff'
        '#dbeafe'='#143b77'; '#374151'='#94a3b8'; '#17171b'='#eaf0f7'; '#26262c'='#cbd5e1'
        '#6b7280'='#526176'; '#93c5fd'='#1d4ed8'; '#d1d5db'='#334155'; '#1b1b20'='#ffffff'
        '#0d0d10'='#f1f5f9'; '#a7f3d0'='#166534'; '#86efac'='#166534'; '#fde047'='#854d0e'
    }
    if ($mapa.ContainsKey($Cor)) { return $mapa[$Cor] }
    return $Cor
}

function Converter-TemaXaml {
    param([string]$Xaml,[string]$Tema)
    if ($Tema -ne 'claro') { return $Xaml }
    return [regex]::Replace($Xaml,'#[0-9a-fA-F]{6}\b',{ param($m) Cor-Tema $m.Value 'claro' })
}

function Ler-TemaOtimizador {
    $global:TemaOtimizador='escuro'
    if ($global:ModoProtegido) { return }
    $arquivo=Join-Path $global:RaizEstado 'preferencias.json'
    if (Test-Path -LiteralPath $arquivo -PathType Leaf) {
        try {
            $obj=Ler-JSON $arquivo
            if ($obj.tema -in @('claro','escuro')) { $global:TemaOtimizador=[string]$obj.tema }
        } catch { }
    }
}

function Ler-JSON {
    param([string]$Caminho)
    return (Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}

function Eh-Win11 {
    return ([Environment]::OSVersion.Version.Build -ge 22000)
}

function Nome-Windows {
    $marca = 'Windows 10'
    if (Eh-Win11) { $marca = 'Windows 11' }
    return ("{0} (build {1})" -f $marca, [Environment]::OSVersion.Version.Build)
}

# registra mensagem no log da janela e no arquivo de log
function Log {
    param([string]$Mensagem, [switch]$Erro)
    $prefixo = ''
    if ($Erro) {
        $prefixo = '[ERRO] '
        $global:ErrosSessao++
        Cor-Status 'vermelho'
    }
    $linha = ("{0}[{1}] {2}" -f $prefixo, (Get-Date -Format 'HH:mm:ss'), $Mensagem)
    if (-not $global:ModoProtegido) { try { Confirmar-PermissaoAlteracao 'estado-local'; Verificar-PastaPrivada $global:PastaLog; Add-Content -LiteralPath $global:ArquivoLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { } }
    if ($global:UI.ContainsKey('LogBox') -and $null -ne $global:UI.LogBox) {
        $global:UI.LogBox.AppendText($linha + "`r`n")
        $global:UI.LogBox.ScrollToEnd()
        Atualizar-UI
    }
}

# escreve na barra de status
function Status {
    param([string]$Texto)
    if ($global:UI.ContainsKey('StatusTexto') -and $null -ne $global:UI.StatusTexto) {
        $global:UI.StatusTexto.Text = $Texto
        Atualizar-UI
    }
}

# muda a cor do ponto de status
function Cor-Status {
    param([string]$Cor)
    if (-not $global:UI.ContainsKey('PontoStatus') -or $null -eq $global:UI.PontoStatus) { return }
    switch ($Cor) {
        'verde'    { $global:UI.PontoStatus.Fill = '#22c55e' }
        'amarelo'  { $global:UI.PontoStatus.Fill = '#eab308' }
        'vermelho' { $global:UI.PontoStatus.Fill = '#ef4444' }
    }
}

# mostra reticencias na barra de progresso enquanto executa algo
function Ocupado {
    param([bool]$Ativo)
    if (-not $global:UI.ContainsKey('BarraProgresso') -or $null -eq $global:UI.BarraProgresso) { return }
    $global:UI.BarraProgresso.IsIndeterminate = $Ativo
    if ($Ativo) { Cor-Status 'amarelo' } else { Cor-Status 'verde' }
    Atualizar-UI
}

# deixa a janela respirar entre passos (message pump do WPF)
function Atualizar-UI {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# Cancelamento cooperativo: nunca interrompe uma alteracao em andamento.
function Iniciar-ProgressoLote {
    param([string]$Titulo,[int]$Total)
    $estado = @{ cancelado=$false; atual=0; total=$Total; janela=$null; barra=$null; texto=$null; fechando=$false }
    if (-not $global:Janela -or -not $global:Janela.IsLoaded) { return $estado }
    $dlg = New-Object System.Windows.Window
    $dlg.Owner=$global:Janela; $dlg.Title=$Titulo; $dlg.Width=460; $dlg.Height=180
    $dlg.WindowStartupLocation='CenterOwner'; $dlg.ResizeMode='NoResize'
    $painel=New-Object System.Windows.Controls.StackPanel
    $painel.Margin='16'
    $texto=New-Object System.Windows.Controls.TextBlock
    $texto.TextWrapping='Wrap'; $texto.Text='Preparando...'
    [void]$painel.Children.Add($texto)
    $barra=New-Object System.Windows.Controls.ProgressBar
    $barra.Minimum=0; $barra.Maximum=[math]::Max(1,$Total); $barra.Height=14; $barra.Margin='0,12,0,12'
    [void]$painel.Children.Add($barra)
    $cancelar=New-Object System.Windows.Controls.Button
    $cancelar.Content='Parar apos a acao atual'
    $cancelar.Tag=$estado
    $cancelar.Add_Click({ $this.Tag.cancelado=$true; $this.IsEnabled=$false; $this.Tag.texto.Text='Parando no proximo ponto seguro...' })
    [void]$painel.Children.Add($cancelar)
    $estado.janela=$dlg; $estado.barra=$barra; $estado.texto=$texto
    $dlg.Tag=$estado
    $dlg.Add_Closing({ param($sender,$eventArgs) if (-not $sender.Tag.fechando) { $sender.Tag.cancelado=$true; $eventArgs.Cancel=$true } })
    $dlg.Content=$painel
    $dlg.Show()
    return $estado
}

function Continuar-ProgressoLote {
    param($Estado,[string]$Descricao)
    if ($Estado.janela) {
        $Estado.barra.Value=$Estado.atual
        if (-not $Estado.cancelado) { $Estado.texto.Text=('{0}/{1}: {2}' -f ($Estado.atual+1),$Estado.total,$Descricao) }
        Atualizar-UI
    }
    if ($Estado.cancelado) { return $false }
    $Estado.atual++
    return $true
}

function Fechar-ProgressoLote {
    param($Estado)
    if ($Estado.janela) { $Estado.fechando=$true; $Estado.janela.Close() }
}

function Perguntar {
    param([string]$Tituloo, [string]$Mensagem)
    $r = [System.Windows.MessageBox]::Show($Mensagem, $Tituloo, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

function Avisar {
    param([string]$Tituloo, [string]$Mensagem)
    [System.Windows.MessageBox]::Show($Mensagem, $Tituloo, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
}

# reinicia o explorador de arquivos (aplica tweaks visuais sem reiniciar o pc)
function Reiniciar-Explorer { throw 'Encerramento de Explorer indisponivel; use a sessao do Windows.' }

# Windows PowerShell 5.1 transforma stderr nativo em ErrorRecord mesmo com exit 0.
# Executa somente utilitarios nativos conhecidos e decide pelo codigo de saida.
function Executar-RegNativo {
    param([ValidateSet('export','import','delete')][string]$Operacao, [string]$Alvo, [string]$Arquivo)
    Confirmar-PermissaoAlteracao $(if ($Operacao -eq 'export') {'estado-local'} else {'rastros'})
    if ($Operacao -eq 'delete') {throw 'Exclusao integral por reg.exe indisponivel.'}
    foreach ($valor in @($Alvo,$Arquivo)) {
        if ($valor -match '["\r\n]') { throw 'Argumento de registro invalido.' }
    }
    $argsReg = @($Operacao, ('"{0}"' -f $Alvo))
    if ($Operacao -eq 'export') { $argsReg += @(('"{0}"' -f $Arquivo), '/y') }
    if ($Operacao -eq 'delete') { $argsReg += '/f' }
    $exe = Join-Path $env:SystemRoot 'System32\reg.exe'
    $proc = Start-Process -FilePath $exe -ArgumentList $argsReg -NoNewWindow -Wait -PassThru -ErrorAction Stop
    try {
        if ($proc.ExitCode -ne 0) { throw ('reg.exe {0} falhou (codigo {1}): {2}' -f $Operacao,$proc.ExitCode,$Alvo) }
    } finally { $proc.Dispose() }
}
