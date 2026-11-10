# Política de segurança

## Versões com suporte

Só a versão mais recente publicada em [Releases](https://github.com/juvxncio/VoltaGoLive/releases)
recebe correções.

## Como reportar uma falha

**Não abra uma issue pública para falhas de segurança.**

1. Vá em <https://github.com/juvxncio/VoltaGoLive/security/advisories/new>
   (aba **Security**, botão **Report a vulnerability**).
2. Descreva o problema, como reproduzir e qual o impacto.
3. **Nunca** inclua o seu arquivo `.conf`, chaves, senhas ou o seu endereço IP. Se precisar
   mostrar um log, use o `Diagnostico.bat`, que já remove esses dados.

Você deve receber uma resposta em até 7 dias. Depois da correção, a falha é descrita no
CHANGELOG, com crédito a quem reportou (se a pessoa quiser).

## O que conta como falha de segurança

- Chave, IP, nome de usuário, nome do computador ou caminho do perfil aparecendo em log,
  relatório de diagnóstico ou na tela.
- Alteração do arquivo `.conf` original do usuário.
- Execução de um arquivo sem assinatura digital válida.
- Tráfego de outros programas entrando no túnel, ou tráfego do Discord saindo fora dele
  enquanto o túnel está ativo.
- Qualquer forma de executar código de terceiros por meio dos scripts.

## O que fica fora do escopo

- Falhas no WireSock, no Discord, no Windows ou na Proton. Reporte aos respectivos responsáveis.
- Bloqueio da conta pelo Discord por uso de VPN.
