# Como contribuir

Obrigado por querer ajudar. Este projeto precisa continuar pequeno, legível e seguro para
pessoas que não são técnicas.

## Preparar o ambiente

Você precisa de Git, PowerShell (o 5.1 do Windows ou o 7) e do
[gitleaks](https://github.com/gitleaks/gitleaks).

```powershell
git clone https://github.com/juvxncio/VoltaGoLive.git
cd VoltaGoLive
git config core.hooksPath .githooks
Install-Module Pester -RequiredVersion 5.9.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
```

O comando `git config core.hooksPath .githooks` liga o hook de pre-commit, que roda o
gitleaks e a verificação do repositório antes de cada commit.

## Antes de abrir um pull request

```powershell
./tools/Add-Bom.ps1          # garante o BOM nos arquivos com acentos
./tools/Test-Repository.ps1  # chaves, travessão, caminhos absolutos, BOM
./tools/Invoke-Lint.ps1      # PSScriptAnalyzer sem nenhum aviso
./tools/Invoke-Tests.ps1     # testes Pester 5
```

Os quatro precisam passar. O CI roda os mesmos comandos no Windows.

## Regras do projeto

- **Compatibilidade com o Windows PowerShell 5.1.** Nada de operador ternário, `??`, `&&`
  ou outros recursos que só existem no PowerShell 7.
- **Estrutura.** Funções públicas em `src/VoltaGoLive/Public` (uma por arquivo, com
  comment-based help e verbo aprovado). Funções internas em `src/VoltaGoLive/Private`,
  com o prefixo `Vgl`.
- **Testes.** Toda lógica que não depende de administrador ou de rede precisa de teste
  Pester. O que depende é isolado numa função pequena e simulado (mock) nos testes.
- **Privacidade.** Tudo que vai para log, tela de diagnóstico ou arquivo passa por
  `Protect-VoltaGoLiveText`. Nunca leia variáveis de ambiente em massa.
- **Segredos.** Nenhum arquivo `.conf`, chave ou `.env` no repositório. O nome do campo da
  chave privada do WireGuard não pode aparecer por extenso em nenhum arquivo versionado: no
  código ele é montado em duas partes (veja `Private/Constants.ps1`), e nos textos escreva
  "chave privada".
- **Texto.** Mensagens em português simples, sempre dizendo o que a pessoa deve fazer.
  Não use travessão em nenhum texto do projeto.
- **Sem binários.** Não adicione executáveis nem redistribua arquivos do WireSock.
- **GitHub Actions.** Permissões mínimas, actions fixadas por SHA de commit, nenhum passo
  que imprima o ambiente.

## Commits e versões

- Mensagens no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/):
  `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, `refactor:`.
- Commits pequenos, um assunto por commit.
- Versões seguem o [SemVer](https://semver.org/lang/pt-BR/). Mudanças visíveis para o
  usuário entram no `CHANGELOG.md`, na seção `[Não lançado]`.

## Publicar uma versão (mantenedor)

1. Atualize `ModuleVersion` em `src/VoltaGoLive/VoltaGoLive.psd1`.
2. No `CHANGELOG.md`, mova os itens de `[Não lançado]` para `## [X.Y.Z] - AAAA-MM-DD`.
3. Faça o commit, crie a tag `vX.Y.Z` e envie a tag. O workflow de release gera o zip e o
   arquivo `SHA256SUMS`.
