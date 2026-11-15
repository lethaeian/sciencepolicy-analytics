# 気圧・体調 — iOS 版（SwiftUI）

Web 版（`../widget/`）と同じ判定・同じ見た目を、ネイティブアプリとして書いたもの。
Web 版ではできなかった**ロック画面ウィジェット**が使える。

## 中身

```
Shared/   取得と判定。本体とウィジェットの両方から使う
  Models.swift      予報の入れもの
  WeatherAPI.swift  Open-Meteo の呼び出し（15秒で打ち切り、失敗の理由を区別する）
  Risk.swift        体調の目安 0〜9。Web 版の riskOf / computeAlarm をそのまま移植
  Theme.swift       配色と、横線で描いた円
  SharedStore.swift 本体とウィジェットの受け渡し（App Group）
App/      画面
  ContentView.swift   縦向き・横向きの組み替え
  PressureWave.swift  気圧の波形（縦軸は1時間あたりの変化量）
  Pieces.swift        3時間おきの列、気温・湿度
  AppModel.swift      取得のだんどり、現在地、画面を消さない
Widget/   ロック画面・ホーム画面のウィジェット
```

判定の係数は Web 版と同じ。片方を変えたらもう片方も合わせること。

## 1. XcodeGen で作る（おすすめ）

```sh
brew install xcodegen
cd ios
xcodegen            # Kiatsu.xcodeproj ができる
open Kiatsu.xcodeproj
```

## 2. 手で作る

1. Xcode → File → New → Project → iOS → App（SwiftUI、名前 `Kiatsu`）
2. できたプロジェクトから `ContentView.swift` と `KiatsuApp.swift` を削除
3. `App/` `Shared/` の中身をドラッグして追加（Copy items は外す）
4. File → New → Target → Widget Extension（名前 `KiatsuWidget`、Include Configuration Intent は外す）
5. 生成されたウィジェットのソースを削除し、`Widget/KiatsuWidget.swift` と `Shared/` を
   そのターゲットにも追加（Target Membership で Shared の5ファイルに両方チェック）

## 3. 実機に入れる前に

- **Bundle Identifier を自分のものに変える**（`com.example.kiatsu` のまま）
- **Signing & Capabilities** でチームを選ぶ
- **App Group を作る**（例 `group.あなたの逆ドメイン.kiatsu`）。本体とウィジェットの両方に付け、
  `Shared/SharedStore.swift` の `appGroup` を同じ文字列に書き換える。
  これをしないとウィジェットが地点を読めない
- 無料の Apple ID だと7日で失効する。年99ドルの登録なら1年＋TestFlight が使える

## 判定が Web 版とずれていないか

`Tests/Fixtures/judgement.json` は、Web 版の `riskOf` / `computeAlarm` を Node で
直接動かして書き出した答え。240通りの無作為な天候が入っていて、危険度0〜9と
4段階すべてを含む。Xcode で `KiatsuTests` を走らせると、Swift 版が同じ答えを
返すかを突き合わせる。

係数を変えたときは、Web 版と Swift 版の両方を直してから作り直すこと。

```sh
node Tools/gen-fixture.js    # 基準データを作り直す（Web 版が正）
node Tools/check-port.js     # Swift を JS に書き写した写しで突き合わせる（Xcode なしの下見）
```

## 分かっていること

- **この環境ではビルド・実機確認ができていない**。Linux のコンテナで書いたもので、
  Swift コンパイラも Xcode も無い。最初のビルドで型の食い違いなどが出る可能性がある。
  エラーが出たらそのまま貼ってもらえれば直す
- **判定ロジックだけは検証済み**。Swift のコードを1行ずつ JS に書き写し、上の
  240件の基準データと突き合わせて全件一致を確認した（`Tools/check-port.js`）。
  危険度・段階・見出し・注記のいずれもずれていない
- ウィジェットの更新間隔は端末側が決める。だいたい15〜60分で、真の常時更新はできない
  （気象データ自体が1時間ごとなので、この用途では足りる）
