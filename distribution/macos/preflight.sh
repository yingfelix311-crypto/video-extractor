#!/bin/bash
installer_lock(){
 local directory="$1" owner
 mkdir -p "$(dirname "$directory")" || return 1
 if ! mkdir "$directory" 2>/dev/null;then
  owner="$(cat "$directory/pid" 2>/dev/null || true)"
  case "$owner" in ''|*[!0-9]*) echo '后台准备锁尚未就绪；请稍后重新连接。' >&2;return 1;;esac
  if kill -0 "$owner" 2>/dev/null;then echo '另一个后台安装正在进行，请稍后重新连接。' >&2;return 1;fi
  # Only remove a dead installer's small lock; never delete runtime/user state.
  rm "$directory/pid" && rmdir "$directory" && mkdir "$directory" || return 1
 fi
 printf '%s\n' "$$" > "$directory/pid"
}
installer_unlock(){
 local directory="$1"
 if [ "$(cat "$directory/pid" 2>/dev/null || true)" = "$$" ];then
  rm "$directory/pid";rmdir "$directory"
 fi
}
runtime_preflight(){
 local base="$1" install_root="$2" relative target
 while IFS= read -r relative;do
  case "$relative" in bin/*|share/lima/*);;*) echo '运行组件清单路径无效。' >&2;return 1;;esac
  case "$relative" in *../*|/*) echo '运行组件清单路径无效。' >&2;return 1;;esac
  target="$install_root/.local/$relative"
  if [ -e "$target" ] || [ -L "$target" ];then
   if [ ! -f "$target" ] || ! cmp -s "$base/runtime/$relative" "$target";then
    printf '已有运行组件与安装包不同：%s。不会覆盖。\n' "$target" >&2;return 1
   fi
  fi
 done < "$base/runtime-files.txt"
}
profile_preflight(){
 local profile="$1" spec key expected actual
 [ -f "$profile" ] || return 0
 for spec in 'cpu:2' 'memory:2' 'disk:20' 'arch:aarch64' 'vmType:vz' 'mountType:virtiofs' 'runtime:docker';do
  key="${spec%%:*}";expected="${spec#*:}"
  actual="$(awk -F: -v key="$key" '$1==key {gsub(/[ \r\"\047]/,"",$2);print $2;exit}' "$profile")"
  if [ "$actual" != "$expected" ];then
   printf '已有 metube 环境的 %s=%s，与原版要求 %s 不同；不会修改。\n' "$key" "$actual" "$expected" >&2;return 1
  fi
 done
}
init_journal_matches(){
 local file="$1" id="$2"
 [ "${#id}" -eq 64 ] || return 1
 case "$id" in *[!0-9a-f]*) return 1;;esac
 [ -f "$file" ] && [ "$(cat "$file")" = "$id" ]
}
