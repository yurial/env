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
  - systemd: `.config/systemd/user/opencode-server.service` — user-сервис `opencode serve` (порт 4096, только localhost; `systemctl --user status|restart opencode-server`; автостарт при загрузке — при включённом `loginctl enable-linger`)
  - `bin/ansi-table.sh` — печатает матрицу 16x16 сочетаний ANSI фон/текст (подбор пар для темы)
- `yurial/.config/opencode/themes/yurial.json` — кастомная тема TUI opencode (16 ANSI-цветов, уникальные контрастные пары фон/текст; выбор в `/themes`). Тема рассчитана на 256-цветной режим (`TERM=screen-256color`); alias `opencode` в `.bashrc` обходит баг opentui 0.4.5 (remote-детект по `SSH_*` отключает 256-цветность). Alias `opencode` подключает TUI к локальному серверу (`opencode attach http://127.0.0.1:4096`).
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

- `opencode.json` — единственный провайдер `myzai` (модели `heavy`=glm-5.3, `flash`=glm-5.3-flash; у `heavy` варианты reasoning `high`/`max`, у `flash` — только `high`). Все прочие встроенные провайдеры (openai, gemini, openrouter, opencode, anthropic и т.д.) отключены через `disabled_providers`. `default_agent: main`. Bash-команды разрешены все, кроме `sleep*`. Телеметрия/шаринг глобально отключены (`"share": "disabled"`).
- `agents/` — определения агентов (тело промпта каждого — в `rules/`):
  - `main` — primary-агент, диспетчер на flash-модели с reasoning `high`: ведёт диалог с пользователем, формирует самодостаточные задания и запускает субагентов по `rules/delegation.md`; сам — только работа с контекстом диалога, тривиальная одношаговая механика и ведение issue.md/TODO.md.
  - `assistant_low` / `assistant_high` — исполнители на flash-модели (glm-5.3-flash, reasoning-вариант `high`, суффикс исторический): low — последовательности с простыми ветвлениями; high — стандартные подзадачи.
  - `assistant_max` — исполнитель на flash-модели (glm-5.3-flash, reasoning-вариант `high`, суффикс исторический): сложные и safety-critical задачи — design, concurrency/correctness-анализ, глубокий дебаг, security review, рефакторинг кода, быстрая поверхностная проверка диффов; эскалация за потолок flash — `assistant_heavy`.
  - `assistant_low` — одиночные команды, последовательности с простыми ветвлениями, механика правок/поиска, исследования / Q&A / независимая проверка утверждений (без правок). Исполнители субделегируют строго вниз по лестнице (assistant_heavy → max/high/low; assistant_max → high/low; assistant_high → low; assistant_low — никого: `task: deny`; вверх и на свой уровень нельзя) — в `task`-permissions каждого агента разрешены только нижестоящие.
  - `assistant_heavy` — исполнитель на модели `myzai/heavy` (glm-5.3, reasoning max): правки артефактов правил (spec/skills/rules, TLA-спеки и их индексы, DEVIATIONS.md), ревью (включая TLA-спеки) и верификация чужих изменений, а также эскалация, когда flash-исполнители не справляются — очень сложный дебаг, поиск неуловимых ошибок, супер-сложные design-задачи.
  - `assistant_astra` — исполнитель на `keydealer/gpt-6-astra`: вне лестницы делегирования; main запускает его только по явной просьбе пользователя («запусти astra …» или `@assistant_astra`), по инициативе агентов не вызывается, сам никого не делегирует (`task: deny`)
  - `build`, `explorer`, `general`, `plan`, `scout` — отключены (`disable: true`).
- `rules/` — промпты и общие правила: `main.md`, `assistant.md` (промпты агентов), `common.md` (дисциплина: worktree на задачу, запрет `sleep`, гигиена коммитов), `delegation.md` (протокол делегирования), `readme.md`, `call.md`, `todowrite.md`.
- `skills/` — специализированные навыки: `coding` (правила написания и ревью кода на любом языке; собственная спека навыка — `SPEC.md`), `spec` (спеки, spec-first flow; механические проверки спек — скрипт `speclint` в каталоге навыка; собственная спека навыка — `SPEC.md`), `tla-plus` (TLA+-спеки и TLC-модели), `tlaps` (иерархические доказательства через tlapm), `tlc-run` (запуск TLC и разбор вывода).

### Как ходит запрос

```
user → main (primary, диспетчер, flash + reasoning high)
          ├─ диалог, уточнения, формирование заданий → сам
           └─ содержательная работа (delegation.md) ──→ assistant_low / assistant_high / assistant_max / assistant_heavy
                                                        (правки spec/skills/rules, TLA-спек и DEVIATIONS.md, а также эскалация за потолок flash — assistant_heavy)
                                                         └─ субделегирование строго вниз по лестнице (правила те же)
                                                            ├─→ assistant_heavy → assistant_low (типовой цикл «правка TLA-спеки → прогон TLC», ведёт heavy)
                                                             └─→ assistant_high → assistant_low, assistant_max → assistant_high, ...
```

`main` ведёт диалог и диспетчеризирует: содержательную работу выполняют субагенты согласно `rules/delegation.md` — лестница исполнителей от assistant_low до assistant_heavy, маппинг задач по стоимости с примерами, типовые делегируемые группы, не более 4 агентов параллельно, возобновление незавершённой сессии по `continue`; исполнители субделегируют строго вниз по лестнице, возможны цепочки вида main → assistant_heavy → assistant_low. `assistant_astra` (keydealer/gpt-6-astra) в лестницу не входит: main запускает его только по явной просьбе пользователя в диалоге.
