hangelog

Todas as mudanças relevantes deste projeto ficam registradas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [0.1.0] - Não lançado

### Adicionado

- Ativação do túnel somente para o Discord (Stable, PTB e Canary) usando o WireSock,
  a partir de uma cópia do arquivo `.conf` do usuário.
- Desativação com limpeza dos arquivos temporários.
- Status com tempo ativo e último handshake.
- Diagnóstico com relatório redigido (sem chaves, IPs, nome de usuário, nome do
  computador ou caminhos do perfil).
- O túnel sobe com permissão de administrador (o WireSock exige isso para usar o driver
  de rede) e é derrubado sem pedir a permissão de novo.
- O log do túnel descarta as linhas em que o WireSock lista os programas abertos no computador.
- Instalação do WireSock pelo winget, a partir da fonte oficial.
- Janela com os botões Ativar, Desativar e Diagnóstico e escolha do arquivo `.conf`
  (`VoltaGoLive.bat`), feita em PowerShell, sem programa compilado.
- Lançadores de dois cliques: `Ativar.bat`, `Desativar.bat`, `Status.bat` e `Diagnostico.bat`.
- Testes Pester, PSScriptAnalyzer, gitleaks e verificação do repositório no CI.
