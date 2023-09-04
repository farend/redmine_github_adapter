# redmine_github_adapter

## インストール方法

Redmineのrootフォルダに移動する。

```sh
$ cd /path/to/redmine
```

plugins以下に配置する。

```sh
git clone git@github.com:NaCl-Ltd/redmine_github_adapter.git plugins/redmine_github_adapter
```

必要なgemをインストールする。

```sh
$ cd /path/to/redmine
$ bunlde install
```

plugin のマイグレーションを実行する。

```sh
$ bundle exec rake redmine:plugins:migrate
```

## 使用方法

### 事前準備（APIトークンの発行）

GitHubにアカウントを作成しログインする。  
画面右上のアイコンをクリックし「Settings」を選択する。  
「Developer settings」＞「Personal access tokens」＞「Tokens (classic)」を選択する。  
トークンの管理画面が表示されるため、「Generate new token」プルダウンメニューから「Generate new token (classic)」を選択する。  
「Note」や「Expiration」は任意の値を入力、「Select scopes」からは「repo」にチェックを入れ「Generate token」を選択する。  
トークンが表示されるためコピーして管理しておく。（以降はこの管理画面からも表示できないため。）

### 全体設定

Redmineへログイン後、トップメニューから「管理」＞「設定」を選択し、Redmine全体の設定メニューを開く。  
「リポジトリ」タブを選択すると「使用するバージョン管理システム」という設定項目が表示されるため、「Github」にチェックをいれ「保存」を選択する。

### プロジェクト設定

GitHubリポジトリを使用するプロジェクトのトップ画面を開く。  
「設定」タブを選択＞「リポジトリ」タブを選択し、「新しいリポジトリ」をクリックする。  
以下を入力して「作成」を選択する。

- バージョン管理システム: GitHub
- メインリポジトリ: 任意
- 識別子: 任意の文字列
- URL: 利用するGitHubリポジトリのURL（例: `https://github.com/redmine/redmine`）
- API トークン: 「事前準備」にて発行したトークン
