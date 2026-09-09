#!/usr/bin/env bash
# Печатает таблицу 16x16 всех сочетаний ANSI 0-15: фон (строки) x текст (столбцы).
# В каждой ячейке — "bg/fg" (номер фона / номер текста).
printf '     '
for fg in $(seq 0 15); do printf '%-7s' "fg=$fg"; done
printf '\n'
for bg in $(seq 0 15); do
  printf 'bg=%-2d' "$bg"
  for fg in $(seq 0 15); do
    printf '\e[48;5;%dm\e[38;5;%dm %-5s \e[0m' "$bg" "$fg" "$bg/$fg"
  done
  printf '\n'
done
