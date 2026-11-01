---
name: renovate-triage
description: Use when asked to handle Renovate PRs or Dependabot alerts in a repository (e.g. 「Renovate やっといて」「Renovate の PR を片付けて」「Dependabot の警告を見て」). Matches open alerts to PRs, puts the PRs in merge order, checks whether each one is ready, and reports what needs a decision. If the repository has its own skill for this under .claude/skills, use that one instead.
---

# Renovate の PR と Dependabot alerts の対応

開いている alerts を PR と突き合わせ、どの順にマージすればよいかと、判断が要るものを報告する。

dev-toolkit のテンプレートの `renovate.json`（`all-non-major` と `github-actions` のグループ、土曜のスケジュール）を前提に書いてあるが、グループの名前や構成が違っても考え方は同じ。

## 0. 前提を確かめる

1. **リポジトリ専用の skill があれば、そちらを使う。** `.claude/skills/` に Renovate を扱う skill があれば、ここで止めてそれに従う。
2. **リポジトリの決まりを読む。** `CLAUDE.md` / `AGENTS.md` と、Renovate の運用文書があればそれを読む。この手順と食い違ったら、リポジトリの文書が正しい。
3. **Renovate の設定を読む。** `renovate.json`（`.github/renovate.json` や `renovate.json5` のこともある）で、グループ、自動マージの対象、スケジュールを確かめる。
4. **マージで何が動くかを読む。** `.github/workflows/` のうち、既定のブランチへの push で走るものを見る。デプロイがあれば、マージがそのままデプロイになるので、報告に書く。

## 1. 状況を集める

```bash
gh api 'repos/{owner}/{repo}/dependabot/alerts' --paginate \
  --jq '.[] | select(.state == "open") | [.number, .dependency.package.name, .dependency.relationship, .dependency.scope, .security_advisory.severity, .dependency.manifest_path, (.security_vulnerability.first_patched_version.identifier // "修正版なし"), .security_advisory.summary] | @tsv'
gh pr list --author "app/renovate" --state open \
  --json number,headRefName,title,labels,mergeable \
  --jq '.[] | [.number, .headRefName, .title, ([.labels[].name] | join(",")), .mergeable] | @tsv'
```

`{owner}/{repo}` は gh がカレントのリポジトリに置き換える。alerts が 403 / 404 なら、無効か権限不足なので、そう報告する。

## 2. alerts を PR と突き合わせる

alert ごとに、どの PR が直すかを差分で探す。

```bash
gh pr diff <PR番号> | grep -n -A2 '<パッケージ名>'
```

| alert の状況 | 扱い |
| --- | --- |
| 開いている PR が修正版へ上げる | その PR を**順位1**に繰り上げる |
| 修正版はあるが、上げる PR が無い | 推移的依存なら、ロックファイル保守で上がるはず。PR が無ければ Dependency Dashboard のチェックボックスで作らせる。親パッケージの指定範囲の外にあって上がらないなら、`overrides` などで宣言するかの判断が要るので、下の材料を添えて**報告する** |
| 修正版が出ていない（`修正版なし`） | PR では直らない。下の材料を添えて**報告する** |

**PR で直らない alert は、判断の材料を集めて報告する。**

- 経路: `pnpm why` / `npm ls` / `uv tree --invert` で、どのパッケージ経由で入っているか
- 本番で動くか: alert の `dependency.scope` と経路
- 脆弱なコードに届くか: アドバイザリの説明にある関数と条件を読み、呼び出し元のソースで、その関数を呼ぶか、どのオプションで呼ぶかを確かめる。手元の `node_modules` などは古いことがあるので、既定のブランチのロックファイルが指す版のソースを見る
- 入力を誰が握るか: 攻撃者がその入力を書けるか

**深刻度や「自動で閉じなかったこと」から重大さを推測しない。** GitHub のプリセット（開発時の依存の影響の小さい alert を閉じるもの）は、深刻度ではなく CWE の一覧で判定する。一覧に無い CWE なら、影響が小さくても開いたまま残る。

**alert を dismiss しない。** 受け入れるかどうかはユーザーが決める。

## 3. 順番を決める

マージは1本ずつ行い、結果を確かめてから次へ進む。同時に複数を入れると、同じロックファイルを取り合い、何が壊したのか切り分けられなくなる。

1. **脆弱性の PR**（`security` ラベル）と、2 で繰り上げた PR
2. **グループ更新** — `all-non-major` を最初に
   - 言語の版のファイルは `all-non-major` が、`pyproject.toml` などの下限は別のグループが上げることがある。既定のブランチの版のファイルが古いままだと、後者はロックファイルを作れず `renovate/artifacts` が赤になる
   - 同じロックファイルを書き換えるグループは、片方をマージするともう片方が作り直しになる。CI の重いものを先にマージしたほうが安く済む。`all-non-major` はたいてい一番重い
   - `all-non-major` の CI が落ちているときは、待たずに他を先に通す
3. **ロックファイル保守** — 次の回まで持ち越さない。推移的依存の脆弱性を自動で直す経路はこれしかない
4. **major** — Release Notes の要点とコードへの影響を添える。1〜3 が済んでから1本ずつ

`automerge: true` のグループは Renovate が自分でマージするので、順番に入れない。スケジュール外では動かないので、緑のまま開いていても異常とは限らない。落ちていたら報告する。

## 4. PR ごとの状態を確かめる

| 見るもの | 確かめ方 |
| --- | --- |
| major か | `major-update` ラベルと、更新表の `Change` の版。単独の更新の表には種別の列が無いので、`\| major \|` の検索だけでは足りない。脆弱性の PR でもメジャーを跨ぐことがある |
| CI | `gh pr checks <番号> --json name,bucket` の `bucket`。`renovate/artifacts` も見る。チェックが1つも無いなら、緑とは書かず、CI で確かめられていないと書く |
| コンフリクト | `mergeable`。`UNKNOWN` は判定中なので、少し待って見直す |

**CI が赤なら、原因がその PR にあるとは決めつけない。** 脆弱性スキャンのようにリポジトリ全体を見る CI は、PR が触っていないファイルでも落ちる。失敗のログに出るファイルが PR の差分にあるかを見る。無ければ既定のブランチの問題なので、それを直す PR を先に通す順番にする。

## 5. 報告する

- マージする順番と、それぞれがマージできる状態か。マージで動くもの（デプロイなど）があれば、それも
- すぐにはマージできない PR と理由（major なら Release Notes の要点とコードへの影響、CI が落ちたなら原因）
- Dependabot alerts の残りと、それぞれの扱いと判断の材料
- 判断が要るもの

## マージされた後

1本マージされると、残りの PR の状態が変わる。次に頼まれたら 1 からやり直し、あわせて次を確かめる。

マージコミットのワークフローは次で見る。落ちていたら、次の PR に進む前に報告する。

```bash
gh run list --branch <既定のブランチ> --commit <マージコミットのSHA> --json workflowName,status,conclusion
```

残りの PR は、次の状態なら作り直させる。`updateNotScheduled: false` の設定では、スケジュールの外ではコンフリクトしても自動で作り直されない。

| 状態 | 対応 |
| --- | --- |
| `mergeable` が `CONFLICTING` | rebase/retry のチェックボックスを入れる |
| `renovate/artifacts` が赤（「Artifact update problem」のコメント） | 原因が既定のブランチ側で解消していれば、チェックボックスを入れる。Renovate はこれをコンフリクトとして扱わないので、自動では作り直さない |
| 既定のブランチの問題で CI が赤だった | それが解消していれば、チェックボックスを入れる |

チェックボックスは PR 本文の `- [ ] <!-- rebase-check -->` を `- [x]` に替えて入れる。本文の一時ファイルはセッションの scratchpad に置く。

```bash
gh pr view <番号> --json body --jq .body > <一時ファイル>
sed -i 's/- \[ \] <!-- rebase-check -->/- [x] <!-- rebase-check -->/' <一時ファイル>
gh pr edit <番号> --body-file <一時ファイル>
```

Dependency Dashboard の「Rebase all open PRs」は使わない。開いている PR すべての CI が回り直す。

**alert は、直す PR をマージしてもすぐには閉じない。** 30分ほどかかることがある。待っている間は、修正が既定のブランチに入ったかを次の2つで確かめる。

```bash
git show origin/<既定のブランチ>:<ロックファイルのパス> | grep -A1 '<パッケージ名>'
gh api 'repos/{owner}/{repo}/dependency-graph/sbom' \
  --jq '.sbom.packages[] | select(.name | test("<パッケージ名>"; "i")) | [.name, .versionInfo] | @tsv'
```

## やってはいけないこと

- Dependabot alert を dismiss する
- Renovate の PR に追加コミットを乗せる（force-push で消える）
- `renovate.json` や依存の宣言をこの作業の中で書き換える。必要なら別の Issue と PR にする
