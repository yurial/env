# env

Персональный репозиторий dotfiles и конфигов opencode.

## Структура

- `install.sh` — установщик. Копирует `$USER/` в `$HOME/` через `rsync`. Запускается без аргументов для текущего пользователя; `./install.sh <username>` ставит конфиги указанному пользователю (через `su -c ... -l`); `./install.sh all` обходит все поддиректории первого уровня кроме скрытых. При запуске создаёт (если ещё не существует) симлинк `.git/hooks/post-checkout`.
- `post-checkout` — git-хук, на который указывает симлинк в `.git/hooks/`. После каждого `git checkout` запускает `install.sh`, чтобы `$HOME/` всегда соответствовал HEAD.
- `yurial/` — dotfiles пользователя `yurial`:
  - shell: `.bashrc`, `.inputrc`, `.screenrc`, `.vimrc`
  - vcs: `.gitconfig`, `.hgrc`
  - ssh: `.ssh/config`, `.ssh/rc`, `.ssh/authorized_keys`
  - opencode: `.config/opencode/` (см. ниже)
- `iu.diachenko` — симлинк на `yurial/`: `./install.sh iu.diachenko` ставит те же конфиги одноимённому пользователю. В обход `install.sh all` не попадает (`find -type d` не следует по симлинкам).

## Установка

```sh
./install.sh           # поставить конфиги текущему $USER
./install.sh yurial    # поставить конфиги пользователю yurial
./install.sh all       # прокатить все поддиректории
```

## OpenCode

Конфигурация живёт в `yurial/.config/opencode/`:

- `opencode.json` — единственный провайдер `vk-zai-personal` (модели `heavy`=glm-5.3, `flash`=glm-5.3-flash, `cheap`=glm-4.6v; у `heavy` и `flash` варианты reasoning `low`/`high`/`max`). Все прочие встроенные провайдеры (openai, gemini, openrouter, opencode, anthropic и т.д.) отключены через `disabled_providers`. `default_agent: main`. Bash-команды разрешены все, кроме `sleep*`. Телеметрия/шаринг глобально отключены (`"share": "disabled"`).
- `agents/` — определения агентов (тело промпта каждого — в `rules/`):
  - `main` — primary-агент, диспетчер на flash-модели с reasoning `low`: ведёт диалог с пользователем, формирует самодостаточные задания и запускает субагентов по `rules/delegation.md`; сам — только работа с контекстом диалога, тривиальная одношаговая механика и ведение issue.md/TODO.md.
  - `assistant_low` / `assistant_high` / `assistant_max` — исполнители на flash-модели (glm-5.3-flash) с reasoning-вариантами low/high/max соответственно (суффикс = вариант reasoning): low — последовательности с простыми ветвлениями; high — стандартные подзадачи; max — сложные и safety-critical задачи, ревью и правки spec/skills/rules и TLA-спек.
  - `assistant_cheap` — одиночные команды и механика на `vk-zai-personal/cheap` (glm-4.6v). «Стоимость» — это маппинг правил делегирования, а не разные модели. Все исполнители сами субагентов не запускают (`task: deny`).
  - `assistant_heavy` — эскалационный исполнитель на модели `vk-zai-personal/heavy` (glm-5.3, reasoning max): подключается, когда flash-исполнители не справляются — очень сложный дебаг, поиск неуловимых ошибок, супер-сложные design-задачи.
  - `build`, `explorer`, `general`, `plan`, `scout` — отключены (`disable: true`).
- `rules/` — промпты и общие правила: `main.md`, `assistant.md` (промпты агентов), `common.md` (дисциплина: worktree на задачу, запрет `sleep`, гигиена коммитов), `delegation.md` (протокол делегирования), `readme.md`, `call.md`, `todowrite.md`.
- `skills/` — специализированные навыки: `spec` (спеки, spec-first flow), `tla-plus` (TLA+-спеки и TLC-модели), `tlaps` (иерархические доказательства через tlapm), `tlc-run` (запуск TLC и разбор вывода).

### Как ходит запрос

```
user → main (primary, диспетчер, flash + reasoning low)
          ├─ диалог, уточнения, формирование заданий → сам
          └─ содержательная работа (delegation.md) ──→ assistant_cheap / assistant_low / assistant_high / assistant_max / assistant_heavy
                                                       (правки spec/skills/rules и TLA-спек — assistant_max; эскалация за потолок flash — assistant_heavy)
```

`main` ведёт диалог и диспетчеризирует: содержательную работу выполняют субагенты согласно `rules/delegation.md` — лестница исполнителей от assistant_cheap до assistant_heavy, маппинг задач по стоимости с примерами, типовые делегируемые группы, не более 4 агентов параллельно, возобновление незавершённой сессии по `continue`.
