# MyFirstiOSApp

最小構成のSwiftUIアプリです。

## ビルド方法
1. このフォルダの中身をGitHubリポジトリへアップロードします。
2. GitHubのActionsタブで `Build IPA` を実行します。
3. 完了後、Artifactsから `MyFirstiOSApp-IPA` をダウンロードします。
4. ZIPを展開すると `MyFirstiOSApp.ipa` があります。
5. iPhoneへ送ってSideStoreでインストールします。

このIPAはGitHub Actions上で未署名ビルドされ、SideStore側で自分のApple Accountを使って署名してインストールする想定です。
