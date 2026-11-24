# F3 - identidade de journal e verificacao de reversao

Refs #2. Primeira entrega: novos journals usam esquema 2, vinculados ao SID efetivo do processo, MachineGuid local e visao do registro (32/64 bits). A reversao e a confirmacao manual recusam contexto divergente ou esquema desconhecido antes de gravar. O identificador de maquina fica no journal local protegido; nao incluir esse campo em exportacoes de diagnostico nem publicar journals de maquinas reais.

O MachineGuid nao e prova criptografica de identidade (pode ser clonado); e uma barreira contra erros de contexto. O esquema legado permanece legivel e reversivel pelas regras anteriores, sem garantia de identidade. Nao altera o formato dos itens antigos. Uma nova sessao nao inicia se o contexto nao puder ser identificado.

A reversao de registro agora verifica o tipo/conteudo restaurado ou ausencia do valor, antes de reportar sucesso. Permanecem os conflitos detectados no snapshot e o marcador de reversao incerta.

Pendentes: identidade por alvo em journals antigos, validacao de caminho/ACL do arquivo e backups individuais, estado de aplicacao por acao, recuperacao automatizada de falhas parciais, verificacao de outros tipos de reversao, compatibilidade com exportacoes e aceite em Windows cliente. Nao e certificacao de rollback integral.
