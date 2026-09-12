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
  - `bin/ansi-table.sh` — печатает матрицу 16x16 сочетаний ANSI фон/текст (подбор пар для темы)
- `yurial/.config/opencode/themes/yurial.json` — кастомная тема TUI opencode (16 ANSI-цветов, уникальные контрастные пары фон/текст; выбор в `/themes`). Тема рассчитана на 256-цветной режим (`TERM=screen-256color`); alias `opencode` в `.bashrc` обходит баг opentui 0.4.5 (remote-детект по `SSH_*` отключает 256-цветность).
- `iu.diachenko` — симлинк на `yurial/`: `./install.sh iu.diachenko` ставит те же конфиги одноимённому пользователю. В обход `install.sh all` не попадает (`find -type d` не следует по симлинкам).

## Установка

```sh
./install.sh           # поставить конфиги текущему $USER
./install.sh yurial    # поставить конфиги пользователю yurial
./install.sh all       # прокатить все поддиректории
```

### Синхронизация установленной копии

Репозиторий — источник истины для установленных конфигов (`yurial/.config/opencode/` и другие dotfiles); установленная копия под `$HOME/` — производная от него. После изменения любого установленного файла в репозитории синхронизируй `$HOME/` запуском `./install.sh` от корня репозитория — это единственный разрешённый способ обновления файлов под `$HOME/`. Ручные `cp`/`rsync`/прямые правки установленных файлов запрещены — обход `install.sh` является нарушением, даже если кажется быстрее. Хук `post-checkout` уже запускает `install.sh` при checkout; синхронизацию после правок без checkout нужно делать явно.

## OpenCode

Конфигурация живёт в `yurial/.config/opencode/`:

- `opencode.json` — единственный провайдер `vk-zai-personal` (модели `heavy`=glm-5.3, `flash`=glm-5.3-flash, `cheap`=glm-4.6v; у `heavy` и `flash` варианты reasoning `low`/`high`/`max`; у `cheap` варианты `stupid` (thinking выключен) и `smart` (thinking включен) через `"thinking":{"type":"disabled"/"enabled"}` — glm-5.3 выключение thinking не поддерживает, glm-4.6v поддерживает). Все прочие встроенные провайдеры (openai, gemini, openrouter, opencode, anthropic и т.д.) отключены через `disabled_providers`. `default_agent: main`. Bash-команды разрешены все, кроме `sleep*`. Телеметрия/шаринг глобально отключены (`"share": "disabled"`).
- `agents/` — определения агентов (тело промпта каждого — в `rules/`):
  - `main` — primary-агент, диспетчер на flash-модели с reasoning `low`: ведёт диалог с пользователем, формирует самодостаточные задания и запускает субагентов по `rules/delegation.md`; сам — только работа с контекстом диалога, тривиальная одношаговая механика и ведение issue.md/TODO.md.
  - `assistant_low` / `assistant_high` / `assistant_max` — исполнители на flash-модели (glm-5.3-flash) с reasoning-вариантами low/high/max соответственно (суффикс = вариант reasoning): low — последовательности с простыми ветвлениями; high — стандартные подзадачи; max — сложные и safety-critical задачи.
  - `assistant_stupid` — исполнитель на `vk-zai-personal/cheap` (glm-4.6v) с вариантом `stupid` (thinking выключен): самый дешёвый исполнитель, scope тот же, что у `assistant_cheap`, — для тривиально предсказуемой работы.
  - `assistant_cheap` — одиночные команды и механика с лёгким суждением, а также исследования / Q&A / независимая проверка утверждений (без правок) на `vk-zai-personal/cheap` (glm-4.6v, вариант `smart` — thinking включен). «Стоимость» — это маппинг правил делегирования, а не разные модели. Исполнители субделегируют строго вниз по лестнице (assistant_heavy → max/high/low/cheap/stupid; assistant_max → high/low/cheap/stupid; assistant_high → low/cheap/stupid; assistant_low → cheap/stupid; assistant_cheap → stupid; assistant_stupid — никого: `task: deny`; вверх и на свой уровень нельзя) — в `task`-permissions каждого агента разрешены только нижестоящие.
  - `assistant_heavy` — исполнитель на модели `vk-zai-personal/heavy` (glm-5.3, reasoning max): правки артефактов правил (spec/skills/rules, TLA-спеки и их индексы, DEVIATIONS.md), а также эскалация, когда flash-исполнители не справляются — очень сложный дебаг, поиск неуловимых ошибок, супер-сложные design-задачи.
  - `build`, `explorer`, `general`, `plan`, `scout` — отключены (`disable: true`).
- `rules/` — промпты и общие правила: `main.md`, `assistant.md` (промпты агентов), `common.md` (дисциплина: worktree на задачу, запрет `sleep`, гигиена коммитов), `delegation.md` (протокол делегирования), `readme.md`, `call.md`, `todowrite.md`.
- `skills/` — специализированные навыки: `spec` (спеки, spec-first flow; механические проверки спек — скрипт `speclint` в каталоге навыка), `tla-plus` (TLA+-спеки и TLC-модели), `tlaps` (иерархические доказательства через tlapm), `tlc-run` (запуск TLC и разбор вывода).

### Как ходит запрос

```
user → main (primary, диспетчер, flash + reasoning low)
          ├─ диалог, уточнения, формирование заданий → сам
           └─ содержательная работа (delegation.md) ──→ assistant_stupid / assistant_cheap / assistant_low / assistant_high / assistant_max / assistant_heavy
                                                        (правки spec/skills/rules, TLA-спек и DEVIATIONS.md, а также эскалация за потолок flash — assistant_heavy)
                                                         └─ субделегирование строго вниз по лестнице (правила те же)
                                                            ├─→ assistant_heavy → assistant_stupid (типовой цикл «правка TLA-спеки → прогон TLC», ведёт heavy)
                                                            └─→ assistant_low → assistant_cheap, assistant_max → assistant_high, ...
```

`main` ведёт диалог и диспетчеризирует: содержательную работу выполняют субагенты согласно `rules/delegation.md` — лестница исполнителей от assistant_stupid до assistant_heavy, маппинг задач по стоимости с примерами, типовые делегируемые группы, не более 4 агентов параллельно, возобновление незавершённой сессии по `continue`; исполнители субделегируют строго вниз по лестнице, возможны цепочки вида main → assistant_heavy → assistant_stupid.
