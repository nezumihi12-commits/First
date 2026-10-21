# UltraDimCamera

iPhoneで背面カメラの映像を見ながら背面LEDを微調光して、操作音を加えず動画・音声を録画するSwiftUIアプリ。

## 主な機能\n- 画面全体を使うライブプレビューと、スクロール不要のカメラ風操作画面（ライトON/OFF、光量、録画を1画面に集約）
- 背面カメラプレビュー
- トーチレベルを0.001〜1.0で指定する対数スライダー。実際の光量はハードウェア制限あり
- AVFoundation の `AVCaptureVideoDataOutput` / `AVCaptureAudioDataOutput` と `AVAssetWriter` による録画（720p設定）
- 録画開始・停止時にアプリ独自の電子音を鳴らさない（OSによる強制音は制御不可）
- マイク権限がある場合は音声付き、なければ無音の動画
- 写真アプリに動画保存
- アプリがバックグラウンドに移ると録画とトーチを停止
- 広告・アカウント・外部通信・解析処理なし

## SideStoreで日本語アプリ名が受理されない場合
このブランチのv1.1で、アプリのProduct Name、Display Name、Bundle Name、Xcodeプロジェクト名、実行ファイル名をすべて英語の `UltraDimCamera` に統一しました。アプリ内の説明文は日本語ですが、IPA/アプリの識別名はASCIIです。

## iPhoneだけでインストール
1. [GitHub Actions](https://github.com/nezumihi12-commits/First/actions) から **Build Ultra Dim Camera IPA** の **feature/ultradim-camera** ブランチの成功した最新の実行を開く。
2. Artifacts の **UltraDimCamera-IPA** をダウンロード。
3. 「ファイル」でZIPを解凍し、 `UltraDimCamera.ipa` を取り出す。
4. SideStoreでそのIPAを選び、iPhoneで署名・インストール。
5. 起動時にカメラ・マイク・写真への追加権限を許可する。

IPAはGitHubのmacOSランナーでビルドした未署名のファイル。SideStoreでApple Accountによる署名が必要。GitHubに署名鍵はアップロード不要。

### 注意
通常のアプリは、iOSが地域等によって強制するシャッター音を上書きできません。このアプリは写真撮影機能を持たず、映像・音声サンプルから直接動画を保存することで録画UI音を加えない設計です。システム音の完全な無音化は保証できません。

実機の光量・録画の安定性・SideStoreでのインストール可否は端末での確認が必要です。