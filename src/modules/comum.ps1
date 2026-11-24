# comum.ps1 - log, status e utilidades do otimizadorPC
# tudo em minusculas sem acento, na convencao do joao

$global:PastaApp      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$global:PastaDados    = Join-Path $global:PastaApp 'data'
$global:RaizEstado = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'otimizadorpc-v2'
$global:PastaLog = Join-Path $global:RaizEstado 'logs'
$global:PastaDesfazer = Join-Path $global:RaizEstado 'desfazer'
$global:PastaQuarantena = Join-Path $global:RaizEstado 'quarentena'
$global:ArquivoLog    = Join-Path $global:PastaLog ("otimizadorpc-" + (Get-Date -Format 'yyyy-MM-dd') + ".log")
$global:VersaoOtimizador = '2.0.0-rc.5'
$global:ErrosSessao   = 0
$global:UI            = @{}

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
    if (-not (Test-Path -LiteralPath $Pasta)) {
        [void][IO.Directory]::CreateDirectory($Pasta,(Nova-ACLPrivada))
    }
    Verificar-PastaPrivada $Pasta
}

function Garantir-Pastas {
    Garantir-PastaPrivada $global:RaizEstado
    foreach ($p in @($global:PastaLog, $global:PastaDesfazer, $global:PastaQuarantena)) {
        Garantir-PastaPrivada $p
    }
}

# Lock exclusivo no volume local, compartilhado entre GUI, CLI e portatil.
# O arquivo permanece; o handle e liberado ao fechar ou morrer o processo.
function Obter-TravaInstancia {
    param([string]$Pasta = $global:RaizEstado)
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
    try { Add-Content -Path $global:ArquivoLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { }
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
function Reiniciar-Explorer {
    Log 'Reiniciando o Explorador de Arquivos...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Log 'Explorador reiniciado.'
}

# Windows PowerShell 5.1 transforma stderr nativo em ErrorRecord mesmo com exit 0.
# Executa somente utilitarios nativos conhecidos e decide pelo codigo de saida.
function Executar-RegNativo {
    param([ValidateSet('export','import','delete')][string]$Operacao, [string]$Alvo, [string]$Arquivo)
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
