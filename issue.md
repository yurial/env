# issue: запуск assistant_astra по явной просьбе пользователя

## Задача
Разрешить main запускать агента `assistant_astra` (в диалоге — «astra») когда пользователь явно попросит, и запретить вызовы по собственной инициативе агента. Решение пользователя от 2026-09-19, в ответ на репорт: Anet не смогла запустить astra — task-разрешения main допускают только четырёх исполнителей лестницы.

## Стадии
- [ ] 1. `yurial/.config/opencode/agents/main.md`: добавить `assistant_astra: allow` в task-разрешения.
- [ ] 2. `yurial/.config/opencode/rules/delegation.md`: правило «вне лестницы, только по явной просьбе, без субделегирования».
- [ ] 3. `yurial/.config/opencode/rules/main.md`: упоминание исключения в промпте main.
- [ ] 4. `README.md`: задокументировать `assistant_astra`.
- [ ] 5. Коммит, merge в master, синк `./install.sh`, уборка worktree/ветки.
