# SPEC_BRANCH.md — Suporte a Seleção de Branch no Pipeline

## Contexto

Atualmente, a branch do repositório da aplicação é definida de forma implícita:

- Para **PTF**: branch padrão `mvp`
- Para **PLN**: branch padrão `v8`

O único mecanismo de customização existente é o parâmetro `APP_REPO_BRANCH_OVERRIDE`, que é descrito como "override técnico opcional" — ou seja, não é voltado para uso cotidiano pelo operador.

O parâmetro `VERSAO_APP` (ou `VERSAO_BANCO` como fallback) é passado para `build_app_artifact.sh` como `--app-version`, e o script resolve a ref como **tag → branch → commit**, sem relação com a branch de clonagem inicial (`--repo-branch`).

---

## Problema

O operador não tem um campo claro e amigável para informar a branch que deseja usar para o deploy da aplicação. O `APP_REPO_BRANCH_OVERRIDE` existe mas é escondido como campo técnico, sem valor padrão visível baseado no tipo de ambiente.

---

## Objetivo

Expor um parâmetro de branch de fácil uso, tornando-o **dependente do `TIPO_AMBIENTE`** com valores padrão pré-preenchidos e permitindo alteração quando necessário.

---

## Solução Proposta

### 1. Novo parâmetro: `APP_REPO_BRANCH`

Substituir o `APP_REPO_BRANCH_OVERRIDE` por um `StringParameterDefinition` visível e amigável, onde o operador digita manualmente o nome da branch desejada. O valor padrão é pré-preenchido conforme o tipo de ambiente.

**Definição do parâmetro:**

```groovy
[$class: 'StringParameterDefinition',
    name: 'APP_REPO_BRANCH',
    defaultValue: '',
    description: 'Branch do repositório da aplicação (ex: PTF → mvp | PLN → v8). Se vazio, usa o padrão do tipo de ambiente.',
    trim: true
],
```

> O valor padrão por tipo de ambiente (`mvp` para PTF, `v8` para PLN) é aplicado na lógica de resolução do Jenkinsfile, não no campo em si.

---

### 2. Lógica de resolução no stage de Validação

Remover o campo `APP_REPO_BRANCH_OVERRIDE` como campo de formulário e usar diretamente `APP_REPO_BRANCH`. O fallback para o padrão do ambiente continua garantido:

```groovy
// Antes
env.APP_REPO_BRANCH = (params.APP_REPO_BRANCH_OVERRIDE?.trim()) 
    ? params.APP_REPO_BRANCH_OVERRIDE.trim() 
    : selectedRepo.branch

// Depois
env.APP_REPO_BRANCH = params.APP_REPO_BRANCH?.trim() ?: selectedRepo.branch
```

> Se o operador deixar `APP_REPO_BRANCH` em branco, o pipeline usa o padrão definido em `appRepoDefaults` (`mvp` para PTF, `v8` para PLN).

---

### 3. Remover `APP_REPO_BRANCH_OVERRIDE`

Com a adição do `APP_REPO_BRANCH` como campo de texto editável pelo operador, o `APP_REPO_BRANCH_OVERRIDE` se torna redundante e deve ser removido do formulário de parâmetros.

---

## Fluxo Atualizado

```
TIPO_AMBIENTE (PTF|PLN)
    └─> APP_REPO_BRANCH (String, digitado pelo operador; se vazio, usa padrão do tipo)
            └─> env.APP_REPO_BRANCH
                    └─> build_app_artifact.sh --repo-branch
```

O parâmetro `APP_VERSION_RESOLVED` (resolvido a partir de `VERSAO_APP` ou `VERSAO_BANCO`) continua sendo passado como `--app-version`, mantendo a lógica de resolução **tag → branch → commit** dentro do script.

---

## Impacto

| Artefato | Alteração |
|---|---|
| `Jenkinsfile` | Novo `StringParameterDefinition APP_REPO_BRANCH`; remoção de `APP_REPO_BRANCH_OVERRIDE`; atualização da lógica de resolução de `env.APP_REPO_BRANCH` |
| `scripts/build_app_artifact.sh` | Nenhuma alteração necessária |
| `README.md` | Documentar o novo parâmetro |

---

## Parâmetros Finais do Pipeline (seção deploy)

| Parâmetro | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `APP_REPO_BRANCH` | String | Não | Branch do repositório da aplicação digitada pelo operador. Se vazio, usa o padrão do `TIPO_AMBIENTE` (`mvp` para PTF, `v8` para PLN) |
| `VERSAO_APP` | String | Não | Tag/branch/commit a fazer checkout. Se vazio, usa `VERSAO_BANCO` |
