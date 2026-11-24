# otimizador-de-windows (OtimizadorPC)

## Abrir sem instalar

Abra o **Windows PowerShell 5.1 como administrador** e cole:

```powershell
irm https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/v2.0.0-rc.5/otimizadorpc.ps1 | iex
```

O OtimizadorPC abre diretamente em memoria, sem instalacao. Requer Windows 10/11 e conexao com a internet.

**Versao candidata v2.0.0-rc.5:** testes automatizados aprovados; validacao manual ainda pendente. O comando executa codigo remoto com privilegios administrativos. Revise a origem e use inicialmente o modo de simulacao. [Release e SHA256](https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/tag/v2.0.0-rc.5).

[![ci](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml/badge.svg)](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml)

App de otimizacao do Windows 10 e 11 em PowerShell + janela nativa WPF (estilo Winutil do Chris Titus, MIT), 100% PT-BR, com journal de desfazer por acao e quarantena. Feito pra uso geral/pessoal: visual, privacidade, desempenho, debloat, desinstalacao limpa e manutencao, tudo num so lugar.

## Compilacao local e distribuicao

O montador gera duas variantes: `dist/otimizadorpc-portatil.ps1` (arquivo local) e `dist/otimizadorpc.ps1` (execucao em memoria), com modulos, catalogos e XAML embutidos. O segundo vem acompanhado de um arquivo SHA256.

Para testar a variante em memoria em uma copia local, abra Windows PowerShell 5.1 como administrador:

```powershell
.\montar-portatil.ps1
& ([scriptblock]::Create([IO.File]::ReadAllText((Resolve-Path 'dist\otimizadorpc.ps1')))) -Cli essencial -Simular
```

Sem os parametros CLI, a interface e aberta. Nao e necessario instalar o app. O modo remoto nao carrega tweaks customizados locais; os logs, journals e backups permanecem em ProgramData\otimizadorpc-v2.

O comando de distribuicao final sera `irm https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/latest/download/otimizadorpc.ps1 | iex` **somente depois de uma release estavel contendo esse asset ser publicada**. A publicacao automatica esta configurada e a primeira pre-release foi publicada. O comando direto executa codigo remoto sem conferir o hash automaticamente: revise a origem e a versao antes de executar como administrador.

O launcher `iniciar.ps1` permanece como alternativa baseada na montagem do codigo-fonte: confere os hashes dos blobs Git dos arquivos obtidos por commit antes de montar em pasta temporaria protegida (execucao elevada). Se a API responder 403/429 durante a validacao de um SHA fixado, um checkout Git correspondente pode fornecer a arvore esperada; os arquivos remotos continuam sujeitos aos mesmos hashes. Essa alternativa nao e execucao exclusivamente em memoria.

O botao Consultar e baixar versao oficial mostra releases estavel/candidata e permite baixar explicitamente um script com SHA256 conferido, sem executar automaticamente. O monitor coleta 10 amostras de CPU/RAM/processos e exporta JSON; diagnostico considera memoria e bateria. Procedimento de entrega: [PUBLICACAO.md](PUBLICACAO.md).

## como usar

1. baixe/clone o repo e abra a pasta
2. (opcional, recomendado) rode a bateria de testes: `powershell -ExecutionPolicy Bypass -File .\testar.ps1`
3. de dois cliques em `rodar-como-admin.bat` (o app pede elevacao sozinho)

nao quer janela? modo cli:

```powershell
.\otimizadorpc.ps1 -Cli seguro -Simular   # so descreve o que faria
.\otimizadorpc.ps1 -Cli balanceado        # aplica o preset
```

## o que tem dentro

- **42 tweaks** em catalogo (3 presets: seguro / balanceado / agressivo): telemetria, privacidade (copilot/ia inclusos), desempenho, barra de tarefas, explorer, energia e rede
- **66 apps** pra instalar via winget e **34 pacotes** da store pra debloat
- **desinstalador com limpeza de rastros**: pastas, registro, servicos orfaos, tarefas agendadas, regras locais de permissao do firewall (desativadas, nao removidas), entradas run e path morto; journal antes das alteracoes e backups de arquivos/chaves
- **journal de desfazer**: cada acao grava o valor anterior; a aba desfazer reverte sessao inteira; o journal e gravado atomicamente antes das acoes registradas, com copia anterior e progresso de reversao; falhas podem exigir revisao manual
- **planos**: exporte os ajustes marcados num .json e importe em outro pc
- **arquivo unico**: `.\montar-portatil.ps1` gera `dist\otimizadorpc-portatil.ps1`, o app inteiro num arquivo so pro pendrive
- servicos: snapshot de inicio normal/atrasado e estado, verificacao de conflitos e restauracao. Recursos opcionais registram dependencias alteradas; reversao automatica somente quando o alvo foi a unica alteracao confirmada, sem estado pendente.
- **tweaks custom locais**: arquivos REGEDIT5 em `custom\` somente com valores string/DWORD/exclusao de valor em HKCU Software, fora de chaves reservadas. Arquivos nao suportados sao recusados por inteiro; cada valor aceito tem journal individual. Importacao integral antiga exige recuperacao manual.

## desenvolvimento v2 (pre-release)

- perfis de selecao: essencial, gamer, notebook, privacidade, corporativo e recomendado (detecta ambiente gerenciado ou bateria). Tambem funcionam no CLI: `.\otimizadorpc.ps1 -Cli notebook -Simular`.
- tema claro/escuro em Config, aplicado ao reabrir. Preferencia salva na pasta protegida do app, sem alterar tema do Windows.
- progresso de ajustes, debloat, recursos e quarentena com cancelamento cooperativo entre acoes. Console de manutencao mantem o dispatcher responsivo enquanto aguarda o processo. Nao interrompe comandos administrativos em andamento.
- inventario com oito abas pesquisaveis e ordenaveis: inicializacao, Run do usuario, servicos, tarefas, discos, rede, drivers e processos; exportacao JSON e atalhos nativos. Acoes com journal limitadas a remover Run do usuario, inicio manual de servicos do catalogo e desativar tarefas nao Microsoft em estado Ready. Alteracoes nativas nao entram no journal. Ajustes exibem rotulos de cautela.
- interface ajusta a altura/largura inicial a area util da tela, controles de varias abas quebram linha e inventario usa consulta cancelavel em runspace.
- ajustes iniciam em simulacao; debloat nao seleciona aplicativos automaticamente e atua apenas no usuario atual, com nomes exatos, sem desprovisionar pacotes. Reinstalacao depende de disponibilidade e verificacao.
- desinstalador: correspondencia exata para pastas/chaves, bloqueio de locais protegidos e links, servicos/tarefas/entradas de inicializacao/PATH candidatos apenas com executavel ou caminho ausente. Nao e prova de que o rastro pertence ao app; revise cada caixa. Desinstaladores com comandos ambiguos devem ser executados pelo Windows, nao por fallback cmd.
- recuperacao de valores de registro e PATH: compara o estado atual com o aplicado e o anterior; interrompe se houver mudanca posterior em vez de sobrescrever. Conflitos exigem revisao manual.
- estado administrativo: a nova pasta ProgramData\otimizadorpc-v2 exige ACL restrita a administradores/SYSTEM, sem confiar automaticamente no estado antigo. Os arquivos anteriores em ProgramData\otimizadorpc permanecem intactos, mas precisam de recuperacao manual/revisao; nao copie journals antigos para a pasta nova.
- manutencao: erros nativos e PowerShell propagados ao console; reset de Windows Update preserva caches com nomes unicos e tenta reiniciar somente os servicos que estavam ativos. Limpeza rapida de temporarios limitada a arquivos na raiz, sem seguir links. Reset de rede exige confirmacao.
- integracao real tambem cobre tarefa descartavel e plano local restrito com exclusao de valor padrao.
- integracao real em VM/runner descartavel verifica os valores de registro do preset, valores padrao, arquivo com caracteres especiais, hash e preservacao de conflitos. O teste se recusa a apagar journals existentes.
- uma trava exclusiva em pasta protegida impede GUI/CLI/portatil v2 simultaneos; fechar a janela durante operacao mutavel e bloqueado. Versoes antigas nao respeitam a trava.
- operacoes mutaveis da interface passam por um controlador que evita reentrada; codigos de saida de desinstaladores e comandos sao verificados.
- RC.4 retira cinco ajustes: hibernacao, svchost, F8, armazenamento reservado e desativacao de avisos RDP. Comandos livres nao sao executados pelo motor nem pelo journal. Recuperacao de comandos antigos exige revisao manual. Efeitos visuais, telemetria do PowerShell e tipo padrao de pastas usam valores de registro com snapshot.
- os perfis novos sao conservadores; nao garantem FPS ou autonomia.

- comparativo antes/depois na pagina inicial: salva referencia JSON e compara medias de CPU, RAM, processos e espaco livre. Nao e benchmark; repita sob condicoes semelhantes. O arquivo inclui nome do PC. Consultas de medicao e armazenamento usam runspace separado, com cancelamento.
- analisador de arquivos grandes na aba Manutencao: somente leitura, ate 30 maiores arquivos, limite de tempo e itens, sem seguir links/junctions; resultados parciais identificados.
- backup de drivers de terceiros na aba Manutencao, usando Export-WindowsDriver. Escolha a pasta de destino; nao reinstala drivers automaticamente.
- teste sintetico padronizado de SHA256 e copia de memoria, tres rodadas com exportacao JSON. Nao representa FPS; compare sob condicoes iguais. Backup de drivers usa runspace sem interromper a exportacao.
- diagnostico local na pagina inicial: memoria, espaco em disco, entradas de inicializacao e sinais de reinicio pendente.
- detalhes da sessao e quarentena: inspecione os itens, estados de reversao e existencia dos backups sem excluir nada.
- reversao individual: desfaz apenas a ultima acao pendente da sessao, respeitando a ordem inversa; nao permite escolher uma acao arbitraria.
- recuperacao: a lista informa quantas acoes foram revertidas; itens concluidos nao sao repetidos.
- se uma acao ficar em andamento ou falhar, a reversao para. Preserve o journal e o arquivo .bak, consulte o log e revise o estado real do sistema. Depois de restaurar e verificar manualmente o estado anterior, use Confirmar recuperacao manual para registrar o atestado e continuar. O app nao verifica o atestado nem repete a acao.
- a copia .bak e um estado anterior, nao uma garantia de recuperacao completa.
- a versao de desenvolvimento requer os testes do GitHub Actions no Windows e verificacao manual da interface antes de ser considerada estavel.

## seguranca

- **nunca** desativa windows defender, firewall ou atualizacoes de seguranca
- nao remove edge/onedrive
- cria ponto de restauracao antes de aplicar (opcional, marcado por padrao)
- detecta pc gerenciado por empresa (dominio/av corporativo) e avisa

documentacao completa: [leia-me.md](leia-me.md)

## licenca

MIT - veja [LICENSE](LICENSE)

uso por sua conta e risco: e um app que mexe no sistema, leia o que cada ajuste faz antes de aplicar.
