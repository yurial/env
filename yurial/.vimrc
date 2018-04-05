syn on
set expandtab
set tabstop=4
set shiftwidth=4
set smarttab
set showmatch
set hlsearch
set incsearch
set ffs=unix
set fencs=utf-8
set number
set nocompatible
set termencoding=utf-8
set backspace=indent,eol,start
set cindent
set cink=
set cinw=
set cinoptions=N-2s,fs,{s,^-1s,:0,g0,h0,t0,i2s,c0,/0,(s
set listchars=tab:>-,trail:~,extends:>,precedes:<
set list

highlight Comment ctermfg=Red
autocmd FileType cpp map <F5> :! g++ %<cr>
autocmd FileType * map <F6> :! make<Enter>
autocmd FileType * map <F7> :! make clean && make<Enter>
autocmd FileType * map <F9> :! make run<Enter>

nmap + :cnext<CR>
nmap _ :cprevious<CR>

nmap t :tabedit %<CR>
nmap = :tabnext<CR>
nmap - :tabprevious<CR>

imap <F11> <Esc>:set<Space>nu!<CR>
nmap <F11> :set<Space>nu!<CR>
au BufNewFile,BufRead *.inc set filetype=cpp
au BufRead,BufNewFile ~/sources/* set ts=4 sw=4 expandtab cinoptions=N-2s,fs,{s,^-1s,:0,g0,h0,t0,i2s,c0,/0,(s
au BufRead,BufNewFile ~/clickhouse/* set ts=4 sw=4 expandtab tags=tags,../tags cino=f1s{1s(4

" Vim jump to the last position when reopening a file
if has("autocmd")
  au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif
