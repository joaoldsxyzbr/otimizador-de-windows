# ============================================================
#  otimizadorpc.ps1 - app de otimizacao do windows do joao
#  janela nativa wpf (estilo winutil do chris titus), win10 e win11
#  como rodar: clique duas vezes em rodar-como-admin.bat
#  modo cli (sem janela): .\otimizadorpc.ps1 -Cli balanceado [-Simular]
# ============================================================

param(
    # modo cli: aplica um preset (seguro/balanceado/agressivo) sem abrir janela
    [string]$Cli,
    # junto com -Cli: so descreve o que faria, nao altera nada
    [switch]$Simular
)

# ---- auto-elevacao para administrador ----
$identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identidade)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        # repassa os parametros pro processo elevado; no modo cli deixa o console
        # visivel e aberto no fim (-NoExit, sempre ANTES do -File, senao o
        # powershell trata como parametro do script) pra ler o resultado
        $argsElev = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
        if ($Cli) { $argsElev += '-NoExit' }
        $argsElev += @('-File', ('"{0}"' -f $PSCommandPath))
        if ($Cli)     { $argsElev += @('-Cli', ('"{0}"' -f $Cli)) }
        if ($Simular) { $argsElev += '-Simular' }
        if ($Cli) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argsElev
        } else {
            Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $argsElev
        }
    } catch { }
    exit
}

$ErrorActionPreference = 'Continue'

# ---- assemblies do wpf ----
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
} catch {
    [System.Windows.MessageBox]::Show('Nao foi possivel carregar o WPF: ' + $_.Exception.Message, 'OtimizadorPC')
    exit 1
}

# ---- modulos do app ----
$pastaModulos = Join-Path $PSScriptRoot 'src\modules'
. (Join-Path $pastaModulos 'comum.ps1')
. (Join-Path $pastaModulos 'motor.ps1')
. (Join-Path $pastaModulos 'consertos.ps1')
. (Join-Path $pastaModulos 'desinstalador.ps1')
. (Join-Path $pastaModulos 'sistema.ps1')
. (Join-Path $pastaModulos 'gui.ps1')

Garantir-Pastas
$global:AmbienteTrabalho = Detectar-AmbienteTrabalho

# ---- catalogos ----
try {
    $global:CatalogoTweaks = Ler-JSON (Join-Path $global:PastaDados 'tweaks.json')
    $global:CatalogoApps   = Ler-JSON (Join-Path $global:PastaDados 'aplicativos.json')
    $global:CatalogoUwp    = Ler-JSON (Join-Path $global:PastaDados 'uwp.json')
} catch {
    $msg = 'Falha ao ler os catalogos em \data: ' + $_.Exception.Message
    if ($Cli) { Write-Host $msg -ForegroundColor Red } else {
        [System.Windows.MessageBox]::Show($msg, 'OtimizadorPC')
    }
    exit 1
}

# ---- tweaks custom (arquivos .reg na pasta custom\ ao lado do app) ----
$tweaksCustom = @(Carregar-TweaksCustom)
$global:CatalogoTweaks.tweaks = @($global:CatalogoTweaks.tweaks) + $tweaksCustom

# ---- modo cli: aplica o preset e sai, sem carregar a janela ----
if ($Cli) {
    # no cli o log vai pro console e pro arquivo; as funcoes de status sao
    # ui-safe (checam o dicionario $global:UI), entao so o log precisa de override
    function global:Log {
        param([string]$Mensagem, [switch]$Erro)
        $prefixo = ''
        if ($Erro) {
            $prefixo = '[ERRO] '
            $global:ErrosSessao++
        }
        $linha = ("{0}[{1}] {2}" -f $prefixo, (Get-Date -Format 'HH:mm:ss'), $Mensagem)
        Write-Host $linha
        try { Add-Content -Path $global:ArquivoLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { }
    }

    Log ('otimizadorpc modo cli - ' + (Nome-Windows))
    Log ('log desta execucao: ' + $global:ArquivoLog)
    if ($global:AmbienteTrabalho.Count -gt 0) {
        Log 'AMBIENTE: este pc parece gerenciado pela empresa; revise o log com atencao.'
    }
    $ok = Aplicar-Preset -Nivel $Cli -Simular:$Simular
    Log ('log completo salvo em: ' + $global:ArquivoLog)
    if ($ok) { exit 0 } else { exit 1 }
}

# ---- janela ----
$xamlCaminho = Join-Path $PSScriptRoot 'src\ui\principal.xaml'
try {
    $xamlTexto = Get-Content -Path $xamlCaminho -Raw -Encoding UTF8
    $leitor = New-Object System.IO.StringReader($xamlTexto)
    $leitorXml = [System.Xml.XmlReader]::Create($leitor)
    $global:Janela = [Windows.Markup.XamlReader]::Load($leitorXml)
    $leitorXml.Close()
    $leitor.Close()
} catch {
    $msg = 'Falha ao montar a janela (XAML): ' + $_.Exception.Message
    [System.Windows.MessageBox]::Show($msg, 'OtimizadorPC') | Out-Null
    exit 1
}

# ---- liga todos os controles nomeados ----
$controles = @(
    'PontoStatus', 'StatusTexto', 'BarraProgresso', 'LogBox',
    'BotaoNavInicio', 'BotaoNavAjustes', 'BotaoNavDebloat', 'BotaoNavDesinstalar', 'BotaoNavInstalar',
    'BotaoNavConfig', 'BotaoNavAtualizacoes', 'BotaoNavManutencao', 'BotaoNavDesfazer',
    'InfoHost', 'InfoSo', 'InfoCpu', 'InfoGpu', 'InfoRam', 'InfoDisco', 'InfoUptime', 'InfoRestore', 'InfoAmbiente', 'InfoDiagnostico',
    'BotaoCriarRestore', 'BotaoInventario',
    'ListaAjustes', 'ChkPontoRestore', 'ChkSimularAjustes', 'BotaoPresetSeguro', 'BotaoPresetBalanceado', 'BotaoPresetAgressivo', 'BotaoPerfilEssencial', 'BotaoPerfilGamer', 'BotaoPerfilNotebook', 'BotaoPerfilPrivacidade', 'BotaoPerfilCorporativo', 'BotaoPerfilRecomendado', 'BotaoAplicarAjustes', 'FiltroAjustes', 'BotaoExportarPlano', 'BotaoImportarPlano',
    'ListaUwp', 'ChkPontoRestoreUwp', 'BotaoRemoverUwp', 'FiltroUwp',
    'ListaProgramas', 'FiltroDesinstalar', 'BotaoAtualizarProgramas', 'ChkPontoRestoreDesinstalar', 'BotaoDesinstalarProg', 'BotaoVarrerRastros', 'RotuloRastros', 'BotaoMarcarRastros', 'BotaoApagarRastros', 'ListaRastros',
    'ListaApps', 'BotaoInstalarApps', 'BotaoAtualizarTudo', 'BotaoMarcarPadroes', 'FiltroApps',
    'ListaRecursos', 'BotaoInstalarRecursos', 'BotaoFixUpdate', 'BotaoFixRede', 'BotaoFixIntegridade', 'BotaoFixWinget', 'PainelLegado',
    'ChkBloquearDrivers', 'ChkAdiarRecursos', 'BotaoAplicarAtualizacoes', 'BotaoBuscarAtualizacoes', 'BotaoResetUpdate2',
    'BotaoLimparTemp', 'BotaoLimpezaDisco', 'BotaoLimpezaDism', 'BotaoVerificarIntegridade', 'BotaoVerificarDisco',
    'BotaoRecuperarIcones', 'BotaoLimparDns', 'BotaoSincronizarHora', 'BotaoBackupDrivers', 'BotaoAnalisarArmazenamento',
    'ListaDesfazer', 'BotaoDesfazer', 'BotaoDesfazerUma', 'BotaoAtualizarListaSessoes', 'BotaoDetalhesSessao'
)
foreach ($nome in $controles) {
    $global:UI[$nome] = $global:Janela.FindName($nome)
    if ($null -eq $global:UI[$nome]) {
        [System.Windows.MessageBox]::Show('Controle nao encontrado no XAML: ' + $nome, 'OtimizadorPC') | Out-Null
        exit 1
    }
}

# ---- monta a interface e mostra ----
Ligar-Tudo

Log ('otimizadorpc iniciado - ' + (Nome-Windows))
Log ('usuario: ' + $env:USERNAME + ' | maquina: ' + $env:COMPUTERNAME)
Log ('pasta do app: ' + $global:PastaApp)
Log 'dica: crie um ponto de restauracao antes do primeiro uso (aba inicio).'
if ($tweaksCustom.Count -gt 0) {
    Log ('tweaks custom carregados da pasta custom\: ' + $tweaksCustom.Count + ' (categoria Customizadas; presets ignoram, so manual).')
} else {
    Log 'dica: coloque seus arquivos .reg em custom\ que eles viram ajustes com journal e desfazer.'
}
if ($global:AmbienteTrabalho.Count -gt 0) {
    Log 'AMBIENTE: este pc parece gerenciado pela empresa:'
    foreach ($a in $global:AmbienteTrabalho) { Log ('  - ' + $a) }
    Log '  recomendacao: use o preset Seguro, rode o modo Simular antes, e evite mexer em rede/telemetria aqui.'
} else {
    Log 'ambiente: pc pessoal (sem dominio, sem antivirus corporativo).'
}

$global:Janela.Title = ('OtimizadorPC - ' + (Nome-Windows) + ' - modo administrador')
[void]$global:Janela.ShowDialog()
