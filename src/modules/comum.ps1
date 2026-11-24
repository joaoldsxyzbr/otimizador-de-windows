# comum.ps1 - log, status e utilidades do otimizadorPC
# tudo em minusculas sem acento, na convencao do joao

$global:PastaApp      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$global:PastaDados    = Join-Path $global:PastaApp 'data'
$global:PastaLog      = Join-Path $env:ProgramData 'otimizadorpc\logs'
$global:PastaDesfazer = Join-Path $env:ProgramData 'otimizadorpc\desfazer'
$global:ArquivoLog    = Join-Path $global:PastaLog ("otimizadorpc-" + (Get-Date -Format 'yyyy-MM-dd') + ".log")
$global:VersaoOtimizador = '2.0.0-rc.3'
$global:ErrosSessao   = 0
$global:UI            = @{}

function Garantir-Pastas {
    foreach ($p in @($global:PastaLog, $global:PastaDesfazer)) {
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }
}

function Ler-JSON {
    param([string]$Caminho)
    return (Get-Content -Path $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json)
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
