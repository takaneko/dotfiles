# 実装計画: .claude の共有可能な資産を .agents へ移しシンボリックリンクで見せる

作成日: 2026-08-28

## 概要

`.claude/` 配下の資産のうち**エージェント非依存で共有可能なもの**の実体を `.agents/` に移し、`.claude/` からは相対シンボリックリンクで見せる構成に変える。Claude Code 以外のエージェントからも同じ実体を参照できるようにしつつ、`.claude/` 決め打ちの既存ツール（グローバル gitignore、スキル内の直書きパス）を壊さない。

あわせて `CLAUDE.md` を `AGENTS.md` の実体に置き換え、`CLAUDE.md` をそこへのシンボリックリンクにする。分類ルールと検証結果は、残り 2 リポジトリにそのまま適用できる形で `AGENTS.md` に書き残す。

**本リポジトリ固有の事情**（他リポジトリと違う点）:

- **`rules/` が存在しない。** 要件の第一候補だが `.claude/rules/` は無い。移せるのは `skills/` のみで、`plans/` は新規作成になる
- **`.gitignore_global` の実体がこのリポジトリにある。** 他リポジトリでは「触れないマシン固有ファイル」だった `~/.gitignore_global` が、ここでは `~/dotfiles/.gitignore_global` へのシンボリックリンク。`.claude/` 決め打ちの除外行（52・58 行目）を**このリポジトリの作業として編集できてしまう**ので、誤って動かさないよう明記する
- **スキルが自分の場所を直書きしている。** `.claude/skills/review-brew-outdated/SKILL.md:101` が `$SKILL_DIR` を `$HOME/dotfiles/.claude/skills/review-brew-outdated` と直書きしている。リンク越しでも解決するが、実体の場所とずれるので更新する
- **ビルド・テスト・lint が無い。** CLAUDE.md 記載のとおり検証は手動。DoD はすべて git / シェルでの確認コマンドになる

先行実装は同一マシン上の別リポジトリ 2 件（本文では**先行実装A / 先行実装B**と呼ぶ）。A は `rules/` `skills/` `plans/` の 3 つとも移行済みで `CLAUDE.md -> AGENTS.md` も済み、B は `rules/` `plans/` が移行済み。分類ルール表・落とし穴の記述は A の `AGENTS.md` の該当節を土台にする。

## 設計判断

- **ディレクトリ単位のリンクにする**（ファイル単位ではなく）。先行実装 2 件が同じ構成で動いており、`skills/` にスキルを足してもリンクを増やさずに済む。タスク 1 の検証でリンク越しに読めないと判明した場合のみファイル単位に切り替える
- **`skills/` を移す**（ユーザー確認済み）。`.claude/skills/` の **6 ファイル**はすべて tracked（`git ls-files .claude/skills | wc -l` → 6）。うち 4 つ（`adapters/*.sh`）は mode `100755` なので、実行ビットを保つため `git mv` を使う。**`git ls-files -s .claude` は 7 行返るが、7 行目は `.claude/.gitignore` で、これは `.claude/` に残す分類**（下の「移さないもの」参照）。この 1 行を数え違えて一緒に移すと `settings.local.json` の除外が外れる
- **`plans/` も移す**（ユーザー確認済み）。現状ディレクトリ自体が無いが、`blueprint` / `blueprint-do` が `.agents/plans/` → `.claude/plans/` の順で探すため、作っておくと今後の計画が自然に `.agents` 側に入る。空ディレクトリは git が追えないので `.gitkeep` を置く
- **本計画ファイル自身を移す必要がある。** この計画は `.agents/plans/` がまだ無い時点で書かれたため `.claude/plans/plan-agents-dir-symlink.md` にある。タスク 3 で `.claude/plans` をリンクに変える前に、計画ファイルを `.agents/plans/` へ移しておかないと**リンクを張る先のディレクトリが空でなく `ln -s` が失敗する**。順序をタスク 3 の中で固定する
- **`CLAUDE.md` → `AGENTS.md` 化を含める**（ユーザー確認済み）。要件そのものには無いが、先行実装と揃えることで横展開時に構成が一貫する
- **移さないもの**: `settings.local.json`（Claude Code 固有かつ gitignore がパス決め打ち）、`.claude/.gitignore`（`settings.local.json` の除外をそのディレクトリに対して効かせている）、`skill-retros/`（スキルの出力。root `.gitignore:2` が `/.claude/skill-retros/` と**アンカー付き**で指しているので移すと除外が外れる）

## 影響範囲

| 層 | 影響 | 主な変更ファイル |
|----|------|-----------------|
| エージェント設定（skills） | あり | `.claude/skills/**`（tracked 6ファイル）→ `.agents/skills/**`、`.claude/skills` をリンク化 |
| エージェント設定（plans） | あり | `.agents/plans/.gitkeep` 新規、`.agents/plans/plan-agents-dir-symlink.md` 移動、`.claude/plans` をリンク化 |
| スキル本文 | あり | `.agents/skills/review-brew-outdated/SKILL.md:101`（`$SKILL_DIR` の直書きパス） |
| ドキュメント | あり | `CLAUDE.md` → `AGENTS.md`（実体）＋ `CLAUDE.md` をリンク化、L122・L126 のパス参照更新、分類ルール節を追記 |
| Neovim 設定（`init.lua`, `lua/**`, `lazy-lock.json`） | なし | — |
| シェル / tmux / git dotfiles（`.bashrc` 等） | なし | — |
| `setup.sh` | **なし** | `DOT_FILES` は `.claude` / `.agents` を一切扱わない（`setup.sh:5-21` で確認済み）。**再実行不要** |
| aqua / Renovate 設定 | なし | — |

## 設計 DoD

- [x] 変更対象のファイルと影響範囲を特定した
- [x] 既存のアーキテクチャ・パターンとの整合性を確認した（先行実装A / 先行実装B と同一構成）
- [x] プロジェクトのどの層に変更が必要か明確にした（エージェント設定とドキュメントのみ。Neovim 設定・シェル dotfiles・`setup.sh` は無変更）

## タスク一覧

| # | 状態 | タスク | 層 | 対象ファイル | 依存 |
|---|------|--------|----|-------------|------|
| 1 | [x] | シンボリックリンク越しの読み取りを実地検証する | 検証（変更なし） | scratchpad のサンドボックス | - |
| 2 | [x] | `skills/` を `.agents/` へ移してリンクを張る | エージェント設定 | `.agents/skills/**`, `.claude/skills` | 1 |
| 3 | [ ] | `plans/` を `.agents/` に作り、本計画を移してリンクを張る | エージェント設定 | `.agents/plans/`, `.claude/plans` | 1 |
| 4 | [ ] | `SKILL.md` の `$SKILL_DIR` 直書きパスを実体側に更新する | スキル本文 | `.agents/skills/review-brew-outdated/SKILL.md` | 2 |
| 5 | [ ] | `CLAUDE.md` を `AGENTS.md` 実体 + リンクにする | ドキュメント | `AGENTS.md`, `CLAUDE.md` | 2, 3 |
| 6 | [ ] | 分類ルールと検証結果を `AGENTS.md` に書き残す | ドキュメント | `AGENTS.md` | 5 |

## タスク詳細

### タスク 1: シンボリックリンク越しの読み取りを実地検証する

**完了日**: 2026-08-28

**層**: 検証（リポジトリへの変更なし）

**対象ファイル**:
- なし（scratchpad にサンドボックスを作って捨てる）

**作業内容**:

要件の「着手前に、Claude Code がシンボリックリンク越しに `skills/` と `rules/` を読めるかを実際に確かめること」に対応する。**リポジトリを触る前に**、scratchpad に本番と同じ形のサンドボックスを作って確かめる。

```bash
SB="$(mktemp -d)/symlink-probe"    # $SCRATCHPAD 等の未定義変数を使わない。
                                   # 空だと rm -rf / mkdir がルート直下を触る
mkdir -p "$SB/.agents/rules" "$SB/.agents/skills/probe-skill/adapters" "$SB/.claude"
echo '# probe rule'  > "$SB/.agents/rules/probe.md"
echo '# probe skill' > "$SB/.agents/skills/probe-skill/SKILL.md"
printf '#!/bin/bash\necho probe-adapter\n' > "$SB/.agents/skills/probe-skill/adapters/probe.sh"
chmod 755 "$SB/.agents/skills/probe-skill/adapters/probe.sh"
ln -s ../.agents/rules  "$SB/.claude/rules"
ln -s ../.agents/skills "$SB/.claude/skills"
```

確かめること（結果はこのタスクの「検証結果」に書き残し、タスク 6 で `AGENTS.md` に転記する）:

1. Claude Code の **Read ツール**で `$SB/.claude/skills/probe-skill/SKILL.md` と `$SB/.claude/rules/probe.md` が読めるか
2. **Glob / Grep ツール**がこのビルドに存在するか（`ToolSearch select:Glob,Grep`）。存在すればリンク越しに引けるか
3. `find "$SB/.claude/skills" -name '*.md'`（末尾スラッシュなし）と `find "$SB/.claude/skills/" -name '*.md'`（あり）の件数差
4. `rg probe "$SB/.claude"`（走査中に遭遇）と `rg probe "$SB/.claude/skills"`（引数で明示）の差
5. シェル glob `ls "$SB"/.claude/skills/*/SKILL.md` が通るか
6. **リンク越しに実行ビットが保たれるか**: `bash "$SB/.claude/skills/probe-skill/adapters/probe.sh"` が動くか（本リポジトリの `adapters/*.sh` は 100755。ここが通らないと `review-brew-outdated` が壊れる。**先行実装では検証されていない本リポジトリ固有の項目**）
7. **git がディレクトリリンクをどう記録するか**: サンドボックスを `git init` して `git add`、`git ls-files -s` の mode が `120000` になり、`git cat-file -p <blob>` がリンク先の相対パスを返すこと
8. **スキルの「発見」はここでは測れない、と確認する**（測定ではなく確認）

**8 について — このタスクの限界を先に書いておく。** 1〜7 はすべて**ファイルの中身に届くか**の検証で、`review-brew-outdated` / `review-renovate-pr` が **Claude Code のプロジェクトスキルとして列挙されるか**は測れない。両スキルはパス指定で呼ばれるのではなく、ランタイムが `.claude/skills/` を走査して見つける。**走査がディレクトリリンクを辿らなければ、1〜7 が全部通っても `/review-brew-outdated` と `/review-renovate-pr` は黙って消える。** しかも scratchpad のサンドボックスはプロジェクトルートではないので、構造上ここでは試せない。

したがって**発見の検証はタスク 2 の DoD に置く**（実際に `.claude/skills` をリンクにした後、`~/dotfiles` の新しいセッションで確かめる）。先行実装A が `.claude/skills -> ../.agents/skills` の構成で 3 スキルを運用できている事実は**傍証にはなるが証明ではない**ので、本リポジトリで必ず確かめる。

**検証結果（2026-08-28 実測 / macOS 25.6.0 / Claude Code Opus 5、`$(mktemp -d)` のサンドボックス）**

先行実装B の計画（タスク1、同じマシン・同日の測定）と照合し、**1〜5 行目は全て一致**した。6 行目は先行実装に対応する値が無い新規項目。

| # | 対象 | 走査中に遭遇したリンク | 引数で明示的に渡したリンク |
|---|---|---|---|
| 1 | Claude Code の **Read ツール** | — | **辿る**（`.claude/skills/probe-skill/SKILL.md`・`.claude/rules/probe.md` とも読めた） |
| 2 | Claude Code の **Glob / Grep ツール** | **測定不能** | **測定不能** |
| 3 | `find` | 辿らない | **辿らない**（0件）。**末尾に `/` を付けると辿る**（1件） |
| 4 | `rg` | **辿らない**（0件。`--follow` で3件） | **辿る**（skills 2件 / rules 1件） |
| 5 | シェル glob（`ls .claude/skills/*/SKILL.md`） | 辿る | 辿る |
| 6 | **実行ビット** | — | **保たれる**。リンク越しに `-rwxr-xr-x`、`bash` 実行・`test -x` とも通った |

- **2 が「測定不能」なのは、このビルドの Claude Code に Glob / Grep ツールが存在しないため。** `ToolSearch select:Glob,Grep` が `No matching deferred tools found` を返した。ファイル探索は Bash 経由の `rg` / `find` で行われるので、**実務上は 3〜5 行目の挙動がそのまま効く**
- **6 は本リポジトリ固有の検証項目**（`adapters/*.sh` が mode 100755）。**通った**ので `skills/` の移動を取りやめる必要は無い
- **7. git の記録**: ディレクトリへのリンクは mode `120000` の blob として記録され、中身はリンク先の相対パスそのもの。**同じ相対パスなら同じ blob になる**ので、期待値を先に固定できる。`.agents/` 側の `probe.sh` は `100755` のまま記録された

  | リンク | blob | 中身 | 本リポジトリでの使用 |
  |---|---|---|---|
  | `.claude/skills -> ../.agents/skills` | `2b7a412` | `../.agents/skills` | **タスク 2 で張る**（サンドボックスで実測、先行実装A と一致） |
  | `.claude/plans -> ../.agents/plans` | `3b851bb` | `../.agents/plans` | **タスク 3 で張る**（先行実装A の `git ls-files -s` から。タスク 3 の DoD の期待値） |
  | `.claude/rules -> ../.agents/rules` | `2d5c9a9` | `../.agents/rules` | **使わない**（本リポジトリに `rules/` は無い）。横展開先用の参考値 |
- **8. スキルの発見は測れなかった**（想定どおり）。サンドボックスはプロジェクトルートではなく、本セッションの利用可能スキル一覧はセッション開始時に確定しているため、`.claude/skills` をリンクにした後の列挙結果はここでは観測できない。**タスク 2 の DoD で判定する**

**判定結果**: Read がリンク越しに通り（1）、実行ビットも保たれた（6）。**タスク 2・3 は当初方針どおりディレクトリ単位のリンクで進める。** ファイル単位への切り替えも `skills/` 移行の取り下げも不要。残るリスクはスキルの発見（8）だけで、これはタスク 2 の DoD で判定する。

**判定**（上の結果に照らした分岐。記録として残す）:

| 結果 | 対応 |
|---|---|
| 1（Read）が読めない | タスク 2・3 を**ファイル単位のリンク**（例: `.claude/skills/review-brew-outdated -> ../../.agents/skills/review-brew-outdated`）に切り替える。タスク 6 の記述もファイル単位構成に合わせる |
| 6（実行ビット）が通らない | `skills/` の移動を取りやめ、`plans/` のみ移す構成に落とす |
| 8（発見）| ここでは判定しない。タスク 2 の DoD で判定し、失敗したらタスク 2 の手順内でロールバックする |

**参考パターン**:
- 先行実装A の `AGENTS.md` の「落とし穴」表
- 先行実装B の計画のタスク1 — 実測値の記録形式

**テスト**:
- なし（検証タスク。リポジトリのコードに変更なし）

**DoD コマンド**:
- なし（読み取り検証のみ）。終わったら `rm -rf "$SB"` でサンドボックスを片付ける

---

### タスク 2: `skills/` を `.agents/` へ移してリンクを張る

**完了日**: 2026-08-28

**層**: エージェント設定

**対象ファイル**:
- `.agents/skills/review-brew-outdated/SKILL.md` — 移動（新規パス）
- `.agents/skills/review-brew-outdated/adapters/{bitbucket,git,github,gitlab}.sh` — 移動（mode 100755 を保つ）
- `.agents/skills/review-renovate-pr/SKILL.md` — 移動
- `.claude/skills` — ディレクトリからシンボリックリンク `../.agents/skills` へ

**作業内容**:

`.claude/skills/` の 6 ファイルはすべて tracked（`git ls-files .claude/skills` で確認済み）。履歴と実行ビットを保つため `git mv` を使う。

**`.claude/.gitignore` は移さない。** `git ls-files -s .claude` は 7 行返るが、7 行目はこのファイルで、`settings.local.json` の除外をそのディレクトリに効かせている。移すと除外が外れる。

```bash
cd ~/dotfiles
mkdir -p .agents
git mv .claude/skills .agents/skills
rmdir .claude/skills 2>/dev/null || true   # 安全弁。タスク3と同じ形
ln -s ../.agents/skills .claude/skills
git add .claude/skills
```

**`rmdir` を省略しないこと。** `git mv` は tracked ファイルしか動かさないので、`.claude/skills/` に untracked なファイル（ローカルで足したスキル、エディタの残骸）が 1 つでもあるとディレクトリが残る。残ったまま `ln -s` するとリンクがディレクトリ**の中**に作られ、`.claude/skills/skills` ができてしまう。`rmdir` が失敗したら中身を確認してから進める:

```bash
ls -la .claude/skills   # rmdir が失敗したときだけ実行。残っているものを確認する
```

`ln -s` の直後に `readlink` でも確かめる（下の DoD）。

**参考パターン**:
- 先行実装A の `.claude/skills` — `../.agents/skills` への同一構成のリンク（`ls -la` で確認可能）
- 先行実装B の `.agents/plans/plan-agents-dir-symlink.md` タスク2 — `rules/` に対する同じ手順

**テスト**:
- なし（自動テストの無いリポジトリ。下の DoD コマンドで代替する）

**DoD コマンド**:
```bash
cd ~/dotfiles
readlink .claude/skills                                   # ../.agents/skills であること
git ls-files -s .claude/skills                            # mode 120000 で1エントリだけ記録されていること
git ls-files .agents/skills | wc -l                       # 6 であること（.claude/.gitignore は含めない）
git ls-files -s .agents/skills                            # adapters/*.sh が 100755 のままであること
git ls-files .claude/.gitignore                            # .claude/ 側に残っていること
cat .claude/skills/review-renovate-pr/SKILL.md > /dev/null # リンク越しに読めること
bash -n .claude/skills/review-brew-outdated/adapters/github.sh  # リンク越しに構文解析できること
test -x .agents/skills/review-brew-outdated/adapters/github.sh && echo "exec bit ok"
git check-ignore -v .claude/settings.local.json           # 除外が効いたままであること
git status --porcelain                                    # 意図した差分だけであること
```

**そして最後に、スキルが発見されることを確かめる（このタスクで一番重要な確認）。** 上のコマンドはすべてファイルの中身に届くかを見ているだけで、Claude Code がリンク越しに `.claude/skills/` を走査してスキルを列挙するかは別問題。**`~/dotfiles` で新しいセッションを開き**、`/review-brew-outdated` と `/review-renovate-pr` の 2 つが利用可能なスキルとして出ることを目視で確認する。

**出てこない場合のロールバック**（ディレクトリ単位 → ファイル単位のリンクに落とす。実体は `.agents/` に置いたまま）:

```bash
cd ~/dotfiles
rm .claude/skills                     # リンクを外す（実体は .agents/skills に残る）
mkdir -p .claude/skills
ln -s ../../.agents/skills/review-brew-outdated .claude/skills/review-brew-outdated
ln -s ../../.agents/skills/review-renovate-pr   .claude/skills/review-renovate-pr
git add -A .claude/skills
```

再度セッションを開いて確認し、それでも出てこない場合は `git mv .agents/skills .claude/skills` で全面的に戻し、`skills/` を移す判断そのものを取り下げる（`plans/` の移行はそのまま進めてよい）。**どちらに落ちたかはタスク 6 に必ず書き残す** — 横展開先で同じ判断をやり直さずに済むため。

**検証結果（2026-08-28 実測 / Claude Code 2.1.250）**: **ディレクトリ単位のリンクで発見された。ロールバック不要。**

新しいセッションを別プロセスとして起動し、`.claude/skills` がリンクの状態で列挙させた:

```bash
cd ~/dotfiles
claude -p "Without using any tools, list the names of the project-level skills available to you that start with 'review-'. If there are none, reply exactly: NONE"
# → review-brew-outdated, review-renovate-pr
```

実体は `.agents/skills/` にしか無く、`.claude/skills` は `../.agents/skills` へのリンクだけなので、**ランタイムの走査がディレクトリリンクを辿っている**ことになる。`claude -p`（print モード）は対話セッションを開かずに済むので、横展開先でも同じ 1 コマンドで確かめられる。

あわせて、タスク 1 で固定した blob の期待値どおりに記録された: `git ls-files -s .claude/skills` → `120000 2b7a412…`。

---

### タスク 3: `plans/` を `.agents/` に作り、本計画を移してリンクを張る

**層**: エージェント設定

**対象ファイル**:
- `.agents/plans/.gitkeep` — 新規（空ディレクトリを git に追わせる）
- `.agents/plans/plan-agents-dir-symlink.md` — 本計画ファイルの移動先
- `.claude/plans` — ディレクトリからシンボリックリンク `../.agents/plans` へ

**作業内容**:

**順序が重要。** 本計画ファイルは `.claude/plans/plan-agents-dir-symlink.md` にある（`.agents/plans/` がまだ無い時点で書かれたため）。先に中身を移して `.claude/plans` を空にしないと `ln -s` がリンクをディレクトリの中に作ってしまう。

```bash
cd ~/dotfiles
mkdir -p .agents/plans
touch .agents/plans/.gitkeep
git mv .claude/plans/plan-agents-dir-symlink.md .agents/plans/plan-agents-dir-symlink.md
rmdir .claude/plans                       # 空になっていなければここで失敗する（想定どおりの安全弁）
ln -s ../.agents/plans .claude/plans
git add .agents/plans .claude/plans
```

計画ファイルは**この計画を作成したコミットで tracked になっている**ので `git mv` を使う。実行前に必ず確認する:

```bash
git ls-files .claude/plans        # 追跡されていれば git mv、空なら素の mv
```

`git mv` は staged-add の段階（コミット前）でも動く。逆に**未ステージの untracked ファイルに `git mv` を打つと失敗する**ので、上の確認を飛ばさない。

移動後、**このタスクの完了チェックを書き込む先は `.agents/plans/plan-agents-dir-symlink.md`** になる。`.claude/plans/plan-agents-dir-symlink.md` からも同じ実体に届くが、以降は `.agents` 側のパスを使う。

**参考パターン**:
- 先行実装B の `.agents/plans/` — `.gitkeep` + 計画ファイルが同居する構成
- 先行実装A の `.agents/plans/.gitkeep` — 空 `plans/` を追わせる先行例

**テスト**:
- なし（下の DoD コマンドで代替する）

**DoD コマンド**:
```bash
cd ~/dotfiles
readlink .claude/plans                                    # ../.agents/plans であること
test -f .agents/plans/plan-agents-dir-symlink.md && echo "plan moved"
cat .claude/plans/plan-agents-dir-symlink.md > /dev/null  # リンク越しに読めること
ls .claude/plans/*.md                                     # シェル glob がリンクを辿ること
git ls-files -s .claude/plans .agents/plans               # .claude/plans が 120000、.gitkeep が 100644
git status --porcelain
```

---

### タスク 4: `SKILL.md` の `$SKILL_DIR` 直書きパスを実体側に更新する

**層**: スキル本文

**対象ファイル**:
- `.agents/skills/review-brew-outdated/SKILL.md` — `$SKILL_DIR` の定義行

**作業内容**:

`SKILL.md:101` が `$SKILL_DIR` を次のように直書きしている:

> Throughout the rest of this doc, `$SKILL_DIR` is this skill's directory: `$HOME/dotfiles/.claude/skills/review-brew-outdated`.

リンク越しでも解決するので**壊れてはいない**が、実体の位置とずれる。実体側のパスに直し、リンク経由でも届くことを併記する。

```
`$HOME/dotfiles/.agents/skills/review-brew-outdated`（`.claude/` 側のリンク経由でも同じ実体に届く）
```

**言い換えに `.claude/skills` という文字列を使わないこと。** 下の DoD がその文字列 0 件を条件にしているため、使うと自分の DoD を満たせなくなる。

**`.claude/skills/...` を含む他の行を機械的に置換しないこと。** 該当は L101 の 1 箇所のみ。置換前に必ず洗い出す:

```bash
rg -n '\.claude/skills' .agents/skills/
```

`review-renovate-pr/SKILL.md` には自分の場所への言及が無いので変更不要（`rg` で確認する）。

**参考パターン**:
- `.agents/skills/review-brew-outdated/SKILL.md:98` — `$SKILL_DIR` を使う側の記述（変更不要。定義側だけ直す）

**テスト**:
- なし（ドキュメント文字列の修正。下の DoD コマンドで代替する）

**DoD コマンド**:
```bash
cd ~/dotfiles
rg -n '\.claude/skills' .agents/skills/    # ヒット 0 件であること
rg -n 'SKILL_DIR. is this skill' .agents/skills/review-brew-outdated/SKILL.md   # 新パスになっていること
git diff --stat
```

---

### タスク 5: `CLAUDE.md` を `AGENTS.md` 実体 + リンクにする

**層**: ドキュメント

**対象ファイル**:
- `AGENTS.md` — `CLAUDE.md`（126行、tracked）の実体としての移動先
- `CLAUDE.md` — ファイルからシンボリックリンク `AGENTS.md` へ

**作業内容**:

```bash
cd ~/dotfiles
git mv CLAUDE.md AGENTS.md
ln -s AGENTS.md CLAUDE.md
git add CLAUDE.md
```

リンク先は `AGENTS.md`（同階層なので `./` も `../` も付けない）。先行実装A の `CLAUDE.md -> AGENTS.md` と同じ形。

あわせて本文中の `.claude/skills/` パス参照を実体側に更新する。**該当は 2 箇所**（移動前の `CLAUDE.md` での行番号）:

- L122 — `` The `/review-renovate-pr` skill (defined in `.claude/skills/review-renovate-pr/SKILL.md`) ``
- L126 — `` The `/review-brew-outdated` skill (defined in `.claude/skills/review-brew-outdated/SKILL.md`) ``

どちらも `.agents/skills/...` に直す。行番号は移動で変わらないが、編集前に `rg -n '\.claude/skills' AGENTS.md` で必ず引き直す。

**DoD で「`.claude/skills` が 0 件」を条件にしないこと。** タスク 6 が追記する構成図には `.claude/skills -> ../.agents/skills` という行が正当に入るため、0 件はタスク 6 の完了後に必ず偽になる。散文中の参照だけを見る（下の DoD）。

**履歴の確認はコミット後に行う。** このタスクは `git mv` + `git add` までで、コミットはしない。`git log` は index ではなくコミットを読むので、この時点では `git log --follow -- AGENTS.md` は何も返さない（`AGENTS.md` はまだどのコミットにも存在しない）。rename の記録は `git status --porcelain` の `R` で確かめる。

**参考パターン**:
- 先行実装A の `CLAUDE.md` — `AGENTS.md` への相対リンク（`readlink` で `AGENTS.md`）

**テスト**:
- なし（下の DoD コマンドで代替する）

**DoD コマンド**:
```bash
cd ~/dotfiles
readlink CLAUDE.md                          # AGENTS.md であること
git ls-files -s CLAUDE.md AGENTS.md         # CLAUDE.md が 120000、AGENTS.md が 100644
head -3 CLAUDE.md                           # リンク越しに読めること
rg -n 'skill \(defined in' AGENTS.md        # 2件とも .agents/skills/... を指していること
wc -l AGENTS.md                             # 126 行から極端に減っていないこと
git status --porcelain CLAUDE.md AGENTS.md  # AGENTS.md が R（rename）で記録されていること
```

---

### タスク 6: 分類ルールと検証結果を `AGENTS.md` に書き残す

**層**: ドキュメント

**対象ファイル**:
- `AGENTS.md` — 「エージェント設定の構成（`.agents/` と `.claude/`）」節を追記

**作業内容**:

要件の「分類ルールと確認結果は、他リポジトリにそのまま適用できる形で計画に書き残すこと」に対応する。先行実装A の `AGENTS.md` の同節の構成を土台に、**本リポジトリの実測値**で書く。

置き場所は「Repository purpose」節の直後（構成の話なので、個別ツールの節より前）。含める内容:

1. **構成図** — 本リポジトリの実態を書く。`rules/` は**無い**ので図に入れない:
   ```
   .agents/skills/  ← 実体    .claude/skills -> ../.agents/skills
   .agents/plans/   ← 実体    .claude/plans  -> ../.agents/plans

   .claude/settings.local.json, .claude/.gitignore, .claude/skill-retros/  ← 実体のまま
   ```
2. **分類ルール表** — 汎用の分類として `rules/` も含めた 4 分類（共有可能 / Claude Code 固有 / スキルの出力 / 不明）。「本リポジトリに無い項目も汎用の分類として並べている」と断る
3. **落とし穴** — タスク 1 の実測値。`find` の末尾スラッシュ差、`rg` の `--follow`、シェル glob、Read ツール、**実行ビットがリンク越しに保たれるか**（本リポジトリ固有の検証項目）。Glob / Grep 欄は**環境ごとに確かめる項目**である旨を添える（このビルドには両ツールが無い）。**サンドボックスだけでなく本リポジトリでも再確認済み**（タスク2 のレビュー時、実測）: `find .claude/skills -name '*.md'` → 0 件 / `find .claude/skills/ -name '*.md'` → 2 件。現状これに依存するスクリプトは repo 内に無い（`setup.sh` / `scripts/` / 両 `SKILL.md` / `CLAUDE.md` を確認済み）が、**黙って 0 件を返す唯一の走査形**なので必ず書く
4. **スキルの発見（本リポジトリで一番効く項目）** — Claude Code がリンク越しに `.claude/skills/` を走査してスキルを列挙できたか、タスク 2 の DoD の実測結果を書く。ディレクトリ単位のリンクで通ったのか、ファイル単位に落としたのか、`skills/` の移行自体を取り下げたのかを明記する。**ファイルの中身が読めることと、スキルが発見されることは別**で、前者だけ確かめて移すと `/`-コマンドが黙って消える、という順序で書く
5. **git での記録のされ方** — ディレクトリへのリンクは mode `120000` の blob で、中身はリンク先の相対パス
6. **gitignore の注意** — ここは**本リポジトリ固有の警告として強めに書く**:
   - `~/.gitignore_global` の実体は `~/dotfiles/.gitignore_global`（このリポジトリのファイル）。`.claude/settings.local.json`（52行目）と `.claude/skill-retros`（58行目）を**パスで直接**指している
   - root `.gitignore:2` の `/.claude/skill-retros/` は**先頭 `/` でアンカーされている**ので `.agents/` へ移すと一切効かなくなる
   - `.claude/.gitignore` はそのディレクトリに対して効くので `.claude/` に残す
   - **いずれも `.claude/` に実体を残す分類なので現状は無影響。移してはいけない**
   - **`.agents/` 側には対応する除外が一切無い**（非対称）。今回移した 6 ファイルは全て追跡されるべきものなので無影響だが、**将来 `.agents/` の下にローカル設定やスキル出力を置くと、そのまま追跡対象になる**。横展開先で `.agents/` に何かを足すときは、先に除外が要るかを判断する
   - 行番号はファイルの変化で動くので、適用先で毎回洗い出す: `grep -n '\.claude/' ~/dotfiles/.gitignore_global`
7. **横展開時の注意** — 残り 2 リポジトリへ適用するときの手順の要点。`git mv` を使うこと、**リンクを張る前に対象ディレクトリを `rmdir` で空にすること**（untracked ファイルが残るとリンクがディレクトリの中に作られる）、`plans/` が無ければ `.gitkeep` で作ること、**移した後に必ずスキルの発見を確かめること**

**参考パターン**:
- 先行実装A の `AGENTS.md` の同節 — 節の構成・表の形。ただし `.claude/` の中身も gitignore の事情も本リポジトリとは違うので、**文面をそのまま持ってこない**
- 先行実装B の計画のタスク1 — 実測値の粒度

**テスト**:
- なし（ドキュメント。下の DoD コマンドで代替する）

**DoD コマンド**:
```bash
cd ~/dotfiles
rg -n 'エージェント設定の構成' AGENTS.md          # 節が入っていること
rg -n 'gitignore_global' AGENTS.md                # gitignore の注意が入っていること
grep -n '\.claude/' .gitignore_global             # 書き残した行番号が実態と合っていること
readlink CLAUDE.md                                # AGENTS.md であること
rg -n 'エージェント設定の構成' CLAUDE.md          # リンク越しに新しい節まで届くこと（head -3 では届かない）
git status --porcelain                            # 意図した差分だけであること
```
