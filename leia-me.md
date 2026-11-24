# otimizadorpc

app de otimizacao do windows do joao, no estilo do winutil do chris titus: janela nativa (wpf), catalogos em json e recuperacao de alteracoes quando possivel.

## como usar (o jeito simples)

1. de duplo clique em `rodar-como-admin.bat`
2. aceite o pedido de administrador (uac)
3. use a barra lateral pra navegar entre as abas

pronto. nao precisa instalar nada.

> alternativa: clique com o direito em `rodar-como-admin.bat` > "executar como administrador", ou abra um powershell como admin e rode `.\otimizadorpc.ps1`.

## o que tem dentro

| aba | o que faz |
| --- | --- |
| **inicio** | informacoes do pc (cpu, ram, disco, uptime) e criacao de ponto de restauracao |
| **ajustes e tweaks** | 47 tweaks em catalogo com 3 presets (seguro / balanceado / agressivo): telemetria, privacidade (inclusive copilot/ia), desempenho, barra de tarefas, explorer, edge (sem remover o navegador), energia e rede |
| **debloat** | remove apps uwp pre-instalados da microsoft (clima bing, 3d viewer, cortana, etc.), com lista de cautela pra nao apagar nada util |
| **desinstalar** | lista os programas instalados, desinstala via comando silencioso (msi/inno/nsis) e varre os rastros que sobram (pastas, registro, atalhos); tudo vai pra quarantena e desfaz |
| **instalar apps** | instalacao em massa via winget (66 apps com ids WinGet; essenciais vem marcados) |
| **config e recursos** | habilitar recursos do windows (hyper-v, wsl 2, sandbox, .net 3.5...), correcoes comuns (reset do windows update, reset de rede) e paineis classicos |
| **atualizacoes** | bloquear drivers via wu e adiar versoes novas (180 dias) sem tocar nas atualizacoes de seguranca |
| **manutencao** | limpeza de temporarios, limpeza de disco, dism, sfc, chkdsk online, cache de icones, dns e hora |
| **desfazer tudo** | lista todas as sessoes aplicadas com journal e reverte item por item, na ordem inversa |

## estado atual e filtros (v1.1)

- aba **ajustes e tweaks** mostra o estado real de cada tweak ao entrar (ou apos aplicar): verde "(ja aplicado)", amarelo "(parcial)", nada = nao aplicado
- aba **debloat** marca em cinza "(nao instalado)" e desmarca os pacotes uwp que nao existem na maquina
- caixas de filtro no topo das abas ajustes, debloat e instalar apps: digita e a lista encolhe na hora (nao diferencia maiuscula, nao precisa acento)
- os verificadores ficam no campo `verificar` do `data/tweaks.json` (mesma ideia do campo de script do winutil)

## como funciona (arquitetura)

- `otimizadorpc.ps1` — ponto de entrada: se auto-eleva pra admin, carrega o wpf e abre a janela
- `rodar-como-admin.bat` — atalho de duplo clique
- `src/ui/principal.xaml` — a janela inteira (dark mode, estilo winutil)
- `src/modules/comum.ps1` — log, status, utilidades
- `src/modules/motor.ps1` — **o coracao**: executa cada acao (registro, servico, comando, appx, recurso, energia) registrando no journal o valor original pra poder desfazer
- `src/modules/consertos.ps1` — correcoes e manutencao; operacoes pesadas abrem uma janela do powershell visivel (sem caixa-preta)
- `src/modules/sistema.ps1` — pagina de informacoes do pc
- `src/modules/gui.ps1` — monta as paginas a partir dos catalogos e liga os botoes
- `src/modules/desinstalador.ps1` — aba desinstalar: le o registro em busca de programas, roda o desinstalador deles (silencioso quando da) e varre rastros por nome (appdata, programdata, program files, menu iniciar, registro)
- `data/tweaks.json` — catalogo de tweaks (mesma ideia do `config/tweaks.json` do winutil)
- `data/aplicativos.json` — catalogo de apps (ids winget conferidos com o catalogo oficial do winutil)
- `data/uwp.json` — catalogo de apps pre-instalados removiveis

## desinstalador com limpeza de rastros (v1.2)

- a aba **desinstalar** lista os programas do registro (os mesmos de "aplicativos e recursos"), com filtro e atualizacao
- **desinstalar selecionado(s)** roda o desinstalador do proprio programa em modo silencioso quando reconhece o instalador (msi, inno setup, nsis); senao abre o desinstalador normal
- **varrer rastros** procura pelo nome do programa: pastas em appdata/programdata/program files, atalhos do menu iniciar e desktop, entrada de desinstalacao que sobrou, chaves de registro (hkcu e hklm), servicos que apontam pra ele, tarefas agendadas, regras de firewall, inicializacao (run) e entrada morta do PATH (v1.3)
- v1.3: programas sem comando de desinstalacao no registro caem no fallback do winget (procura pelo nome, em modo silencioso)
- servicos e tarefas da varredura nunca sao apagados: apenas parados/desativados, e o Desfazer restaura o tipo e o estado anteriores; regra de firewall removida e recriada na hora pelo journal; entrada do PATH sai sem quebrar o resto (mantem o tipo do valor e variaveis como %ProgramFiles%; relogon aplica)
- **apagar rastros** nao apaga de vez: move os arquivos pra `c:\programdata\otimizadorpc\quarantena` e exporta as chaves de registro pra `.reg`; a aba **desfazer tudo** restaura cada item na hora
- nomes genericos demais (ex.: "microsoft") sao bloqueados na varredura pra nao casar com coisas inocentes
- varredura e proposta automaticamente depois de cada desinstalacao

## testes automatizados

antes de qualquer mudanca ou uso no pc do trabalho, rode no terminal dentro da pasta:

```
powershell -ExecutionPolicy Bypass -File .\testar.ps1
```

isso valida offline (sem abrir a janela): os 3 catalogos json campo a campo, encoding ascii dos scripts, xaml bem formado, todos os controles do entrypoint com x:Name, paginas navegaveis e funcoes chamadas vs definidas. tudo verde = ok; qualquer vermelho aponta arquivo e campo.

## blindagem pro pc do trabalho (v1.3)

- **deteccao automatica de ambiente**: na inicializacao o app olha se o pc ingressa em dominio (ad), azure ad (entra) ou tem antivirus corporativo (mcafee, symantec, crowdstrike, etc.). o resultado aparece no inicio (linha "ambiente") e no log, com recomendacao pra pc gerenciado
- **modo simulacao**: na aba ajustes, marque "simular" e clique em aplicar: o log mostra tudo o que seria feito, sem alterar nada. rode assim antes de qualquer primeira aplicacao no pc do trabalho
- **backup .reg integral**: cada acao de registro exporta a chave inteira pra um .reg em `c:\programdata\otimizadorpc\desfazer` antes de mexer (alem do journal, que ja guarda o valor anterior de cada item)

## catalogo profundo (v1.3)

13 tweaks novos trazidos do catalogo oficial do winutil (chris titus), com curadoria: tudo o que la era duplicado do que ja tinhamos, remocao de edge/onedrive, bitlocker, hosts/acl hacks e coisas arriscadas foi descartado.

- **privacidade**: edge-debloat (13 politicas do edge: desativa telemetria, autopreenchimento, sugestoes de follow e afins, sem remover o navegador)
- **barra de tarefas**: bateria-porcentagem (icone com %), barra a esquerda (win11), remover home/galeria do explorer (win11)
- **explorer**: arquivos ocultos e extensoes sempre visiveis
- **preferencias**: rdp sem aviso, logon verboso, tela de bloqueio off (direto pro login), teclas de aderencia sem popup, mouse sem aceleracao (precisao bruta)
- **sistema**: bloquear coinstaladores de driver via windows update, preferir ipv4, armazenamento reservado off (dism)

os mesmos niveis de antes valem: tweaks "agressivo" nao entram no preset seguro/balanceado; quem mexe em rede/energia avisa no log. o detalhe que importa: tudo com journal de desfazer igual aos outros.

## interface v1.3 (restyle)

- as caixas de marcar viraram interruptores (toggle estilo winutil): pill azul quando ligado
- aba ativa da barra lateral ganhou barra azul + fundo destacado, e cada aba tem icone (fonte Segoe MDL2 do proprio windows)
- botoes com hover/pressed, cantos arredondados; scrollbar fina e escura; listas com selecao azul escura; campo de filtro com borda azul ao focar
- se algum icone da barra lateral aparecer como quadradinho vazio, avise no chat: e um glifo errado, corrige em uma linha

## portatil, planos e modo cli (v1.4)

os 3 recursos vieram dos pontos fortes dos projetos irmaos (winutil e win11debloat):

- **arquivo unico (portatil):** `montar-portatil.ps1` na raiz gera `dist\otimizadorpc-portatil.ps1` + `dist\rodar-portatil.bat`. todos os modulos, os 3 catalogos json e a janela xaml ficam EMBUTIDOS num ps1 so; copia os 2 arquivos pra qualquer pasta (ou pendrive) e roda o bat. e o mesmo truque do compile.ps1 do winutil. o ps1 final e gravado em utf-8 com bom (o xaml embutido tem acentos). regra: nao editar o arquivo gerado, editar os fontes e mandar montar de novo.
- **planos de ajustes (export/import):** na aba ajustes tem "exportar plano" / "importar plano". salva num .json os ids dos ajustes marcados, e importar marca os correspondentes na lista (aplica nada sozinho). serve pra repetir seu setup em outro pc ou guardar uma combinacao que voce gosta. ids que nao existem no catalogo sao avisados no log.
- **modo cli (sem janela):** `.\otimizadorpc.ps1 -Cli seguro` (ou `-Cli balanceado` / `-Cli agressivo`, com `-Simular` junto pra so descrever). aplica o preset headless, com o mesmo fluxo do botao da gui: ponto de restauracao, journal por acao e log em arquivo no programdata. a elevacao repassa os parametros; no modo cli o console fica aberto no fim pra ler o resultado. tambem funciona no portatil: `otimizadorpc-portatil.ps1 -Cli balanceado -Simular`.

## tweaks custom e apps arriscados (v1.5)

dois pontos fortes do win11debloat que entraram na v1.5:

- **seus proprios tweaks sem programar:** jogue arquivos `.reg` na pasta `custom\` (ao lado do app; ela e criada sozinha no primeiro uso). cada arquivo vira um ajuste na aba **ajustes**, categoria **customizadas**, com journal e desfazer como qualquer outro: antes de importar, o app exporta backup .reg de cada chave tocada (`reg export`); desfazer reimporta os backups, e chaves que nao existiam antes sao apagadas. customs nunca entram em preset nenhum (nem no cli `-cli`): sao aplicados so na mao. no portatil a pasta `custom\` fica ao lado do ps1 unico.
- **confirmacao extra pra apps arriscados:** na aba desinstalar, se a selecao tiver cara de driver, runtime (visual c++, directx, .net) ou seguranca (antivirus, firewall), aparece uma segunda janela avisando os nomes e o motivo ("driver de video", "runtime exigido por jogos"...). so desinstala depois desse ok extra; cancelar aqui aborta tudo. e o "confirm-unsafe-app-removal" do win11debloat, versao casa.

## robustez e catalogo (v1.6)

fechando os buracos que sobraram da comparacao com os dois populares:

- **journal atomico:** a sessao registra o estado anterior antes da acao e preserva uma copia anterior (.bak). O desfazer registra o progresso e interrompe se o resultado for incerto. Consulte o log e preserve os arquivos para revisao manual. Nem toda operacao pode ser revertida automaticamente.
- **desfazer de app da store:** ao remover um pacote uwp, o journal guarda a familia do pacote; o desfazer tenta `Add-AppxPackage -RegisterByFamilyName` (volta na hora quando a remocao foi por usuario). quando foi removido com -AllUsers e nao da, o log diz pra buscar na store.
- **4 tweaks novos** (valores conferidos no catalogo oficial do winutil): **desativar copilot e ia** (recall desligado via politica, ia do notepad, servico de ia, pacote do copilot; win11, agressivo), **esconder recomendacoes do menu iniciar** (win11, balanceado; atencao: derruba o spotlight da tela de bloqueio), **esconder a busca da barra** e **esconder o botao de visao de tarefas** (ambos os windows). o catalogo agora tem 47 tweaks.

## desfazer / seguranca

- antes de aplicar ajustes o app **cria ponto de restauracao** (marcado por padrao)
- todas as acoes de registro, servico, recurso e energia **guardam o valor anterior** num journal por sessao em `c:\programdata\otimizadorpc\desfazer`
- a aba **desfazer tudo** lista as sessoes e reverte na ordem inversa
- apps da store removidos no debloat sao reinstalaveis pela microsoft store
- **nada aqui desativa windows defender, firewall e nem atualizacoes de seguranca.**

## por que nao fork direto do winutil

o winutil e MIT licenciado e foi a referencia: arquitetura de catalogos json, modo dark, journal de undo. mas o projeto original tem pipeline de compilacao e estrutura de runspaces complexos; esta versao e enxuta, legivel e adaptada pro joao (pt-br, sem one drive e sem remocao de edge por padrao, avisos de seguranca no catalogo).

## limitacoes conhecidas

- windows 10 e 11 (alguns tweaks marcados "win11" nao aparecem no 10, e vice-versa)
- tweaks visuais podem pedir relogon completo pra aparecer
- winget precisa do "app installer" da store; a aba config tenta instalar/reparar sozinho
