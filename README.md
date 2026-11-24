# otimizador-de-windows (OtimizadorPC)

[![ci](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml/badge.svg)](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml)

App de otimizacao do Windows 10 e 11 em PowerShell + janela nativa WPF (estilo Winutil do Chris Titus, MIT), 100% PT-BR, com journal de desfazer por acao e quarantena. Feito pra uso geral/pessoal: visual, privacidade, desempenho, debloat, desinstalacao limpa e manutencao, tudo num so lugar.

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

- **47 tweaks** em catalogo (3 presets: seguro / balanceado / agressivo): telemetria, privacidade (copilot/ia inclusos), desempenho, barra de tarefas, explorer, energia e rede
- **66 apps** pra instalar via winget e **34 pacotes** da store pra debloat
- **desinstalador com limpeza de rastros**: pastas, registro, servicos orfaos, tarefas agendadas, regras locais de permissao do firewall (desativadas, nao removidas), entradas run e path morto; journal antes das alteracoes e backups de arquivos/chaves
- **journal de desfazer**: cada acao grava o valor anterior; a aba desfazer reverte sessao inteira; o journal e gravado atomicamente antes das acoes registradas, com copia anterior e progresso de reversao; falhas podem exigir revisao manual
- **planos**: exporte os ajustes marcados num .json e importe em outro pc
- **arquivo unico**: `.\montar-portatil.ps1` gera `dist\otimizadorpc-portatil.ps1`, o app inteiro num arquivo so pro pendrive
- **tweaks custom**: jogue seus .reg em `custom\` e eles viram ajustes com journal e desfazer

## desenvolvimento v2 (pre-release)

- perfis de selecao: essencial, gamer, notebook, privacidade, corporativo e recomendado (detecta ambiente gerenciado ou bateria). Tambem funcionam no CLI: `.\otimizadorpc.ps1 -Cli notebook -Simular`.
- os perfis novos sao conservadores; nao garantem FPS ou autonomia. O ajuste de avisos RDP fica exclusivamente manual por reduzir protecoes contra conexoes nao confiaveis.

- analisador de arquivos grandes na aba Manutencao: somente leitura, ate 30 maiores arquivos, limite de tempo e itens, sem seguir links/junctions; resultados parciais identificados.
- backup de drivers de terceiros na aba Manutencao, usando Export-WindowsDriver. Escolha a pasta de destino; nao reinstala drivers automaticamente.
- inventario local de inicializacao, servicos, tarefas, discos e adaptadores de rede, exportacao JSON sob demanda e atalhos para ferramentas nativas. O inventario nao altera o Windows; revise o relatorio antes de compartilhar.
- diagnostico local na pagina inicial: memoria, espaco em disco, entradas de inicializacao e sinais de reinicio pendente.
- recuperacao: a lista informa quantas acoes foram revertidas; itens concluidos nao sao repetidos.
- se uma acao ficar em andamento ou falhar, a reversao para. Preserve o journal e o arquivo .bak, consulte o log e revise o estado real do sistema. Nao repita a acao nem edite o journal sem verificar os efeitos.
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
