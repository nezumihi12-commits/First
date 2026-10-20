# 微光カメラ / Ultra Dim Camera

iPhoneの背面カメラ映像を見ながら、背面LEDトーチを微調光して動画を撮影する無料のSwiftUIアプリです。

## 機能
- カメラプレビュー（背面広角カメラ）
- 録画中を含め、トーチの光量を0.001〜1.0の範囲で指定（対数スライダー）
- マイク音声を含む720p動画を録画（マイクを許可しない場合は無音）
- 撮影後に写真アプリへ保存（写真への追加権限が必要）
- アプリが背景に移るとトーチと録画を停止
- アプリ内広告なし、アカウント不要、通信・解析処理なし

**注意**：「0.1%」などはAppleの `AVCaptureDevice.setTorchModeOn(level:)` に渡す *正規化された要求値* です。実際の発光量がその割合になるわけではありません。iPhoneのLEDの物理的な最低光量以下にはできません。機種によって細かな指定が区別されない場合があります。バックグラウンド点灯には対応していません。

## iPhoneだけでSideStoreにインストール
1. このリポジトリの **Actions** → **Build Ultra Dim Camera IPA** を開く。
2. `feature/ultradim-camera` ブランチの成功した実行を選ぶ（またはActionsからワークフローを実行）。
3. その実行の **Artifacts** → `UltraDimCamera-IPA` をダウンロードする。
4. iPhoneの「ファイル」でダウンロードしたZIPを展開し、`UltraDimCamera.ipa` を取り出す。
5. SideStoreから `UltraDimCamera.ipa` を選び、Apple Accountで署名・インストールする（SideStoreは事前設定が必要）。
6. 初回起動時にカメラ、マイク、写真への追加を許可する。

ビルドはGitHub ActionsのmacOSランナー上でXcodeGen + Xcodeにより実行し、**未署名のIPA**を生成します。GitHub上にはApple Accountの認証情報や署名鍵を置きません。SideStore側で署名します。

## 開発・確認
```sh
brew install xcodegen
xcodegen generate
xcodebuild -project MyFirstiOSApp.xcodeproj -scheme MyFirstiOSApp -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

iOS 16以降、背面トーチのあるiPhone向け。GitHub Actionsでビルドは確認できますが、LEDの実光量や録画安定性は実機試験が必要です。
