# F7 - manutencao conservadora

Refs #2. Primeira entrega nesta fase. Os botoes anteriormente chamados Resetar Rede e Resetar Windows Update agora abrem as configuracoes nativas, mediante confirmacao. Nao executam winsock reset, TCP/IP reset, release/renew, parada de servicos nem renomeacao de caches. As funcoes mantem nomes internos para compatibilidade; a interface descreve o novo comportamento. Reparos de rede/atualizacao que exigem intervencao devem ser feitos por procedimento autorizado e especifico.

CHKDSK usa o volume real do sistema e nao solicita reparo; verificacao de volume em uso pode exigir nova analise. DISM/SFC usam executaveis nativos por caminho explicito. O console nao solicita ExecutionPolicy Bypass. Limpeza de temporarios do app restringe-se ao Temp do usuario atual, com previa, arquivos antigos e confirmacao de exclusao definitiva; para limpeza de sistema, usar ferramenta nativa. DNS pede consentimento e nao altera servidores. Sincronizacao de hora usa a fonte ja configurada, verifica codigo de retorno e nao altera politicas.

Testes por mocks nao executam resets nem reparos. Permanecem pendentes a cobertura de politicas por operacao, a revisao de recuperacao de cache de icones, o processamento assincrono de manutencao, a validacao de ferramentas e codigos por build/edicao e testes em Windows cliente. A protecao global nao foi retirada.
