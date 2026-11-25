# Validacao consolidada V2 (issue #2 / PR #9)

Base testada: d089b6d7a36875674030974cacb7e20be8f3f61b, CI 45514516072 aprovado. Este lote e um commit unico para um CI integrado final, nao uma release. Nenhuma consulta externa ao repositorio foi usada.

| Fase | Evidencia / alteracao | Gate ainda aberto |
| --- | --- | --- |
| F0 | Base RC.9, inventario de modulos e telas, historico na issue | Medicao de latencia e memoria em cliente real |
| F1 | Inventarios de Inicio, Ajustes, Debloat, Desinstalar, Config, Atualizacoes e Desfazer nao modais; testes WPF | Consolidacao total dos workers, limite global de concorrencia, DPI, cancelamento de providers bloqueados e meta 250 ms em cliente |
| F2 | Barreiras de registro, servico, energia, recursos, AppX, instalador, firewall e journal | Politica efetiva, identidade e privilegios por todas as operacoes; modo global mantido ate paridade |
| F3 | Identidade, escrita atomica com ACL, intencao/efeito confirmado para acoes instrumentadas, hash de backups de arquivo e registro | Estados de todos os caminhos legados, hash integral de pastas, ACL de backups, reconciliacao de queda, exportacao sanitizada |
| F4 | Triagem e atalhos nativos de inicializacao, armazenamento, Windows Update; amostras sob demanda | Validacao de indicadores e experiencia em hardware modesto |
| F5 | Matriz estatica de 42 tweaks, presets conservadores e recomendacao comum GUI/CLI | Referencias oficiais por mecanismo e medicao comparativa em cargas reais; sem alegacao de ganho |
| F6 | Classificacao, AppX por usuario, MSI, assinatura/hash, quarentena, fonte/ID/versao WinGet | Dependencias completas, inventario AppX/MSI combinado e origem efetiva de instaladores, resultados por app estruturados |
| F7 | Diagnosticos nativos, sem reset generico, CHKDSK sem reparo, Temp do usuario, fontes de hora preservadas | Validacao de codigos/efeitos por build e manutencao em cliente |
| F8 | CI unico ao fim do lote com unidade, WPF, portatil, simulacao e integracao real descartavel | Aceite manual e promocao de release pelo mantenedor |

## Roteiro de aceite manual (nao executado)

- Windows 10/11 cliente em VM descartavel, Home/Pro quando disponivel; snapshot antes.
- Usuario padrao: abrir, alternar todas as abas durante consulta, verificar cancelamento, sem gravar estado.
- Admin autorizado: repetir com antivirus comum e VPN instalada; nao remover protecao, nao modificar VPN, verificar politica de rede e Windows Update.
- Executar somente preferencias reversiveis selecionadas; comparar valores/tipos anteriores e posteriores, reverter e testar conflito externo.
- Instalar/desinstalar aplicativo de teste em VM; verificar catalogo, fonte, dependencias e quarentena; simular hash divergente e confirmar preservacao de dados.
- Testar build/edicao, falta de rede, recurso pendente, DPI 100/125/150%, abertura e memoria; registrar tempos e falhas.
- Comparar amostras antes/depois com mesma carga, sem prometer FPS ou causalidade por amostra isolada.
- Confirmar artefato portatil exato, SHA256 e origem; nao publicar estavel sem aprovacao explicita e resultados acima.

Limites: estado de intencao sem confirmacao nao equivale a sucesso; journals antigos sem hash para restauracao de arquivo/registro exigem revisao manual; pastas tem somente verificacao de localizacao, tipo e movimentacao, nao verificacao recursiva de conteudo. Hash detecta mudanca de conteudo, nao autentica um journal contra administrador. As verificacoes de politica sao conservadoras e incompletas; nao removem o bloqueio global. A integracao CI usa runner Windows Server e stub de ponto de restauracao. Nenhuma fase foi certificada integralmente.

## Complemento de autorizacao e diagnostico

CI do lote b4123c6 aprovado (45515404147). A nova rodada distingue registro de conta profissional de ingresso organizacional do dispositivo; dominio, Entra join, MDM, agentes, politicas e consultas inconclusivas continuam protegidos. A previa essencial e a analise de armazenamento somente leitura funcionam no modo protegido. Preferencias do Explorer Advanced verificam indicadores GPO locais antes de aplicar e reverter; uma segunda leitura do valor antes da escrita recusa mudanca concorrente detectada. Nao cobre todas as politicas efetivas ou elimina a janela de corrida. A GUI nao encerra Explorer depois dos ajustes. O gate de paridade F2 continua aberto.
